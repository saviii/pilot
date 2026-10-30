import Foundation
import Testing
@testable import PilotKit

@Suite struct Sonos {
    @Test func envelopeEscapesArguments() {
        let body = SonosSOAP.envelope(.rendering, "SetEQ", [("EQType", "NightMode"), ("DesiredValue", "<1&>")])
        #expect(body.contains("<u:SetEQ xmlns:u=\"urn:schemas-upnp-org:service:RenderingControl:1\">"))
        #expect(body.contains("<InstanceID>0</InstanceID><EQType>NightMode</EQType>"))
        #expect(body.contains("<DesiredValue>&lt;1&amp;&gt;</DesiredValue>"))
        #expect(SonosSOAP.soapAction(.transport, "Play") == "\"urn:schemas-upnp-org:service:AVTransport:1#Play\"")
    }

    @Test func readsTheSpeaker() throws {
        let speaker = try #require(SonosSOAP.describe(try text("device_description.xml")))
        #expect(speaker.room == "Family Room")
        #expect(speaker.model == "Sonos Arc Ultra")
        #expect(speaker.player == "RINCON_000000000000001400")
    }

    @Test func readsTheTrackWithArtFromTheSpeaker() throws {
        let xml = try text("position.xml")
        #expect(SonosSOAP.source(trackURI: SonosSOAP.value("TrackURI", in: xml) ?? "") == .music)
        let track = try #require(SonosSOAP.track(from: SonosSOAP.value("TrackMetaData", in: xml), host: "192.168.1.40"))
        #expect(track.title == "Nights & Days")
        #expect(track.artist == "Someone")
        #expect(track.art?.absoluteString == "http://192.168.1.40:1400/getaa?s=1&u=x")
    }

    @Test func sources() {
        #expect(SonosSOAP.source(trackURI: "x-sonos-htastream:RINCON_1:spdif") == .tv)
        #expect(SonosSOAP.source(trackURI: "x-sonos-vli:RINCON_1:1,airplay:x") == .airPlay)
    }

    @Test func valueWithAttributes() {
        #expect(SonosSOAP.value("dc:title", in: "<dc:title id=\"1\">Hi</dc:title>") == "Hi")
        #expect(SonosSOAP.value("Missing", in: "<a>1</a>") == nil)
    }

    @Test func sleepTimer() {
        #expect(SonosSOAP.sleepDuration(minutes: 90) == "01:30:00")
        #expect(SonosSOAP.sleepDuration(minutes: nil) == "")
        #expect(SonosSOAP.seconds("0:45:10") == 2710)
        #expect(SonosSOAP.seconds("0:00:00") == nil)
        #expect(SonosSOAP.seconds("") == nil)
    }
}
