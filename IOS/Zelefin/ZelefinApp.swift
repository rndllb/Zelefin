import SwiftUI
import UIKit

enum InterfaceOrientationLock {
    @MainActor
    private static var allowsLandscapeOnPhone = false

    @MainActor
    static var mask: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom != .phone {
            return .all
        }
        return allowsLandscapeOnPhone ? .allButUpsideDown : .portrait
    }

    /// Playback opens in landscape; turning the phone back to portrait still works while it plays.
    @MainActor
    static func setPhoneLandscapeAllowed(_ allowed: Bool) {
        allowsLandscapeOnPhone = allowed
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            return
        }
        // UIKit caches each controller's supported orientations. Without this the new mask waits for
        // some later re-query, so turning the phone did nothing until something else forced one.
        for window in scene.windows {
            var controller = window.rootViewController
            while let current = controller {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = current.presentedViewController
            }
        }
        // No error handler: UIKit calls it off the main thread, and a closure written here is
        // main-actor isolated, so Swift 6 traps when it runs.
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: allowed ? playbackOrientation : .portrait))
    }

    /// The landscape side the phone is already tilted to. Device and interface orientations are
    /// mirrored: a phone turned left shows the interface rotated right.
    @MainActor
    private static var playbackOrientation: UIInterfaceOrientationMask {
        UIDevice.current.orientation == .landscapeRight ? .landscapeLeft : .landscapeRight
    }
}

#if targetEnvironment(macCatalyst)
/// Loads `ZelefinMacBridge.bundle` (AppKit) from the app's PlugIns folder. Catalyst's split view can't
/// stop the sidebar from collapsing or resizing; AppKit's can.
enum MacBridge {
    @MainActor private static var bridge: NSObject?

    @MainActor
    static func start() {
        guard bridge == nil,
              let url = Bundle.main.builtInPlugInsURL?.appendingPathComponent("ZelefinMacBridge.bundle"),
              let bundle = Bundle(url: url), bundle.load(),
              let type = bundle.principalClass as? NSObject.Type else { return }
        let instance = type.init()
        instance.perform(NSSelectorFromString("start"))
        bridge = instance
    }

    @MainActor private static var titlebarControls: [UUID: CGRect] = [:]

    /// Records a control drawn in the window's title bar strip, in window points, or forgets it when
    /// `frame` is nil. The bridge sends clicks inside these to the app rather than to the title bar.
    @MainActor
    static func setTitlebarControl(_ id: UUID, frame: CGRect?) {
        titlebarControls[id] = frame
        bridge?.setValue(titlebarControls.values.map { NSValue(cgRect: $0) }, forKey: "titlebarControls")
    }
}

/// Lets clicks reach a control drawn level with the close, minimize, and zoom buttons, where the
/// title bar otherwise takes them for dragging the window.
private struct MacTitlebarControl: ViewModifier {
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                MacBridge.setTitlebarControl(id, frame: frame)
            }
            .onDisappear {
                MacBridge.setTitlebarControl(id, frame: nil)
            }
    }
}

extension View {
    func macTitlebarControl() -> some View {
        modifier(MacTitlebarControl())
    }
}

/// Apple Music's window on the Mac: no title bar, so the sidebar runs to the top and holds the
/// close, minimize and zoom buttons.
enum MacWindowChrome {
    @MainActor
    static func apply() {
        MacFullScreenSidebar.install()
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            guard let titlebar = scene.titlebar else { continue }
            titlebar.titleVisibility = .hidden
            titlebar.toolbar = nil
        }
    }
}

/// UIKit floats the Mac sidebar 8 pt in from the window's edges, but in full screen it starts below
/// the hidden title bar instead, 32 pt down, so there's more room above it than below. A watcher inside
/// the sidebar moves it back up each time the split view lays it out in full screen.
@MainActor
enum MacFullScreenSidebar {
    static func install(attempts: Int = 20) {
        var installed = false
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                guard let column = sidebarColumn(in: window) else { continue }
                installed = true
                guard !column.subviews.contains(where: { $0 is SidebarLayoutWatcher }) else { continue }
                let watcher = SidebarLayoutWatcher(frame: column.bounds)
                watcher.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                watcher.column = column
                column.addSubview(watcher)
                fit(column)
            }
        }
        // The split view is built a moment after the window appears.
        guard !installed, attempts > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { install(attempts: attempts - 1) }
    }

    /// The view the split view places for the sidebar: the sidebar's ancestor just inside the
    /// container that spans the whole split view.
    private static func sidebarColumn(in window: UIWindow) -> UIView? {
        guard let split = splitController(in: window.rootViewController),
              var view = split.viewControllers.first?.viewIfLoaded else { return nil }
        while let parent = view.superview, parent !== split.view, parent.bounds.size != split.view.bounds.size {
            view = parent
        }
        return view.superview == nil ? nil : view
    }

    private static func splitController(in controller: UIViewController?) -> UISplitViewController? {
        guard let controller else { return nil }
        if let split = controller as? UISplitViewController { return split }
        for child in controller.children {
            if let split = splitController(in: child) { return split }
        }
        return nil
    }

    static func fit(_ column: UIView) {
        guard let window = column.window, let screen = window.windowScene?.screen,
              window.bounds.size == screen.bounds.size else { return }
        let inset = column.frame.minX
        guard inset > 0, column.frame.minY > inset else { return }
        column.frame = CGRect(x: inset, y: inset, width: column.frame.width, height: column.frame.maxY - inset)
    }
}

/// Sits inside the sidebar and resizes with it, so it hears each new layout the split view gives it.
private final class SidebarLayoutWatcher: UIView {
    weak var column: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let column { MacFullScreenSidebar.fit(column) }
    }
}
#endif

@MainActor
final class ZelefinAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        LibraryAlertCenter.shared.prepare()
        #if targetEnvironment(macCatalyst)
        MacBridge.start()
        #endif
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        InterfaceOrientationLock.mask
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushNotificationCenter.didRegister(deviceToken: deviceToken)
    }
}

@main
struct ZelefinApp: App {
    @UIApplicationDelegateAdaptor(ZelefinAppDelegate.self) private var appDelegate
    @State private var session = SessionStore()
    @State private var downloads = DownloadStore()
    @State private var deepLinks = DeepLinkStore()

    init() {
        PlaybackPreferences.moveEveryoneToMPVOnce()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .background(Color.zelefinPage)
                .environment(session)
                .environment(\.libraryArtworkRevision, session.artworkRevision)
                .environment(downloads)
                .environment(deepLinks)
                .task { [session, downloads] in
                    downloads.chosenVersion = { session.launchOptions(for: $0).mediaSourceID }
                }
                #if targetEnvironment(macCatalyst)
                .onAppear(perform: MacWindowChrome.apply)
                .onReceive(NotificationCenter.default.publisher(for: UIScene.didActivateNotification)) { _ in
                    MacWindowChrome.apply()
                }
                #endif
        }
    }
}
