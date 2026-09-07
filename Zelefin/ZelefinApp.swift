import SwiftUI

@main
struct ZelefinApp: App {
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
