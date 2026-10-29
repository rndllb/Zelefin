import AppKit

/// AppKit's side of the Mac Catalyst app, loaded from the app's PlugIns folder: Catalyst's split view
/// can't stop its sidebar from collapsing, AppKit's can. The sidebar is the Mac's only navigation, so
/// it stays put: it can't collapse, can't be dragged to another width, and has no sidebar button.
@objc(ZelefinMacBridge)
@MainActor
final class ZelefinMacBridge: NSObject {
    /// Each sidebar's width when it first opened, which SwiftUI sets; it's kept from then on.
    private var lockedWidths: [ObjectIdentifier: CGFloat] = [:]
    /// The app's controls in the title bar strip (back, filter, search), in window points from the
    /// top left. The app sets these as the controls move.
    @objc var titlebarControls: [NSValue] = []
    /// The view a click in a title bar control went to, which gets the rest of that click too.
    private var clickTarget: NSView?

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
        // Opening a page shows the sidebar button again without a window event to catch it on, so
        // the toolbar is checked when it gains an item and a few times a second. That only reads a
        // handful of items.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toolbarWillAddItem(_:)),
            name: NSToolbar.willAddItemNotification,
            object: nil
        )
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                NSApp.windows.forEach { self?.hideSidebarButtons(in: $0) }
            }
        }
        // The title bar strip takes clicks for dragging the window, even over the app's controls
        // drawn there. Clicks inside those controls go to the app instead.
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.route(event) ?? false }
            return handled ? nil : event
        }
    }

    /// True when the click went to the app instead of the title bar.
    private func route(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown:
            guard let target = titlebarControlTarget(for: event) else { return false }
            clickTarget = target
            target.mouseDown(with: event)
            return true
        case .leftMouseDragged:
            guard let target = clickTarget else { return false }
            target.mouseDragged(with: event)
            return true
        case .leftMouseUp:
            guard let target = clickTarget else { return false }
            clickTarget = nil
            target.mouseUp(with: event)
            return true
        default:
            return false
        }
    }

    /// The app's view under a click that lands on one of its controls inside the title bar strip.
    private func titlebarControlTarget(for event: NSEvent) -> NSView? {
        guard let window = event.window, let content = window.contentView, let frame = content.superview else { return nil }
        let local = content.convert(event.locationInWindow, from: nil)
        let fromTop = CGPoint(x: local.x, y: content.isFlipped ? local.y : content.bounds.height - local.y)
        let titlebarHeight = window.frame.height - window.contentLayoutRect.height
        guard fromTop.y <= titlebarHeight,
              titlebarControls.contains(where: { $0.rectValue.contains(fromTop) }) else { return nil }
        return content.hitTest(frame.convert(event.locationInWindow, from: nil))
    }

    @objc private func toolbarWillAddItem(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            NSApp.windows.forEach { self?.hideSidebarButtons(in: $0) }
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
