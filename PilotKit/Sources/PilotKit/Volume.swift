import Foundation

/// Which volume Pilot shows and moves, everywhere: the main bar, the side buttons and the
/// Lock Screen panel. When the Sonos is playing the TV's sound, what you hear is the Sonos.
public enum Volume {
    public enum Source: Equatable, Sendable { case tv, sonos }

    public static func source(sonosFound: Bool, sonosReachable: Bool, sonosPlayingTV: Bool) -> Source {
        sonosFound && sonosReachable && sonosPlayingTV ? .sonos : .tv
    }
}
