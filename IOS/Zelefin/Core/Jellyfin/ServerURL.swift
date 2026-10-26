import Foundation

enum ServerURL {
    static func normalize(_ raw: String) throws -> URL {
        let trimmed = repairScheme(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !trimmed.isEmpty else { throw ZelefinError.invalidServerURL }

        let prefixed: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            prefixed = trimmed
        } else {
            prefixed = "https://\(trimmed)"
        }

        guard var components = URLComponents(string: prefixed),
              let scheme = components.scheme,
              let host = components.host,
              !host.isEmpty,
              scheme == "http" || scheme == "https"
        else {
            throw ZelefinError.invalidServerURL
        }

        while components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        if components.path == "/" {
            components.path = ""
        }

        guard let url = components.url else {
            throw ZelefinError.invalidServerURL
        }
        return url
    }

    /// LAN addresses default to HTTP; public hosts still default to HTTPS.
    static func normalizeLanAddress(_ raw: String) throws -> URL {
        let trimmed = repairScheme(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !trimmed.isEmpty else { throw ZelefinError.invalidServerURL }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return try normalize(trimmed)
        }
        let hostPart = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? trimmed
        let host = hostPart.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? hostPart
        if isInternalHost(host) {
            return try normalize("http://\(trimmed)")
        }
        return try normalize(trimmed)
    }

    /// Keyboards capitalize the first letter, and `https:/` or `https//` are easy slips. Left alone,
    /// `Https://host` gained a second `https://` and the device looked up a server named "Https".
    private static func repairScheme(_ value: String) -> String {
        guard let match = value.range(of: #"^(https?)(:/{0,3}|/{1,3})"#, options: [.regularExpression, .caseInsensitive]) else {
            return value
        }
        let prefix = value[match]
        let scheme = prefix.lowercased().hasPrefix("https") ? "https" : "http"
        return scheme + "://" + value[match.upperBound...]
    }

    static func resolve(base: URL, path: String, token: String? = nil) -> URL? {
        let resolved: URL?
        if let absolute = URL(string: path), absolute.scheme != nil, absolute.host != nil {
            resolved = rewriteIfNeeded(absolute, publicBase: base)
        } else {
            resolved = join(base: base, path: path)
        }
        return appendToken(resolved, token: token)
    }

    /// Returns `url` with `query` items appended.
    static func appending(_ query: [(String, String?)], to url: URL) -> URL {
        guard !query.isEmpty else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = components.queryItems ?? []
        items.append(contentsOf: query.map { URLQueryItem(name: $0.0, value: $0.1) })
        components.queryItems = items
        return components.url ?? url
    }

    static func rewriteIfNeeded(_ url: URL, publicBase: URL) -> URL {
        guard let host = url.host, let publicHost = publicBase.host else { return url }
        let sameHost = host.caseInsensitiveCompare(publicHost) == .orderedSame
        guard !sameHost, isInternalHost(host) else { return url }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.scheme = publicBase.scheme
        components.host = publicHost
        components.port = publicBase.port

        let publicPath = trimmedPath(publicBase.path)
        let remotePath = url.path.hasPrefix("/") ? url.path : "/\(url.path)"
        if !publicPath.isEmpty,
           remotePath != publicPath,
           !remotePath.hasPrefix(publicPath + "/")
        {
            components.path = publicPath + remotePath
        }
        return components.url ?? url
    }

    static func isInternalHost(_ host: String) -> Bool {
        let value = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if value == "localhost" || value == "::1" || value.hasPrefix("127.") || value == "0.0.0.0" {
            return true
        }
        if value.hasSuffix(".local") || value.hasSuffix(".lan") || value.hasSuffix(".internal") || value.hasSuffix(".home") {
            return true
        }
        if !value.contains("."), !value.contains(":") {
            return true
        }
        return isPrivateIPv4(value)
    }

