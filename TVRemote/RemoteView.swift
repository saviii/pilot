import SwiftUI

/// Laid out like LG's own remote, top to bottom: power and inputs, app
/// shortcut keys, the click wheel, back and home, volume, then playback.
/// No channel keys: everything here is apps, so up and down is the wheel's job.
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
            Playback(sheet: $sheet)
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
                case .numbers: NumberPadSheet().presentationDetents([.height(470)])
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
    case keyboard, inputs, numbers, apps
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
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                Button("Forget this TV", role: .destructive) { tv.forget() }
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                    Caption("LG · \(tv.host ?? "")")
                }
                .frame(height: 44)
            }
            Spacer()
            IconKey(symbol: "cable.connector", size: 44) { sheet = .inputs }
            IconKey(symbol: "gearshape.fill", size: 44) { tv.press(.settings) }
            IconKey(symbol: "power", size: 44, tint: Theme.accent) { tv.powerOff() }
        }
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
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pinned) { app in
                        Button {
                            haptic()
                            tv.launch(app)
                        } label: {
                            AppIcon(app: app, inset: 4).frame(width: 66, height: 50)
                        }
                        .buttonStyle(KeyStyle(shape: RoundedRectangle(cornerRadius: 14)))
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()

            Key(shape: RoundedRectangle(cornerRadius: 14), action: { sheet = .apps }) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 50, height: 50)
            }
        }
        .onAppear { pins.seedIfNeeded(with: tv.shortcuts) }
        .onChange(of: tv.apps) { pins.seedIfNeeded(with: tv.shortcuts) }
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

                if let active, active != .ok {
                    Wedge(zone: active, inner: inner)
                        .fill(Theme.keyPressed)
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
                            haptic()
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
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(active == zone ? Theme.accent : Theme.muted)
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
        haptic()
        tv.press(button)
        repeating = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            while !Task.isCancelled {
                haptic()
                tv.press(button)
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
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

/// One bar: hold − or + to keep going, tap the level to mute.
private struct VolumeBar: View {
    @EnvironmentObject private var tv: TVConnection

    var body: some View {
        HStack(spacing: 4) {
            step("minus", shape: UnevenRoundedRectangle(topLeadingRadius: 32, bottomLeadingRadius: 32,
                                                       bottomTrailingRadius: 8, topTrailingRadius: 8),
                 action: tv.volumeDown)

            Key(shape: RoundedRectangle(cornerRadius: 8), action: tv.toggleMute) {
                HStack(spacing: 10) {
                    Image(systemName: tv.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tv.muted ? Theme.accent : Theme.muted)
                        .frame(width: 22)
                    Text(tv.volume.map { String(format: "%02d", $0) } ?? "--")
                        .font(Theme.dot(34))
                        .foregroundStyle(tv.muted ? Theme.muted : Theme.accent)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.15), value: tv.volume)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 64)
            }

            step("plus", shape: UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8,
                                                      bottomTrailingRadius: 32, topTrailingRadius: 32),
                 action: tv.volumeUp)
        }
    }

    private func step(_ symbol: String, shape: UnevenRoundedRectangle, action: @escaping () -> Void) -> some View {
        Key(repeats: true, shape: shape, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 84, height: 64)
        }
    }
}

// MARK: - Playback

private struct Playback: View {
    @EnvironmentObject private var tv: TVConnection
    @Binding var sheet: Sheet?

    var body: some View {
        HStack {
            IconKey(symbol: "backward.fill", size: 50, repeats: true) { tv.press(.rewind) }
            Spacer()
            IconKey(symbol: "play.fill", size: 50) { tv.press(.play) }
            Spacer()
            IconKey(symbol: "pause.fill", size: 50) { tv.press(.pause) }
            Spacer()
            IconKey(symbol: "forward.fill", size: 50, repeats: true) { tv.press(.fastForward) }
            Spacer()
            Key(shape: Circle(), action: { sheet = .numbers }) {
                Text("123")
                    .font(Theme.mono(11))
                    .frame(width: 50, height: 50)
            }
        }
    }
}
