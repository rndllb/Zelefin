import Foundation
import Security

struct SavedSession: Codable, Equatable, Sendable, Identifiable {
    var serverURL: URL
    var accessToken: String
    var userID: String
    var userName: String
    var deviceID: String
    var userImageTag: String?
    var serverVersion: String?
    var serverName: String?
    var backend: MediaBackend
    var refreshToken: String?
    var profileID: String?
    var profileToken: String?
    var profileName: String?
    var userRole: String?
    var isPrimaryProfile: Bool

    var id: String { accountID }

    var accountID: String {
        let host = serverURL.host?.lowercased() ?? serverURL.absoluteString.lowercased()
        return "\(host)|\(userID)"
    }

    var displayServer: String {
        let name = serverName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        return serverURL.host ?? serverURL.absoluteString
    }

    var usesSilo: Bool { backend == .silo }

    init(
        serverURL: URL,
        accessToken: String,
        userID: String,
        userName: String,
        deviceID: String,
        userImageTag: String? = nil,
        serverVersion: String? = nil,
        serverName: String? = nil,
        backend: MediaBackend = .jellyfin,
        refreshToken: String? = nil,
        profileID: String? = nil,
        profileToken: String? = nil,
        profileName: String? = nil,
        userRole: String? = nil,
        isPrimaryProfile: Bool = false
    ) {
        self.serverURL = serverURL
        self.accessToken = accessToken
        self.userID = userID
        self.userName = userName
        self.deviceID = deviceID
        self.userImageTag = userImageTag
        self.serverVersion = serverVersion
        self.serverName = serverName
        self.backend = backend
        self.refreshToken = refreshToken
        self.profileID = profileID
        self.profileToken = profileToken
        self.profileName = profileName
        self.userRole = userRole
        self.isPrimaryProfile = isPrimaryProfile
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverURL = try container.decode(URL.self, forKey: .serverURL)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        userID = try container.decode(String.self, forKey: .userID)
        userName = try container.decode(String.self, forKey: .userName)
        deviceID = try container.decode(String.self, forKey: .deviceID)
        userImageTag = try container.decodeIfPresent(String.self, forKey: .userImageTag)
        serverVersion = try container.decodeIfPresent(String.self, forKey: .serverVersion)
        serverName = try container.decodeIfPresent(String.self, forKey: .serverName)
        backend = try container.decodeIfPresent(MediaBackend.self, forKey: .backend) ?? .jellyfin
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        profileID = try container.decodeIfPresent(String.self, forKey: .profileID)
        profileToken = try container.decodeIfPresent(String.self, forKey: .profileToken)
        profileName = try container.decodeIfPresent(String.self, forKey: .profileName)
        userRole = try container.decodeIfPresent(String.self, forKey: .userRole)
        isPrimaryProfile = try container.decodeIfPresent(Bool.self, forKey: .isPrimaryProfile) ?? false
    }
}

struct SavedAccountBox: Codable, Equatable, Sendable {
    var accounts: [SavedSession]
    var currentID: String

    var current: SavedSession? {
        accounts.first { $0.accountID == currentID } ?? accounts.first
    }

    mutating func upsert(_ session: SavedSession, select: Bool = true) {
        if let index = accounts.firstIndex(where: { $0.accountID == session.accountID }) {
            accounts[index] = session
        } else {
            accounts.append(session)
        }
        if select {
            currentID = session.accountID
        }
    }

    mutating func select(_ id: String) -> SavedSession? {
        guard let session = accounts.first(where: { $0.accountID == id }) else { return nil }
        currentID = id
        return session
    }

    mutating func remove(id: String) -> SavedSession? {
        accounts.removeAll { $0.accountID == id }
        if currentID == id {
            currentID = accounts.first?.accountID ?? ""
        }
        return current
    }

    static func decode(from data: Data) throws -> SavedAccountBox {
        let decoder = JSONDecoder()
        if let box = try? decoder.decode(SavedAccountBox.self, from: data), !box.accounts.isEmpty {
            return box
        }
        let session = try decoder.decode(SavedSession.self, from: data)
        return SavedAccountBox(accounts: [session], currentID: session.accountID)
    }
}

/// Persists signed-in accounts. Keychain is preferred; UserDefaults is used when
/// the process has no keychain entitlement (common in unsigned Simulator runs, status -34018).
struct SessionVault: Sendable {
    private let defaultsKey = "zelefin.saved-session"
    private let service = "app.zelefin.client.session"
    private let account = "current"

    func load() throws -> SavedSession? {
        try loadBox()?.current
    }

    func loadBox() throws -> SavedAccountBox? {
        if let data = try loadDataFromKeychain() {
            return try SavedAccountBox.decode(from: data)
        }
        if let data = UserDefaults.standard.data(forKey: defaultsKey) {
            return try SavedAccountBox.decode(from: data)
        }
        return nil
    }

    func save(_ session: SavedSession, select: Bool = true) throws {
        var box = (try? loadBox()) ?? SavedAccountBox(accounts: [], currentID: "")
        box.upsert(session, select: select)
        try persist(box)
    }

    func persist(_ box: SavedAccountBox) throws {
        if box.accounts.isEmpty {
            delete()
            return
        }
        let data = try JSONEncoder().encode(box)
        deleteQuietly()
        if addToKeychain(data) {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            return
        }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    func delete() {
        deleteQuietly()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private func loadDataFromKeychain() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private func addToKeychain(_ data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private func deleteQuietly() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}
