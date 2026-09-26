import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(DownloadStore.self) private var downloads
    @Environment(DeepLinkStore.self) private var deepLinks
    @Environment(PlusEntitlement.self) private var plus
    @Environment(\.openURL) private var openURL
    @State private var profileSheet: ProfileSheet?

    var body: some View {
        rootContent
            .sheet(item: $profileSheet) { destination in
                ProfileSheetContainer(destination: destination)
                    .environment(session)
                    .environment(downloads)
                    .environment(plus)
            }
            .modifier(RootNotificationModifier(profileSheet: $profileSheet))
            .modifier(RootSessionLifecycleModifier(profileSheet: $profileSheet))
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
                .environment(plus)
            }
            .fullScreenCover(item: Binding(
                get: { session.pendingPlayerItem },
                set: { session.pendingPlayerItem = $0 }
            )) { item in
                PlayerView(item: item)
                    .environment(session)
                    .environment(downloads)
                    .environment(plus)
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
            .alert(
                "Signed Out",
                isPresented: Binding(
                    get: { session.authNotice != nil },
                    set: { if !$0 { session.authNotice = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(session.authNotice ?? "")
            }
            .preferredColorScheme(.dark)
            .zelefinAccentTint()
            .task {
                plus.isReviewDemo = session.isReviewDemo
                await plus.start()
                await session.restore()
                plus.isReviewDemo = session.isReviewDemo
                consumePendingNotificationDestination()
                await deepLinks.flushPending(session: session)
            }
            .onChange(of: session.isReviewDemo) { _, demo in
                plus.isReviewDemo = demo
            }
    }

    @ViewBuilder
    private var rootContent: some View {
        if session.isRestoring {
            ZelefinLoadingView()
        } else if session.isSignedIn {
            MainTabView()
                .fullScreenCover(isPresented: Binding(
                    get: { session.needsFirstRunSetup },
                    set: { if !$0 { session.completeFirstRunSetup() } }
                )) {
                    FirstRunSetupView()
                        .environment(session)
                }
        } else {
            ConnectView()
        }
    }

    private func consumePendingNotificationDestination() {
        if let itemID = LibraryAlertCenter.shared.takePendingItemID() {
            deepLinks.openLibraryItem(itemID, session: session)
        }
        if LibraryAlertCenter.shared.takePendingScheduledTasks() {
            guard session.isSignedIn, plus.isUnlocked else { return }
            profileSheet = .scheduledTasks
        }
    }
}

private struct RootNotificationModifier: ViewModifier {
    @Environment(SessionStore.self) private var session
    @Environment(DeepLinkStore.self) private var deepLinks
    @Environment(PlusEntitlement.self) private var plus
    @Binding var profileSheet: ProfileSheet?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .zelefinProfileSheet)) { notification in
                guard session.isSignedIn else { return }
                profileSheet = notification.object as? ProfileSheet
            }
            .onReceive(NotificationCenter.default.publisher(for: .zelefinRemotePlayItem)) { notification in
                guard let itemID = notification.object as? String else { return }
                if session.syncPlayGroupID != nil {
                    Task { await session.presentSyncPlayItem(id: itemID) }
                } else {
                    deepLinks.openLibraryItem(itemID, session: session)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .zelefinSyncPlayJoined)) { notification in
                session.noteSyncPlayJoined(
                    groupID: notification.object as? String,
                    name: notification.userInfo?["name"] as? String
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .zelefinSyncPlayLeft)) { _ in
                session.noteSyncPlayLeft()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zelefinSyncPlayQueueItem)) { notification in
                session.noteSyncPlayPlaylistItem(notification.object as? String)
            }
            .onReceive(NotificationCenter.default.publisher(for: .zelefinPushTokenReady)) { notification in
                guard let token = notification.object as? String else { return }
                Task { await session.registerPushToken(token) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .zelefinOpenLibraryItem)) { notification in
                _ = LibraryAlertCenter.shared.takePendingItemID()
                guard let itemID = notification.object as? String else { return }
                deepLinks.openLibraryItem(itemID, session: session)
            }
            .onReceive(NotificationCenter.default.publisher(for: .zelefinOpenScheduledTasks)) { _ in
                _ = LibraryAlertCenter.shared.takePendingScheduledTasks()
                guard session.isSignedIn, plus.isUnlocked else { return }
                profileSheet = .scheduledTasks
            }
    }
}

private struct RootSessionLifecycleModifier: ViewModifier {
    @Environment(SessionStore.self) private var session
    @Environment(DeepLinkStore.self) private var deepLinks
    @Environment(PlusEntitlement.self) private var plus
    @Environment(\.scenePhase) private var scenePhase
    @Binding var profileSheet: ProfileSheet?

    func body(content: Content) -> some View {
        content
            .onChange(of: session.isSignedIn) { _, signedIn in
                if !signedIn {
                    profileSheet = nil
                    deepLinks.dismissPresentedItem()
                } else {
                    Task { await deepLinks.flushPending(session: session) }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard session.isSignedIn, !session.isReviewDemo else { return }
                if phase == .active {
                    consumePendingNotificationDestination()
                }
            }
            .onOpenURL { url in
                Task { await deepLinks.handle(url, session: session) }
            }
    }

    private func consumePendingNotificationDestination() {
        if let itemID = LibraryAlertCenter.shared.takePendingItemID() {
            deepLinks.openLibraryItem(itemID, session: session)
        }
        if LibraryAlertCenter.shared.takePendingScheduledTasks() {
            guard session.isSignedIn, plus.isUnlocked else { return }
            profileSheet = .scheduledTasks
        }
    }
}
