import SwiftUI

/// Laid out like LG's own remote, top to bottom: power and inputs, app
/// shortcut keys, the click wheel, back and home, volume and channel
/// rockers, then playback.
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
            .frame(maxWidth: 290, maxHeight: 290)
            .aspectRatio(1, contentMode: .fit)

            Spacer(minLength: 16)
            HStack {
                IconKey(symbol: "arrow.uturn.backward", longPress: { tv.press(.exit) }) { tv.press(.back) }
                Spacer()
                IconKey(symbol: "house.fill") { tv.press(.home) }
                Spacer()
                IconKey(symbol: "cursorarrow", tint: pointer ? Theme.accent : Theme.ink) { pointer.toggle() }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 16)
            Rockers(sheet: $sheet)
            Spacer(minLength: 16)
            Playback(sheet: $sheet)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Theme.background.ignoresSafeArea())
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

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(Theme.accent).frame(width: 6, height: 6)
                Caption("LG · \(tv.host ?? "")")
            }
            .contextMenu {
                Button("Forget this TV", role: .destructive) { tv.forget() }
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

    var body: some View {
        HStack(spacing: 8) {
            ForEach(tv.shortcuts) { app in
                Key(shape: RoundedRectangle(cornerRadius: 14), action: { tv.launch(app) }) {
                    AppIcon(app: app, size: 26)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
            }
            Key(shape: RoundedRectangle(cornerRadius: 14), action: { sheet = .apps }) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
        }
    }
}

struct AppIcon: View {
    let app: TVConnection.App
    var size: CGFloat

    var body: some View {
        AsyncImage(url: app.icon) { image in
            image.resizable().scaledToFit()
                .frame(width: size * 1.6, height: size * 1.6)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } placeholder: {
            Text(app.title)
                .font(Theme.mono(9))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 4)
        }
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

// MARK: - Volume and channel

private struct Rockers: View {
    @EnvironmentObject private var tv: TVConnection
    @Binding var sheet: Sheet?

    var body: some View {
        HStack(alignment: .center) {
            Rocker(label: "VOL", up: "plus", down: "minus", onUp: tv.volumeUp, onDown: tv.volumeDown)
            Spacer()
            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    Text(tv.muted ? "--" : tv.volume.map { String(format: "%02d", $0) } ?? "--")
                        .font(Theme.dot(46))
                        .foregroundStyle(tv.muted ? Theme.muted : Theme.accent)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.15), value: tv.volume)
                    Caption(tv.muted ? "Muted" : "Volume")
                }
                HStack(spacing: 12) {
                    IconKey(symbol: "speaker.slash.fill", size: 48,
                            tint: tv.muted ? Theme.accent : Theme.ink) { tv.toggleMute() }
                    IconKey(symbol: "keyboard", size: 48) { sheet = .keyboard }
                }
            }
            Spacer()
            Rocker(label: "CH", up: "chevron.up", down: "chevron.down",
                   onUp: { tv.press(.channelUp) }, onDown: { tv.press(.channelDown) })
        }
    }
}

private struct Rocker: View {
    let label: String
    let up: String
    let down: String
    let onUp: () -> Void
    let onDown: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            half(up, top: true, action: onUp)
            Caption(label).frame(height: 26)
            half(down, top: false, action: onDown)
        }
    }

    private func half(_ symbol: String, top: Bool, action: @escaping () -> Void) -> some View {
        let big: CGFloat = 32, small: CGFloat = 8
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: top ? big : small, bottomLeadingRadius: top ? small : big,
            bottomTrailingRadius: top ? small : big, topTrailingRadius: top ? big : small)
        return Key(repeats: true, shape: shape, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .frame(width: 64, height: 66)
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
