import SwiftUI

enum PlaybackQueueMenuContext: Equatable, Sendable {
    case continueWatching
    case nextUp
    case recentlyWatched
    case episode
    case featured
}

enum PlaybackQueueMenuAction: Equatable, Sendable {
    case download
    case play
    case goToShow
    case markWatched
    case removeFromRecentlyWatched
}

enum PlaybackQueueMenuLayout {
    static func actions(
        context: PlaybackQueueMenuContext,
        kind: MediaKind
    ) -> [PlaybackQueueMenuAction] {
        _ = kind
        switch context {
        case .episode:
            return [.download, .play, .markWatched]
        case .continueWatching, .nextUp, .featured:
            return [.download, .play, .goToShow, .markWatched]
        case .recentlyWatched:
            return [.download, .play, .goToShow, .markWatched, .removeFromRecentlyWatched]
        }
    }

    static func playTitle(for kind: MediaKind) -> String {
        kind == .episode ? "Play Episode" : "Play"
    }

    static func goToTitle(for kind: MediaKind) -> String {
        switch kind {
        case .episode, .season, .series:
            "Go to Show"
        default:
            "Go to Movie"
        }
    }

    static func goToSymbol(for kind: MediaKind) -> String {
        switch kind {
        case .episode, .season, .series:
            "tv"
        default:
            "film"
        }
    }

    static func watchedTitle(isWatched: Bool) -> String {
        isWatched ? "Mark as Unwatched" : "Mark as Watched"
    }

    static func watchedSymbol(isWatched: Bool) -> String {
        isWatched ? "eye.slash" : "checkmark.circle"
    }
}

struct PlaybackQueueMenuContent: View {
    let item: MediaItem
    let context: PlaybackQueueMenuContext
    var onPlay: () -> Void
    var onDownload: () -> Void
    var onMarkWatched: () -> Void
    var onRemoveFromRecentlyWatched: (() -> Void)? = nil

    @Environment(DownloadStore.self) private var downloads
    @Environment(SessionStore.self) private var session

    var body: some View {
        let actions = PlaybackQueueMenuLayout.actions(context: context, kind: item.kind)
        let downloadState = downloads.control(for: item, account: session.session)

        if actions.contains(.download) {
            Button(DownloadControlCopy.title(for: downloadState), systemImage: DownloadControlCopy.symbol(for: downloadState)) {
                onDownload()
            }
            .disabled(downloadState == .unavailable)
        }
        if actions.contains(.play) {
            Button(PlaybackQueueMenuLayout.playTitle(for: item.kind), systemImage: "play.fill") {
                onPlay()
            }
        }
        if actions.contains(.goToShow) {
            NavigationLink {
                ItemDetailView(item: item)
            } label: {
                Label(
                    PlaybackQueueMenuLayout.goToTitle(for: item.kind),
                    systemImage: PlaybackQueueMenuLayout.goToSymbol(for: item.kind)
                )
            }
        }
        if actions.contains(.markWatched) {
            Button(
                PlaybackQueueMenuLayout.watchedTitle(isWatched: item.isWatched),
                systemImage: PlaybackQueueMenuLayout.watchedSymbol(isWatched: item.isWatched)
            ) {
                onMarkWatched()
            }
        }
        if actions.contains(.removeFromRecentlyWatched), let onRemoveFromRecentlyWatched {
            Button("Remove from Recently Watched", systemImage: "eye.slash", role: .destructive) {
                onRemoveFromRecentlyWatched()
            }
        }
    }
}

/// Overflow control on Continue Watching / Next Up / Recently Watched cards and list rows.
struct PlaybackQueueOverflowButton: View {
    let item: MediaItem
    let context: PlaybackQueueMenuContext
    var onPlay: () -> Void
    var onDidChange: (() -> Void)? = nil
    var labelOpacity: Double = 0.75
    var usesCardChrome = true
    var usesHeroChrome = false
    var onMenuVisibilityChange: ((Bool) -> Void)? = nil

    @Environment(SessionStore.self) private var session
    @Environment(DownloadStore.self) private var downloads
    @State private var errorMessage: String?
    @State private var removalPrompt: DownloadRemovalPrompt?

    var body: some View {
        Menu {
            PlaybackQueueMenuContent(
                item: item,
                context: context,
                onPlay: onPlay,
                onDownload: { Task { await requestDownloadAction() } },
                onMarkWatched: { Task { await toggleWatched() } },
                onRemoveFromRecentlyWatched: context == .recentlyWatched
                    ? { Task { await removeFromRecentlyWatched() } }
                    : nil
            )
            .onAppear { onMenuVisibilityChange?(true) }
            .onDisappear { onMenuVisibilityChange?(false) }
        } label: {
            if usesHeroChrome {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
                    .zelefinLiquidGlassCircle()
            } else {
                Image(systemName: "ellipsis")
                    .font(usesCardChrome ? .system(size: 18, weight: .bold) : .body.weight(.bold))
                    .foregroundStyle(.white.opacity(labelOpacity))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More")
        .alert("Library", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .downloadRemovalConfirmation($removalPrompt) {
            downloads.removeDownloaded(item: item, account: session.session)
            onDidChange?()
        }
    }

    private func requestDownloadAction() async {
        switch downloads.control(for: item, account: session.session) {
        case .unavailable:
            return
        case .downloading:
            downloads.cancelTransfer(for: item, account: session.session)
        case .downloaded:
            removalPrompt = .make(item: item)
        case .idle:
            await startDownload()
        }
    }

    private func startDownload() async {
        do {
            try await downloads.toggle(
                item: item,
                library: session.library,
                account: session.session
            )
            onDidChange?()
        } catch {
            guard !DownloadFailure.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func toggleWatched() async {
        do {
            if item.isWatched {
                try await session.markUnwatched(item)
            } else {
                try await session.markWatched(item)
            }
            onDidChange?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeFromRecentlyWatched() async {
        do {
            try await session.hideFromRecentlyWatched(item)
            onDidChange?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
