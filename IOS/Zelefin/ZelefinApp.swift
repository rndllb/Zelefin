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

@MainActor
final class ZelefinAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        LibraryAlertCenter.shared.prepare()
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
                .background(Color.black)
                .environment(session)
                .environment(\.libraryArtworkRevision, session.artworkRevision)
                .environment(downloads)
                .environment(deepLinks)
        }
    }
}
