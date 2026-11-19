import Foundation
import PilotKit
import Security

/// The Christmas tree: a Govee plug, switched through Govee's online API (its plugs
/// don't take commands on the Wi-Fi). The API key lives in the Keychain; which plug
/// it is lives in UserDefaults. No key, no tree button.
@MainActor
final class Tree: ObservableObject {
    static let shared = Tree()

    @Published private(set) var plug: GoveePlug? = {
        guard let data = UserDefaults.standard.data(forKey: "tree.plug") else { return nil }
        return try? JSONDecoder().decode(GoveePlug.self, from: data)
    }()
    /// nil until Govee has said.
    @Published private(set) var on: Bool?
    /// A switch is on its way to Govee and back (about a second).
    @Published private(set) var busy = false

    var hasKey: Bool { Keychain.read() != nil }

    /// Saves the key if Govee accepts it and lists a plug, and remembers the first plug.
    func connect(key: String) async throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let (data, _) = try await URLSession.shared.data(for: Govee.devicesRequest(key: key))
        guard let found = try Govee.plugs(from: data).first else {
            throw GoveeError(message: "Govee didn't list a plug on this account.")
        }
        Keychain.save(key)
        plug = found
        UserDefaults.standard.set(try? JSONEncoder().encode(found), forKey: "tree.plug")
        await refresh()
    }

    func forget() {
        Keychain.delete()
        UserDefaults.standard.removeObject(forKey: "tree.plug")
        plug = nil
        on = nil
    }

    func refresh() async {
        guard let plug, let key = Keychain.read(),
            let (data, _) = try? await URLSession.shared.data(for: Govee.stateRequest(key: key, plug: plug)),
            let state = try? Govee.isOn(fromState: data)
        else { return }
        if !busy { on = state }
    }

    /// Flips it straight away on screen; puts it back if Govee says no.
    func toggle() {
        guard let plug, let key = Keychain.read(), !busy else { return }
        let target = !(on ?? false)
        let before = on
        on = target
        busy = true
        Task {
            defer { busy = false }
            do {
                let (data, _) = try await URLSession.shared.data(for: Govee.controlRequest(key: key, plug: plug, on: target))
                try Govee.checkControl(data)
            } catch {
                log("tree \(target ? "on" : "off") failed: \(error.localizedDescription)", "tree")
                on = before
            }
        }
    }
}

/// The Govee key, in the Keychain (this device only).
private enum Keychain {
    static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "fyi.savi.tvremote.govee",
        kSecAttrAccount as String: "api-key",
    ]

    static func save(_ key: String) {
        delete()
        var item = query
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func read() -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
