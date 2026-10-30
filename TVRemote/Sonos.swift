import Foundation

/// The Sonos in the room, over its local control port (the same UPnP calls
/// Home Assistant and the Sonos remote apps use). Nothing changes unless you
/// change it: Pilot only reads and sets what you tap.
@MainActor
final class Sonos: ObservableObject {
    struct Track: Equatable {
        var title: String
        var artist: String?
        var art: URL?
    }

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
        let prefix = me.split(separator: ".").dropLast().joined(separator: ".")
        let found = await withTaskGroup(of: (String, String, String, String)?.self) { group in
            for last in 1...254 {
                let address = "\(prefix).\(last)"
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
              let model = value("modelName", in: xml),
              let udn = value("UDN", in: xml) else { return nil }
        return (address, value("roomName", in: xml) ?? "Sonos", model, udn.replacingOccurrences(of: "uuid:", with: ""))
    }

    // MARK: Reading

    func refresh() async {
        guard host != nil else { return }
        if let xml = try? await call(.transport, "GetTransportInfo") {
            playing = Self.value("CurrentTransportState", in: xml) == "PLAYING"
        }
        if let xml = try? await call(.transport, "GetPositionInfo") {
            let uri = Self.value("TrackURI", in: xml) ?? ""
            onTV = uri.hasPrefix("x-sonos-htastream:")
            fromAirPlay = uri.hasPrefix("x-sonos-vli:")
            track = onTV ? nil : Self.track(from: Self.value("TrackMetaData", in: xml), host: host)
        }
        if let xml = try? await call(.rendering, "GetVolume", [("Channel", "Master")]),
           let level = Self.value("CurrentVolume", in: xml).flatMap(Int.init) { volume = level }
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
            sleepLeft = Self.seconds(Self.value("RemainingSleepTimerDuration", in: xml))
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
        let duration = minutes.map { String(format: "%02d:%02d:00", $0 / 60, $0 % 60) } ?? ""
        sleepLeft = minutes.map { $0 * 60 }
        Task { _ = try? await call(.transport, "ConfigureSleepTimer", [("NewSleepTimerDuration", duration)]) }
    }

    private func set(_ type: String, _ value: Int) {
        quietUntil = Date().addingTimeInterval(3)
        Task { _ = try? await call(.rendering, "SetEQ", [("EQType", type), ("DesiredValue", "\(value)")]) }
    }

    // MARK: SOAP

    private enum Service {
        case transport, rendering
        var path: String { self == .transport ? "AVTransport" : "RenderingControl" }
        var urn: String { "urn:schemas-upnp-org:service:\(path):1" }
    }

    private func call(_ service: Service, _ action: String, _ args: [(String, String)] = []) async throws -> String {
        guard let host, let url = URL(string: "http://\(host):1400/MediaRenderer/\(service.path)/Control") else {
            throw TVError(message: "No Sonos")
        }
        let fields = ([("InstanceID", "0")] + args).map { "<\($0.0)>\(Self.escape($0.1))</\($0.0)>" }.joined()
        let body = """
        <?xml version="1.0" encoding="utf-8"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" \
        s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:\(action) xmlns:u="\(service.urn)">\
        \(fields)</u:\(action)></s:Body></s:Envelope>
        """
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(service.urn)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(body.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw TVError(message: "Sonos said no to \(action)") }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Little XML helpers

    nonisolated static func value(_ tag: String, in xml: String) -> String? {
        guard let open = xml.range(of: "<\(tag)>") ?? xml.range(of: "<\(tag) [^>]*>", options: .regularExpression),
              let close = xml.range(of: "</\(tag)>", range: open.upperBound..<xml.endIndex) else { return nil }
        return unescape(String(xml[open.upperBound..<close.lowerBound]))
    }

    nonisolated private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    nonisolated private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    nonisolated private static func track(from didl: String?, host: String?) -> Track? {
        guard let didl, let title = value("dc:title", in: didl), !title.isEmpty else { return nil }
        var art: URL?
        if let raw = value("upnp:albumArtURI", in: didl) {
            art = raw.hasPrefix("http") ? URL(string: raw) : host.flatMap { URL(string: "http://\($0):1400\(raw)") }
        }
        return Track(title: title, artist: value("dc:creator", in: didl), art: art)
    }

    nonisolated private static func seconds(_ text: String?) -> Int? {
        guard let parts = text?.split(separator: ":").compactMap({ Int($0) }), parts.count == 3 else { return nil }
        let total = parts[0] * 3600 + parts[1] * 60 + parts[2]
        return total > 0 ? total : nil
    }
}
