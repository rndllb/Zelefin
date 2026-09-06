import Foundation
import Security

struct SecretStore: Sendable {
    private let service = "app.zelefin.client.secrets"

    func load(account: String) -> String? {
        if let keychain = loadFromKeychain(account: account) {
            return keychain
        }
        return UserDefaults.standard.string(forKey: defaultsKey(account))
    }

    func save(_ value: String, account: String) {
        delete(account: account)
        guard let data = value.data(using: .utf8) else { return }
        if addToKeychain(data, account: account) {
            UserDefaults.standard.removeObject(forKey: defaultsKey(account))
            return
        }
        UserDefaults.standard.set(value, forKey: defaultsKey(account))
    }

    func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        _ = SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: defaultsKey(account))
    }

    private func defaultsKey(_ account: String) -> String {
        "zelefin.secret.\(account)"
    }

    private func loadFromKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func addToKeychain(_ data: Data, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }
}
