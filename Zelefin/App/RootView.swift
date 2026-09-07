import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(DownloadStore.self) private var downloads
    @Environment(DeepLinkStore.self) private var deepLinks
    @Environment(\.openURL) private var openURL
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
                .environment(downloads)
        }
        .onReceive(NotificationCenter.default.publisher(for: .zelefinProfileSheet)) { notification in
            guard session.isSignedIn else { return }
            profileSheet = notification.object as? ProfileSheet
        }
        .onChange(of: session.isSignedIn) { _, signedIn in
            if !signedIn {
                profileSheet = nil
                deepLinks.dismissPresentedItem()
            } else {
                Task { await deepLinks.flushPending(session: session) }
            }
        }
        .onOpenURL { url in
            Task { await deepLinks.handle(url, session: session) }
        }
        .sheet(item: Binding(
            get: { deepLinks.presentedItem },
            set: { deepLinks.presentedItem = $0 }
        )) { item in
            NavigationStack {
                ItemDetailView(itemID: item.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { deepLinks.dismissPresentedItem() }
                        }
                    }
            }
            .environment(session)
            .environment(downloads)
        }
        .alert(
            "Can't Open Title",
            isPresented: Binding(
                get: { deepLinks.errorMessage != nil },
                set: { if !$0 { deepLinks.clearError() } }
            )
        ) {
            if let url = deepLinks.browserFallbackURL {
                Button("Open in Browser") { openURL(url) }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(deepLinks.errorMessage ?? "")
        }
        .preferredColorScheme(.dark)
        .tint(session.isSignedIn ? Color.accentColor : .white)
        .task {
            await session.restore()
            await deepLinks.flushPending(session: session)
        }
    }
}
