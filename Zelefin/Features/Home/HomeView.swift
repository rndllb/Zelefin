import SwiftUI

struct HomeView: View {
    @Environment(SessionStore.self) private var session
    #if os(iOS)
    @Environment(\.tabBarPlacement) private var tabBarPlacement
    @State private var headerVisible = true
    #endif

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Group {
                    if session.isLoadingHome && session.homeLayout.sections.isEmpty {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let errorMessage = session.homeError, session.homeLayout.sections.isEmpty {
                        ContentUnavailableView(
                            "Couldn’t Load Home",
                            systemImage: "wifi.exclamationmark",
                            description: Text(errorMessage)
                        )
                    } else if session.homeLayout.sections.isEmpty {
                        ContentUnavailableView(
                            "No Titles Yet",
                            systemImage: "play.rectangle.on.rectangle",
                            description: Text("Movies and shows from this server will show up here.")
                        )
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 28) {
                                if !session.homeLayout.featured.isEmpty {
                                    let heroSize = CGSize(
                                        width: geo.size.width,
                                        height: PosterMetrics.heroHeight(for: geo.size)
                                    )
                                    FeaturedHero(items: session.homeLayout.featured, size: heroSize) { item in
                                        session.library?.backdropURL(for: item)
                                    }
                                    .frame(width: heroSize.width, height: heroSize.height)
                                }

                                ForEach(session.homeLayout.sections) { section in
                                    MediaRow(section: section)
                                }
                            }
                            .padding(.bottom, 32)
                        }
                        .refreshable { await session.refreshHome() }
                        .scrollClipDisabled()
                        .zelefinScrollEdgeBlur()
                        #if os(iOS)
                        .zelefinHeaderScrollVisibility($headerVisible)
                        #endif
                    }
                }

                #if os(iOS)
                FloatingPageHeader(title: "Home", isVisible: RootPageChrome.showsTitle ? headerVisible : true)
                    .padding(.top, ScreenInsets.top)
                    .transition(.opacity)
                #endif
            }
        }
        .background(Color.black.ignoresSafeArea())
        #if os(iOS)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .animation(ZelefinMotion.sidebarChrome, value: tabBarPlacement)
        #else
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ProfileMenu()
            }
        }
        #endif
    }
}

