import Foundation

enum RequestActivityPresenter {
    @MainActor
    static func start(
        id: String,
        title: String,
        subtitle: String,
        statusLine: String = "Pending",
        badgeLabel: String = "PENDING"
    ) {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        ZelefinLiveActivityController.shared.start(
            kind: .request,
            id: id,
            groupID: "requests",
            title: title,
            subtitle: subtitle,
            fraction: nil,
            statusLine: statusLine,
            badgeLabel: badgeLabel
        )
        #endif
    }

    @MainActor
    static func update(id: String, statusLine: String, badgeLabel: String) {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        ZelefinLiveActivityController.shared.update(
            id: id,
            statusLine: statusLine,
            badgeLabel: badgeLabel
        )
        #endif
    }

    @MainActor
    static func finish(id: String, available: Bool, statusLine: String) {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        ZelefinLiveActivityController.shared.finish(
            id: id,
            success: available,
            statusLine: statusLine
        )
        #endif
    }

    @MainActor
    static func stop(id: String) {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        ZelefinLiveActivityController.shared.stop(id: id)
        #endif
    }
}
