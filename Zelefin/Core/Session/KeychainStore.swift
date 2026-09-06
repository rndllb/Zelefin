import Foundation
import Security

struct SavedSession: Codable, Equatable, Sendable {
    var serverURL: URL
    var accessToken: String
    var userID: String
    var userName: String
    var deviceID: String
    var userImageTag: String?
    var serverVersion: String?
}

/// Persists the signed-in session. Keychain is preferred; UserDefaults is used when
/// the process has no keychain entitlement (common in unsigned Simulator runs, status -34018).
struct SessionVault: Sendable {
    private let defaultsKey = "zelefin.saved-session"
    private let service = "app.zelefin.client.session"
    private let account = "current"

    func load() throws -> SavedSession? {
        if let session = try loadFromKeychain() {
            return session
        }
        return loadFromDefaults()
    }

    func save(_ session: SavedSession) throws {
        let data = try JSONEncoder().encode(session)
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

    private func loadFromKeychain() throws -> SavedSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return try JSONDecoder().decode(SavedSession.self, from: data)
    }

    private func loadFromDefaults() -> SavedSession? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(SavedSession.self, from: data)
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
