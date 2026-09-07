import SwiftUI

@main
struct ZelefinApp: App {
    @State private var session = SessionStore()
    @State private var downloads = DownloadStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(downloads)
                .background(Color.black)
        }
    }
}
