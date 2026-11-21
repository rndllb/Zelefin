import Foundation

/// SyncPlay group Live Activity (join / queue / leave). Kept separate from video playback so
/// Picture in Picture is never blocked by a Now Playing activity.
enum SyncPlayActivityPresenter {
    static let activityID = "syncPlay"

    @MainActor
    static func start(groupName: String, statusLine: String = "Joined") {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        ZelefinLiveActivityController.shared.start(
            kind: .syncPlay,
            id: activityID,
            title: groupName,
            subtitle: AppLanguage.string("account.syncplay", default: "SyncPlay"),
            fraction: nil,
            statusLine: statusLine,
            badgeLabel: "SYNCPLAY"
        )
        #endif
    }

    @MainActor
    static func update(statusLine: String, groupName: String? = nil) {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        ZelefinLiveActivityController.shared.update(
            id: activityID,
            statusLine: statusLine,
            badgeLabel: "SYNCPLAY",
            title: groupName
        )
        #endif
    }

    @MainActor
    static func stop() {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        ZelefinLiveActivityController.shared.stop(id: activityID)
        #endif
    }
}
