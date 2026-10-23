import Foundation

/// A household profile on a Silo account.
struct SiloProfile: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var avatar: String?
    var avatarURL: URL?
    var hasPin: Bool
    var isChild: Bool
    var isPrimary: Bool
    var avatarSource: String?

    enum CodingKeys: String, CodingKey {
        case id, name, avatar
        case avatarURL = "avatar_url"
        case hasPin = "has_pin"
        case isChild = "is_child"
        case isPrimary = "is_primary"
        case avatarSource = "avatar_source"
    }

    var hasUploadedAvatar: Bool { avatarSource == "upload" }
    var hasAvatar: Bool { avatarSource == "upload" || avatarSource == "preset" }

    /// `avatar_url` is a URI reference, often relative to the Silo address, and presets point
    /// at SVGs that UIImage can't draw, so they're asked for as PNG.
    func resolved(against base: URL) -> SiloProfile {
        guard let avatarURL else { return self }
        var copy = self
        copy.avatarURL = SiloProfileAvatars.displayURL(baseURL: base, raw: avatarURL.relativeString)
        return copy
    }
}

/// Kept with the Jellyfin session so profiles can be switched, and profile pictures changed,
/// without asking for the Silo password again.
struct SiloLink: Codable, Equatable, Sendable {
    var nativeURL: URL
    var accessToken: String
    var refreshToken: String
    var profileID: String
    var profileName: String
    var profileHasPin: Bool
    var profileToken: String?
}

struct SiloProfileCollection: Decodable, Sendable {
    var items: [SiloProfile]
    var avatarUploadEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case items
        case avatarUploadEnabled = "avatar_upload_enabled"
    }
}

struct SiloTokenPair: Decodable, Sendable {
    var accessToken: String
    var refreshToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

struct SiloProfileVerification: Decodable, Sendable {
    var valid: Bool
    var profileToken: String?

    enum CodingKeys: String, CodingKey {
        case valid
        case profileToken = "profile_token"
    }
}

struct SiloConnectInfo: Decodable, Sendable {
    struct Jellyfin: Decodable, Sendable {
        var enabled: Bool
        var pendingRestart: Bool
        var publicURL: String
        var serverName: String

        enum CodingKeys: String, CodingKey {
            case enabled
            case pendingRestart = "pending_restart"
            case publicURL = "public_url"
            case serverName = "server_name"
        }
    }

    var jellyfin: Jellyfin

