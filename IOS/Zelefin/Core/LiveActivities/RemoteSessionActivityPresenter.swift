import Foundation

enum RemoteSessionActivityPresenter {
    static let activityID = "remoteSession"
    static let preferenceKey = "liveActivityRemoteSessions"

    @MainActor
    static func startOrUpdate(otherCount: Int, topTitle: String?) {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        guard otherCount > 0 else {
            stop()
            return
        }
        let title = topTitle?.nilIfEmpty ?? "Other devices"
        let status = otherCount == 1 ? "1 session" : "\(otherCount) sessions"
        if ZelefinLiveActivityController.shared.hasActive(.remoteSession) {
            ZelefinLiveActivityController.shared.updateKind(
                .remoteSession,
                statusLine: status,
                badgeLabel: "SESSIONS",
                title: title,
                subtitle: AppLanguage.string("ui.now_playing_elsewhere", default: "Now playing elsewhere")
            )
        } else {
            ZelefinLiveActivityController.shared.start(
                kind: .remoteSession,
                id: activityID,
                title: title,
                subtitle: AppLanguage.string("ui.now_playing_elsewhere", default: "Now playing elsewhere"),
                fraction: nil,
                statusLine: status,
                badgeLabel: "SESSIONS"
            )
        }
        #endif
    }

    @MainActor
    static func stop() {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        ZelefinLiveActivityController.shared.stopKind(.remoteSession)
        #endif
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
