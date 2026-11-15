import Foundation

/// Bridges user-visible `CatalogIndexProgress` bars to the catalog Live Activity.
/// Silent poster prefetch stays out of this path.
@MainActor
enum CatalogIndexLiveActivity {
    private static var startedAt: Date?
    private static var didStart = false

    static func sync(_ progress: CatalogIndexProgress?) {
        guard let progress else {
            finishIfNeeded()
            return
        }
        if !didStart {
            startedAt = .now
            didStart = true
            // Defer the actual start slightly so tiny catalogs don't flash the Lock Screen.
            let started = startedAt
            Task {
                try? await Task.sleep(for: .seconds(CatalogActivityPresenter.minimumVisibleSeconds))
                guard didStart, startedAt == started else { return }
                CatalogActivityPresenter.start(
                    statusLine: "\(progress.label) · \(progress.countLabel)"
                )
                CatalogActivityPresenter.update(
                    fraction: progress.isDeterminate ? progress.fraction : nil,
                    statusLine: "\(progress.label) · \(progress.countLabel)"
                )
            }
            return
        }
        CatalogActivityPresenter.update(
            fraction: progress.isDeterminate ? progress.fraction : nil,
            statusLine: "\(progress.label) · \(progress.countLabel)"
        )
        if progress.isFinished {
            finishIfNeeded(success: true)
        }
    }

    static func finishIfNeeded(success: Bool = true) {
        guard didStart else { return }
        let elapsed = startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        didStart = false
        startedAt = nil
        if elapsed < CatalogActivityPresenter.minimumVisibleSeconds {
            CatalogActivityPresenter.stop()
        } else {
            CatalogActivityPresenter.finish(success: success)
        }
    }
}
