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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(Look.accent).frame(width: 6, height: 6)
                Text(state.tv.uppercased()).font(Look.mono(10)).foregroundStyle(Look.muted)
                if let app = state.app {
                    Text("· \(app)").font(.caption).foregroundStyle(Look.ink.opacity(0.8)).lineLimit(1)
                }
                Spacer()
                Level(state: state, size: 24)
            }
            Controls()
        }
        .padding(16)
        .foregroundStyle(Look.ink)
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

/// − + for volume, then play and pause.
private struct Controls: View {
    var body: some View {
        HStack(spacing: 8) {
            key("minus", .volumeDown)
            key("plus", .volumeUp)
            Spacer(minLength: 12)
            key("play.fill", .play)
            key("pause.fill", .pause)
        }
    }

    private func key(_ symbol: String, _ action: TVAction) -> some View {
        Button(intent: TVActionIntent(action)) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 56, height: 40)
                .background(Look.key, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Look.ink)
    }
}
