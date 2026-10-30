import SwiftUI

/// Laid out like LG's own remote, top to bottom: what's on, inputs and power,
/// your apps, the click wheel, back and home, volume, then playback.
/// No channel or number keys: everything here is apps, so up and down is the wheel's job.
struct RemoteView: View {
    @EnvironmentObject private var tv: TVConnection
    @State private var pointer = false
    @State private var sheet: Sheet?

    var body: some View {
        VStack(spacing: 0) {
            TopBar(sheet: $sheet)
            Spacer(minLength: 12)
            AppKeys(sheet: $sheet)
            Spacer(minLength: 16)

            Group {
                if pointer { Trackpad() } else { ClickWheel() }
            }
            .frame(maxWidth: 310, maxHeight: 310)
            .aspectRatio(1, contentMode: .fit)

            Spacer(minLength: 16)
            HStack {
                IconKey(symbol: "arrow.uturn.backward", longPress: { tv.press(.exit) }) { tv.press(.back) }
                Spacer()
                IconKey(symbol: "house.fill") { tv.press(.home) }
                Spacer()
                IconKey(symbol: "keyboard") { sheet = .keyboard }
                Spacer()
                IconKey(symbol: "cursorarrow", tint: pointer ? Theme.accent : Theme.ink) { pointer.toggle() }
            }

            Spacer(minLength: 16)
            VolumeBar()
            Spacer(minLength: 16)
            Playback()
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Theme.background.ignoresSafeArea())
        #if DEBUG
        .onAppear { if CommandLine.arguments.contains("-apps") { sheet = .apps } }
        #endif
        .sheet(item: $sheet) { kind in
            Group {
                switch kind {
                case .keyboard: KeyboardSheet().presentationDetents([.height(170)])
                case .inputs: InputsSheet().presentationDetents([.medium])
                case .apps: AppsSheet().presentationDetents([.medium, .large])
                }
            }
            .presentationBackground(Theme.background)
            .presentationDragIndicator(.visible)
            .environmentObject(tv)
        }
    }
}

enum Sheet: String, Identifiable {
    case keyboard, inputs, apps
    var id: String { rawValue }
}

// MARK: - Top bar

private struct TopBar: View {
    @EnvironmentObject private var tv: TVConnection
    @Binding var sheet: Sheet?
    @AppStorage("appearance") private var appearance: Appearance = .system

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                Button("Forget this TV", role: .destructive) { tv.forget() }
            } label: {
                HStack(spacing: 8) {
                    if tv.state == .connected, let app = tv.foregroundApp {
                        // What's on the TV, in its own colors.
                        AppIcon(app: app, radius: 5, inset: 1).frame(width: 22, height: 22)
                        Caption(app.title)
                    } else {
                        // Orange when connected; faint while it reconnects.
                        Circle()
                            .fill(tv.state == .connected ? Theme.accent : Theme.muted)
                            .frame(width: 6, height: 6)
                        Caption("LG · \(tv.host ?? "")")
                    }
                }
                .frame(height: 44)
                .animation(.easeOut(duration: 0.2), value: tv.foreground)
                .animation(.easeOut(duration: 0.2), value: tv.state == .connected)
            }
            Spacer()
            AppearanceKey(appearance: $appearance)
            IconKey(symbol: "cable.connector", size: 44) { sheet = .inputs }
            IconKey(symbol: "gearshape.fill", size: 44) { tv.press(.settings) }
            PowerKey()
        }
    }
}

/// One key that cycles System → Light → Dark; its icon shows the current one.
private struct AppearanceKey: View {
    @Binding var appearance: Appearance

    var body: some View {
        Key(shape: Circle(), action: { appearance = appearance.next }) {
            Image(systemName: appearance.symbol)
                .font(.system(size: 14, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Appearance")
        .accessibilityValue(appearance.title)
    }
}

// MARK: - App shortcut keys

private struct AppKeys: View {
    @EnvironmentObject private var tv: TVConnection
    @Binding var sheet: Sheet?
    private let pins = Pins()

    private var pinned: [TVConnection.App] {
        pins.ids.compactMap { id in tv.apps.first { $0.id == id } }
    }

    var body: some View {
        GeometryReader { geo in
            // Exactly five tiles fit the frame; a sixth peeks in from the edge.
            let gap: CGFloat = 8
            let tile = (geo.size.width - gap * 4) / 5

            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: gap) {
                        ForEach(pinned) { app in
                            Button {
                                haptic()
                                tv.launch(app)
                            } label: {
                                AppIcon(app: app, inset: 4).frame(width: tile, height: 50)
                            }
                            .buttonStyle(KeyStyle(shape: RoundedRectangle(cornerRadius: 14)))
                        }
                        add(width: pinned.isEmpty ? geo.size.width : tile)
                            .id("add")
                    }
                    .padding(.vertical, 3)
                }
                // Scroll edge to edge, but line the tiles up with the page margin.
                .contentMargins(.horizontal, 24, for: .scrollContent)
                .padding(.horizontal, -24)
                .onChange(of: pins.ids) { old, new in
                    guard new.count > old.count else { return }
                    withAnimation(.easeInOut(duration: 0.3)) { reader.scrollTo("add", anchor: .trailing) }
                }
            }
        }
        .frame(height: 56)
        .onAppear { pins.seedIfNeeded(with: tv.shortcuts) }
        .onChange(of: tv.apps) { pins.seedIfNeeded(with: tv.shortcuts) }
    }

