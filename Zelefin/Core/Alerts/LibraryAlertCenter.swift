import Foundation
import UserNotifications

extension Notification.Name {
    static let zelefinOpenLibraryItem = Notification.Name("zelefin.openLibraryItem")
    static let zelefinOpenScheduledTasks = Notification.Name("zelefin.openScheduledTasks")
}

enum LibraryAlertUserInfo {
    static let itemID = "itemID"
    static let kind = "kind"
}

@MainActor
final class LibraryAlertCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LibraryAlertCenter()

    private let center = UNUserNotificationCenter.current()
    private(set) var pendingItemID: String?
    private(set) var pendingScheduledTasks = false

    func prepare() {
        center.delegate = self
    }

    func takePendingItemID() -> String? {
        let value = pendingItemID
        pendingItemID = nil
        return value
    }

    func takePendingScheduledTasks() -> Bool {
        let value = pendingScheduledTasks
        pendingScheduledTasks = false
        return value
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func post(_ alerts: [LibraryAlert]) {
        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            content.userInfo = Self.userInfo(for: alert)
            let request = UNNotificationRequest(
                identifier: alert.id,
                content: content,
                trigger: nil
            )
            Task {
                try? await center.add(request)
            }
        }
    }

    private static func userInfo(for alert: LibraryAlert) -> [String: String] {
        var info = [LibraryAlertUserInfo.kind: alert.kind.rawValue]
        if let itemID = alert.itemID, !itemID.isEmpty {
            info[LibraryAlertUserInfo.itemID] = itemID
        }
        return info
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let kind = userInfo[LibraryAlertUserInfo.kind] as? String
        if kind == LibraryAlert.Kind.scheduledTask.rawValue {
            await MainActor.run {
                LibraryAlertCenter.shared.pendingScheduledTasks = true
                NotificationCenter.default.post(name: .zelefinOpenScheduledTasks, object: nil)
            }
            return
        }
        guard let itemID = userInfo[LibraryAlertUserInfo.itemID] as? String, !itemID.isEmpty else { return }
        await MainActor.run {
            LibraryAlertCenter.shared.pendingItemID = itemID
            NotificationCenter.default.post(name: .zelefinOpenLibraryItem, object: itemID)
        }
    }
}
