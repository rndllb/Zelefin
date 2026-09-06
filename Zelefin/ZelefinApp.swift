import SwiftUI

@main
struct ZelefinApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .background(Color.black)
        }
    }
}