    /// True when `host` is on a network the device is attached to right now, so Auto can skip the
    /// speed test. A LAN IP reached through a VPN subnet route (Tailscale) is still private, but the
    /// stream crosses the VPN's uplink and has to be measured like any remote server.
    static func isOnLocalNetwork(_ host: String, subnets: [LocalSubnet] = LocalSubnet.current()) -> Bool {
        let value = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        guard let address = LocalSubnet.ipv4(value) else { return isInternalHost(value) }
        if value.hasPrefix("127.") { return true }
        guard isPrivateIPv4(value) else { return false }
        return subnets.contains { $0.contains(address) }
    }

    static func join(base: URL, path: String) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let split = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let rawPath = String(split[0])
        let query = split.count > 1 ? String(split[1]) : nil

        let trimmedBase = trimmedPath(components.path)
        let extra: String
        if rawPath.isEmpty {
            extra = ""
        } else if rawPath.hasPrefix("/") {
            extra = rawPath
        } else {
            extra = "/\(rawPath)"
        }
        components.path = trimmedBase + extra

        if let query, !query.isEmpty {
            components.percentEncodedQuery = query
        }

        return components.url
    }

    private static func appendToken(_ url: URL?, token: String?) -> URL? {
        guard let url else { return nil }
        guard let token, !token.isEmpty else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = components.queryItems ?? []
        let hasKey = items.contains {
            $0.name.caseInsensitiveCompare("api_key") == .orderedSame
                || $0.name.caseInsensitiveCompare("ApiKey") == .orderedSame
        }
        if !hasKey {
            items.append(URLQueryItem(name: "api_key", value: token))
            components.queryItems = items
        }
        return components.url ?? url
    }

    private static func trimmedPath(_ path: String) -> String {
        var value = path
        while value.count > 1, value.hasSuffix("/") {
            value.removeLast()
        }
        if value == "/" { return "" }
        return value
    }

    private static func isPrivateIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4, host.split(separator: ".").count == 4 else { return false }
        switch parts[0] {
        case 10, 127: return true
        case 169: return parts[1] == 254
        case 172: return (16 ... 31).contains(parts[1])
        case 192: return parts[1] == 168
        default: return false
        }
    }

    /// An IPv4 network the device sits on directly.
    struct LocalSubnet: Equatable, Sendable {
        var address: UInt32
        var mask: UInt32

        func contains(_ ip: UInt32) -> Bool {
            ip & mask == address & mask
        }

        static func ipv4(_ value: String) -> UInt32? {
            var parsed = in_addr()
            guard inet_pton(AF_INET, value, &parsed) == 1 else { return nil }
            return UInt32(bigEndian: parsed.s_addr)
        }

        /// Wi-Fi and Ethernet (`en*`) only. VPN tunnels (`utun`, `ipsec`) and cellular (`pdp_ip`)
        /// don't put the device on the server's LAN, even when they route to its addresses.
        static func current() -> [LocalSubnet] {
            var head: UnsafeMutablePointer<ifaddrs>?
            guard getifaddrs(&head) == 0, let first = head else { return [] }
            defer { freeifaddrs(head) }
            var subnets: [LocalSubnet] = []
            for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
                let entry = pointer.pointee
                let flags = Int32(entry.ifa_flags)
                guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                      String(cString: entry.ifa_name).hasPrefix("en"),
                      let address = entry.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
                      let netmask = entry.ifa_netmask else { continue }
                let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
                }
                let mask = netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
                }
                guard mask != 0 else { continue }
                subnets.append(LocalSubnet(address: ip, mask: mask))
            }
            return subnets
        }
    }

    /// Jellyfin session socket. Remote control only works while this connection stays up.
    static func sessionSocket(base: URL, token: String, deviceID: String) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        switch components.scheme?.lowercased() {
        case "https": components.scheme = "wss"
        case "http": components.scheme = "ws"
        default: return nil
        }
        var path = components.path
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        if path == "/" { path = "" }
        components.path = path + "/socket"
        var items = (components.queryItems ?? []).filter { $0.name != "api_key" && $0.name != "deviceId" }
        items.append(URLQueryItem(name: "api_key", value: token))
        items.append(URLQueryItem(name: "deviceId", value: deviceID))
        components.queryItems = items
        return components.url
    }
}