    /// The Jellyfin-compatible address, or the reason Zelefin can't use it yet.
    func compatibleURL() throws -> URL {
        guard jellyfin.enabled else {
            throw ZelefinError.server("Turn on Silo's Jellyfin-compatible API in its admin settings, then sign in again.")
        }
        guard !jellyfin.pendingRestart else {
            throw ZelefinError.server("Restart Silo to finish turning on its Jellyfin-compatible API, then sign in again.")
        }
        let raw = jellyfin.publicURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = try? ServerURL.normalize(raw), !raw.isEmpty else {
            throw ZelefinError.server("Set a public address for Silo's Jellyfin-compatible API in its admin settings, then sign in again.")
        }
        return url
    }
}

/// Silo's own API, used only for signing in, household profiles, and profile pictures.
/// Libraries and playback go through Silo's Jellyfin-compatible API like any Jellyfin server.
actor SiloAccountClient {
    let baseURL: URL
    private(set) var accessToken: String
    private(set) var refreshToken: String
    private var onTokens: (@Sendable (String, String) -> Void)?

    init(baseURL: URL, accessToken: String = "", refreshToken: String = "") {
        self.baseURL = baseURL
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }

    func setTokenHandler(_ handler: @escaping @Sendable (String, String) -> Void) {
        onTokens = handler
    }

    /// Silo's main address answers its own setup check without signing in.
    static func isSiloAddress(_ url: URL) async -> Bool {
        for path in ["/api/v2/system/setup", "/api/v1/health"] {
            guard let probe = ServerURL.resolve(base: url, path: path) else { continue }
            var request = URLRequest(url: probe)
            request.timeoutInterval = 6
            guard let (data, response) = try? await JellyfinNetworking.apiData(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
                continue
            }
            return true
        }
        return false
    }

    func login(username: String, password: String) async throws {
        let pair: SiloTokenPair = try await send(
            "POST",
            "/api/v2/auth/login",
            json: ["username": username, "password": password],
            authorized: false
        )
        store(pair)
    }

    func profiles() async throws -> SiloProfileCollection {
        var collection: SiloProfileCollection = try await send("GET", "/api/v2/profiles")
        collection.items = collection.items.map { $0.resolved(against: baseURL) }
        return collection
    }

    /// The profile token Silo wants beside `X-Profile-Id` for a PIN profile.
    func verifyPIN(profileID: String, pin: String) async throws -> String {
        let result: SiloProfileVerification = try await send(
            "POST",
            "/api/v2/profiles/\(Self.path(profileID))/verify-pin",
            json: ["pin": pin]
        )
        guard result.valid, let token = result.profileToken, !token.isEmpty else {
            throw ZelefinError.server("That PIN is not correct.")
        }
        return token
    }

    func connectInfo() async throws -> SiloConnectInfo {
        try await send("GET", "/api/v2/compat/connect-info")
    }

    /// Approves a Jellyfin Quick Connect code for one profile, so the Jellyfin-compatible
    /// session that collects it belongs to that profile.
    func approveHandoff(code: String, profileID: String, profileToken: String?) async throws {
        struct Decision: Decodable { var status: String }
        let decision: Decision = try await send(
            "POST",
            "/api/v2/auth/device/approve-handoff",
            json: ["code": code],
            headers: Self.profileHeaders(profileID, profileToken)
        )
        guard decision.status == "approved" else {
            throw ZelefinError.server("Silo did not approve this profile for Zelefin.")
        }
    }

    func uploadAvatar(profileID: String, profileToken: String?, jpeg: Data) async throws -> SiloProfile {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"avatar\"; filename=\"avatar.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(jpeg)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var headers = Self.profileHeaders(profileID, profileToken)
        headers["Content-Type"] = "multipart/form-data; boundary=\(boundary)"
        let profile: SiloProfile = try await send(
            "PUT",
            "/api/v2/profiles/\(Self.path(profileID))/avatar",
            body: body,
            headers: headers
        )
        return profile.resolved(against: baseURL)
    }

    /// `preset` is a reference such as `preset:dicebear:fun-emoji:mango-otter`; nil clears the avatar.
    func setAvatarPreset(profileID: String, profileToken: String?, preset: String?) async throws -> SiloProfile {
        var headers = Self.profileHeaders(profileID, profileToken)
        headers["Content-Type"] = "application/json"
        let value: Any = preset ?? NSNull()
        let body = try JSONSerialization.data(withJSONObject: ["avatar": value])
        let profile: SiloProfile = try await send(
            "PATCH",
            "/api/v2/profiles/\(Self.path(profileID))",
            body: body,
            headers: headers
        )
        return profile.resolved(against: baseURL)
    }

    func deleteAvatar(profileID: String, profileToken: String?) async throws {
        _ = try await data(
            "DELETE",
            "/api/v2/profiles/\(Self.path(profileID))/avatar",
            body: nil,
            headers: Self.profileHeaders(profileID, profileToken),
            authorized: true
        )
    }

    func logout() async {
        _ = try? await data("POST", "/api/v2/auth/logout", body: nil, headers: [:], authorized: true)
    }

    // MARK: Transport

    private func send<T: Decodable>(
        _ method: String,
        _ path: String,
        json: [String: String]? = nil,
        body: Data? = nil,
        headers: [String: String] = [:],
        authorized: Bool = true
    ) async throws -> T {
        var headers = headers
        var payload = body
        if let json {
            payload = try JSONSerialization.data(withJSONObject: json)
            headers["Content-Type"] = "application/json"
        }
        let data = try await data(method, path, body: payload, headers: headers, authorized: authorized)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ZelefinError.server("Silo sent a reply Zelefin could not read.")
        }
    }

    private func data(
        _ method: String,
        _ path: String,
        body: Data?,
        headers: [String: String],
        authorized: Bool,
        retried: Bool = false
    ) async throws -> Data {
        guard let url = ServerURL.resolve(base: baseURL, path: path) else { throw ZelefinError.invalidServerURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        if authorized, !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await JellyfinNetworking.apiData(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, authorized, !retried, !refreshToken.isEmpty {
            try await refresh()
            return try await self.data(method, path, body: body, headers: headers, authorized: authorized, retried: true)
        }
        guard (200 ..< 300).contains(status) else {
            if status == 401, authorized {
                throw ZelefinError.server("Your Silo sign-in expired. Sign in again.")
            }
            throw ZelefinError.server(Self.problemMessage(in: data) ?? "Silo could not do that (HTTP \(status)).")
        }
        return data
    }

    private func refresh() async throws {
        let pair: SiloTokenPair = try await send(
            "POST",
            "/api/v2/auth/refresh",
            json: ["refresh_token": refreshToken],
            authorized: false
        )
        store(pair)
    }

    private func store(_ pair: SiloTokenPair) {
        accessToken = pair.accessToken
        refreshToken = pair.refreshToken
        onTokens?(pair.accessToken, pair.refreshToken)
    }

    /// RFC 7807 problem details: the field errors when there are any, else `detail`, else `title`.
    static func problemMessage(in data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let fieldErrors = (json["errors"] as? [[String: Any]] ?? [])
            .compactMap { ($0["detail"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !fieldErrors.isEmpty { return fieldErrors.joined(separator: " ") }
        for key in ["detail", "title", "Message"] {
            if let text = (json[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return text
            }
        }
        return nil
    }

    private static func profileHeaders(_ profileID: String, _ profileToken: String?) -> [String: String] {
        var headers = ["X-Profile-Id": profileID]
        if let profileToken, !profileToken.isEmpty {
            headers["X-Profile-Token"] = profileToken
        }
        return headers
    }

    private static func path(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    }
}
