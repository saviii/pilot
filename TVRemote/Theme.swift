import SwiftUI

/// Colors and type from savi.fyi's default dark scheme.
enum Theme {
    static let background = Color(red: 13 / 255, green: 4 / 255, blue: 2 / 255)
    static let key = Color(red: 28 / 255, green: 12 / 255, blue: 9 / 255)
    static let keyPressed = Color(red: 44 / 255, green: 19 / 255, blue: 13 / 255)
    static let ink = Color(red: 255 / 255, green: 236 / 255, blue: 228 / 255)
    static let muted = ink.opacity(0.45)
    static let hairline = Color.white.opacity(0.07)
    static let accent = Color(red: 255 / 255, green: 85 / 255, blue: 26 / 255)

    /// Doto, the dot-matrix face, for numbers.
    static func dot(_ size: CGFloat) -> Font { .custom("Doto", size: size).weight(.black) }
    /// Martian Mono, for small labels.
    static func mono(_ size: CGFloat) -> Font { .custom("Martian Mono", size: size).weight(.medium) }
}

func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}

/// A key that fires on release, or repeats while held (arrows, volume),
/// with an optional long-press action (hold Back to exit, like LG's remote).
struct Key<Label: View, Background: Shape>: View {
    var repeats = false
    var longPress: (() -> Void)?
    let shape: Background
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var pressed = false
    @State private var holding: Task<Void, Never>?
    @State private var consumed = false

    var body: some View {
        label()
            .foregroundStyle(Theme.ink)
            .background(pressed ? Theme.keyPressed : Theme.key, in: shape)
            .overlay(shape.stroke(Theme.hairline, lineWidth: 1))
            .contentShape(shape)
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: pressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        consumed = false
                        startHolding()
                    }
                    .onEnded { _ in
                        holding?.cancel()
                        pressed = false
                        if !repeats && !consumed { fire(action) }
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }

    private func startHolding() {
        if repeats {
            fire(action)
            holding = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                while !Task.isCancelled {
                    fire(action)
                    try? await Task.sleep(for: .milliseconds(120))
                }
            }
        } else if let longPress {
            holding = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(550))
                guard !Task.isCancelled else { return }
                consumed = true
                fire(longPress, .medium)
            }
        }
    }

    private func fire(_ run: () -> Void, _ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        haptic(style)
        run()
    }
}

/// The common case: a round key with an SF Symbol.
struct IconKey: View {
    let symbol: String
    var size: CGFloat = 56
    var tint: Color = Theme.ink
    var repeats = false
    var longPress: (() -> Void)?
    let action: () -> Void

    var body: some View {
        Key(repeats: repeats, longPress: longPress, shape: Circle(), action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
        }
    }
}

/// A tiny Martian Mono caption under or beside a control.
struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(9))
            .tracking(1.2)
            .foregroundStyle(Theme.muted)
    }
}
