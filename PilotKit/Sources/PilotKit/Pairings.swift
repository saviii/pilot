import Foundation

/// Somewhere to keep small values. UserDefaults in the app; a dictionary in tests.
public protocol KeyValueStore: AnyObject {
    func string(forKey key: String) -> String?
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: KeyValueStore {}

/// A TV this phone has paired with.
public struct SavedTV: Codable, Hashable, Identifiable, Sendable {
    public var host: String
    public var name: String
    public var id: String { host }

    public init(host: String, name: String) {
        self.host = host
        self.name = name
    }
}

/// What the phone remembers about each TV, all keyed by its address: the pairing key
/// the TV gave us, its MAC address (for waking it), and the list of saved TVs.
public struct Pairings {
    public let store: KeyValueStore

    public init(store: KeyValueStore) { self.store = store }

    public func key(for host: String) -> String? { store.string(forKey: "key.\(host)") }
    public func setKey(_ key: String, for host: String) { store.set(key, forKey: "key.\(host)") }
    public func mac(for host: String) -> String? { store.string(forKey: "mac.\(host)") }
    public func setMac(_ mac: String, for host: String) { store.set(mac, forKey: "mac.\(host)") }

    public var saved: [SavedTV] {
        guard let data = store.data(forKey: "tvs"),
              let list = try? JSONDecoder().decode([SavedTV].self, from: data) else { return [] }
        return list
    }

    public func save(_ list: [SavedTV]) {
        store.set(try? JSONEncoder().encode(list), forKey: "tvs")
    }

    /// Forgets one TV: its key, its MAC and its place in the list.
    public func forget(_ host: String) {
        store.removeObject(forKey: "key.\(host)")
        store.removeObject(forKey: "mac.\(host)")
        save(saved.filter { $0.host != host })
    }

    /// The TV at `old` now answers at `new` (the router gave it another address).
    /// Its key, MAC and name move over; nothing is left behind at the old address.
    public func move(from old: String, to new: String) {
        if let key = key(for: old) { setKey(key, for: new) }
        if let mac = mac(for: old) { setMac(mac, for: new) }
        store.removeObject(forKey: "key.\(old)")
        store.removeObject(forKey: "mac.\(old)")
        save(saved.map { $0.host == old ? SavedTV(host: new, name: $0.name) : $0 })
    }
}
