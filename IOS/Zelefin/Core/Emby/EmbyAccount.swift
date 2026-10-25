import Foundation
import JellyfinAPI

extension EmbyLibraryClient {
    func changePassword(current: String, new: String) async throws {
        try await api.send(
            "POST",
            "/Users/\(userID)/Password",
            json: ["Id": userID, "CurrentPw": current, "NewPw": new, "ResetPassword": false]
        )
    }

    /// Emby, like Jellyfin, reads uploaded image bodies as base64 text.
    func uploadUserImage(userID: String, jpeg: Data) async throws {
        _ = try await api.data(
            "POST",
            "/Users/\(userID)/Images/Primary",
            body: JellyfinImagePayload.requestBody(imageJPEG: jpeg),
            contentType: "image/jpeg"
        )
    }

    func deleteUserImage(userID: String) async throws {
        try await api.send("DELETE", "/Users/\(userID)/Images/Primary")
    }
}

/// Emby replaces a user's whole record or policy on update, so these edits read Emby's own JSON
/// and change only the fields Zelefin's editor shows.
struct EmbyUserAdminClient: UserAdministering {
    let api: EmbyAPI

    static let editedPolicyKeys = [
        "IsAdministrator",
        "IsDisabled",
        "EnableSubtitleManagement",
        "RemoteClientBitrateLimit",
        "MaxParentalRating",
        "BlockUnratedItems",
        "EnableAllFolders",
        "EnabledFolders"
    ]

    func users() async throws -> [ServerUserAccount] {
        let result = try await api.decode(EmbyUserPage.self, "/Users/Query")
        return (result.items ?? []).compactMap { dto in
            guard let id = dto.id, !id.isEmpty else { return nil }
            return ServerUserAccount(dto: dto)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func user(id: String) async throws -> ServerUserAccount {
        guard !id.isEmpty else { throw ZelefinError.missingUser }
        let dto = try await api.decode(UserDto.self, "/Users/\(id)")
        guard let userID = dto.id, !userID.isEmpty else { throw ZelefinError.missingUser }
        return ServerUserAccount(dto: dto)
    }

    func mediaFolders() async throws -> [AdminMediaFolder] {
        let result = try await api.decode(BaseItemDtoQueryResult.self, "/Library/MediaFolders", query: [("IsHidden", "false")])
        return (result.items ?? []).compactMap { item in
            guard let id = item.id, !id.isEmpty else { return nil }
            let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return AdminMediaFolder(id: id, name: name.isEmpty ? "Library" : name)
        }
    }

    func parentalRatings() async throws -> [ParentalRatingChoice] {
        let ratings = try await api.decode([ParentalRating].self, "/Localization/ParentalRatings")
        var seen = Set<String>()
        return ratings.compactMap { rating in
            let name = rating.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return nil }
            let choice = ParentalRatingChoice(name: name, value: rating.value)
            guard seen.insert(choice.id).inserted else { return nil }
            return choice
        }
    }

    func updatePolicy(userID: String, policy: UserPolicy) async throws {
        guard !userID.isEmpty else { throw ZelefinError.missingUser }
        let current = try await rawUser(id: userID)["Policy"] as? [String: Any] ?? [:]
        let body = try Self.policyBody(current: current, applying: policy)
        try await api.send("POST", "/Users/\(userID)/Policy", json: body)
    }

    static func policyBody(current: [String: Any], applying policy: UserPolicy) throws -> [String: Any] {
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(policy)) as? [String: Any] ?? [:]
        var next = current
        for key in editedPolicyKeys {
            next[key] = encoded[key]
        }
        let known = Set(UnratedItem.allCases.map(\.rawValue))
        let embyOnly = (current["BlockUnratedItems"] as? [String] ?? []).filter { !known.contains($0) }
        if !embyOnly.isEmpty {
            next["BlockUnratedItems"] = (encoded["BlockUnratedItems"] as? [String] ?? []) + embyOnly
        }
        return next
    }

    func renameUser(_ account: ServerUserAccount, name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ZelefinError.server("Enter a username.") }
        guard let userID = account.dto.id, !userID.isEmpty else { throw ZelefinError.missingUser }
        var user = try await rawUser(id: userID)
        user["Name"] = trimmed
        try await api.send("POST", "/Users/\(userID)", json: user)
    }

    func resetPassword(userID: String) async throws {
        guard !userID.isEmpty else { throw ZelefinError.missingUser }
        try await api.send("POST", "/Users/\(userID)/Password", json: ["Id": userID, "ResetPassword": true])
    }

    func setPassword(userID: String, newPassword: String) async throws {
        guard !userID.isEmpty else { throw ZelefinError.missingUser }
        guard !newPassword.isEmpty else { throw ZelefinError.server("Enter a new password.") }
        try await api.send(
            "POST",
            "/Users/\(userID)/Password",
            json: ["Id": userID, "NewPw": newPassword, "ResetPassword": false]
        )
    }

    private func rawUser(id: String) async throws -> [String: Any] {
        guard let user = EmbyJSON.object(from: try await api.data("GET", "/Users/\(id)")) else {
            throw ZelefinError.missingUser
        }
        return user
    }
}

struct EmbyUserPage: Decodable, Sendable {
    var items: [UserDto]?

    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }
}

/// Emby's own subtitle providers, searched and downloaded through its RemoteSearch routes.
struct EmbySubtitleClient: RemoteSubtitleSearching {
    let api: EmbyAPI
    let userID: String

    func search(itemID: String, language: String, perfectMatch: Bool) async throws -> [RemoteSubtitleMatch] {
        let results = try await api.decode(
            [RemoteSubtitleInfo].self,
            "/Items/\(itemID)/RemoteSearch/Subtitles/\(language)",
            query: [("IsPerfectMatch", perfectMatch ? "true" : nil)]
        )
        return results.compactMap(RemoteSubtitleMatch.init)
    }

    func download(itemID: String, subtitleID: String, userID: String) async throws {
        let before = await subtitleCount(itemID: itemID)
        try await api.send("POST", "/Items/\(itemID)/RemoteSearch/Subtitles/\(subtitleID)")
        for _ in 0 ..< 20 {
            try? await Task.sleep(for: .milliseconds(400))
            if await subtitleCount(itemID: itemID) != before { return }
        }
    }

    private func subtitleCount(itemID: String) async -> Int {
        let dto = try? await api.decode(BaseItemDto.self, "/Users/\(userID)/Items/\(itemID)")
        let streams = dto?.mediaStreams ?? dto?.mediaSources?.first?.mediaStreams ?? []
        return streams.filter { $0.type == .subtitle }.count
    }
}
