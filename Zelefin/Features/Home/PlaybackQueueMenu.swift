import SwiftUI

enum PlaybackQueueMenuContext: Equatable, Sendable {
    case continueWatching
    case nextUp
    case recentlyWatched
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
        var actions: [PlaybackQueueMenuAction] = [.download, .play, .goToShow, .markWatched]
        if context == .recentlyWatched {
            actions.append(.removeFromRecentlyWatched)
        }
        return actions
    }

    static func playTitle(for kind: MediaKind) -> String {
        kind == .episode ? "Play Episode" : "Play"
    }

    static func goToTitle(for kind: MediaKind) -> String {
        kind == .episode || kind == .season ? "Go to Show" : "Go to Movie"
    }

    static func goToSymbol(for kind: MediaKind) -> String {
        kind == .episode || kind == .season ? "tv" : "film"
    }
}

struct PlaybackQueueMenuContent: View {
    let item: MediaItem
    let context: PlaybackQueueMenuContext
    var onPlay: () -> Void
    var onMarkWatched: () -> Void
    var onRemoveFromRecentlyWatched: (() -> Void)? = nil

    var body: some View {
        Button("Download", systemImage: "arrow.down.to.line") {}
        Button(PlaybackQueueMenuLayout.playTitle(for: item.kind), systemImage: "play.fill") {
            onPlay()
        }
        NavigationLink {
            ItemDetailView(item: item)
        } label: {
            Label(
                PlaybackQueueMenuLayout.goToTitle(for: item.kind),
                systemImage: PlaybackQueueMenuLayout.goToSymbol(for: item.kind)
            )
        }
        Button("Mark as Watched", systemImage: "checkmark.circle") {
            onMarkWatched()
        }
        if context == .recentlyWatched, let onRemoveFromRecentlyWatched {
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

    @Environment(SessionStore.self) private var session
    @State private var errorMessage: String?

    var body: some View {
        Menu {
            PlaybackQueueMenuContent(
                item: item,
                context: context,
                onPlay: onPlay,
                onMarkWatched: { Task { await markWatched() } },
                onRemoveFromRecentlyWatched: context == .recentlyWatched
                    ? { Task { await removeFromRecentlyWatched() } }
                    : nil
            )
        } label: {
            Image(systemName: "ellipsis")
                .font(usesCardChrome ? .system(size: 18, weight: .bold) : .body.weight(.bold))
                .foregroundStyle(.white.opacity(labelOpacity))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
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
    }

    private func markWatched() async {
        do {
            try await session.markWatched(item)
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
