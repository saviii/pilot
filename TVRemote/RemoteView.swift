import SwiftUI

/// One three-column grid, after a real remote: power, what's on and remote
/// settings across the top; the wheel; back, home and type; playback; the
/// volume rocker with mute, Sonos, pointer and screenshot beside it; then your
/// six apps. No channel or number keys: everything here is apps.
struct RemoteView: View {
    @EnvironmentObject private var tv: TVConnection
    @StateObject private var pointer = AirPointer()
    @StateObject private var buttons = VolumeButtons()
    @ObservedObject private var sonos = Sonos.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: Sheet?
    @AppStorage("appearance") private var appearance: Appearance = .system

    var body: some View {
        VStack(spacing: 0) {
            TopRow(sheet: $sheet)
            Spacer(minLength: 14)
            ClickWheel()
                .frame(maxWidth: 250, maxHeight: 250)
                .aspectRatio(1, contentMode: .fit)
            Spacer(minLength: 14)
            KeyGrid(sheet: $sheet)
            Spacer(minLength: 14)
            SixApps(sheet: $sheet)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Theme.background.ignoresSafeArea())
        .environmentObject(pointer)
        .environmentObject(sonos)
        .task {
            await sonos.findIfNeeded()
            // Keep the Sonos's level current, so the rocker shows what you hear.
            while !Task.isCancelled {
                await sonos.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        // The phone's side buttons turn the TV up and down while Pilot is open.
        .background(HiddenVolumeView(buttons: buttons).frame(width: 1, height: 1).offset(x: -200))
        .onAppear { buttons.start(up: { Loudness.up(tv, sonos) }, down: { Loudness.down(tv, sonos) }) }
        .onDisappear { buttons.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { buttons.start(up: { Loudness.up(tv, sonos) }, down: { Loudness.down(tv, sonos) }) } else { buttons.stop() }
        }
        // The phone's keyboard covers the remote rather than squashing it.
        .ignoresSafeArea(.keyboard)
        #if DEBUG
            .onAppear {
                if CommandLine.arguments.contains("-apps") { sheet = .remote }
                if CommandLine.arguments.contains("-tvs") { sheet = .tvs }
                if CommandLine.arguments.contains("-kb") { sheet = .keyboard }
                if CommandLine.arguments.contains("-sonos") {
                    Task {
                        await sonos.findIfNeeded(); sheet = .sonos
                    }
                }
            }
        #endif
        // When the TV asks for text, the keyboard comes up on its own, and goes when the TV's does.
        .onChange(of: tv.keyboardOpen) { _, open in
            if open, sheet == nil { sheet = .keyboard }
            if !open, sheet == .keyboard { sheet = nil }
        }
        .sheet(item: $sheet) { kind in
            Group {
                switch kind {
                case .keyboard: KeyboardSheet().presentationDetents([.height(320)])
                case .inputs: InputsSheet().presentationDetents([.medium, .large])
                case .remote: RemoteSettingsSheet().presentationDetents([.large])
                case .sonos: SonosSheet().environmentObject(sonos).presentationDetents([.large])
                case .screenshot: ScreenshotSheet().presentationDetents([.height(400)])
                case .tvs: TVsSheet().presentationDetents([.height(CGFloat(250 + tv.saved.count * 100 + (tv.inputs.isEmpty ? 0 : 96)))])
                }
            }
            .presentationBackground(Theme.background)
            .presentationDragIndicator(.visible)
            // Sheets are their own windows: give them the same appearance as the remote.
            .preferredColorScheme(appearance.scheme)
            .environmentObject(tv)
        }
    }
}

enum Sheet: String, Identifiable {
    case keyboard, inputs, remote, tvs, screenshot, sonos
    var id: String { rawValue }
}

// MARK: - Top row

/// Power in its corner, what's on in the middle (opens your TVs and inputs),
/// remote settings opposite.
private struct TopRow: View {
    @EnvironmentObject private var tv: TVConnection
    @Binding var sheet: Sheet?

    var body: some View {
        HStack(spacing: 12) {
            PowerKey()
            Spacer(minLength: 0)
            Button {
                haptic()
                sheet = .tvs
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        if tv.state == .connected, let app = tv.foregroundApp {
                            AppIcon(app: app, radius: 18, inset: 4)
                        } else if tv.state == .connected, let input = tv.foregroundInput {
                            Circle().fill(Theme.background)
                            Text(input.port.map(String.init) ?? "").font(Theme.dot(17)).foregroundStyle(Theme.accent)
                        } else {
                            Circle().fill(Theme.background)
                            Image(systemName: "tv").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        HStack(spacing: 5) {
                            Circle().fill(tv.state == .connected ? Theme.accent : Theme.muted).frame(width: 4, height: 4)
                            Caption(tv.current?.name ?? "LG TV").lineLimit(1)
                        }
                    }
                }
                .padding(.leading, 6)
                .padding(.trailing, 18)
                .frame(height: 48)
                .background(Theme.key, in: Capsule())
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                .shadow(color: Theme.shadow, radius: 2, y: 1)
                .animation(.easeOut(duration: 0.2), value: tv.foreground)
                .contentShape(Capsule())
            }
            .buttonStyle(Pressable())
            .foregroundStyle(Theme.ink)
            .layoutPriority(1)
            Spacer(minLength: 0)
            Key(shape: Circle(), action: { sheet = .remote }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel("Remote settings")
        }
    }

    private var title: String {
        if tv.state == .connected { return tv.foregroundApp?.title ?? tv.foregroundInput?.label ?? "Home" }
        if tv.waking { return "Turning on" }
        // Still trying vs. given up: after a few quiet retries, the TV is off (or away).
        if tv.unreachable { return "TV is off" }
        return "Connecting"
    }
}

/// An app's tile, the way the TV draws it: its icon on its brand color.
struct AppIcon: View {
    @EnvironmentObject private var tv: TVConnection
    let app: TVConnection.App
    var radius: CGFloat = 14
    var inset: CGFloat = 6
    /// Enlarge the TV's icon art inside its frame (its own background fills the rest).
    var zoom: CGFloat = 1
    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Color(hex: app.color) ?? Theme.key)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().padding(inset).scaleEffect(zoom)
                } else {
                    // Until the logo arrives: the name, else its first word, else its first letter,
                    // in a color that reads on the app's own (white on dark, dark on pale).
                    ViewThatFits(in: .horizontal) {
                        Text(app.title).lineLimit(1).fixedSize()
                        Text(app.title.split(whereSeparator: { " :".contains($0) }).first.map(String.init) ?? app.title)
                            .lineLimit(1).fixedSize()
                        Text(app.title.prefix(1))
                    }
                    .font(Theme.mono(9))
                    .foregroundStyle(app.color == nil ? Theme.ink : (Color.isPale(app.color) ? Color.black.opacity(0.8) : Color.white))
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
    /// White or near-white ("#ffffff"): it needs a stronger outline to show its edge.
    static func isPale(_ hex: String?) -> Bool {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let v = Int(hex.dropFirst(), radix: 16) else { return false }
        let r = Double((v >> 16) & 0xFF), g = Double((v >> 8) & 0xFF), b = Double(v & 0xFF)
        return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 > 0.85
    }

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
    @EnvironmentObject private var pointer: AirPointer
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
                VStack(spacing: 6) {
                    Text("OK").font(Theme.mono(15))
                    if pointer.active {
                        // While pointing, OK clicks where the pointer is.
                        Text("CLICK").font(Theme.mono(8)).tracking(1.4)
                            .foregroundStyle(active == .ok ? Theme.background : Theme.accent)
                            .transition(.opacity)
                    }
                }
                .foregroundStyle(active == .ok ? Theme.background : Theme.ink)
                .animation(.easeOut(duration: 0.15), value: pointer.active)
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
                            // While you're pointing (or just were), OK clicks where the pointer is.
                            if pointer.recentlyUsed { tv.click() } else { tv.press(.enter) }
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
        let button: TVConnection.Button =
            switch zone {
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
                    let nearArrow = [
                        CGPoint(x: 0, y: marker), CGPoint(x: 0, y: -marker),
                        CGPoint(x: marker, y: 0), CGPoint(x: -marker, y: 0),
                    ]
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
        let mid: Double =
            switch zone {
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

// MARK: - The grid

/// Three equal columns, every key the same height.
private struct KeyGrid: View {
    @EnvironmentObject private var tv: TVConnection
    @EnvironmentObject private var sonos: Sonos
    @Binding var sheet: Sheet?

    private let height: CGFloat = 54
    private let gap: CGFloat = 10

    var body: some View {
        VStack(spacing: gap) {
            HStack(spacing: gap) {
                // Hold Back to leave the app, like LG's remote. Not on an HDMI input:
                // there EXIT leaves the console for the TV's input picker.
                Key(longPress: tv.foregroundInput == nil ? { tv.press(.exit) } : nil, shape: Capsule(), action: { tv.press(.back) }) {
                    glyph("arrow.uturn.backward")
                }
                .accessibilityLabel("Back")
                Key(shape: Capsule(), action: { tv.press(.home) }) { glyph("house.fill") }
                    .accessibilityLabel("Home")
                Key(shape: Capsule(), action: { sheet = .keyboard }) { glyph("keyboard") }
                    .accessibilityLabel("Type on the TV")
            }

            HStack(spacing: gap) {
                Key(repeats: true, shape: Capsule(), action: { tv.press(.rewind) }) { glyph("backward.fill") }
                    .accessibilityLabel("Rewind")
                PlayPause()
                Key(repeats: true, shape: Capsule(), action: { tv.press(.fastForward) }) { glyph("forward.fill") }
                    .accessibilityLabel("Fast forward")
            }

            HStack(alignment: .top, spacing: gap) {
                VolumeRocker()
                VStack(spacing: gap) {
                    let muted = Loudness.muted(tv, sonos)
                    Key(shape: Capsule(), action: { Loudness.toggleMute(tv, sonos) }) {
                        glyph(muted ? "speaker.slash.fill" : "speaker.slash", tint: muted ? Theme.accent : Theme.ink)
                    }
                    .accessibilityLabel(muted ? "Unmute" : "Mute")
                    if sonos.host != nil {
                        Key(shape: Capsule(), action: { sheet = .sonos }) { glyph("hifispeaker.2.fill") }
                            .accessibilityLabel("Sonos")
                    } else {
                        Key(shape: Capsule(), action: { sheet = .inputs }) { glyph("cable.connector") }
                            .accessibilityLabel("Inputs")
                    }
                }
                VStack(spacing: gap) {
                    PointerKey()
                    Key(shape: Capsule(), action: { sheet = .screenshot }) { glyph("camera") }
                        .accessibilityLabel("Screenshot the TV")
                }
            }
        }
    }

    private func glyph(_ symbol: String, tint: Color = Theme.ink) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }
}

/// Play and pause. If the app on screen says whether it's playing, one key with
/// the true state; most streaming apps don't, so then both, side by side.
private struct PlayPause: View {
    @EnvironmentObject private var tv: TVConnection

    var body: some View {
        if let state = tv.playState {
            let playing = state == "playing"
            Key(
                shape: Capsule(),
                action: {
                    tv.press(playing ? .pause : .play)
                    tv.playState = playing ? "paused" : "playing"  // the TV's report confirms it
                }
            ) {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .accessibilityLabel(playing ? "Pause" : "Play")
        } else {
            HStack(spacing: 2) {
                Key(
                    shape: UnevenRoundedRectangle(
                        topLeadingRadius: 27, bottomLeadingRadius: 27,
                        bottomTrailingRadius: 6, topTrailingRadius: 6),
                    action: { tv.press(.play) }
                ) { half("play.fill") }
                .accessibilityLabel("Play")
                Key(
                    shape: UnevenRoundedRectangle(
                        topLeadingRadius: 6, bottomLeadingRadius: 6,
                        bottomTrailingRadius: 27, topTrailingRadius: 27),
                    action: { tv.press(.pause) }
                ) { half("pause.fill") }
                .accessibilityLabel("Pause")
            }
        }
    }

    private func half(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
    }
}

/// Volume as a tall rocker: hold + or − to keep going; the level in Doto between.
/// It's the Sonos's level when the Sonos is playing the TV (that's what you hear).
private struct VolumeRocker: View {
    @EnvironmentObject private var tv: TVConnection
    @EnvironmentObject private var sonos: Sonos

    var body: some View {
        let muted = Loudness.muted(tv, sonos)
        let level = Loudness.level(tv, sonos)
        VStack(spacing: 0) {
            Key(repeats: true, shape: Rectangle(), action: { Loudness.up(tv, sonos) }) {
                Image(systemName: "plus").font(.system(size: 17, weight: .bold))
                    .frame(maxWidth: .infinity).frame(height: 40)
            }
            Text(muted ? "--" : level.map { String(format: "%02d", $0) } ?? "--")
                .font(Theme.dot(22))
                .foregroundStyle(muted ? Theme.muted : Theme.accent)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.15), value: level)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Theme.key)
            Key(repeats: true, shape: Rectangle(), action: { Loudness.down(tv, sonos) }) {
                Image(systemName: "minus").font(.system(size: 17, weight: .bold))
                    .frame(maxWidth: .infinity).frame(height: 40)
            }
        }
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
        .shadow(color: Theme.shadow, radius: 2, y: 1)
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue(muted ? "Muted" : "\(level ?? 0)")
        .accessibilityAdjustableAction { direction in
            if direction == .increment { Loudness.up(tv, sonos) } else { Loudness.down(tv, sonos) }
        }
    }
}

// MARK: - Pointer

/// Hold to point: the TV's pointer follows the phone while the key is down.
private struct PointerKey: View {
    @EnvironmentObject private var tv: TVConnection
    @EnvironmentObject private var pointer: AirPointer