    private func add(width: CGFloat) -> some View {
        Button {
            haptic()
            sheet = .apps
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
                if pinned.isEmpty { Text("Add apps").font(Theme.mono(12)) }
            }
            .frame(width: width, height: 50)
        }
        .buttonStyle(KeyStyle(shape: RoundedRectangle(cornerRadius: 14)))
    }
}

/// An app's tile, the way the TV draws it: its icon on its brand color.
struct AppIcon: View {
    @EnvironmentObject private var tv: TVConnection
    let app: TVConnection.App
    var radius: CGFloat = 14
    var inset: CGFloat = 6
    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Color(hex: app.color) ?? Theme.key)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().padding(inset)
                } else {
                    Text(app.title)
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .task(id: app.icon) {
                if let url = app.icon { image = await tv.image(url) }
            }
    }
}

extension Color {
    /// "#FD312E" → Color. Nil for anything else.
    init?(hex: String?) {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let value = Int(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

// MARK: - Click wheel

/// One ring for the four arrows (hold to repeat) and OK in the middle,
/// like the wheel on LG's remote.
private struct ClickWheel: View {
    @EnvironmentObject private var tv: TVConnection
    @State private var active: Zone?
    @State private var repeating: Task<Void, Never>?

    enum Zone { case up, down, left, right, ok }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2
            let inner = radius * 0.4

            ZStack {
                Circle().fill(Theme.key)
                Circle().stroke(Theme.hairline, lineWidth: 1)

                // The ring is a dot matrix, like the icon; the quarter under your thumb lights up.
                let pitch = side / 21
                DotRing(inner: inner + pitch, outer: radius - pitch * 0.6, pitch: pitch, marker: radius * 0.7, color: Theme.muted.opacity(0.24))
                ForEach([Zone.up, .down, .left, .right], id: \.self) { zone in
                    DotRing(inner: inner + pitch, outer: radius - pitch * 0.6, pitch: pitch, marker: radius * 0.7, color: Theme.accent)
                        .mask(Wedge(zone: zone, inner: inner))
                        .opacity(active == zone ? 1 : 0)
                }

                marker("chevron.up", .up).offset(y: -radius * 0.7)
                marker("chevron.down", .down).offset(y: radius * 0.7)
                marker("chevron.left", .left).offset(x: -radius * 0.7)
                marker("chevron.right", .right).offset(x: radius * 0.7)

                Circle()
                    .fill(Theme.background)
                    .frame(width: inner * 2 + 8, height: inner * 2 + 8)
                Circle()
                    .fill(active == .ok ? Theme.accent : Theme.key)
                    .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                    .frame(width: inner * 2, height: inner * 2)
                    .scaleEffect(active == .ok ? 0.97 : 1)
                Text("OK")
                    .font(Theme.mono(15))
                    .foregroundStyle(active == .ok ? Theme.background : Theme.ink)
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
            .animation(.easeOut(duration: 0.15), value: active)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard active == nil,
                              let zone = zone(at: value.startLocation, radius: radius, inner: inner)
                        else { return }
                        active = zone
                        if zone != .ok { startRepeating(zone) }
                    }
                    .onEnded { _ in
                        repeating?.cancel()
                        if active == .ok {
                            haptic(.medium)
                            tv.press(.enter)
                        }
                        active = nil
                    }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func marker(_ symbol: String, _ zone: Zone) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(active == zone ? Theme.accent : Theme.ink.opacity(0.7))
    }

    private func zone(at point: CGPoint, radius: CGFloat, inner: CGFloat) -> Zone? {
        let dx = point.x - radius, dy = point.y - radius
        let distance = hypot(dx, dy)
        if distance < inner { return .ok }
        if distance > radius { return nil }
        if abs(dx) > abs(dy) { return dx > 0 ? .right : .left }
        return dy > 0 ? .down : .up
    }

    private func startRepeating(_ zone: Zone) {
        let button: TVConnection.Button = switch zone {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .ok: .enter
        }
        haptic(.light)
        tv.press(button)
        repeating = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            while !Task.isCancelled {
                haptic(.soft)
                tv.press(button)
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }
}

/// Dots on a square grid centered on the wheel, kept to the ring between two radii.
private struct DotRing: View {
    let inner: CGFloat
    let outer: CGFloat
    let pitch: CGFloat
    /// Distance of the four arrows from the center; the dots leave room around them.
    let marker: CGFloat
    let color: Color

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let steps = Int(outer / pitch) + 1
            let dot = pitch * 0.18
            var path = Path()
            for row in -steps...steps {
                for col in -steps...steps {
                    let x = CGFloat(col) * pitch, y = CGFloat(row) * pitch
                    let distance = hypot(x, y)
                    guard distance > inner, distance < outer else { continue }
                    let nearArrow = [CGPoint(x: 0, y: marker), CGPoint(x: 0, y: -marker),
                                     CGPoint(x: marker, y: 0), CGPoint(x: -marker, y: 0)]
                        .contains { hypot(x - $0.x, y - $0.y) < pitch * 1.3 }
                    if nearArrow { continue }
                    path.addEllipse(in: CGRect(x: center.x + x - dot, y: center.y + y - dot, width: dot * 2, height: dot * 2))
                }
            }
            context.fill(path, with: .color(color))
        }
        .allowsHitTesting(false)
    }
}

/// The quarter of the ring under your thumb.
private struct Wedge: Shape {
    let zone: ClickWheel.Zone
    let inner: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let mid: Double = switch zone {
        case .right: 0
        case .down: 90
        case .left: 180
        default: 270
        }
        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: .degrees(mid - 45), endAngle: .degrees(mid + 45), clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: .degrees(mid + 45), endAngle: .degrees(mid - 45), clockwise: true)
        path.closeSubpath()
        return path
    }
}

