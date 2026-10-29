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
    static let requestServiceKey = "zelefin.requests.service"
    private static let seerrSessionAccount = "seerr-session"
    private static let ombiSessionAccount = "ombi-session"
    private static let seerrCredentialsAccount = "seerr-credentials"
    private static let legacyAPIKeyAccount = "seerr-api-key"
    private static let secrets = SecretStore()

    /// Seerr or Ombi. Both use the server, username, and password fields below.
    static var requestService: RequestService {
        get { UserDefaults.standard.string(forKey: requestServiceKey).flatMap(RequestService.init(rawValue:)) ?? .seerr }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: requestServiceKey) }
    }

    static var ombiSession: OmbiSession? {
        get {
            guard let raw = secrets.load(account: ombiSessionAccount),
                  let data = raw.data(using: .utf8),
                  let session = try? JSONDecoder().decode(OmbiSession.self, from: data),
                  !session.token.isEmpty
            else { return nil }
            return session
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue),
               let raw = String(data: data, encoding: .utf8)
            {
                secrets.save(raw, account: ombiSessionAccount)
            } else {
                secrets.delete(account: ombiSessionAccount)
            }
        }
    }

    /// The signed-in name on the chosen request server.
    static var requestDisplayName: String? {
        switch requestService {
        case .seerr: seerrSession?.displayName
        case .ombi: ombiSession?.displayName
        }
    }

    static var hasRequestSession: Bool {
        requestDisplayName != nil
    }

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
        seerrURL != nil && hasRequestSession
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

    static var seerrClient: (any RequestServiceClient)? {
        guard let url = seerrURL else { return nil }
        switch requestService {
        case .seerr:
            guard let session = seerrSession else { return nil }
            return SeerrClient(baseURL: url, session: session)
        case .ombi:
            guard let session = ombiSession else { return nil }
            return OmbiClient(baseURL: url, session: session)
        }
    }

    /// Signs in to the chosen request server and keeps the password for signing in again later.
    /// Returns the name it signed in as.
    static func signIn(username: String, password: String, ownerAccountID: String?) async throws -> String {
        let candidates = ServerURL.candidates(seerrURLString)
        guard let last = candidates.last else {
            throw ZelefinError.server("Enter a valid \(requestService.name) URL.")
        }
        for url in candidates {
            do {
                let name = try await signIn(to: url, username: username, password: password, ownerAccountID: ownerAccountID)
                seerrURLString = url.absoluteString
                return name
            } catch is URLError where url != last {
                continue
            }
        }
        throw ZelefinError.server("Enter a valid \(requestService.name) URL.")
    }

    private static func signIn(to url: URL, username: String, password: String, ownerAccountID: String?) async throws -> String {
        switch requestService {
        case .seerr:
            let signedIn = try await SeerrClient.signIn(baseURL: url, username: username, password: password)
            rememberSignIn(signedIn, username: username, password: password, ownerAccountID: ownerAccountID)
            return signedIn.displayName
        case .ombi:
            let signedIn = try await OmbiClient.signIn(baseURL: url, username: username, password: password)
            seerrSession = nil
            ombiSession = signedIn
            seerrCredentials = SeerrCredentials(username: username, password: password)
            seerrOwnerAccountID = ownerAccountID
            return signedIn.displayName
        }
    }

    /// The saved address, cleaned the way the sign-in screen cleans a server address.
    static var seerrURL: URL? {
        ServerURL.candidates(seerrURLString).first
    }

    static func clearSeerrSession() {
        seerrSession = nil
        ombiSession = nil
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

    /// Confirms the stored session, or signs in again with the saved password. Network failures keep the session.
    static func refreshUser() async -> SeerrUser? {
        guard let client = seerrClient else { return nil }
        do {
            let user = try await client.currentUser()
            rename(to: user.displayLabel)
            return user
        } catch {
            guard error.isSeerrUnauthorized else { return nil }
            return await reauthenticate()
        }
    }

    private static func rename(to name: String) {
        switch requestService {
        case .seerr:
            if var saved = seerrSession {
                saved.displayName = name
                seerrSession = saved
            }
        case .ombi:
            if var saved = ombiSession {
                saved.displayName = name
                ombiSession = saved
            }
        }
    }

    private static func reauthenticate() async -> SeerrUser? {
        guard let url = seerrURL, let credentials = seerrCredentials else {
            clearSeerrSession()
            return nil
        }
        if requestService == .ombi {
            do {
                let signedIn = try await OmbiClient.signIn(baseURL: url, username: credentials.username, password: credentials.password)
                ombiSession = signedIn
                return try await OmbiClient(baseURL: url, session: signedIn).currentUser()
            } catch {
                if error.isSeerrUnauthorized { clearSeerrSession() }
                return nil
            }
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
