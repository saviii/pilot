import Foundation
import PilotKit

/// One volume for the main bar and the side buttons: when the Sonos is playing
/// the TV's sound, what you hear is the Sonos, so that's the number to show and
/// move. Otherwise it's the TV's own volume.
@MainActor
enum Loudness {
    static func usesSonos(_ sonos: Sonos) -> Bool {
        Volume.source(sonosFound: sonos.host != nil, sonosReachable: sonos.reachable, sonosPlayingTV: sonos.onTV) == .sonos
    }

    static func level(_ tv: TVConnection, _ sonos: Sonos) -> Int? { usesSonos(sonos) ? sonos.volume : tv.volume }
    static func muted(_ tv: TVConnection, _ sonos: Sonos) -> Bool { usesSonos(sonos) ? sonos.muted : tv.muted }

    /// Sonos steps by 2 so a press feels like the TV's remote does through it.
    static func up(_ tv: TVConnection, _ sonos: Sonos) { usesSonos(sonos) ? sonos.nudge(2) : tv.volumeUp() }
    static func down(_ tv: TVConnection, _ sonos: Sonos) { usesSonos(sonos) ? sonos.nudge(-2) : tv.volumeDown() }
    static func set(_ level: Int, _ tv: TVConnection, _ sonos: Sonos) { usesSonos(sonos) ? sonos.setVolume(level) : tv.setVolume(level) }
    static func toggleMute(_ tv: TVConnection, _ sonos: Sonos) { usesSonos(sonos) ? sonos.toggleMute() : tv.toggleMute() }
}