// MARK: - Trackpad (the Magic Remote's pointer)

/// Drag to move the TV's pointer, tap to click, drag along the right edge to scroll.
private struct Trackpad: View {
    @EnvironmentObject private var tv: TVConnection
    @State private var last: CGPoint?
    @State private var touching = false

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 36)
                .fill(touching ? Theme.keyPressed : Theme.key)
                .overlay(RoundedRectangle(cornerRadius: 36).stroke(Theme.hairline, lineWidth: 1))
                .overlay(alignment: .trailing) {
                    // Scroll strip: a column of dots, the site's motif.
                    VStack(spacing: 10) {
                        ForEach(0..<9, id: \.self) { _ in
                            Circle().fill(Theme.muted.opacity(0.6)).frame(width: 3, height: 3)
                        }
                    }
                    .padding(.trailing, 18)
                }
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.15), value: touching)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            touching = true
                            defer { last = value.location }
                            guard let last else { return }
                            let dx = value.location.x - last.x
                            let dy = value.location.y - last.y
                            if value.startLocation.x > geo.size.width - 48 {
                                tv.scroll(dy: -dy)
                            } else {
                                tv.move(dx: dx * 1.6, dy: dy * 1.6)
                            }
                        }
                        .onEnded { value in
                            touching = false
                            last = nil
                            if hypot(value.translation.width, value.translation.height) < 6 {
                                haptic()
                                tv.click()
                            }
                        }
                )
        }
    }
}

// MARK: - Volume

/// One bar: − and + step (hold to keep going); drag across the level to set it;
/// tap the level to mute.
private struct VolumeBar: View {
    @EnvironmentObject private var tv: TVConnection

    var body: some View {
        HStack(spacing: 4) {
            step("minus", shape: UnevenRoundedRectangle(topLeadingRadius: 32, bottomLeadingRadius: 32,
                                                       bottomTrailingRadius: 8, topTrailingRadius: 8),
                 action: tv.volumeDown)
            VolumeLevel()
            step("plus", shape: UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8,
                                                      bottomTrailingRadius: 32, topTrailingRadius: 32),
                 action: tv.volumeUp)
        }
    }

    private func step(_ symbol: String, shape: UnevenRoundedRectangle, action: @escaping () -> Void) -> some View {
        Key(repeats: true, shape: shape, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 76, height: 64)
        }
    }
}

private struct VolumeLevel: View {
    @EnvironmentObject private var tv: TVConnection
    @State private var start: Int?
    @State private var pressed = false
    private let ticks = UISelectionFeedbackGenerator()
    private let shape = RoundedRectangle(cornerRadius: 8)

