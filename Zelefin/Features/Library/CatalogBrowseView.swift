import SwiftUI

struct CatalogBrowseView: View {
    @Environment(SessionStore.self) private var session
    #if os(iOS)
    @Environment(\.tabBarPlacement) private var tabBarPlacement
    #endif
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    let title: String
    let libraryKind: LibraryKind

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    #if os(iOS)
    @State private var headerVisible = true
    #endif

    private var columns: [GridItem] {
        PosterGridLayout.columns(for: sidebarLayout)
    }

    private var emptyMessage: String {
        switch libraryKind {
        case .movies: "Movies from this server will show up here."
        case .shows: "Shows from this server will show up here."
        default: "Titles from this server will show up here."
        }
    }

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView().tint(.white)
            } else if items.isEmpty {
                ContentUnavailableView(
                    "No Titles Yet",
                    systemImage: libraryKind == .shows ? "tv" : "film",
                    description: Text(emptyMessage)
                )
            } else {
                ScrollView {
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
                    .padding(.top, RootPageChrome.showsTitle ? RootPageChrome.headerRowHeight : 0)
                    .padding(.bottom, 32)
                }
                .zelefinScrollEdgeBlur()
                #if os(iOS)
                .zelefinHeaderScrollVisibility($headerVisible)
                #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            FloatingPageHeader(
                title: title,
                isVisible: RootPageChrome.showsTitle ? headerVisible : true,
                liftsIntoPadTabBar: true
            )
        }
        .animation(ZelefinMotion.sidebarChrome, value: tabBarPlacement)
        #else
        .navigationTitle(title)
        #endif
        .task { await load() }
        .onChange(of: session.libraries) { _, _ in
            Task { await load() }
        }
    }

    private func load() async {
        guard let library = session.library else {
            isLoading = false
            return
        }
        var catalog = session.libraries
        if catalog.isEmpty {
            catalog = (try? await library.libraries()) ?? []
        }
        let matches = HomeLayoutPreferences.libraries(catalog, matching: libraryKind)
        items = await library.items(inLibraries: matches)
        isLoading = false
    }
}
