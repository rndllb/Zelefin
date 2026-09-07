import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @State private var profileSheet: ProfileSheet?

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
        .sheet(item: $profileSheet) { destination in
            ProfileSheetContainer(destination: destination)
                .environment(session)
        }
        .onReceive(NotificationCenter.default.publisher(for: .zelefinProfileSheet)) { notification in
            guard session.isSignedIn else { return }
            profileSheet = notification.object as? ProfileSheet
        }
        .onChange(of: session.isSignedIn) { _, signedIn in
            if !signedIn {
                profileSheet = nil
            }
        }
        .preferredColorScheme(.dark)
        .tint(session.isSignedIn ? Color.accentColor : .white)
        .task {
            await session.restore()
        }
    }
}
