import Foundation
@testable import PilotKit
import Testing

/// A KeyValueStore that's just a dictionary.
final class MemoryStore: KeyValueStore {
    var values: [String: Any] = [:]
    func string(forKey key: String) -> String? { values[key] as? String }
    func data(forKey key: String) -> Data? { values[key] as? Data }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
}

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

func json(_ name: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: fixture(name)) as? [String: Any])
}

func text(_ name: String) throws -> String {
    String(decoding: try fixture(name), as: UTF8.self)
}
