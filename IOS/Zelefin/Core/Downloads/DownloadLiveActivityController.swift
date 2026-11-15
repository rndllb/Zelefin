import Foundation

/// Platform-neutral entry point the download store calls. Live Activities exist only on the iPhone/
/// iPad (not Mac Catalyst), so every call becomes a no-op there and the store needs no `#if`s.
enum DownloadActivityPresenter {
    /// Start the Live Activity. `posterFileURL` is the saved artwork; a small thumbnail of it is
    /// carried in the activity so the Lock Screen and Dynamic Island can show the poster with no
    /// shared container or entitlement.
    /// `groupID` coalesces many episode jobs (one season download) into a single activity.
    @MainActor
    static func start(
        id: String,
        groupID: String? = nil,
        title: String,
        subtitle: String,
        posterFileURL: URL?,
        fraction: Double?,
        statusLine: String
    ) {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        ZelefinLiveActivityController.shared.start(
            kind: .download,
            id: id,
            groupID: groupID,
            title: title,
            subtitle: subtitle,
            posterFileURL: posterFileURL,
            fraction: fraction,
            statusLine: statusLine,
            badgeLabel: "DOWNLOADING"
        )
        #endif
    }

    @MainActor
    static func update(id: String, fraction: Double?, statusLine: String) {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        ZelefinLiveActivityController.shared.update(
            id: id,
            fraction: fraction,
            statusLine: statusLine,
            badgeLabel: "DOWNLOADING"
        )
        #endif
    }

    @MainActor
    static func finish(id: String, success: Bool, statusLine: String) {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        ZelefinLiveActivityController.shared.finish(
            id: id,
            success: success,
            statusLine: statusLine
        )
        #endif
    }

    /// Dismiss immediately — used when the user cancels a download.
    @MainActor
    static func stop(id: String) {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        ZelefinLiveActivityController.shared.stop(id: id)
        #endif
    }
}
