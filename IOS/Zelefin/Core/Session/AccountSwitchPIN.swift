import CryptoKit
import Foundation
import LocalAuthentication
import Security
import UIKit

/// Device-local 4–6 digit PIN that locks a saved account so others can’t sign into it.
/// Stored in the Keychain as a salted hash — never the digits themselves.
enum AccountSwitchPIN {
    private static let service = "app.zelefin.client.account-pin"
    private static let biometricsPrefix = "zelefin.account-pin.biometrics."

    static var biometricsName: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "Face ID or Touch ID"
        }
        switch context.biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        case .none:
            return "Face ID or Touch ID"
        @unknown default:
            return "Face ID or Touch ID"
        }
    }

    static var canUseBiometrics: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    static func isValidPIN(_ pin: String) -> Bool {
        guard pin.count >= 4, pin.count <= 6 else { return false }
        return pin.allSatisfy(\.isNumber)
    }

    static func hasPIN(for accountID: String) -> Bool {
        loadDigest(accountID: accountID) != nil
    }

    static func biometricsEnabled(for accountID: String) -> Bool {
        guard hasPIN(for: accountID) else { return false }
        let key = biometricsPrefix + accountID
        if UserDefaults.standard.object(forKey: key) == nil {
            return canUseBiometrics
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func setBiometricsEnabled(_ enabled: Bool, for accountID: String) {
        UserDefaults.standard.set(enabled, forKey: biometricsPrefix + accountID)
    }

    static func setPIN(_ pin: String, for accountID: String) throws {
        let trimmed = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidPIN(trimmed) else {
            throw ZelefinError.server("Enter a 4 to 6 digit PIN.")
        }
        let digest = Self.digest(trimmed, accountID: accountID)
        remove(for: accountID)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: digest
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ZelefinError.server("Zelefin could not save this PIN on the device.")
        }
        if UserDefaults.standard.object(forKey: biometricsPrefix + accountID) == nil {
            setBiometricsEnabled(canUseBiometrics, for: accountID)
        }
    }

    static func verifyPIN(_ pin: String, for accountID: String) -> Bool {
        let trimmed = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stored = loadDigest(accountID: accountID) else { return false }
        return stored == digest(trimmed, accountID: accountID)
    }

    static func remove(for accountID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID
        ]
        _ = SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: biometricsPrefix + accountID)
    }

    @MainActor
    static func authenticateBiometrics(reason: String) async -> Bool {
        guard canUseBiometrics else { return false }
        let context = LAContext()
        context.localizedFallbackTitle = "Enter PIN"
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch {
            return false
        }
    }

    private static func digest(_ pin: String, accountID: String) -> Data {
        let payload = Data("zelefin.pin.v1|\(accountID)|\(pin)".utf8)
        return Data(SHA256.hash(data: payload))
    }

    private static func loadDigest(accountID: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }
}

/// Prompts for Face ID / Touch ID or the account PIN before signing into a locked login.
@MainActor
enum AccountSwitchUnlock {
    static func unlockIfNeeded(account: SavedSession) async -> Bool {
        let accountID = account.accountID
        guard AccountSwitchPIN.hasPIN(for: accountID) else { return true }

        if AccountSwitchPIN.biometricsEnabled(for: accountID) {
            let reason = "Unlock \(account.userName)’s account"
            if await AccountSwitchPIN.authenticateBiometrics(reason: reason) {
                return true
            }
        }

        return await promptPIN(named: account.userName, accountID: accountID)
    }

    private static func promptPIN(named name: String, accountID: String) async -> Bool {
        await waitUntilNoModal()
        guard let presenter = topViewController() else { return false }
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: "Account PIN",
                message: "Enter the PIN to unlock \(name)’s account on this device.",
                preferredStyle: .alert
            )
            alert.addTextField { field in
                field.isSecureTextEntry = true
                field.keyboardType = .numberPad
                field.placeholder = "PIN"
                field.textContentType = .oneTimeCode
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            if AccountSwitchPIN.canUseBiometrics, AccountSwitchPIN.biometricsEnabled(for: accountID) {
                alert.addAction(UIAlertAction(title: AccountSwitchPIN.biometricsName, style: .default) { _ in
                    Task { @MainActor in
                        let ok = await AccountSwitchPIN.authenticateBiometrics(reason: "Unlock \(name)’s account")
                        if ok {
                            continuation.resume(returning: true)
                            return
                        }
                        let retry = await promptPIN(named: name, accountID: accountID)
                        continuation.resume(returning: retry)
                    }
                })
            }
            alert.addAction(UIAlertAction(title: "Unlock", style: .default) { _ in
                let pin = alert.textFields?.first?.text ?? ""
                if AccountSwitchPIN.verifyPIN(pin, for: accountID) {
                    continuation.resume(returning: true)
                } else {
                    Task { @MainActor in
                        await showWrongPIN()
                        let retry = await promptPIN(named: name, accountID: accountID)
                        continuation.resume(returning: retry)
                    }
                }
            })
            presenter.present(alert, animated: true)
        }
    }

    private static func showWrongPIN() async {
        guard let presenter = topViewController() else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alert = UIAlertController(title: nil, message: "That PIN is incorrect.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                continuation.resume()
            })
            presenter.present(alert, animated: true)
        }
    }

    private static func topViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let window = windows.first { $0.isKeyWindow } ?? windows.first { !$0.isHidden }
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }

    private static func waitUntilNoModal() async {
        for _ in 0..<40 {
            let presenting = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .contains { window in
                    !window.isHidden && window.rootViewController?.presentedViewController != nil
                }
            if !presenting { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}
