import Foundation

/// A Govee plug Pilot can switch: Govee's online API, since its plugs don't take
/// commands on the local Wi-Fi. Every call carries the owner's API key, which
/// Govee emails from the Govee Home app (Profile, Settings, Apply for API Key).
public struct GoveePlug: Codable, Equatable, Sendable {
    public var sku: String
    public var device: String
    public var name: String

    public init(sku: String, device: String, name: String) {
        self.sku = sku
        self.device = device
        self.name = name
    }
}

public struct GoveeError: LocalizedError, Equatable, Sendable {
    public let message: String
    public var errorDescription: String? { message }
    public init(message: String) { self.message = message }
}

public enum Govee {
    static let base = URL(string: "https://openapi.api.govee.com/router/api/v1/")!

    /// Lists the account's devices.
    public static func devicesRequest(key: String) -> URLRequest {
        request("user/devices", key: key, body: nil)
    }

    /// Turns a plug on or off.
    public static func controlRequest(key: String, plug: GoveePlug, on: Bool, requestId: String = UUID().uuidString) -> URLRequest {
        request(
            "device/control", key: key,
            body: [
                "requestId": requestId,
                "payload": [
                    "sku": plug.sku,
                    "device": plug.device,
                    "capability": ["type": "devices.capabilities.on_off", "instance": "powerSwitch", "value": on ? 1 : 0],
                ],
            ])
    }

    /// Asks whether a plug is on.
    public static func stateRequest(key: String, plug: GoveePlug, requestId: String = UUID().uuidString) -> URLRequest {
        request("device/state", key: key, body: ["requestId": requestId, "payload": ["sku": plug.sku, "device": plug.device]])
    }

    /// The devices in a devices reply that can be switched on and off.
    public static func plugs(from data: Data) throws -> [GoveePlug] {
        let reply = try object(data)
        let devices = reply["data"] as? [[String: Any]] ?? []
        return devices.compactMap { device in
            guard let sku = device["sku"] as? String, let id = device["device"] as? String,
                let capabilities = device["capabilities"] as? [[String: Any]],
                capabilities.contains(where: { $0["instance"] as? String == "powerSwitch" })
            else { return nil }
            return GoveePlug(sku: sku, device: id, name: device["deviceName"] as? String ?? sku)
        }
    }

    /// Whether a plug is on, from a state reply; nil if it didn't say.
    public static func isOn(fromState data: Data) throws -> Bool? {
        let reply = try object(data)
        let capabilities = (reply["payload"] as? [String: Any])?["capabilities"] as? [[String: Any]] ?? []
        guard let power = capabilities.first(where: { $0["instance"] as? String == "powerSwitch" }),
            let value = (power["state"] as? [String: Any])?["value"]
        else { return nil }
        return (value as? Int).map { $0 == 1 } ?? (value as? Bool)
    }

    /// Checks a control reply went through.
    public static func checkControl(_ data: Data) throws {
        _ = try object(data)
    }

    // MARK: Plumbing

    private static func request(_ path: String, key: String, body: [String: Any]?) -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "Govee-API-Key")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    /// Govee answers 200 with `code` inside; anything else carries a message. An
    /// empty or non-JSON reply (a bad request) gets a plain one.
    private static func object(_ data: Data) throws -> [String: Any] {
        guard let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GoveeError(message: "Govee didn't understand the request.")
        }
        let code = reply["code"] as? Int ?? reply["status"] as? Int ?? 200
        guard code == 200 else {
            let message = reply["message"] as? String ?? reply["msg"] as? String ?? "Govee said no (\(code))."
            throw GoveeError(message: code == 401 ? "Govee didn't accept that key." : message)
        }
        return reply
    }
}
