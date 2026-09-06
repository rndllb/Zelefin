import Foundation

struct SeerrSession: Codable, Equatable, Sendable {
    var cookieName: String
    var cookieValue: String
    var displayName: String
}

enum PluginSettings {
    static let seerrURLKey = "zelefin.seerr.url"
    private static let seerrSessionAccount = "seerr-session"
    private static let legacyAPIKeyAccount = "seerr-api-key"
    private static let secrets = SecretStore()

    static var seerrURLString: String {
        get { UserDefaults.standard.string(forKey: seerrURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: seerrURLKey) }
    }

    static var seerrSession: SeerrSession? {
        get {
            guard let raw = secrets.load(account: seerrSessionAccount),
                  let data = raw.data(using: .utf8),
                  let session = try? JSONDecoder().decode(SeerrSession.self, from: data),
                  !session.cookieValue.isEmpty
            else { return nil }
            return session
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue),
               let raw = String(data: data, encoding: .utf8)
            {
                secrets.save(raw, account: seerrSessionAccount)
            } else {
                secrets.delete(account: seerrSessionAccount)
            }
            secrets.delete(account: legacyAPIKeyAccount)
        }
    }

    static var isSeerrConfigured: Bool {
        seerrURL != nil && seerrSession != nil
    }

    static var seerrClient: SeerrClient? {
        guard let url = seerrURL, let session = seerrSession else { return nil }
        return SeerrClient(baseURL: url, session: session)
    }

    static var normalizedSeerrURLString: String {
        let trimmed = seerrURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return String(trimmed.trimmingSuffix(while: { $0 == "/" }))
        }
        return "https://\(trimmed.trimmingSuffix(while: { $0 == "/" }))"
    }

    static var seerrURL: URL? {
        URL(string: normalizedSeerrURLString)
    }

    static func clearSeerrSession() {
        seerrSession = nil
    }
}

private extension String {
    func trimmingSuffix(while predicate: (Character) -> Bool) -> String {
        var value = self
        while let last = value.last, predicate(last) {
            value.removeLast()
        }
        return value
    }
}
