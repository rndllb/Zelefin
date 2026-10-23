import Foundation

struct SeerrSession: Codable, Equatable, Sendable {
    var cookieName: String
    var cookieValue: String
    var displayName: String
}

struct SeerrCredentials: Codable, Equatable, Sendable {
    var username: String
    var password: String
}

enum PluginSettings {
    static let seerrURLKey = "zelefin.seerr.url"
    static let seerrOwnerKey = "zelefin.seerr.owner"
    private static let seerrSessionAccount = "seerr-session"
    private static let seerrCredentialsAccount = "seerr-credentials"
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

    static var seerrCredentials: SeerrCredentials? {
        get {
            guard let raw = secrets.load(account: seerrCredentialsAccount),
                  let data = raw.data(using: .utf8),
                  let credentials = try? JSONDecoder().decode(SeerrCredentials.self, from: data),
                  !credentials.username.isEmpty,
                  !credentials.password.isEmpty
            else { return nil }
            return credentials
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue),
               let raw = String(data: data, encoding: .utf8)
            {
                secrets.save(raw, account: seerrCredentialsAccount)
            } else {
                secrets.delete(account: seerrCredentialsAccount)
            }
        }
    }

    static var seerrOwnerAccountID: String? {
        get {
            let value = UserDefaults.standard.string(forKey: seerrOwnerKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: seerrOwnerKey)
            } else {
                UserDefaults.standard.removeObject(forKey: seerrOwnerKey)
            }
        }
    }

    static var isSeerrConfigured: Bool {
        seerrURL != nil && seerrSession != nil
    }

    static func rememberSignIn(
        _ session: SeerrSession,
        username: String,
        password: String,
        ownerAccountID: String?
    ) {
        seerrSession = session
        seerrCredentials = SeerrCredentials(username: username, password: password)
        seerrOwnerAccountID = ownerAccountID
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
        seerrCredentials = nil
        seerrOwnerAccountID = nil
    }

    /// Keep Seerr across relaunch and app updates. Drop it only when a different Jellyfin user is applied.
    static func shouldClearSession(
        switchingFrom currentAccountID: String?,
        to nextAccountID: String,
        ownerAccountID: String? = seerrOwnerAccountID
    ) -> Bool {
        if let currentAccountID, currentAccountID != nextAccountID { return true }
        if let ownerAccountID, ownerAccountID != nextAccountID { return true }
        return false
    }

    /// Confirms the stored cookie, or signs in again with the saved password. Network failures keep the session.
    static func refreshUser() async -> SeerrUser? {
        guard let client = seerrClient else { return nil }
        do {
            let user = try await client.currentUser()
            if var saved = seerrSession {
                saved.displayName = user.displayLabel
                seerrSession = saved
            }
            return user
        } catch {
            guard error.isSeerrUnauthorized else { return nil }
            return await reauthenticate()
        }
    }

    private static func reauthenticate() async -> SeerrUser? {
        guard let url = seerrURL, let credentials = seerrCredentials else {
            clearSeerrSession()
            return nil
        }
        do {
            let signedIn = try await SeerrClient.signIn(
                baseURL: url,
                username: credentials.username,
                password: credentials.password
            )
            seerrSession = signedIn
            let user = try await SeerrClient(baseURL: url, session: signedIn).currentUser()
            var saved = signedIn
            saved.displayName = user.displayLabel
            seerrSession = saved
            return user
        } catch {
            if error.isSeerrUnauthorized {
                clearSeerrSession()
            }
            return nil
        }
    }
}

extension Error {
    var isSeerrUnauthorized: Bool {
        if let error = self as? ZelefinError, case .seerrUnauthorized = error {
            return true
        }
        return false
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