    var body: some View {
        let level = tv.volume ?? 0
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: tv.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tv.muted ? Theme.accent : Theme.muted)
                Text(tv.volume.map { String(format: "%02d", $0) } ?? "--")
                    .font(Theme.dot(28))
                    .foregroundStyle(tv.muted ? Theme.muted : Theme.accent)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            // The level as a row of dots, out of 100.
            HStack(spacing: 4) {
                ForEach(0..<16, id: \.self) { i in
                    Circle()
                        .fill(!tv.muted && Double(i) < (Double(level) / 100 * 16).rounded(.up) ? Theme.accent : Theme.muted.opacity(0.3))
                        .frame(width: 4, height: 4)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: tv.volume)
        .animation(.easeOut(duration: 0.15), value: tv.muted)
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(pressed ? Theme.keyPressed : Theme.key, in: shape)
        .overlay(shape.stroke(Theme.hairline, lineWidth: 1))
        .shadow(color: pressed ? .clear : Theme.shadow, radius: 2, y: 1)
        .contentShape(shape)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    pressed = true
                    if start == nil { start = tv.volume ?? 0; ticks.prepare() }
                    guard let start, abs(value.translation.width) > 6 else { return }
                    let target = min(100, max(0, start + Int(value.translation.width / 6)))
                    if target != tv.volume {
                        ticks.selectionChanged()
                        tv.setVolume(target)
                    }
                }
                .onEnded { value in
                    pressed = false
                    start = nil
                    if hypot(value.translation.width, value.translation.height) < 6 {
                        haptic()
                        tv.toggleMute()
                    }
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue(tv.muted ? "Muted" : "\(level)")
        .accessibilityAdjustableAction { direction in
            if direction == .increment { tv.volumeUp() } else { tv.volumeDown() }
        }
    }
}

// MARK: - Playback

/// Rewind, play/pause, fast-forward. If the app on screen reports whether it's
/// playing, it's one key showing the true state. Most streaming apps don't, so
/// then it's play and pause side by side: each always does what it shows.
private struct Playback: View {
    @EnvironmentObject private var tv: TVConnection

    var body: some View {
        HStack(spacing: 12) {
            IconKey(symbol: "backward.fill", size: 56, repeats: true) { tv.press(.rewind) }
            if let state = tv.playState {
                let playing = state == "playing"
                Key(shape: Capsule(), action: {
                    tv.press(playing ? .pause : .play)
                    tv.playState = playing ? "paused" : "playing"   // the TV's report confirms it
                }) {
                    glyph(playing ? "pause.fill" : "play.fill")
                }
            } else {
                HStack(spacing: 4) {
                    Key(shape: UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 28,
                                                      bottomTrailingRadius: 8, topTrailingRadius: 8),
                        action: { tv.press(.play) }) { glyph("play.fill") }
                    Key(shape: UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8,
                                                      bottomTrailingRadius: 28, topTrailingRadius: 28),
                        action: { tv.press(.pause) }) { glyph("pause.fill") }
                }
            }
            IconKey(symbol: "forward.fill", size: 56, repeats: true) { tv.press(.fastForward) }
        }
        .animation(.easeOut(duration: 0.2), value: tv.playState == nil)
    }

    private func glyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .semibold))
            .contentTransition(.symbolEffect(.replace))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
    }
}

// MARK: - Power

/// Hold to turn the TV off: a ring of dots fills around the key, then it fires.
/// Let go early and it drains away.
private struct PowerKey: View {
    @EnvironmentObject private var tv: TVConnection
    @State private var progress: CGFloat = 0
    @State private var holding = false
    @State private var fired = false
    @State private var timer: Task<Void, Never>?

    private let hold: Double = 0.8

    var body: some View {
        Image(systemName: "power")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: 44, height: 44)
            .background(holding ? Theme.keyPressed : Theme.key, in: Circle())
            .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
            .overlay(
                Circle()
                    .inset(by: -5)
                    .trim(from: 0, to: progress)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0.1, 5.5]))
                    .rotationEffect(.degrees(-90))
            )
            .scaleEffect(holding ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: holding)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !holding, !fired else { return }
                        holding = true
                        haptic(.light)
                        withAnimation(.linear(duration: hold)) { progress = 1 }
                        timer = Task { @MainActor in
                            try? await Task.sleep(for: .seconds(hold))
                            guard !Task.isCancelled else { return }
                            fired = true
                            haptic(.heavy)
                            tv.powerOff()
                        }
                    }
                    .onEnded { _ in
                        timer?.cancel()
                        holding = false
                        fired = false
                        withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
                    }
            )
            .accessibilityLabel("Turn TV off")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { tv.powerOff() }
    }
}
