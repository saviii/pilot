import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct PilotWidgets: WidgetBundle {
    var body: some Widget { PilotLiveActivity() }
}

/// Colors and type from savi.fyi's dark scheme (the Lock Screen panel is always dark).
private enum Look {
    static let background = Color(red: 13 / 255, green: 4 / 255, blue: 2 / 255)
    static let key = Color(red: 34 / 255, green: 15 / 255, blue: 11 / 255)
    static let ink = Color(red: 255 / 255, green: 236 / 255, blue: 228 / 255)
    static let muted = ink.opacity(0.5)
    static let accent = Color(red: 255 / 255, green: 85 / 255, blue: 26 / 255)
    static func dot(_ size: CGFloat) -> Font { .custom("Doto", size: size).weight(.black) }
    static func mono(_ size: CGFloat) -> Font { .custom("Martian Mono", size: size).weight(.medium) }
}

struct PilotLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PilotActivityAttributes.self) { context in
            LockScreenPanel(state: context.state)
                .activityBackgroundTint(Look.background)
                .activitySystemActionForegroundColor(Look.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.tv.uppercased(), systemImage: "tv")
                        .font(Look.mono(10))
                        .foregroundStyle(Look.muted)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Level(state: context.state, size: 22).padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Controls().padding(.top, 6)
                }
            } compactLeading: {
                Image(systemName: "tv").foregroundStyle(Look.accent)
            } compactTrailing: {
                Level(state: context.state, size: 15)
            } minimal: {
                Image(systemName: "tv").foregroundStyle(Look.accent)
            }
        }
    }
}

private struct LockScreenPanel: View {
    let state: PilotActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                // What's on, in its own color.
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(color(state.appColor) ?? Look.key)
                    Text(state.app.map { String($0.prefix(1)) } ?? "")
                        .font(Look.mono(12))
                        .foregroundStyle(state.appColor == "#ffffff" ? Color.black : Color.white)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.app ?? "TV").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text("PILOT · \(state.tv.uppercased())").font(Look.mono(9)).foregroundStyle(Look.muted).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Level(state: state, size: 26)
                    Meter(state: state)
                }
            }
            Controls()
        }
        .padding(16)
        .foregroundStyle(Look.ink)
    }

    private func color(_ hex: String?) -> Color? {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let v = Int(hex.dropFirst(), radix: 16) else { return nil }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// The level as a row of dots, out of 100.
private struct Meter: View {
    let state: PilotActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<8, id: \.self) { i in
                Circle()
                    .fill(!state.muted && Double(i) < (Double(state.volume ?? 0) / 100 * 8).rounded(.up) ? Look.accent : Look.ink.opacity(0.2))
                    .frame(width: 3, height: 3)
            }
        }
    }
}

/// The volume in Doto, or "--" when muted.
private struct Level: View {
    let state: PilotActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        Text(state.muted ? "--" : state.volume.map { String(format: "%02d", $0) } ?? "--")
            .font(Look.dot(size))
            .foregroundStyle(state.muted ? Look.muted : Look.accent)
            .monospacedDigit()
    }
}

/// − + for volume, then play and pause: two split keys, like the remote.
private struct Controls: View {
    var body: some View {
        HStack(spacing: 6) {
            key("minus", .volumeDown, leading: true)
            key("plus", .volumeUp, leading: false)
            Spacer(minLength: 10)
            key("play.fill", .play, leading: true)
            key("pause.fill", .pause, leading: false)
        }
    }

    private func key(_ symbol: String, _ action: TVAction, leading: Bool) -> some View {
        Button(intent: TVActionIntent(action)) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    Look.key,
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: leading ? 22 : 8, bottomLeadingRadius: leading ? 22 : 8,
                        bottomTrailingRadius: leading ? 8 : 22, topTrailingRadius: leading ? 8 : 22))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Look.ink)
    }
}