    var body: some View {
        Image(systemName: "cursorarrow.rays")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(pointer.active ? Theme.background : Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(pointer.active ? Theme.accent : Theme.key, in: Capsule())
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
            .shadow(color: pointer.active ? .clear : Theme.shadow, radius: 2, y: 1)
            .scaleEffect(pointer.active ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: pointer.active)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pointer.active else { return }
                        haptic(.medium)
                        pointer.start(tv)
                    }
                    .onEnded { _ in
                        haptic(.light)
                        pointer.stop()
                    }
            )
            .onDisappear { pointer.stop() }
            .accessibilityLabel("Point")
            .accessibilityHint("Hold and move the phone to move the TV's pointer")
    }
}

// MARK: - Your six

/// The six app pills, on the same three columns. The one on the TV right now
/// gets an orange ring. An empty slot is a dotted outline; it opens remote settings.
private struct SixApps: View {
    @EnvironmentObject private var tv: TVConnection
    @Binding var sheet: Sheet?
    private let pins = Pins()

    private var slots: [TVConnection.App?] {
        let apps = pins.ids.compactMap { id in tv.apps.first { $0.id == id } }
        return (0..<6).map { $0 < apps.count ? apps[$0] : nil }
    }

    var body: some View {
        let slots = slots
        VStack(spacing: 10) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { col in slot(slots[row * 3 + col]) }
                }
            }
        }
        .onAppear { pins.seedIfNeeded(with: tv.shortcuts) }
        .onChange(of: tv.apps) { pins.seedIfNeeded(with: tv.shortcuts) }
    }

    @ViewBuilder
    private func slot(_ app: TVConnection.App?) -> some View {
        if let app {
            // The app's own color edge to edge, its logo large; an outline and a shadow
            // keep the edge clear even when the color is close to the background.
            Button {
                haptic()
                tv.launch(app)
            } label: {
                AppIcon(app: app, radius: 22, inset: 0, zoom: 1.35)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    // White pills get a dark line just inside the edge, in both modes: a light one blurs into the white.
                    .overlay(
                        Color.isPale(app.color)
                            ? Capsule().strokeBorder(Color.black.opacity(0.22), lineWidth: 1)
                            : Capsule().strokeBorder(Theme.ink.opacity(0.14), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            }
            .buttonStyle(Pressable())
            .overlay(Capsule().stroke(Theme.accent, lineWidth: 2).opacity(tv.foreground == app.id ? 1 : 0))
            .animation(.easeOut(duration: 0.2), value: tv.foreground)
            .accessibilityLabel(app.title)
        } else {
            Button {
                haptic()
                sheet = .remote
            } label: {
                Capsule()
                    .strokeBorder(Theme.muted.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, 6]))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Capsule())
            }
            .buttonStyle(Pressable())
            .accessibilityLabel("Add an app")
        }
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
        if tv.state != .connected && tv.canWake {
            // Off: one tap turns it on (nothing to guard against).
            Key(shape: Circle(), action: { tv.wake() }) {
                Image(systemName: "power")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tv.waking ? Theme.muted : Theme.accent)
                    .frame(width: 48, height: 48)
                    .symbolEffect(.pulse, isActive: tv.waking)
            }
            .accessibilityLabel("Turn TV on")
        } else {
            offKey
        }
    }

    private var offKey: some View {
        Image(systemName: "power")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: 48, height: 48)
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