struct MediaRow: View {
    @Environment(SessionStore.self) private var session
    @Environment(DownloadStore.self) private var downloads
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    let section: HomeSection
    @State private var playingItem: MediaItem?
    @State private var playbackError: String?
    @State private var removalPrompt: DownloadRemovalPrompt?
    @State private var removalItem: MediaItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if section.showsChevron {
                NavigationLink {
                    sectionDestination
                } label: {
                    SectionHeader(title: section.title)
                }
                .buttonStyle(.plain)
            } else {
                SectionHeader(title: section.title, showsChevron: false)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: PosterMetrics.rowSpacing) {
                    ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                        queueCard(item, rank: index + 1)
                            .frame(width: cardWidth(for: section.style), alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .fullScreenCover(item: $playingItem) { item in
            PlayerView(item: item)
        }
        .alert("Playback", isPresented: Binding(
            get: { playbackError != nil },
            set: { if !$0 { playbackError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playbackError ?? "")
        }
        .downloadRemovalConfirmation($removalPrompt) {
            if let removalItem {
                downloads.removeDownloaded(item: removalItem, account: session.session)
            }
            removalItem = nil
        }
    }

    @ViewBuilder
    private var sectionDestination: some View {
        if HomeLayoutPreferences.isPlaybackQueueSection(section.id) {
            ContinueWatchingListView(
                title: section.title,
                items: section.items,
                mode: .upNext,
                menuContext: HomeLayoutPreferences.menuContext(forSectionID: section.id) ?? .continueWatching
            )
        } else if section.isRecentlyWatched {
            ContinueWatchingListView(
                title: section.title,
                items: section.items,
                mode: .watched,
                menuContext: .recentlyWatched
            )
        } else if section.isCatalogBrowse {
            CatalogCardGridView(section: section)
        } else {
            SectionGridView(section: section)
        }
    }

    @ViewBuilder
    private func itemDestination(_ item: MediaItem) -> some View {
        if item.kind == .genre {
            CatalogGridView(title: item.name, query: .genre(item.id))
        } else if item.kind == .collection {
            CatalogGridView(title: item.name, query: .parent(item.id))
        } else {
            ItemDetailView(item: item)
        }
    }

    @ViewBuilder
    private func queueCard(_ item: MediaItem, rank: Int) -> some View {
        let context = HomeLayoutPreferences.menuContext(forSectionID: section.id)
        let cardView = card(for: item, rank: rank, showsOverflowIcon: context == nil)
        ZStack(alignment: .bottomTrailing) {
            Group {
                if playsOnTap(item) {
                    Button {
                        play(item)
                    } label: {
                        cardView
                    }
                } else {
                    NavigationLink {
                        itemDestination(item)
                    } label: {
                        cardView
                    }
                }
            }
            .buttonStyle(.plain)

            if let context {
                PlaybackQueueOverflowButton(
                    item: item,
                    context: context,
                    onPlay: { play(item) }
                )
                .padding(.trailing, 2)
                .padding(.bottom, 2)
            }
        }
        #if os(tvOS)
        .contextMenu {
            if let context {
                PlaybackQueueMenuContent(
                    item: item,
                    context: context,
                    onPlay: { play(item) },
                    onDownload: { Task { await requestDownload(item) } },
                    onMarkWatched: { Task { await toggleWatched(item) } },
                    onRemoveFromRecentlyWatched: context == .recentlyWatched
                        ? { Task { await hideFromRecentlyWatched(item) } }
                        : nil
                )
            }
        }
        #endif
    }

    @ViewBuilder
    private func card(for item: MediaItem, rank: Int, showsOverflowIcon: Bool = true) -> some View {
        let url = session.library?.artworkURL(for: item, style: section.style)
        switch section.style {
        case .landscape:
            LandscapeCard(item: item, imageURL: url, showsOverflowIcon: showsOverflowIcon)
        case .replayLandscape:
            ReplayLandscapeCard(item: item, imageURL: url, showsOverflowIcon: showsOverflowIcon)
        case .portrait:
            PortraitPoster(item: item, imageURL: url)
        case .ranked:
            PortraitPoster(item: item, imageURL: url, rank: rank)
        case .labeledPortrait:
            LabeledPortraitCard(
                title: item.browsingCardTitle,
                imageURL: url,
                washColor: item.kind == .genre ? LabeledPortraitCard.genreWash(for: item.name) : nil
            )
        }
    }

    private func cardWidth(for style: HomeSection.Style) -> CGFloat {
        let scale = sidebarLayout.scale
        switch style {
        case .landscape, .replayLandscape:
            return PosterMetrics.landscapeSize.width * scale
        case .portrait, .ranked, .labeledPortrait:
            return PosterMetrics.portraitSize.width * scale
        }
    }

    private func playsOnTap(_ item: MediaItem) -> Bool {
        HomeLayoutPreferences.isPlaybackQueueSection(section.id) && item.kind == .episode
    }

    private func play(_ item: MediaItem) {
        playingItem = item
    }

    #if os(tvOS)
    private func toggleWatched(_ item: MediaItem) async {
        do {
            if item.isWatched {
                try await session.markUnwatched(item)
            } else {
                try await session.markWatched(item)
            }
        } catch {
            playbackError = error.localizedDescription
        }
    }

    private func requestDownload(_ item: MediaItem) async {
        switch downloads.control(for: item, account: session.session) {
        case .unavailable:
            return
        case .downloading:
            downloads.cancelTransfer(for: item, account: session.session)
        case .downloaded:
            removalItem = item
            removalPrompt = .make(item: item)
        case .idle:
            await startDownload(item)
        }
    }

    private func startDownload(_ item: MediaItem) async {
        do {
            try await downloads.toggle(item: item, library: session.library, account: session.session)
        } catch {
            guard !DownloadFailure.isCancellation(error) else { return }
            playbackError = error.localizedDescription
        }
    }

    private func hideFromRecentlyWatched(_ item: MediaItem) async {
        do {
            try await session.hideFromRecentlyWatched(item)
        } catch {
            playbackError = error.localizedDescription
        }
    }
    #endif
}

struct SectionGridView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    let section: HomeSection

    private var columns: [GridItem] {
        PosterGridLayout.columns(for: sidebarLayout)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(section.items) { item in
                    NavigationLink {
                        if item.kind == .collection {
                            CatalogGridView(title: item.name, query: .parent(item.id))
                        } else {
                            ItemDetailView(item: item)
                        }
                    } label: {
                        FillingPortraitPoster(
                            item: item,
                            imageURL: session.library?.primaryURL(for: item)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(section.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
    }
}

struct ContinueWatchingListView: View {
    @Environment(SessionStore.self) private var session
    var title: String = "Continue Watching"
    let items: [MediaItem]
    var mode: Mode = .upNext
    var menuContext: PlaybackQueueMenuContext = .continueWatching
    @State private var rows: [MediaItem]
    @State private var playingItem: MediaItem?
    @State private var playbackError: String?

    enum Mode {
        case upNext
        case watched
    }

    init(
        title: String = "Continue Watching",
        items: [MediaItem],
        mode: Mode = .upNext,
        menuContext: PlaybackQueueMenuContext = .continueWatching
    ) {
        self.title = title
        self.items = items
        self.mode = mode
        self.menuContext = menuContext
        _rows = State(initialValue: items)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 0) {
                        Group {
                            if mode == .upNext, item.kind == .episode {
                                Button {
                                    play(item)
                                } label: {
                                    ContinueWatchingRow(item: item, mode: mode, showsOverflow: false)
                                }
                            } else {
                                NavigationLink {
                                    ItemDetailView(item: item)
                                } label: {
                                    ContinueWatchingRow(item: item, mode: mode, showsOverflow: false)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        PlaybackQueueOverflowButton(
                            item: item,
                            context: menuContext,
                            onPlay: { play(item) },
                            onDidChange: { rows.removeAll { $0.id == item.id } },
                            labelOpacity: 0.45,
                            usesCardChrome: false
                        )
                        .padding(.trailing, 4)
                    }

                    if index < rows.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 1 / 3)
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        .fullScreenCover(item: $playingItem) { item in
            PlayerView(item: item)
        }
        .alert("Playback", isPresented: Binding(
            get: { playbackError != nil },
            set: { if !$0 { playbackError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playbackError ?? "")
        }
    }

    private func play(_ item: MediaItem) {
        playingItem = item
    }
}

private struct ContinueWatchingRow: View {
    @Environment(SessionStore.self) private var session
    let item: MediaItem
    var mode: ContinueWatchingListView.Mode = .upNext
    var showsOverflow = true

    private var subtitle: String {
        switch mode {
        case .upNext: item.continueWatchingListSubtitle
        case .watched: item.recentlyWatchedListSubtitle
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(
                url: session.library?.artworkURL(for: item, style: mode == .watched ? .replayLandscape : .landscape),
                aspectRatio: 16 / 9
            )
            .frame(width: 118, height: 66)
            .posterCard(cornerRadius: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.continueWatchingTitle)
                    .font(.body)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if showsOverflow {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, showsOverflow ? 16 : 0)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.continueWatchingTitle), \(subtitle)")
    }
}

struct CatalogCardGridView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    let section: HomeSection

    private var columns: [GridItem] {
        PosterGridLayout.columns(for: sidebarLayout)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(section.items) { item in
                    NavigationLink {
                        if item.kind == .genre {
                            CatalogGridView(title: item.name, query: .genre(item.id))
                        } else {
                            CatalogGridView(title: item.name, query: .parent(item.id))
                        }
                    } label: {
                        FillingPosterCell { size in
                            LabeledPortraitCard(
                                title: item.browsingCardTitle,
                                imageURL: session.library?.artworkURL(for: item, style: .labeledPortrait),
                                washColor: item.kind == .genre ? LabeledPortraitCard.genreWash(for: item.name) : nil,
                                width: size.width,
                                height: size.height
                            )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(section.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct CatalogGridView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    let title: String
    let query: Query

    enum Query: Hashable {
        case genre(String)
        case parent(String)
        case person(String)
    }

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var browseQuery = CatalogBrowseQuery.default
    @State private var options = CatalogFilterOptions()
    @State private var showFilters = false
    @State private var showSort = false
    @State private var indexProgress: CatalogIndexProgress?

    private var columns: [GridItem] {
        PosterGridLayout.columns(for: sidebarLayout)
    }

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .tint(.white)
                    .padding(.top, 80)
                    .frame(maxWidth: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView(
                    browseQuery.isDefault ? "No Titles" : "No Matches",
                    systemImage: "rectangle.stack",
                    description: Text(browseQuery.isDefault ? "Nothing in this category yet." : "No titles match these filters.")
                )
                .padding(.top, 40)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    CatalogIndexBar(progress: indexProgress)
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(items) { item in
                            NavigationLink {
                                if item.kind == .collection {
                                    CatalogGridView(title: item.name, query: .parent(item.id))
                                } else {
                                    ItemDetailView(item: item)
                                }
                            } label: {
                                FillingPortraitPoster(
                                    item: item,
                                    imageURL: session.library?.primaryURL(for: item)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        .catalogFilterSortToolbar(
            filterCount: browseQuery.activeFilterCount,
            sortTitle: browseQuery.sort.title,
            showFilters: $showFilters,
            showSort: $showSort
        )
        .catalogFilterSheets(
            query: $browseQuery,
            options: options,
            showFilters: $showFilters,
            showSort: $showSort
        )
        .task { await loadOptions() }
        .task { await load() }
        .onChange(of: browseQuery) { _, _ in
            guard !showFilters, !showSort else { return }
            Task { await load() }
        }
        .onChange(of: showFilters) { _, open in
            if !open { Task { await load() } }
        }
        .onChange(of: showSort) { _, open in
            if !open { Task { await load() } }
        }
    }

    private func loadOptions() async {
        guard let library = session.library else { return }
        switch query {
        case .genre, .person:
            options = await library.mixedCatalogFilterOptions()
        case let .parent(id):
            options = await library.collectionFilterOptions(parentID: id)
        }
    }

    private func load() async {
        guard let library = session.library else {
            isLoading = false
            indexProgress = nil
            return
        }
        do {
            let onPage: CatalogPageHandler = { update in
                indexProgress = .listing(loaded: update.items.count, total: update.totalCount)
                guard !update.items.isEmpty else { return }
                items = update.items
                isLoading = false
            }
            switch query {
            case let .genre(id):
                items = try await library.items(genreID: id, query: browseQuery, onPage: onPage)
            case let .parent(id):
                items = try await library.items(parentID: id, query: browseQuery, onPage: onPage)
            case let .person(id):
                items = try await library.items(personID: id, query: browseQuery, onPage: onPage)
            }
        } catch is CancellationError {
            return
        } catch {
            items = []
        }
        isLoading = false
        await finishArtwork(for: items, library: library)
    }

    private func finishArtwork(for items: [MediaItem], library: JellyfinLibraryClient) async {
        guard !items.isEmpty else {
            indexProgress = nil
            return
        }
        let urls = PosterPrefetcher.posterURLs(for: items, library: library)
        await PosterPrefetcher.download(urls) { cached, total in
            if cached >= total {
                indexProgress = nil
            } else {
                indexProgress = .artwork(cached: cached, total: total)
            }
        }
        indexProgress = nil
    }
}
