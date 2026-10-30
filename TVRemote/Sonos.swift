import Foundation
import PilotKit

/// The Sonos in the room, over its local control port (the same UPnP calls
/// Home Assistant and the Sonos remote apps use). Nothing changes unless you
/// change it: Pilot only reads and sets what you tap.
@MainActor
final class Sonos: ObservableObject {
    typealias Track = SonosSOAP.Track

    @Published private(set) var host: String? = UserDefaults.standard.string(forKey: "sonos")
    @Published private(set) var room = UserDefaults.standard.string(forKey: "sonos.room") ?? "Sonos"
    @Published private(set) var model = UserDefaults.standard.string(forKey: "sonos.model") ?? ""
    private var player = UserDefaults.standard.string(forKey: "sonos.player")   // RINCON_… id

    @Published private(set) var onTV = true
    /// Something is AirPlaying to it (this phone, most likely).
    @Published private(set) var fromAirPlay = false
    @Published private(set) var playing = false
    @Published private(set) var track: Track?
    @Published var volume = 0
    @Published private(set) var muted = false
    /// The last read worked: it's on the Wi-Fi and answering.
    @Published private(set) var reachable = false
    @Published private(set) var speech = false
    @Published private(set) var night = false
    @Published var sub = 0
    /// Newer bars (Arc Ultra) call Speech Enhancement "SpeechEnhanceEnabled" and
    /// ignore the old "DialogLevel"; older ones only know "DialogLevel".
    private var speechType = "SpeechEnhanceEnabled"
    /// Just after you change something, don't let a refresh read the old value back.
    private var quietUntil = Date.distantPast

    /// Seconds left on the Sonos's own sleep timer, if one is set.
    @Published private(set) var sleepLeft: Int?

    // MARK: Finding it

    /// Looks for a Sonos on this phone's Wi-Fi (skipping a Sub, which plays through the bar).
    func findIfNeeded() async {
        guard host == nil, let me = TVFinder.localAddress() else { return }
        let found = await withTaskGroup(of: (String, String, String, String)?.self) { group in
            for address in Finding.neighbors(of: me) {
                group.addTask { await Self.describe(address) }
            }
            var hits: [(String, String, String, String)] = []
            for await hit in group { if let hit { hits.append(hit) } }
            return hits
        }
        guard let main = found.first(where: { !$0.2.contains("Sub") }) ?? found.first else { return }
        host = main.0; room = main.1; model = main.2; player = main.3
        UserDefaults.standard.set(main.0, forKey: "sonos")
        UserDefaults.standard.set(main.1, forKey: "sonos.room")
        UserDefaults.standard.set(main.2, forKey: "sonos.model")
        UserDefaults.standard.set(main.3, forKey: "sonos.player")
    }

