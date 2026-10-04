import UIKit
import UserNotifications

/// Shows a Jellyfin user message in-app when Zelefin is open. Closed-app
/// delivery is the Zelefin plugin push, not a local notification from a dying socket.
@MainActor
enum SessionMessageCenter {
    nonisolated static let notificationID = "zelefin.session-message"
    nonisolated static let kind = "sessionMessage"

    private static var lastFingerprint: String?
    private static var lastPresentedAt: Date?

    static func present(_ message: SessionDisplayMessage) {
        guard !isDuplicate(message) else { return }
        guard isAppActive else { return }
        NotificationCenter.default.post(name: .zelefinSessionMessage, object: message)
    }

    static func presentPush(
        _ userInfo: [AnyHashable: Any],
        fallbackTitle: String? = nil,
        fallbackBody: String? = nil
    ) {
        guard let message = SessionDisplayMessage.fromPush(
            userInfo,
            fallbackTitle: fallbackTitle,
            fallbackBody: fallbackBody
        ) else { return }
        present(message)
    }

    private static func isDuplicate(_ message: SessionDisplayMessage) -> Bool {
        let fingerprint = "\(message.header)\n\(message.text)"
        let now = Date()
        if lastFingerprint == fingerprint, let lastPresentedAt, now.timeIntervalSince(lastPresentedAt) < 3 {
            return true
        }
        lastFingerprint = fingerprint
        lastPresentedAt = now
        return false
    }

    private static var isAppActive: Bool {
        UIApplication.shared.applicationState == .active
    }
}
