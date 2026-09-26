import Foundation
import UIKit
import UserNotifications

enum PushNotificationCenter {
    private static let tokenKey = "zelefin.push.token"

    static var storedToken: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }

    static func didRegister(deviceToken: Data) {
        storedToken = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        NotificationCenter.default.post(name: .zelefinPushTokenReady, object: storedToken)
    }

    static func requestPermissionIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            await MainActor.run {
                registerForRemoteNotifications()
            }
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                if granted {
                    await MainActor.run {
                        registerForRemoteNotifications()
                    }
                }
                return granted
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    @MainActor
    static func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    static func itemID(in userInfo: [AnyHashable: Any]) -> String? {
        let keys = ["itemId", "itemID", "id"]
        for key in keys {
            if let value = userInfo[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    static func handle(_ userInfo: [AnyHashable: Any]) {
        guard let itemID = itemID(in: userInfo) else { return }
        NotificationCenter.default.post(name: .zelefinPushOpenItem, object: itemID)
    }
}

extension Notification.Name {
    static let zelefinPushTokenReady = Notification.Name("zelefin.pushTokenReady")
    static let zelefinPushOpenItem = Notification.Name("zelefin.pushOpenItem")
}
