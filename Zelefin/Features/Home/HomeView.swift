import SwiftUI

struct HomeView: View {
    @Environment(SessionStore.self) private var session

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
                                    FeaturedHero(items: session.homeLayout.featured) { item in
                                        session.library?.backdropURL(for: item)
                                    }
                                    .frame(height: PosterMetrics.heroHeight(for: geo.size))
                                }

                                ForEach(session.homeLayout.sections) { section in
                                    MediaRow(section: section)
                                }
                            }
                            .padding(.bottom, 32)
                        }
                        .refreshable { await session.refreshHome() }
                    }
                }

                #if os(iOS)
                FloatingPageHeader(title: "Home")
                    .padding(.top, ScreenInsets.top)
                #endif
            }
        }
        .background(Color.black.ignoresSafeArea())
        #if os(iOS)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
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
    let section: HomeSection
    @State private var playbackPlan: PlaybackPlan?
    @State private var playbackError: String?

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
        .fullScreenCover(item: $playbackPlan) { plan in
            PlayerView(plan: plan)
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
                        Task { await play(item) }
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
                    onPlay: { Task { await play(item) } }
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
                    onPlay: { Task { await play(item) } },
                    onMarkWatched: { Task { await markWatched(item) } },
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
        switch style {
        case .landscape, .replayLandscape:
            PosterMetrics.landscapeSize.width
        case .portrait, .ranked, .labeledPortrait:
            PosterMetrics.portraitSize.width
        }
    }

    private func playsOnTap(_ item: MediaItem) -> Bool {
        HomeLayoutPreferences.isPlaybackQueueSection(section.id) && item.kind == .episode
    }

    private func play(_ item: MediaItem) async {
        guard let library = session.library else { return }
        do {
            playbackPlan = try await library.playbackPlan(for: item)
        } catch {
            playbackError = error.localizedDescription
        }
    }

    #if os(tvOS)
    private func markWatched(_ item: MediaItem) async {
        do {
            try await session.markWatched(item)
        } catch {
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
    let section: HomeSection

    private let columns = [
        GridItem(.adaptive(minimum: PosterMetrics.portraitSize.width), spacing: PosterMetrics.rowSpacing)
    ]

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
                        PortraitPoster(
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
    @State private var playbackPlan: PlaybackPlan?
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
                                    Task { await play(item) }
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
                            onPlay: { Task { await play(item) } },
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
        .fullScreenCover(item: $playbackPlan) { plan in
            PlayerView(plan: plan)
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

    private func play(_ item: MediaItem) async {
        guard let library = session.library else { return }
        do {
            playbackPlan = try await library.playbackPlan(for: item)
        } catch {
            playbackError = error.localizedDescription
        }
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
    let section: HomeSection

    private let columns = [
        GridItem(.adaptive(minimum: PosterMetrics.portraitSize.width), spacing: PosterMetrics.rowSpacing)
    ]

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
                        LabeledPortraitCard(
                            title: item.browsingCardTitle,
                            imageURL: session.library?.artworkURL(for: item, style: .labeledPortrait),
                            washColor: item.kind == .genre ? LabeledPortraitCard.genreWash(for: item.name) : nil
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(width: PosterMetrics.portraitSize.width)
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
    let title: String
    let query: Query

    enum Query: Hashable {
        case genre(String)
        case parent(String)
        case person(String)
    }

    @State private var items: [MediaItem] = []
    @State private var isLoading = true

    private let columns = [
        GridItem(.adaptive(minimum: PosterMetrics.portraitSize.width), spacing: PosterMetrics.rowSpacing)
    ]

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .tint(.white)
                    .padding(.top, 80)
                    .frame(maxWidth: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView(
                    "No Titles",
                    systemImage: "rectangle.stack",
                    description: Text("Nothing in this category yet.")
                )
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(items) { item in
                        NavigationLink {
                            if item.kind == .collection {
                                CatalogGridView(title: item.name, query: .parent(item.id))
                            } else {
                                ItemDetailView(item: item)
                            }
                        } label: {
                            PortraitPoster(
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
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        .task { await load() }
    }

    private func load() async {
        guard let library = session.library else {
            isLoading = false
            return
        }
        do {
            switch query {
            case let .genre(id):
                items = try await library.items(genreID: id)
            case let .parent(id):
                items = try await library.items(parentID: id)
            case let .person(id):
                items = try await library.items(personID: id)
            }
        } catch is CancellationError {
            return
        } catch {
            items = []
        }
        isLoading = false
    }
}
