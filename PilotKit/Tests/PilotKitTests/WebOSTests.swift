import Foundation
import Testing
@testable import PilotKit

@Suite struct Registration {
    @Test func firstTimeHasNoKey() throws {
        let hello = WebOS.registration(key: nil)
        let payload = try #require(hello["payload"] as? [String: Any])
        #expect(hello["type"] as? String == "register")
        #expect(payload["client-key"] == nil)
        #expect(payload["pairingType"] as? String == "PROMPT")
        #expect(payload["forcePairing"] as? Bool == false)
    }

    @Test func pairedSendsItsKey() throws {
        let payload = try #require(WebOS.registration(key: "abc")["payload"] as? [String: Any])
        #expect(payload["client-key"] as? String == "abc")
    }

    @Test func asksForTheScreenshotAndNetworkPermissions() throws {
        // Screenshots and waking the TV depend on these two.
        #expect(WebOS.permissions.contains("CAPTURE_TV_SCREEN"))
        #expect(WebOS.permissions.contains("READ_NETWORK_STATE"))
    }

    @Test func readsThePrompt() {
        let reply = ["id": "register", "type": "response", "payload": ["pairingType": "PROMPT"]] as [String: Any]
        #expect(WebOS.registerReply(reply) == .prompt)
    }

    @Test func readsRegisteredWithItsKey() {
        let reply = ["id": "register", "type": "registered", "payload": ["client-key": "k1"]] as [String: Any]
        #expect(WebOS.registerReply(reply) == .registered(key: "k1"))
    }

    @Test func readsARefusal() {
        #expect(WebOS.registerReply(["id": "register", "type": "error"]) == .refused)
    }

    @Test func ignoresOtherMessages() {
        #expect(WebOS.registerReply(["id": "7", "type": "response", "payload": [:]]) == nil)
    }
}

@Suite struct Replies {
    @Test func appsKeepTheLargeIconAndSkipBrokenOnes() throws {
        let apps = WebOS.apps(from: try json("launchpoints.json"))
        #expect(apps.map(\.id) == ["netflix", "youtube.leanback.v4", "com.webos.app.livetv"])
        #expect(apps[0].icon?.lastPathComponent == "netflix-large.png")
        #expect(apps[0].color == "#141414")
        #expect(apps[1].icon?.lastPathComponent == "youtube.png")
        #expect(apps[2].icon == nil)
    }

    @Test func inputs() throws {
        let inputs = WebOS.inputs(from: try json("inputs.json"))
        #expect(inputs.count == 3)
        #expect(inputs[1] == TVInput(id: "HDMI_2", label: "PlayStation 5", connected: true, port: 2, signal: true, appId: "com.webos.app.hdmi2"))
        #expect(inputs[2].label == "HDMI_3")  // no label: falls back to the id
    }

    @Test func volumeNestedOrFlat() {
        let nested = WebOS.volume(from: ["volumeStatus": ["volume": 12, "muteStatus": true]])
        #expect(nested.level == 12 && nested.muted == true)
        let flat = WebOS.volume(from: ["volume": 31, "muted": false])
        #expect(flat.level == 31 && flat.muted == false)
    }

    @Test func requestShape() {
        let request = WebOS.request(id: "3", uri: "ssap://audio/volumeUp")
        #expect(request["type"] as? String == "request")
        #expect(request["uri"] as? String == "ssap://audio/volumeUp")
        #expect(request["id"] as? String == "3")
    }
}

@Suite struct Waking {
    @Test func prefersTheWiFiAddress() throws {
        #expect(WebOS.macAddress(from: try json("getinfo.json")) == "aa:bb:cc:00:00:02")
    }

    @Test func fallsBackToWired() {
        #expect(WebOS.macAddress(from: ["wiredInfo": ["macAddress": "aa:bb:cc:00:00:01"]]) == "aa:bb:cc:00:00:01")
    }

    @Test func rejectsJunk() {
        #expect(WebOS.macAddress(from: ["wifiInfo": ["macAddress": "not a mac"]]) == nil)
        #expect(WebOS.wakePacket(mac: "aa:bb:cc") == nil)
        #expect(WebOS.wakePacket(mac: "aa:bb:cc:dd:ee:zz") == nil)
    }

    @Test func magicPacket() throws {
        let packet = try #require(WebOS.wakePacket(mac: "aa:bb:cc:00:00:02"))
        #expect(packet.count == 102)
        #expect(packet.prefix(6).allSatisfy { $0 == 0xFF })
        #expect(Array(packet[6..<12]) == [0xAA, 0xBB, 0xCC, 0x00, 0x00, 0x02])
        #expect(Array(packet.suffix(6)) == [0xAA, 0xBB, 0xCC, 0x00, 0x00, 0x02])
    }
}
