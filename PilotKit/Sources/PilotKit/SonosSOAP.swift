import Foundation

/// The UPnP calls a Sonos answers on port 1400 (the same ones Home Assistant and
/// the Sonos remote apps use), and the bits of XML we read back.
public enum SonosSOAP {
    public enum Service: Sendable {
        case transport, rendering
        public var path: String { self == .transport ? "AVTransport" : "RenderingControl" }
        public var urn: String { "urn:schemas-upnp-org:service:\(path):1" }
    }

    public struct Track: Equatable, Sendable {
        public var title: String
        public var artist: String?
        public var art: URL?

        public init(title: String, artist: String? = nil, art: URL? = nil) {
            self.title = title
            self.artist = artist
            self.art = art
        }
    }

    /// The SOAP body for one action. Arguments are escaped; InstanceID 0 comes first.
    public static func envelope(_ service: Service, _ action: String, _ args: [(String, String)] = []) -> String {
        let fields = ([("InstanceID", "0")] + args).map { "<\($0.0)>\(escape($0.1))</\($0.0)>" }.joined()
        return """
        <?xml version="1.0" encoding="utf-8"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" \
        s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:\(action) xmlns:u="\(service.urn)">\
        \(fields)</u:\(action)></s:Body></s:Envelope>
        """
    }

    /// The SOAPACTION header for one action.
    public static func soapAction(_ service: Service, _ action: String) -> String {
        "\"\(service.urn)#\(action)\""
    }

    /// The text inside the first `<tag>` (attributes allowed), unescaped.
    public static func value(_ tag: String, in xml: String) -> String? {
        guard let open = xml.range(of: "<\(tag)>") ?? xml.range(of: "<\(tag) [^>]*>", options: .regularExpression),
              let close = xml.range(of: "</\(tag)>", range: open.upperBound..<xml.endIndex) else { return nil }
        return unescape(String(xml[open.upperBound..<close.lowerBound]))
    }

    public static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    public static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// The track in a DIDL-Lite blob. Art paths without a host are on the speaker itself.
    public static func track(from didl: String?, host: String?) -> Track? {
        guard let didl, let title = value("dc:title", in: didl), !title.isEmpty else { return nil }
        var art: URL?
        if let raw = value("upnp:albumArtURI", in: didl) {
            art = raw.hasPrefix("http") ? URL(string: raw) : host.flatMap { URL(string: "http://\($0):1400\(raw)") }
        }
        return Track(title: title, artist: value("dc:creator", in: didl), art: art)
    }

    /// "H:MM:SS" to seconds; nil for none or zero.
    public static func seconds(_ text: String?) -> Int? {
        guard let parts = text?.split(separator: ":").compactMap({ Int($0) }), parts.count == 3 else { return nil }
        let total = parts[0] * 3600 + parts[1] * 60 + parts[2]
        return total > 0 ? total : nil
    }

    /// The sleep timer's duration argument; empty turns it off.
    public static func sleepDuration(minutes: Int?) -> String {
        minutes.map { String(format: "%02d:%02d:00", $0 / 60, $0 % 60) } ?? ""
    }

    /// What's playing, from the TrackURI: the TV's sound, AirPlay, or music.
    public enum Source: Equatable, Sendable { case tv, airPlay, music }

    public static func source(trackURI uri: String) -> Source {
        if uri.hasPrefix("x-sonos-htastream:") { return .tv }
        if uri.hasPrefix("x-sonos-vli:") { return .airPlay }
        return .music
    }

    /// (room, model, RINCON id) from a speaker's device_description.xml.
    public static func describe(_ xml: String) -> (room: String, model: String, player: String)? {
        guard let model = value("modelName", in: xml), let udn = value("UDN", in: xml) else { return nil }
        return (value("roomName", in: xml) ?? "Sonos", model, udn.replacingOccurrences(of: "uuid:", with: ""))
    }
}
