import Foundation

enum CatalogActivityPresenter {
    static let activityID = "catalog"

    /// Skip noisy one-shot work; only surface user-visible indexing that lasts a moment.
    static let minimumVisibleSeconds: TimeInterval = 1.5

    @MainActor
    static func start(title: String = "Updating library", statusLine: String = "Listing…") {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        ZelefinLiveActivityController.shared.start(
            kind: .catalog,
            id: activityID,
            title: title,
            subtitle: "Catalog",
            fraction: 0,
            statusLine: statusLine,
            badgeLabel: "INDEXING"
        )
        #endif
    }

    @MainActor
    static func update(fraction: Double?, statusLine: String) {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        ZelefinLiveActivityController.shared.update(
            id: activityID,
            fraction: fraction,
            statusLine: statusLine,
            badgeLabel: "INDEXING"
        )
        #endif
    }

    @MainActor
    static func finish(success: Bool = true, statusLine: String = "Up to date") {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        ZelefinLiveActivityController.shared.finish(
            id: activityID,
            success: success,
            statusLine: statusLine,
            dismissAfter: 3
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
