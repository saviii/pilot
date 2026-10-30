import Foundation
import Testing

@testable import PilotKit

@Suite struct Neighbors {
    @Test func everyOtherAddressOnTheSubnet() {
        let all = Finding.neighbors(of: "192.168.1.42")
        #expect(all.count == 253)
        #expect(all.first == "192.168.1.1" && all.last == "192.168.1.254")
        #expect(!all.contains("192.168.1.42"))
    }

    @Test func nothingForABadAddress() {
        #expect(Finding.neighbors(of: "fe80::1").isEmpty)
    }

    @Test func sortsLikeAPerson() {
        #expect(Finding.sorted(["192.168.1.10", "192.168.1.9", "192.168.1.100"]) == ["192.168.1.9", "192.168.1.10", "192.168.1.100"])
    }
}

/// The TV got a new address from the router (this happened: it looked "off" while on).
@Suite struct TVMoved {
    /// A fake Wi-Fi: which addresses accept our key, and who we asked.
    actor FakeWiFi {
        let ours: String?
        var asked: [String] = []
        init(ours: String?) { self.ours = ours }
        func accepts(_ address: String) -> Bool { asked.append(address); return address == ours }
    }

    @Test func findsOurTVAtItsNewAddress() async {
        let wifi = FakeWiFi(ours: "192.168.1.57")
        let found = await Finding.moved(
            from: "192.168.1.20", known: ["192.168.1.20"],
            answering: ["192.168.1.57"], accepts: { await wifi.accepts($0) })
        #expect(found == "192.168.1.57")
    }

    @Test func neverOffersOurKeyToTVsWeKnow() async {
        // The upstairs TV is saved too: it must not be asked (it would show a pairing prompt).
        let wifi = FakeWiFi(ours: nil)
        let found = await Finding.moved(
            from: "192.168.1.20", known: ["192.168.1.20", "192.168.1.31"],
            answering: ["192.168.1.20", "192.168.1.31"], accepts: { await wifi.accepts($0) })
        #expect(found == nil)
        #expect(await wifi.asked.isEmpty)
    }

    @Test func skipsAStrangersTV() async {
        let wifi = FakeWiFi(ours: "192.168.1.88")
        let found = await Finding.moved(
            from: "192.168.1.20", known: ["192.168.1.20"],
            answering: ["192.168.1.88", "192.168.1.12"], accepts: { await wifi.accepts($0) })
        #expect(found == "192.168.1.88")
        #expect(await wifi.asked == ["192.168.1.12", "192.168.1.88"])  // in address order
    }

    @Test func nothingAnswers() async {
        let found = await Finding.moved(from: "192.168.1.20", known: [], answering: [], accepts: { _ in true })
        #expect(found == nil)
    }
}

@Suite struct Remembering {
    @Test func movingKeepsTheKeyMacAndName() {
        let store = MemoryStore()
        let pairings = Pairings(store: store)
        pairings.save([SavedTV(host: "192.168.1.20", name: "Living room"), SavedTV(host: "192.168.1.31", name: "Upstairs")])
        pairings.setKey("k1", for: "192.168.1.20")
        pairings.setMac("aa:bb:cc:00:00:02", for: "192.168.1.20")

        pairings.move(from: "192.168.1.20", to: "192.168.1.57")

        #expect(pairings.key(for: "192.168.1.57") == "k1")
        #expect(pairings.mac(for: "192.168.1.57") == "aa:bb:cc:00:00:02")
        #expect(pairings.key(for: "192.168.1.20") == nil)
        #expect(pairings.mac(for: "192.168.1.20") == nil)
        #expect(pairings.saved == [SavedTV(host: "192.168.1.57", name: "Living room"), SavedTV(host: "192.168.1.31", name: "Upstairs")])
    }

    @Test func forgettingLeavesTheOthers() {
        let pairings = Pairings(store: MemoryStore())
        pairings.save([SavedTV(host: "a", name: "A"), SavedTV(host: "b", name: "B")])
        pairings.setKey("ka", for: "a")
        pairings.forget("a")
        #expect(pairings.key(for: "a") == nil)
        #expect(pairings.saved == [SavedTV(host: "b", name: "B")])
    }
}
