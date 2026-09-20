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
    case removeFromHomeQueue
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
        case .continueWatching, .nextUp:
            return [.download, .play, .goToShow, .markWatched, .removeFromHomeQueue]
        case .featured:
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
    var onAddSubtitles: (() -> Void)? = nil
    var onRemoveFromHomeQueue: (() -> Void)? = nil
    var onRemoveFromRecentlyWatched: (() -> Void)? = nil

    @Environment(DownloadStore.self) private var downloads
    @Environment(SessionStore.self) private var session

    var body: some View {
        let actions = PlaybackQueueMenuLayout.actions(context: context, kind: item.kind)
        let downloadState: DownloadControlState = session.downloadsAvailable
            ? downloads.control(for: item, account: session.session)
            : .unavailable

        TitleUserActions(item: item, onChange: { _ in })

        if actions.contains(.download) {
            Button(DownloadControlCopy.title(for: downloadState), systemImage: DownloadControlCopy.symbol(for: downloadState)) {
                onDownload()
            }
            .disabled(downloadState == .unavailable)
        }
        if item.kind == .movie || item.kind == .episode {
            TitlePlaybackMenus(item: item, onAddSubtitles: onAddSubtitles)
        } else if session.shouldShowAddSubtitles(for: item), let onAddSubtitles {
            Button("Add Subtitles", systemImage: "captions.bubble") {
                onAddSubtitles()
            }
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
        if actions.contains(.removeFromHomeQueue),
           session.jellyfinEnhancedAvailable,
           let onRemoveFromHomeQueue
        {
            Button(
                JellyfinEnhancedHomeHide.menuTitle(
                    for: JellyfinEnhancedHomeHide.surface(queueKind: item.queueKind)
                ),
                systemImage: "eye.slash"
            ) {
                onRemoveFromHomeQueue()
            }
        }
        if actions.contains(.removeFromRecentlyWatched), let onRemoveFromRecentlyWatched {
            Button("Remove from Recently Watched", systemImage: "eye.slash", role: .destructive) {
                onRemoveFromRecentlyWatched()
            }
        }
    }
}

struct TitlePlaybackMenus: View {
    let item: MediaItem
    var audioTracks: [MediaTrack]? = nil
    var subtitleTracks: [MediaTrack]? = nil
    var streamRevision: Int = 0
    var onAddSubtitles: (() -> Void)? = nil

    @Environment(SessionStore.self) private var session
    @State private var loadedAudio: [MediaTrack] = []
    @State private var loadedSubtitles: [MediaTrack] = []
    @State private var didLoadTracks = false
    @State private var localRevision = 0
    @State private var versions: [MediaVersion] = []

    var body: some View {
        let options = session.launchOptions(for: item.id)
        let quality = options.resolvedQuality
        Group {
            if versions.count > 1 {
                Menu("Version") {
                    ForEach(versions) { version in
                        Button {
                            session.updateLaunchOptions(for: item.id) { $0.mediaSourceID = version.id }
                        } label: {
                            if options.mediaSourceID == version.id || (options.mediaSourceID == nil && version.id == versions.first?.id) {
                                Label(version.title, systemImage: "checkmark")
                            } else {
                                Text(version.title)
                            }
                        }
                    }
                }
            }
            if !session.usesSilo {
                Button {
                    session.updateLaunchOptions(for: item.id) { $0.skipCinemaIntros.toggle() }
                } label: {
                    if options.skipCinemaIntros {
                        Label("Skip Cinema Intros", systemImage: "checkmark")
                    } else {
                        Text("Skip Cinema Intros")
                    }
                }
            }
            Menu("Quality") {
                ForEach(PlaybackQuality.allCases) { option in
                    Button {
                        session.updateLaunchOptions(for: item.id) { $0.quality = option }
                    } label: {
                        if option == quality {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            }
            Menu("Select Audio") {
                if audio.isEmpty {
                    Text(didLoadTracks ? "No audio tracks" : "Loading…")
                } else {
                    ForEach(audio) { track in
                        Button {
                            session.updateLaunchOptions(for: item.id) { $0.audioIndex = track.id }
                        } label: {
                            if options.audioIndex == track.id || (options.audioIndex == nil && track.isSelected) {
                                Label(track.title, systemImage: "checkmark")
                            } else {
                                Text(track.title)
                            }
                        }
                    }
                }
            }
            Menu("Select Subtitles") {
                Button {
                    session.updateLaunchOptions(for: item.id) { current in
                        current.subtitlesDisabled = true
                        current.subtitleIndex = nil
                    }
                } label: {
                    if options.subtitlesDisabled {
                        Label("Off", systemImage: "checkmark")
                    } else {
                        Text("Off")
                    }
                }
                if subtitles.isEmpty {
                    Text(didLoadTracks ? "No subtitles" : "Loading…")
                } else {
                    ForEach(subtitles) { track in
                        Button {
                            session.updateLaunchOptions(for: item.id) { current in
                                current.subtitlesDisabled = false
                                current.subtitleIndex = track.id
                            }
                        } label: {
                            if !options.subtitlesDisabled,
                               options.subtitleIndex == track.id || (options.subtitleIndex == nil && track.isSelected) {
                                Label(track.title, systemImage: "checkmark")
                            } else {
                                Text(track.title)
                            }
                        }
                    }
                }
            }
            if session.shouldShowAddSubtitles(for: item), let onAddSubtitles {
                Button("Add Subtitles", systemImage: "captions.bubble") {
                    onAddSubtitles()
                }
            }
        }
        .task(id: "\(item.id)-\(streamRevision)-\(localRevision)") {
            await reloadTracks()
            versions = await session.library?.mediaVersions(for: item.id) ?? []
        }
        .onReceive(NotificationCenter.default.publisher(for: .zelefinSubtitlesSaved)) { notification in
            guard let savedID = notification.userInfo?[SubtitleCatalogRefresh.itemIDKey] as? String,
                  savedID == item.id
            else { return }
            localRevision += 1
        }
    }

    private func reloadTracks() async {
        guard audioTracks == nil || subtitleTracks == nil else {
            didLoadTracks = true
            return
        }
        didLoadTracks = false
        let fetched = await session.library?.streamTracks(for: item.id) ?? (audio: [], subtitles: [])
        if audioTracks == nil {
            loadedAudio = fetched.audio
        }
        if subtitleTracks == nil {
            loadedSubtitles = fetched.subtitles
        }
        didLoadTracks = true
    }

    private var audio: [MediaTrack] {
        audioTracks ?? loadedAudio
    }

    private var subtitles: [MediaTrack] {
        subtitleTracks ?? loadedSubtitles
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
    @Environment(PlusEntitlement.self) private var plus
    @State private var errorMessage: String?
    @State private var removalPrompt: DownloadRemovalPrompt?
    @State private var subtitleSearchItem: MediaItem?

    var body: some View {
        Menu {
            PlaybackQueueMenuContent(
                item: item,
                context: context,
                onPlay: onPlay,
                onDownload: { Task { await requestDownloadAction() } },
                onMarkWatched: { Task { await toggleWatched() } },
                onAddSubtitles: {
                    subtitleSearchItem = item
                },
                onRemoveFromHomeQueue: (context == .continueWatching || context == .nextUp)
                    ? { Task { await removeFromHomeQueue() } }
                    : nil,
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
        .openSubtitlesSearch(item: $subtitleSearchItem)
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
            guard plus.require(.downloads) else { return }
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

    private func removeFromHomeQueue() async {
        do {
            try await session.hideFromHomeQueue(item)
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
