import ActivityKit
import Foundation

/// Starts, updates and ends the Lock Screen panel, and carries out its buttons.
@MainActor
enum LiveRemote {
    private static var activity: Activity<PilotActivityAttributes>? {
        Activity<PilotActivityAttributes>.activities.first
    }

    private static func state(_ tv: TVConnection) -> PilotActivityAttributes.ContentState {
        .init(tv: tv.current?.name ?? "TV", app: tv.foregroundApp?.title ?? tv.foregroundInput?.label,
              volume: tv.volume, muted: tv.muted)
    }

    /// You left Pilot while connected: put the panel up.
    static func start(_ tv: TVConnection) {
        guard tv.state == .connected, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if activity != nil { return update(tv) }
        _ = try? Activity.request(attributes: PilotActivityAttributes(),
                                  content: .init(state: state(tv), staleDate: nil))
    }

    static func update(_ tv: TVConnection) {
        guard let activity else { return }
        let content = ActivityContent(state: state(tv), staleDate: nil)
        Task { await activity.update(content) }
    }

    /// Back in Pilot (or the TV went off): the panel isn't needed.
    static func end() {
        for activity in Activity<PilotActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// A panel button: reconnect if iOS froze us, send it, then refresh the panel.
    static func run(_ action: TVAction) async {
        let tv = TVConnection.shared
        if tv.state != .connected { tv.reconnect() }
        guard await tv.waitUntilConnected(seconds: 4) else { return }
        switch action {
        case .volumeDown: tv.volumeDown()
        case .volumeUp: tv.volumeUp()
        case .play: tv.play()
        case .pause: tv.pause()
        }
        // Give the TV a moment to report the new volume.
        try? await Task.sleep(for: .milliseconds(400))
        update(tv)
    }
}
