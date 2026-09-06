import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            if session.isRestoring {
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                }
            } else if session.isSignedIn {
                MainTabView()
            } else {
                ConnectView()
            }
        }
        .preferredColorScheme(.dark)
        .tint(session.isSignedIn ? Color.accentColor : .white)
        .task {
            await session.restore()
        }
    }
}
