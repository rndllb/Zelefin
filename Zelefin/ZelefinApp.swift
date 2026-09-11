import SwiftUI
import UIKit

@MainActor
final class ZelefinAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        LibraryAlertCenter.shared.prepare()
        LibraryAlertMonitor.registerBackgroundRefresh()
        return true
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
                .environment(session)
                .environment(downloads)
                .environment(deepLinks)
                .background(Color.black)
        }
    }
}
