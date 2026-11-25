import Foundation
import Darwin

/// Classifies hosts of pasted links. Loopback, private, link-local, shared,
/// multicast and reserved ranges, and names that only exist on the local
/// network, are not public internet addresses.
enum NetworkAddress {
    private static let localSuffixes = [".local", ".localhost", ".localdomain", ".home.arpa", ".lan", ".internal", ".intranet"]

    /// Decided from the text alone, without a lookup.
    static func isLocal(host raw: String) -> Bool {
        var host = raw.lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        while host.hasSuffix(".") { host.removeLast() }
        if host.isEmpty || host == "localhost" || localSuffixes.contains(where: host.hasSuffix) { return true }
        if let address = ipv6(host) { return isLocal(ipv6: address) }
        // inet_aton also reads the short and numeric forms, such as 2130706433.
        var ipv4 = in_addr()
        if inet_aton(host, &ipv4) != 0 { return isLocal(ipv4: UInt32(bigEndian: ipv4.s_addr)) }
        // A single-label name is completed by the local resolver.
        return !host.contains(".")
    }

    /// True when the name resolves to any address that is not public. A name
    /// that does not resolve is left to the request itself to fail.
    static func resolvesToLocal(host: String) -> Bool {
        if isLocal(host: host) { return true }
        var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return false }
        defer { freeaddrinfo(first) }
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let entry = cursor {
            if let address = entry.pointee.ai_addr {
                switch Int32(address.pointee.sa_family) {
                case AF_INET:
                    let value = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
                    if isLocal(ipv4: value) { return true }
                case AF_INET6:
                    let bytes = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
                        withUnsafeBytes(of: pointer.pointee.sin6_addr) { Array($0) }
                    }
                    if isLocal(ipv6: bytes) { return true }
                default: return true
                }
            }
            cursor = entry.pointee.ai_next
        }
        return false
    }

    static func isLocal(ipv4 value: UInt32) -> Bool {
        let ranges: [(UInt32, UInt32)] = [
            (0x0000_0000, 8), (0x0A00_0000, 8), (0x6440_0000, 10), (0x7F00_0000, 8), (0xA9FE_0000, 16),
            (0xAC10_0000, 12), (0xC000_0000, 24), (0xC000_0200, 24), (0xC0A8_0000, 16), (0xC612_0000, 15),
            (0xC633_6400, 24), (0xCB00_7100, 24), (0xE000_0000, 4), (0xF000_0000, 4)
        ]
        return ranges.contains { value >> (32 - $0.1) == $0.0 >> (32 - $0.1) }
    }

    static func isLocal(ipv6 bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return true }
        if bytes.allSatisfy({ $0 == 0 }) { return true }                                  // ::
        if bytes[0..<15].allSatisfy({ $0 == 0 }) && bytes[15] == 1 { return true }       // ::1
        if bytes[0] == 0xFF { return true }                                               // multicast
        if bytes[0] & 0xFE == 0xFC { return true }                                        // unique local
        if bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80 { return true }                    // link-local
        if bytes[0] == 0xFE && bytes[1] & 0xC0 == 0xC0 { return true }                    // site-local
        func embedded() -> UInt32 { bytes[12..<16].reduce(0) { $0 << 8 | UInt32($1) } }
        // IPv4-mapped, IPv4-compatible and NAT64 forms carry an IPv4 address.
        if bytes[0..<10].allSatisfy({ $0 == 0 }) && bytes[10] == 0xFF && bytes[11] == 0xFF { return isLocal(ipv4: embedded()) }
        if bytes[0..<12].allSatisfy({ $0 == 0 }) { return isLocal(ipv4: embedded()) }
        if bytes[0..<12].elementsEqual([0x00, 0x64, 0xFF, 0x9B, 0, 0, 0, 0, 0, 0, 0, 0]) { return isLocal(ipv4: embedded()) }
        return false
    }

    private static func ipv6(_ host: String) -> [UInt8]? {
        guard host.contains(":") else { return nil }
        // A zone index, as in fe80::1%en0, only exists for local scopes.
        if host.contains("%") { return [UInt8](repeating: 0, count: 16) }
        var address = in6_addr()
        guard inet_pton(AF_INET6, host, &address) == 1 else { return [UInt8](repeating: 0, count: 16) }
        return withUnsafeBytes(of: address) { Array($0) }
    }
}
