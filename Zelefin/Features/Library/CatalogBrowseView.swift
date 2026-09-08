import SwiftUI

struct CatalogBrowseView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.tabBarPlacement) private var tabBarPlacement
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    let title: String
    let libraryKind: LibraryKind

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var query = CatalogBrowseQuery.default
    @State private var options = CatalogFilterOptions()
    @State private var showFilters = false
    @State private var showSort = false
    @State private var indexProgress: CatalogIndexProgress?
    @State private var headerVisible = true

    private var columns: [GridItem] {
        PosterGridLayout.columns(for: sidebarLayout)
    }

    private var emptyMessage: String {
        if !query.isDefault {
            return "No titles match these filters."
        }
        switch libraryKind {
        case .movies: return "Movies from this server will show up here."
        case .shows: return "Shows from this server will show up here."
        case .collections: return "Collections from this server will show up here."
        default: return "Titles from this server will show up here."
        }
    }

    private var emptySymbol: String {
        switch libraryKind {
        case .shows: "tv"
        case .collections: "square.grid.2x2.fill"
        default: "film"
        }
    }

    private var gridTopPadding: CGFloat {
        if RootPageChrome.showsTitle { return RootPageChrome.headerRowHeight }
        if tabBarPlacement == .sidebar { return RootPageChrome.headerRowHeight }
        return 0
    }

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView().tint(.white)
            } else if items.isEmpty {
                ContentUnavailableView(
                    query.isDefault ? "No Titles Yet" : "No Matches",
                    systemImage: emptySymbol,
                    description: Text(emptyMessage)
                )
            } else {
                ScrollView {
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
                        .padding(.bottom, 32)
                    }
                    .padding(.top, gridTopPadding)
                }
                .zelefinScrollEdgeBlur()
                .zelefinHeaderScrollVisibility($headerVisible)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            FloatingPageHeader(
                title: title,
                isVisible: RootPageChrome.showsTitle ? headerVisible : true,
                liftsIntoPadTabBar: true
            ) {
                CatalogFilterSortButtons(
                    filterCount: query.activeFilterCount,
                    sortTitle: query.sort.title,
                    onSort: { showSort = true },
                    onFilter: { showFilters = true }
                )
            }
        }
        .animation(ZelefinMotion.sidebarChrome, value: tabBarPlacement)
        .catalogFilterSheets(
            query: $query,
            options: options,
            showFilters: $showFilters,
            showSort: $showSort
        )
        .task { await loadOptions() }
        .task { await load() }
        .onChange(of: query) { _, _ in
            guard !showFilters, !showSort else { return }
            Task { await load() }
        }
        .onChange(of: showFilters) { _, open in
            if !open { Task { await load() } }
        }
        .onChange(of: showSort) { _, open in
            if !open { Task { await load() } }
        }
        .onChange(of: session.libraries) { _, _ in
            Task { await load() }
        }
    }

    private func loadOptions() async {
        guard let library = session.library else { return }
        options = await library.catalogFilterOptions(for: libraryKind)
    }

    private func load() async {
        if query.isDefault, items.isEmpty, let cached = session.cachedCatalog(kind: libraryKind), !cached.isEmpty {
            items = cached
            isLoading = false
        }
        guard let library = session.library else {
            isLoading = false
            indexProgress = nil
            return
        }
        var catalog = session.libraries
        if catalog.isEmpty {
            catalog = (try? await library.libraries()) ?? []
        }
        let showingCachedDefault = query.isDefault && !items.isEmpty
        let fresh = await library.browseCatalog(
            kind: libraryKind,
            libraries: catalog,
            query: query
        ) { update in
            applyListing(update, protectingCachedDefault: showingCachedDefault)
        }
        if !fresh.isEmpty || !query.isDefault {
            items = fresh
            if query.isDefault {
                session.saveCatalog(fresh, kind: libraryKind)
            }
        }
        isLoading = false
        await finishArtwork(for: fresh.isEmpty ? items : fresh, library: library)
    }

    private func applyListing(_ update: CatalogPageUpdate, protectingCachedDefault: Bool) {
        indexProgress = .listing(loaded: update.items.count, total: update.totalCount)
        guard !update.items.isEmpty else { return }
        if protectingCachedDefault, update.items.count < items.count { return }
        items = update.items
        isLoading = false
    }

    private func finishArtwork(for items: [MediaItem], library: JellyfinLibraryClient) async {
        guard PosterPrefetcher.prefetchesPosters(for: libraryKind), !items.isEmpty else {
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
