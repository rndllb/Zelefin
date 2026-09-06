import Foundation

enum PlaybackHTTPHeaders {
    /// Gateway tokens, Jellyfin token, and cookies the player must send with every byte of the stream.
    static func fields(for url: URL) -> [String: String] {
        var fields = AccessGateway.httpHeaders
        if let token = apiKey(from: url), !token.isEmpty {
            fields["X-Emby-Token"] = token
            fields["Authorization"] = "MediaBrowser Token=\"\(token)\""
        }
        guard let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty else {
            return fields
        }
        let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
        if let cookieHeader, !cookieHeader.isEmpty {
            fields["Cookie"] = cookieHeader
        }
        return fields
    }

    private static func apiKey(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "api_key" })?
            .value
    }
}
