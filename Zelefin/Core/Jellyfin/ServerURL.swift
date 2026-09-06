import Foundation

enum ServerURL {
    static func normalize(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
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
}
