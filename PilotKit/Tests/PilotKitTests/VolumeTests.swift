import Testing

@testable import PilotKit

/// The Lock Screen panel showed the TV's own volume while the app showed the Sonos's.
@Suite struct WhichVolume {
    @Test func theSonosWhenItPlaysTheTV() {
        #expect(Volume.source(sonosFound: true, sonosReachable: true, sonosPlayingTV: true) == .sonos)
    }

    @Test func theTVOtherwise() {
        #expect(Volume.source(sonosFound: false, sonosReachable: false, sonosPlayingTV: false) == .tv)
        #expect(Volume.source(sonosFound: true, sonosReachable: false, sonosPlayingTV: true) == .tv)
        #expect(Volume.source(sonosFound: true, sonosReachable: true, sonosPlayingTV: false) == .tv)
    }
}
