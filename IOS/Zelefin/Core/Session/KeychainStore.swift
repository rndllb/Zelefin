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
    /// A Silo server answering through its Jellyfin-compatible API, which leaves out Jellyfin's
    /// administration, SyncPlay, playlists, remote control, and Live TV.
    var isSiloServer: Bool
    /// Present when Zelefin signed in through Silo's own sign-in and picked a household profile.
    var siloLink: SiloLink?
    /// Signed in through the Silo-native backend Zelefin no longer has; its tokens do not work
    /// against the Jellyfin-compatible API, so the account is dropped on load.
    private(set) var isRetiredSiloSignIn = false

    var id: String { accountID }

    var accountID: String {
        let host = serverURL.host?.lowercased() ?? serverURL.absoluteString.lowercased()
        return "\(host)|\(userID)"
    }

    /// Silo's Jellyfin-compatible API names a profile's user `username#profile`; only the
    /// profile is shown.
    static func displayName(_ raw: String, isSiloServer: Bool) -> String {
        guard isSiloServer, let hash = raw.lastIndex(of: "#") else { return raw }
        let profile = raw[raw.index(after: hash)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return profile.isEmpty ? raw : profile
    }

    var displayServer: String {
        let name = serverName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        return serverURL.host ?? serverURL.absoluteString
    }

    init(
        serverURL: URL,
        accessToken: String,
        userID: String,
        userName: String,
        deviceID: String,
        userImageTag: String? = nil,
        serverVersion: String? = nil,
        serverName: String? = nil,
        isSiloServer: Bool = false,
        siloLink: SiloLink? = nil
    ) {
        self.serverURL = serverURL
        self.accessToken = accessToken
        self.userID = userID
        self.userName = userName
        self.deviceID = deviceID
        self.userImageTag = userImageTag
        self.serverVersion = serverVersion
        self.serverName = serverName
        self.isSiloServer = isSiloServer
        self.siloLink = siloLink
    }

    private enum CodingKeys: String, CodingKey {
        case serverURL, accessToken, userID, userName, deviceID, userImageTag, serverVersion, serverName
        case isSiloServer, siloLink
        case backend
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
        isSiloServer = try container.decodeIfPresent(Bool.self, forKey: .isSiloServer) ?? false
        userName = Self.displayName(userName, isSiloServer: isSiloServer)
        siloLink = try? container.decodeIfPresent(SiloLink.self, forKey: .siloLink)
        isRetiredSiloSignIn = (try? container.decodeIfPresent(String.self, forKey: .backend)) == "silo"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(serverURL, forKey: .serverURL)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encode(userID, forKey: .userID)
        try container.encode(userName, forKey: .userName)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encodeIfPresent(userImageTag, forKey: .userImageTag)
        try container.encodeIfPresent(serverVersion, forKey: .serverVersion)
        try container.encodeIfPresent(serverName, forKey: .serverName)
        try container.encode(isSiloServer, forKey: .isSiloServer)
        try container.encodeIfPresent(siloLink, forKey: .siloLink)
    }
}

struct SavedAccountBox: Codable, Equatable, Sendable {
    var accounts: [SavedSession]
    var currentID: String
    /// Accounts left out on load because they came from the retired Silo-native sign-in.
    private(set) var retiredSiloAccounts = 0

    private enum CodingKeys: String, CodingKey {
        case accounts, currentID
    }

    init(accounts: [SavedSession], currentID: String) {
        self.accounts = accounts
        self.currentID = currentID
    }

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
        var box: SavedAccountBox
        if let decoded = try? decoder.decode(SavedAccountBox.self, from: data), !decoded.accounts.isEmpty {
            box = decoded
        } else {
            let session = try decoder.decode(SavedSession.self, from: data)
            box = SavedAccountBox(accounts: [session], currentID: session.accountID)
        }
        let retired = box.accounts.filter(\.isRetiredSiloSignIn).count
        box.accounts.removeAll(where: \.isRetiredSiloSignIn)
        box.retiredSiloAccounts = retired
        return box
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
