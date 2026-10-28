import AppKit

/// AppKit's side of the Mac Catalyst app, loaded from the app's PlugIns folder: Catalyst's split view
/// can't stop its sidebar from collapsing, AppKit's can. The sidebar is the Mac's only navigation, so
/// it stays put: it can't collapse, can't be dragged to another width, and has no sidebar button.
@objc(ZelefinMacBridge)
@MainActor
final class ZelefinMacBridge: NSObject {
    /// Each sidebar's width when it first opened, which SwiftUI sets; it's kept from then on.
    private var lockedWidths: [ObjectIdentifier: CGFloat] = [:]

    @objc func start() {
        // Windows update after every event, so a sidebar or toolbar item that turns up late is
        // caught on the next one.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidUpdate(_:)),
            name: NSWindow.didUpdateNotification,
            object: nil
        )
        // Launch has no events yet, so the first few seconds are covered by a timer too.
        var remaining = 25
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                NSApp.windows.forEach { self?.apply(to: $0) }
            }
            remaining -= 1
            if remaining <= 0 { timer.invalidate() }
        }
    }

    @objc private func windowDidUpdate(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        apply(to: window)
    }

    private func apply(to window: NSWindow) {
        lockSidebars(in: window)
        hideSidebarButtons(in: window)
    }

    private func lockSidebars(in window: NSWindow) {
        guard let content = window.contentView else { return }
        for splitView in splitViews(in: content) {
            guard let controller = splitView.delegate as? NSSplitViewController,
                  let sidebar = controller.splitViewItems.first(where: { $0.behavior == .sidebar }),
                  !sidebar.isCollapsed else { continue }
            let key = ObjectIdentifier(sidebar)
            let width = lockedWidths[key] ?? sidebar.viewController.view.frame.width
            guard width > 100 else { continue }
            lockedWidths[key] = width
            if sidebar.canCollapse { sidebar.canCollapse = false }
            if sidebar.minimumThickness != width { sidebar.minimumThickness = width }
            if sidebar.maximumThickness != width { sidebar.maximumThickness = width }
        }
    }

    private func hideSidebarButtons(in window: NSWindow) {
        guard let toolbar = window.toolbar else { return }
        for item in toolbar.items where isSidebarButton(item) && !item.isHidden {
            item.isHidden = true
        }
    }

    private func isSidebarButton(_ item: NSToolbarItem) -> Bool {
        item.itemIdentifier == .toggleSidebar
            || item.action == #selector(NSSplitViewController.toggleSidebar(_:))
            || item.itemIdentifier.rawValue.localizedCaseInsensitiveContains("togglesidebar")
    }

    private func splitViews(in view: NSView) -> [NSSplitView] {
        var found: [NSSplitView] = []
        if let split = view as? NSSplitView { found.append(split) }
        for subview in view.subviews {
            found += splitViews(in: subview)
        }
        return found
    }
}
