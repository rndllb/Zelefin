import Foundation
import JellyfinAPI

struct ServerUserAccount: Identifiable, Equatable, Sendable {
    var dto: UserDto

    var id: String { dto.id ?? "" }

    var name: String {
        let trimmed = dto.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "User" : trimmed
    }

    var policy: UserPolicy? { dto.policy }
    var isAdministrator: Bool { dto.policy?.isAdministrator == true }
    var isDisabled: Bool { dto.policy?.isDisabled == true }
    var primaryImageTag: String? { dto.primaryImageTag }

    var statusSubtitle: String {
        var parts: [String] = []
        if isAdministrator { parts.append("Administrator") }
        if isDisabled { parts.append("Disabled") }
        if parts.isEmpty { parts.append("User") }
        return parts.joined(separator: " · ")
    }
}

struct AdminMediaFolder: Identifiable, Equatable, Sendable, Hashable {
    let id: String
    let name: String
}

struct ParentalRatingChoice: Identifiable, Equatable, Sendable, Hashable {
    var id: String { "\(value ?? -1)-\(name)" }
    let name: String
    let value: Int?
}

struct UserPolicyDraft: Equatable, Sendable {
    var isAdministrator: Bool
    var isDisabled: Bool
    var remoteClientBitrateLimit: Int
    var maxParentalRating: Int?
    var blockUnratedItems: Set<UnratedItem>
    var enableAllFolders: Bool
    var enabledFolders: Set<String>
}

extension UserPolicyDraft {
    init(policy: UserPolicy) {
        isAdministrator = policy.isAdministrator == true
        isDisabled = policy.isDisabled == true
        remoteClientBitrateLimit = max(0, policy.remoteClientBitrateLimit ?? 0)
        maxParentalRating = policy.maxParentalRating
        blockUnratedItems = Set(policy.blockUnratedItems ?? [])
        enableAllFolders = policy.enableAllFolders ?? true
        enabledFolders = Set(policy.enabledFolders ?? [])
    }

    func applying(to policy: UserPolicy) -> UserPolicy {
        var next = policy
        next.isAdministrator = isAdministrator
        next.isDisabled = isDisabled
        next.remoteClientBitrateLimit = remoteClientBitrateLimit
        next.maxParentalRating = maxParentalRating
        next.blockUnratedItems = Array(blockUnratedItems).sorted { $0.rawValue < $1.rawValue }
        next.enableAllFolders = enableAllFolders
        next.enabledFolders = enableAllFolders ? [] : Array(enabledFolders).sorted()
        return next
    }
}

enum RemoteBitrateLimit: Int, CaseIterable, Identifiable, Sendable {
    case unlimited = 0
    case kbps420 = 420_000
    case kbps720 = 720_000
    case mbps1 = 1_000_000
    case mbps2 = 2_000_000
    case mbps4 = 4_000_000
    case mbps8 = 8_000_000
    case mbps15 = 15_000_000
    case mbps40 = 40_000_000
    case mbps80 = 80_000_000
    case mbps120 = 120_000_000

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .unlimited: "Unlimited"
        case .kbps420: "420 kbps"
        case .kbps720: "720 kbps"
        case .mbps1: "1 Mbps"
        case .mbps2: "2 Mbps"
        case .mbps4: "4 Mbps"
        case .mbps8: "8 Mbps"
        case .mbps15: "15 Mbps"
        case .mbps40: "40 Mbps"
        case .mbps80: "80 Mbps"
        case .mbps120: "120 Mbps"
        }
    }

    static func resolved(_ bitsPerSecond: Int) -> Int {
        let clamped = max(0, bitsPerSecond)
        if allCases.contains(where: { $0.rawValue == clamped }) {
            return clamped
        }
        return clamped
    }
}

extension UnratedItem {
    var settingsTitle: String {
        switch self {
        case .movie: "Movies"
        case .trailer: "Trailers"
        case .series: "Shows"
        case .music: "Music"
        case .book: "Books"
        case .liveTvChannel: "Live TV channels"
        case .liveTvProgram: "Live TV programs"
        case .channelContent: "Channel content"
        case .other: "Other"
        }
    }
}

enum UserImageAdminPolicy {
    static func canChangePhoto(actorIsAdmin: Bool, actorUserID: String?, targetUserID: String) -> Bool {
        guard !targetUserID.isEmpty else { return false }
        if actorUserID == targetUserID { return true }
        return actorIsAdmin
    }
}

protocol UserAdministering: Sendable {
    func users() async throws -> [ServerUserAccount]
    func user(id: String) async throws -> ServerUserAccount
    func mediaFolders() async throws -> [AdminMediaFolder]
    func parentalRatings() async throws -> [ParentalRatingChoice]
    func updatePolicy(userID: String, policy: UserPolicy) async throws
    func renameUser(_ account: ServerUserAccount, name: String) async throws
    func resetPassword(userID: String) async throws
    func setPassword(userID: String, newPassword: String) async throws
}

struct JellyfinUserAdminClient: UserAdministering {
    private let client: JellyfinClient

    init(client: JellyfinClient) {
        self.client = client
    }

    func users() async throws -> [ServerUserAccount] {
        let result = try await client.send(Paths.getUsers())
        return result.value.compactMap { dto in
            guard let id = dto.id, !id.isEmpty else { return nil }
            return ServerUserAccount(dto: dto)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func user(id: String) async throws -> ServerUserAccount {
        guard !id.isEmpty else { throw ZelefinError.missingUser }
        let dto = try await client.send(Paths.getUserByID(userID: id)).value
        guard let userID = dto.id, !userID.isEmpty else {
            throw ZelefinError.missingUser
        }
        return ServerUserAccount(dto: dto)
    }

    func mediaFolders() async throws -> [AdminMediaFolder] {
        let result = try await client.send(Paths.getMediaFolders())
        return (result.value.items ?? []).compactMap { item in
            guard let id = item.id, !id.isEmpty else { return nil }
            let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return AdminMediaFolder(id: id, name: name.isEmpty ? "Library" : name)
        }
    }

    func parentalRatings() async throws -> [ParentalRatingChoice] {
        let result = try await client.send(Paths.getParentalRatings)
        var seen = Set<String>()
        return result.value.compactMap { rating in
            let name = rating.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return nil }
            let choice = ParentalRatingChoice(name: name, value: rating.value)
            guard seen.insert(choice.id).inserted else { return nil }
            return choice
        }
    }

    func updatePolicy(userID: String, policy: UserPolicy) async throws {
        guard !userID.isEmpty else { throw ZelefinError.missingUser }
        _ = try await client.send(Paths.updateUserPolicy(userID: userID, policy))
    }

    func renameUser(_ account: ServerUserAccount, name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ZelefinError.server("Enter a username.")
        }
        guard let userID = account.dto.id, !userID.isEmpty else {
            throw ZelefinError.missingUser
        }
        var dto = account.dto
        dto.name = trimmed
        _ = try await client.send(Paths.updateUser(userID: userID, dto))
    }

    func resetPassword(userID: String) async throws {
        guard !userID.isEmpty else { throw ZelefinError.missingUser }
        let body = UpdateUserPassword(isResetPassword: true)
        _ = try await client.send(Paths.updateUserPassword(userID: userID, body))
    }

    func setPassword(userID: String, newPassword: String) async throws {
        guard !userID.isEmpty else { throw ZelefinError.missingUser }
        guard !newPassword.isEmpty else {
            throw ZelefinError.server("Enter a new password.")
        }
        let body = UpdateUserPassword(isResetPassword: false, newPw: newPassword)
        _ = try await client.send(Paths.updateUserPassword(userID: userID, body))
    }
}
