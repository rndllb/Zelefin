import Foundation
import UserNotifications

extension Notification.Name {
    static let zelefinOpenLibraryItem = Notification.Name("zelefin.openLibraryItem")
    static let zelefinOpenScheduledTasks = Notification.Name("zelefin.openScheduledTasks")
    static let zelefinPlaybackSessions = Notification.Name("zelefin.playbackSessions")
    static let zelefinLibraryChanged = Notification.Name("zelefin.libraryChanged")
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
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                PushNotificationCenter.registerForRemoteNotifications()
            }
            return granted
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
            center.add(request)
        }
    }

    nonisolated static func userInfo(for alert: LibraryAlert) -> [String: String] {
        var info = [LibraryAlertUserInfo.kind: alert.kind.rawValue]
        if let itemID = alert.itemID, !itemID.isEmpty {
            info[LibraryAlertUserInfo.itemID] = itemID
        }
        return info
    }

    /// Completion-handler form is required: the `async` `didReceive` bridging resumes
    /// off the main thread, and UIKit then snapshots the scene from that queue (SIGABRT).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let destination = LibraryAlertDestination.parse(response.notification.request.content.userInfo)
        // UN's completion handler is not Sendable; it must still run on the main queue
        // so UIKit can snapshot the scene without SIGABRT.
        nonisolated(unsafe) let finish = completionHandler
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                LibraryAlertCenter.shared.remember(destination)
                finish()
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    LibraryAlertCenter.shared.publishRememberedOpen()
                }
            }
        }
    }

    private func remember(_ destination: LibraryAlertDestination?) {
        switch destination {
        case .scheduledTasks:
            pendingScheduledTasks = true
        case .libraryItem(let itemID):
            pendingItemID = itemID
        case nil:
            break
        }
    }

    private func publishRememberedOpen() {
        if pendingScheduledTasks {
            NotificationCenter.default.post(name: .zelefinOpenScheduledTasks, object: nil)
        }
        if let itemID = pendingItemID {
            NotificationCenter.default.post(name: .zelefinOpenLibraryItem, object: itemID)
        }
    }
}

enum LibraryAlertDestination: Equatable, Sendable {
    case libraryItem(String)
    case scheduledTasks

    static func parse(_ userInfo: [AnyHashable: Any]) -> LibraryAlertDestination? {
        let kind = userInfo[LibraryAlertUserInfo.kind] as? String
        if kind == LibraryAlert.Kind.scheduledTask.rawValue {
            return .scheduledTasks
        }
        if let itemID = userInfo[LibraryAlertUserInfo.itemID] as? String, !itemID.isEmpty {
            return .libraryItem(itemID)
        }
        if let itemID = userInfo["itemId"] as? String, !itemID.isEmpty {
            return .libraryItem(itemID)
        }
        return nil
    }
}
