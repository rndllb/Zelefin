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

    @MainActor
    static func setPhoneLandscapeAllowed(_ allowed: Bool) {
        allowsLandscapeOnPhone = allowed
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            return
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
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
