import SwiftUI

struct LibraryView: View {
    @Environment(SessionStore.self) private var session
    #if os(iOS)
    @Environment(\.tabBarPlacement) private var tabBarPlacement
    #endif
    @State private var libraries: [MediaLibrary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    #if os(iOS)
    @State private var headerVisible = true
    #endif

    var body: some View {
        Group {
            if isLoading {
                ProgressView().tint(.white)
            } else {
                List {
                    Section {
                        if let errorMessage, libraries.isEmpty {
                            Text(errorMessage)
                                .foregroundStyle(.secondary)
                                .zelefinLibraryListRow()
                        }
                        ForEach(libraries) { library in
                            NavigationLink {
                                LibraryItemsView(library: library)
                            } label: {
                                Label(library.name, systemImage: icon(for: library))
                            }
                            .zelefinLibraryListRow()
                        }
                        NavigationLink {
                            CatalogBrowseView(title: "Collections", libraryKind: .collections)
                        } label: {
                            Label("Collections", systemImage: "square.grid.2x2.fill")
                        }
                        .zelefinLibraryListRow()
                        NavigationLink {
                            DownloadedItemsView()
                        } label: {
                            Label("Downloaded", systemImage: "arrow.down.circle")
                        }
                        .zelefinLibraryListRow()
                        NavigationLink {
                            LibraryGenresView()
                        } label: {
                            Label("Genres", systemImage: "square.grid.2x2")
                        }
                        .zelefinLibraryListRow()
                    }

                    if let movies = libraries.first(where: { $0.kind == .movie }) {
                        LibraryPreviewSection(title: "Movies", library: movies)
                    }
                    if let shows = libraries.first(where: { $0.kind == .series }) {
                        LibraryPreviewSection(title: "TV Shows", library: shows)
                    }
                }
                .listStyle(.plain)
                #if os(iOS)
                .scrollContentBackground(.hidden)
                .zelefinScrollEdgeBlur()
                .contentMargins(.top, RootPageChrome.showsTitle ? RootPageChrome.headerRowHeight : 0, for: .scrollContent)
                .zelefinHeaderScrollVisibility($headerVisible)
                #endif
            }
        }
        .background(Color.black.ignoresSafeArea())
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            FloatingPageHeader(
                title: "Library",
                isVisible: RootPageChrome.showsTitle ? headerVisible : true,
                liftsIntoPadTabBar: true
            )
        }
        .animation(ZelefinMotion.sidebarChrome, value: tabBarPlacement)
        #else
        .navigationTitle("Library")
        #endif
        .task {
            if !session.libraries.isEmpty {
                libraries = HomeLayoutPreferences.libraryTabLibraries(session.libraries)
                isLoading = false
            }
            await load()
        }
        .onChange(of: session.libraries) { _, catalog in
            guard !catalog.isEmpty else { return }
            libraries = HomeLayoutPreferences.libraryTabLibraries(catalog)
            isLoading = false
            errorMessage = nil
        }
    }

    private func icon(for library: MediaLibrary) -> String {
        switch library.libraryKind {
        case .movies: "film"
        case .shows: "tv"
        case .liveTV: "dot.radiowaves.left.and.right"
        case .collections: "square.grid.2x2.fill"
        default: "rectangle.stack"
        }
    }

    private func load() async {
        guard let client = session.library else {
            errorMessage = "Not signed in."
            isLoading = false
            return
        }
        do {
            libraries = HomeLayoutPreferences.libraryTabLibraries(try await client.libraries())
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct LibraryPreviewSection: View {
    @Environment(SessionStore.self) private var session
    let title: String
    let library: MediaLibrary
    @State private var items: [MediaItem] = []

    var body: some View {
        Section {
            if !items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PosterMetrics.rowSpacing) {
                        ForEach(items.prefix(12)) { item in
                            NavigationLink {
                                ItemDetailView(item: item)
                            } label: {
                                PortraitPoster(
                                    item: item,
                                    imageURL: session.library?.primaryURL(for: item)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.black)
                .listRowSeparator(.hidden)
            }
        } header: {
            NavigationLink {
                LibraryItemsView(library: library)
            } label: {
                HStack(spacing: 4) {
                    Text(title)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .task {
            items = (try? await session.library?.items(in: library)) ?? []
        }
    }
}

struct LibraryGenresView: View {
    @Environment(SessionStore.self) private var session
    @State private var genres: [MediaItem] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if genres.isEmpty {
                ContentUnavailableView(
                    "No Genres",
                    systemImage: "square.grid.2x2",
                    description: Text("Genres from your libraries will show up here.")
                )
            } else {
                List {
                    ForEach(genres) { genre in
                        NavigationLink {
                            CatalogGridView(title: genre.name, query: .genre(genre.id))
                        } label: {
                            Label {
                                Text(genre.name)
                            } icon: {
                                Image(systemName: GenreSymbol.systemImage(for: genre.name))
                                    .foregroundStyle(Color.blue)
                            }
                        }
                        .zelefinLibraryListRow()
                    }
                }
                .listStyle(.plain)
                #if os(iOS)
                .scrollContentBackground(.hidden)
                #endif
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Genres")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        .task { await load() }
    }

    private func load() async {
        if let cached = session.homeLayout.sections.first(where: { $0.id == "genres" })?.items, !cached.isEmpty {
            genres = cached
            isLoading = false
            return
        }
        genres = await session.library?.genresSectionIgnoringErrors()?.items ?? []
        isLoading = false
    }
}

struct LibraryItemsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    let library: MediaLibrary
    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var query = CatalogBrowseQuery.default
    @State private var options = CatalogFilterOptions()
    @State private var showFilters = false
    @State private var showSort = false
    @State private var indexProgress: CatalogIndexProgress?

    private var columns: [GridItem] {
        PosterGridLayout.columns(for: sidebarLayout)
    }

    var body: some View {
        ScrollView {
            if isLoading && items.isEmpty {
                ProgressView().tint(.white).padding(.top, 80)
            } else if items.isEmpty {
                ContentUnavailableView(
                    query.isDefault ? "No Titles Yet" : "No Matches",
                    systemImage: "rectangle.stack",
                    description: Text(query.isDefault ? "Titles from this library will show up here." : "No titles match these filters.")
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
        .navigationTitle(library.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        .catalogFilterSortToolbar(
            filterCount: query.activeFilterCount,
            sortTitle: query.sort.title,
            showFilters: $showFilters,
            showSort: $showSort
        )
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
    }

    private func loadOptions() async {
        guard let client = session.library else { return }
        options = await client.catalogFilterOptions(for: library)
    }

    private func load() async {
        guard let client = session.library else {
            items = []
            isLoading = false
            indexProgress = nil
            return
        }
        items = (try? await client.items(in: library, query: query) { update in
            indexProgress = .listing(loaded: update.items.count, total: update.totalCount)
            guard !update.items.isEmpty else { return }
            items = update.items
            isLoading = false
        }) ?? []
        isLoading = false
        await finishArtwork(for: items, client: client)
    }

    private func finishArtwork(for items: [MediaItem], client: JellyfinLibraryClient) async {
        guard PosterPrefetcher.prefetchesPosters(for: library.libraryKind), !items.isEmpty else {
            indexProgress = nil
            return
        }
        let urls = PosterPrefetcher.posterURLs(for: items, library: client)
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
