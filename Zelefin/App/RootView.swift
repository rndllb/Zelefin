import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(DownloadStore.self) private var downloads
    @Environment(DeepLinkStore.self) private var deepLinks
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
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
        .onReceive(NotificationCenter.default.publisher(for: .zelefinRemotePlayItem)) { notification in
            guard let itemID = notification.object as? String else { return }
            deepLinks.openLibraryItem(itemID, session: session)
        }
        .onReceive(NotificationCenter.default.publisher(for: .zelefinOpenLibraryItem)) { notification in
            guard let itemID = notification.object as? String else { return }
            deepLinks.openLibraryItem(itemID, session: session)
        }
        .onReceive(NotificationCenter.default.publisher(for: .zelefinOpenScheduledTasks)) { _ in
            guard session.isSignedIn else { return }
            profileSheet = .scheduledTasks
        }
        .onChange(of: session.isSignedIn) { _, signedIn in
            if !signedIn {
                profileSheet = nil
                deepLinks.dismissPresentedItem()
                LibraryAlertMonitor.shared.stop()
            } else {
                Task { await deepLinks.flushPending(session: session) }
                startLibraryAlertMonitor()
            }
        }
        .onChange(of: session.isAdministrator) { _, isAdmin in
            guard isAdmin else { return }
            startLibraryAlertMonitor()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, session.isSignedIn, !session.isReviewDemo else { return }
            LibraryAlertMonitor.shared.attach(session: session)
            LibraryAlertMonitor.scheduleBackgroundRefresh()
            Task { await LibraryAlertMonitor.shared.poll(session: session) }
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
        .zelefinAccentTint()
        .task {
            await session.restore()
            startLibraryAlertMonitor()
            if let itemID = LibraryAlertCenter.shared.takePendingItemID() {
                deepLinks.openLibraryItem(itemID, session: session)
            }
            if LibraryAlertCenter.shared.takePendingScheduledTasks() {
                profileSheet = .scheduledTasks
            }
            await deepLinks.flushPending(session: session)
        }
    }

    private func startLibraryAlertMonitor() {
        LibraryAlertMonitor.shared.attach(session: session)
        guard session.isSignedIn, !session.isReviewDemo else { return }
        LibraryAlertMonitor.shared.start(session: session)
    }
}
