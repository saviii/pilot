import SwiftUI

/// System, light or dark. Stored, and applied at the app's root.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
    var next: Appearance {
        switch self {
        case .system: .light
        case .light: .dark
        case .dark: .system
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Colors and type from savi.fyi's default scheme, light and dark.
enum Theme {
    static let background = adaptive(light: (246, 240, 236), dark: (13, 4, 2))
    static let key = adaptive(light: (252, 250, 248), dark: (28, 12, 9))
    static let keyPressed = adaptive(light: (236, 227, 221), dark: (44, 19, 13))
    static let ink = adaptive(light: (27, 14, 9), dark: (255, 236, 228))
    static let muted = adaptive(light: (27, 14, 9, 0.55), dark: (255, 236, 228, 0.45))
    static let hairline = adaptive(light: (27, 14, 9, 0.09), dark: (255, 255, 255, 0.07))
    static let shadow = adaptive(light: (27, 14, 9, 0.06), dark: (0, 0, 0, 0))
    static let accent = adaptive(light: (226, 62, 26), dark: (255, 85, 26))

    private static func adaptive(light: (Int, Int, Int), dark: (Int, Int, Int)) -> Color {
        adaptive(light: (light.0, light.1, light.2, 1), dark: (dark.0, dark.1, dark.2, 1))
    }

    private static func adaptive(light: (Int, Int, Int, Double), dark: (Int, Int, Int, Double)) -> Color {
        Color(UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: c.3)
        })
    }

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
            .shadow(color: pressed ? .clear : Theme.shadow, radius: 2, y: 1)
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

/// The same look as `Key`, as a ButtonStyle, for keys inside scroll views
/// (a Button lets the scroll view take the drag; Key's gesture would swallow it).
struct KeyStyle<S: Shape>: ButtonStyle {
    let shape: S

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.ink)
            .background(configuration.isPressed ? Theme.keyPressed : Theme.key, in: shape)
            .overlay(shape.stroke(Theme.hairline, lineWidth: 1))
            .shadow(color: configuration.isPressed ? .clear : Theme.shadow, radius: 2, y: 1)
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The apps you've put in the top strip, in the order you added them.
/// Stored as app ids; seeded once with LG's own shortcut keys.
struct Pins: DynamicProperty {
    @AppStorage("pins") private var raw = ""
    @AppStorage("pinsSeeded") private var seeded = false

    var ids: [String] {
        get { raw.split(separator: ",").map(String.init) }
        nonmutating set { raw = newValue.joined(separator: ",") }
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    func toggle(_ id: String) {
        if contains(id) { ids.removeAll { $0 == id } } else { ids.append(id) }
    }

    func seedIfNeeded(with apps: [TVConnection.App]) {
        guard !seeded, !apps.isEmpty else { return }
        ids = apps.map(\.id)
        seeded = true
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

/// Presses in slightly, for buttons that aren't keys (the tiles in the apps sheet).
struct Pressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