    /// (address, room, model, RINCON id) if this address is a Sonos.
    nonisolated private static func describe(_ address: String) async -> (String, String, String, String)? {
        guard let url = URL(string: "http://\(address):1400/xml/device_description.xml") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 1.5)
        request.httpMethod = "GET"
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let xml = String(data: data, encoding: .utf8),
              let speaker = SonosSOAP.describe(xml) else { return nil }
        return (address, speaker.room, speaker.model, speaker.player)
    }

    // MARK: Reading

    func refresh() async {
        guard host != nil else { return }
        if let xml = try? await call(.transport, "GetTransportInfo") {
            playing = Self.value("CurrentTransportState", in: xml) == "PLAYING"
        }
        if let xml = try? await call(.transport, "GetPositionInfo") {
            let source = SonosSOAP.source(trackURI: Self.value("TrackURI", in: xml) ?? "")
            onTV = source == .tv
            fromAirPlay = source == .airPlay
            track = onTV ? nil : SonosSOAP.track(from: Self.value("TrackMetaData", in: xml), host: host)
        }
        if let xml = try? await call(.rendering, "GetVolume", [("Channel", "Master")]),
           let level = Self.value("CurrentVolume", in: xml).flatMap(Int.init) {
            volume = level
            reachable = true
        } else {
            reachable = false
        }
        if let xml = try? await call(.rendering, "GetMute", [("Channel", "Master")]) {
            muted = Self.value("CurrentMute", in: xml) == "1"
        }
        guard Date() > quietUntil else { return }
        if let value = await eq("SpeechEnhanceEnabled") {
            speechType = "SpeechEnhanceEnabled"
            speech = value == 1
        } else if let value = await eq("DialogLevel") {
            speechType = "DialogLevel"
            speech = value == 1
        }
        night = await eq("NightMode") == 1
        if let level = await eq("SubGain") { sub = level }
        if let xml = try? await call(.transport, "GetRemainingSleepTimerDuration") {
            sleepLeft = SonosSOAP.seconds(Self.value("RemainingSleepTimerDuration", in: xml))
        }
    }

    private func eq(_ type: String) async -> Int? {
        guard let xml = try? await call(.rendering, "GetEQ", [("EQType", type)]) else { return nil }
        return Self.value("CurrentValue", in: xml).flatMap(Int.init)
    }

    // MARK: Changing (only when you tap)

    func setSpeech(_ on: Bool) { speech = on; set(speechType, on ? 1 : 0) }
    func setNight(_ on: Bool) { night = on; set("NightMode", on ? 1 : 0) }
    func commitSub() { set("SubGain", sub) }

    func commitVolume() {
        quietUntil = Date().addingTimeInterval(3)
        Task { _ = try? await call(.rendering, "SetVolume", [("Channel", "Master"), ("DesiredVolume", "\(volume)")]) }
    }

    /// One step on the main volume bar or the phone's side buttons.
    func nudge(_ delta: Int) {
        volume = min(100, max(0, volume + delta))
        commitVolume()
    }

    func setVolume(_ level: Int) {
        volume = level
        commitVolume()
    }

    func toggleMute() {
        muted.toggle()
        quietUntil = Date().addingTimeInterval(3)
        let value = muted ? "1" : "0"
        Task { _ = try? await call(.rendering, "SetMute", [("Channel", "Master"), ("DesiredMute", value)]) }
    }

    func playPause() {
        let action = playing ? "Pause" : "Play"
        playing.toggle()
        Task { _ = try? await call(.transport, action, action == "Play" ? [("Speed", "1")] : []) }
    }

    func next() { Task { _ = try? await call(.transport, "Next"); await refresh() } }
    func previous() { Task { _ = try? await call(.transport, "Previous"); await refresh() } }

    /// Put the TV's sound back on the Sonos (after it's been playing music).
    func backToTV() {
        guard let player else { return }
        Task {
            _ = try? await call(.transport, "SetAVTransportURI",
                                [("CurrentURI", "x-sonos-htastream:\(player):spdif"), ("CurrentURIMetaData", "")])
            await refresh()
        }
    }

    /// The Sonos's own sleep timer; nil turns it off.
    func sleep(minutes: Int?) {
        let duration = SonosSOAP.sleepDuration(minutes: minutes)
        sleepLeft = minutes.map { $0 * 60 }
        Task { _ = try? await call(.transport, "ConfigureSleepTimer", [("NewSleepTimerDuration", duration)]) }
    }

    private func set(_ type: String, _ value: Int) {
        quietUntil = Date().addingTimeInterval(3)
        Task { _ = try? await call(.rendering, "SetEQ", [("EQType", type), ("DesiredValue", "\(value)")]) }
    }

    // MARK: SOAP

    private typealias Service = SonosSOAP.Service

    private func call(_ service: Service, _ action: String, _ args: [(String, String)] = []) async throws -> String {
        guard let host, let url = URL(string: "http://\(host):1400/MediaRenderer/\(service.path)/Control") else {
            throw TVError(message: "No Sonos")
        }
        let body = SonosSOAP.envelope(service, action, args)
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue(SonosSOAP.soapAction(service, action), forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(body.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw TVError(message: "Sonos said no to \(action)") }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Little XML helpers

    nonisolated static func value(_ tag: String, in xml: String) -> String? { SonosSOAP.value(tag, in: xml) }
}
