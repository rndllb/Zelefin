import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(DownloadStore.self) private var downloads
    @Environment(DeepLinkStore.self) private var deepLinks
    @Environment(\.openURL) private var openURL
    @State private var profileSheet: ProfileSheet?

    var body: some View {
        rootContent
            .sheet(item: $profileSheet) { destination in
                ProfileSheetContainer(destination: destination)
                    .environment(session)
                    .environment(downloads)
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
            }
            .fullScreenCover(item: Binding(
                get: { session.pendingPlayerItem },
                set: { session.pendingPlayerItem = $0 }
            )) { item in
                PlayerView(item: item)
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
            .alert(
                session.incomingSessionMessage?.alertTitle ?? "Message",
                isPresented: Binding(
                    get: { session.incomingSessionMessage != nil },
                    set: { if !$0 { session.incomingSessionMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { session.incomingSessionMessage = nil }
            } message: {
                if let body = session.incomingSessionMessage?.alertBody {
                    Text(body)
                }
            }
            .task(id: session.incomingSessionMessage?.id) {
                await dismissSessionMessageIfTimedOut()
            }
            .preferredColorScheme(.dark)
            .zelefinAccentTint()
            .task {
                await session.restore()
                consumePendingNotificationDestination()
                await deepLinks.flushPending(session: session)
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
            guard session.isSignedIn else { return }
            profileSheet = .scheduledTasks
        }
    }

    private func dismissSessionMessageIfTimedOut() async {
        guard let message = session.incomingSessionMessage, let timeout = message.timeoutMs, timeout > 0 else { return }
        try? await Task.sleep(for: .milliseconds(timeout))
        if session.incomingSessionMessage?.id == message.id {
            session.incomingSessionMessage = nil
        }
    }
}

private struct RootNotificationModifier: ViewModifier {
    @Environment(SessionStore.self) private var session
    @Environment(DeepLinkStore.self) private var deepLinks
    @Binding var profileSheet: ProfileSheet?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .zelefinProfileSheet)) { notification in
                guard session.isSignedIn else { return }
                profileSheet = notification.object as? ProfileSheet
            }
            .onReceive(NotificationCenter.default.publisher(for: .zelefinRemotePlayItem)) { notification in
                guard let itemID = notificationString(notification.object) else { return }
                if session.syncPlayGroupID != nil {
                    Task {
                        let start = (notification.userInfo?["startSeconds"] as? TimeInterval)
                            ?? (notification.userInfo?["startSeconds"] as? Double)
                        await session.presentSyncPlayItem(id: itemID, start: start)
                    }
                } else {
                    deepLinks.openLibraryItem(itemID, session: session)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .zelefinSyncPlayJoined)) { notification in
                session.noteSyncPlayJoined(
                    groupID: notificationString(notification.object),
                    name: notification.userInfo?["name"] as? String
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .zelefinSyncPlayLeft)) { _ in
                session.noteSyncPlayLeft()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zelefinSyncPlayQueueItem)) { notification in
                session.noteSyncPlayPlaylistItem(notificationString(notification.object))
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
                guard session.isSignedIn else { return }
                profileSheet = .scheduledTasks
            }
            .onReceive(NotificationCenter.default.publisher(for: .zelefinSessionMessage)) { notification in
                guard let message = notification.object as? SessionDisplayMessage else { return }
                session.incomingSessionMessage = message
            }
    }
}

private struct RootSessionLifecycleModifier: ViewModifier {
    @Environment(SessionStore.self) private var session
    @Environment(DeepLinkStore.self) private var deepLinks
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
            guard session.isSignedIn else { return }
            profileSheet = .scheduledTasks
        }
    }
}

private func notificationString(_ object: Any?) -> String? {
    switch object {
    case let text as String:
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    case let uuid as UUID:
        return uuid.uuidString
    default:
        return nil
    }
}
