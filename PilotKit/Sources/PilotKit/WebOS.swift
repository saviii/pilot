import Foundation

/// An app the TV can open, from its launch points.
public struct TVApp: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let icon: URL?
    public var color: String?

    public init(id: String, title: String, icon: URL?, color: String? = nil) {
        self.id = id
        self.title = title
        self.icon = icon
        self.color = color
    }
}

/// One of the TV's HDMI (or other) inputs.
public struct TVInput: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let connected: Bool
    public var port: Int?
    public var signal: Bool
    public var appId: String?

    public init(id: String, label: String, connected: Bool, port: Int? = nil, signal: Bool = false, appId: String? = nil) {
        self.id = id
        self.label = label
        self.connected = connected
        self.port = port
        self.signal = signal
        self.appId = appId
    }
}

/// The messages LG's "connect apps" socket speaks: the same ones LG's own phone app
/// sends. Building and reading them lives here; the socket lives in the app.
public enum WebOS {
    /// The permissions we ask for when pairing. The TV shows these once, on screen.
    public static let permissions = [
        "LAUNCH", "LAUNCH_WEBAPP", "APP_TO_APP", "CLOSE",
        "CONTROL_AUDIO", "CONTROL_POWER", "CONTROL_DISPLAY",
        "CONTROL_INPUT_JOYSTICK", "CONTROL_INPUT_MEDIA_PLAYBACK",
        "CONTROL_INPUT_TEXT", "CONTROL_MOUSE_AND_KEYBOARD", "CONTROL_INPUT_TV",
        "READ_INSTALLED_APPS", "READ_RUNNING_APPS", "READ_APP_STATUS",
        "READ_POWER_STATE", "READ_SETTINGS", "READ_INPUT_DEVICE_LIST", "CAPTURE_TV_SCREEN", "READ_NETWORK_STATE",
        "WRITE_NOTIFICATION_TOAST",
    ]

    /// The hello the TV expects: who we are, what we'd like to do, and our key if we have one.
    public static func registration(key: String?) -> [String: Any] {
        var payload: [String: Any] = [
            "forcePairing": false,
            "pairingType": "PROMPT",
            "manifest": [
                "manifestVersion": 1,
                "appVersion": "1.0",
                "permissions": permissions,
            ],
        ]
        if let key { payload["client-key"] = key }
        return ["type": "register", "id": "register", "payload": payload]
    }

    /// What the TV said to our hello.
    public enum RegisterReply: Equatable, Sendable {
        /// It's asking on screen: press OK on the TV.
        case prompt
        /// We're in. A new key comes with a first pairing.
        case registered(key: String?)
        /// It said no.
        case refused
    }

    /// Reads a reply to `registration(key:)`; nil for anything else.
    public static func registerReply(_ json: [String: Any]) -> RegisterReply? {
        guard json["id"] as? String == "register" else { return nil }
        let payload = json["payload"] as? [String: Any] ?? [:]
        switch json["type"] as? String {
        case "response" where payload["pairingType"] as? String == "PROMPT": return .prompt
        case "registered": return .registered(key: payload["client-key"] as? String)
        case "error": return .refused
        default: return nil
        }
    }

    /// A request to one of the TV's `ssap://` services.
    public static func request(id: String, uri: String, payload: [String: Any] = [:]) -> [String: Any] {
        ["type": "request", "id": id, "uri": uri, "payload": payload]
    }

    /// The apps from `listLaunchPoints`.
    public static func apps(from payload: [String: Any]) -> [TVApp] {
        guard let points = payload["launchPoints"] as? [[String: Any]] else { return [] }
        return points.compactMap { point in
            guard let id = point["id"] as? String, let title = point["title"] as? String else { return nil }
            let icon = (point["largeIcon"] as? String) ?? (point["icon"] as? String)
            return TVApp(id: id, title: title, icon: icon.flatMap(URL.init(string:)), color: point["iconColor"] as? String)
        }
    }

    /// The inputs from `getExternalInputList`.
    public static func inputs(from payload: [String: Any]) -> [TVInput] {
        guard let devices = payload["devices"] as? [[String: Any]] else { return [] }
        return devices.compactMap { device in
            guard let id = device["id"] as? String else { return nil }
            return TVInput(
                id: id, label: device["label"] as? String ?? id,
                connected: device["connected"] as? Bool ?? false,
                port: device["port"] as? Int,
                signal: device["hdmiSignalExist"] as? Bool ?? false,
                appId: device["appId"] as? String)
        }
    }

    /// Volume and mute from `getVolume` (older firmware nests them, newer doesn't).
    public static func volume(from payload: [String: Any]) -> (level: Int?, muted: Bool?) {
        let status = payload["volumeStatus"] as? [String: Any] ?? payload
        return (status["volume"] as? Int, (status["muteStatus"] ?? status["muted"]) as? Bool)
    }

    /// The TV's network (MAC) address from `connectionmanager/getinfo`, Wi-Fi first.
    public static func macAddress(from info: [String: Any]) -> String? {
        let wifi = (info["wifiInfo"] as? [String: Any])?["macAddress"] as? String
        let wired = (info["wiredInfo"] as? [String: Any])?["macAddress"] as? String
        guard let mac = wifi ?? wired, wakePacket(mac: mac) != nil else { return nil }
        return mac
    }

    /// The Wake-on-LAN "magic packet": six 0xFF bytes, then the MAC sixteen times.
    public static func wakePacket(mac: String) -> Data? {
        let bytes = mac.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        guard bytes.count == 6, mac.split(separator: ":").count == 6 else { return nil }
        return Data(repeating: 0xFF, count: 6) + Data((0..<16).flatMap { _ in bytes })
    }
}
