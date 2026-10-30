import ActivityKit
import AppIntents
import Foundation

/// The Lock Screen / Dynamic Island panel that stays up after you leave Pilot.
struct PilotActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var tv: String
        var app: String?
        var appColor: String? = nil
        var volume: Int?
        var muted: Bool
    }
}

enum TVAction: String, AppEnum {
    case volumeDown, volumeUp, play, pause

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "TV action"
    static var caseDisplayRepresentations: [TVAction: DisplayRepresentation] = [
        .volumeDown: "Volume down", .volumeUp: "Volume up", .play: "Play", .pause: "Pause",
    ]
}

/// A button on the panel. iOS runs it in the app, woken in the background for a moment.
struct TVActionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Control the TV"
    static var isDiscoverable = false
    /// Volume and pause are harmless: no unlocking needed on the Lock Screen.
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var openAppWhenRun = false

    @Parameter(title: "Action") var action: TVAction

    init() {}
    init(_ action: TVAction) { self.action = action }

    func perform() async throws -> some IntentResult {
        #if APP
            await LiveRemote.run(action)
        #endif
        return .result()
    }
}
