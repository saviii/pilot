import Foundation
import PilotKit

/// Looks for LG TVs on the Wi-Fi: tries every address on this phone's subnet
/// at once and keeps the ones that answer like a TV. Takes a couple of seconds.
@MainActor
final class TVFinder: ObservableObject {
    @Published private(set) var found: [String] = []
    @Published private(set) var scanning = false

    func scan(with tv: TVConnection) async {
        guard !scanning else { return }
        scanning = true
        defer { scanning = false }
        found = await Self.find(with: tv)
    }

    /// Every address on this phone's subnet that answers like an LG TV, in order.
    static func find(with tv: TVConnection) async -> [String] {
        guard let me = localAddress() else { return [] }
        let hits = await withTaskGroup(of: String?.self) { group in
            for address in Finding.neighbors(of: me) {
                group.addTask { await tv.isTV(address) ? address : nil }
            }
            var hits: [String] = []
            for await hit in group { if let hit { hits.append(hit) } }
            return hits
        }
        return Finding.sorted(hits)
    }

    /// This phone's IPv4 address on Wi-Fi.
    static func localAddress() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var addresses: [(interface: String, address: String)] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len), &name, socklen_t(name.count), nil, 0, NI_NUMERICHOST)
            addresses.append((String(cString: entry.ifa_name), String(cString: name)))
        }
        // Wi-Fi is en0 on a phone; otherwise any private address will do.
        let local = addresses.filter { LocalTrust.isLocal($0.address) && !$0.address.hasPrefix("169.254") }
        return (local.first { $0.interface == "en0" } ?? local.first)?.address
    }
}
