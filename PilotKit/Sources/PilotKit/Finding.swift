import Foundation

/// Looking for TVs and speakers on the phone's Wi-Fi.
public enum Finding {
    /// Every other address on the phone's /24 subnet, .1 to .254.
    public static func neighbors(of me: String) -> [String] {
        let parts = me.split(separator: ".")
        guard parts.count == 4 else { return [] }
        let prefix = parts.dropLast().joined(separator: ".")
        return (1...254).map { "\(prefix).\($0)" }.filter { $0 != me }
    }

    /// Addresses in the order a person would read them (.9 before .10).
    public static func sorted(_ addresses: [String]) -> [String] {
        addresses.sorted { lastOctet($0) < lastOctet($1) }
    }

    private static func lastOctet(_ address: String) -> Int {
        address.split(separator: ".").last.flatMap { Int($0) } ?? 0
    }

    /// The router gave a paired TV a new address. Of the TVs that answered, offer our
    /// pairing only to ones we don't already know, in order, and return the first that
    /// accepts it: that's ours. Only our TV accepts our key; any other would ask to pair.
    public static func moved(
        from old: String, known: Set<String>, answering: [String],
        accepts: (String) async -> Bool
    ) async -> String? {
        for address in sorted(answering) where address != old && !known.contains(address) {
            if await accepts(address) { return address }
        }
        return nil
    }
}
