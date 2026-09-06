import SwiftUI

struct LibraryView: View {
    @Environment(SessionStore.self) private var session
    #if os(iOS)
    @Environment(\.tabBarPlacement) private var tabBarPlacement
    #endif
    @State private var libraries: [MediaLibrary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView().tint(.white)
            } else if let errorMessage {
                ContentUnavailableView("Couldn’t Load Library", systemImage: "books.vertical", description: Text(errorMessage))
            } else {
                List {
                    Section {
                        ForEach(libraries) { library in
                            NavigationLink {
                                LibraryItemsView(library: library)
                            } label: {
                                Label(library.name, systemImage: icon(for: library))
                            }
                        }
                    }

                    if let movies = libraries.first(where: { $0.kind == .movie }) {
                        LibraryPreviewSection(title: "Movies", library: movies)
                    }
                    if let shows = libraries.first(where: { $0.kind == .series }) {
                        LibraryPreviewSection(title: "TV Shows", library: shows)
                    }
                }
                #if os(iOS)
                .scrollContentBackground(.hidden)
                #endif
            }
        }
        .background(Color.black.ignoresSafeArea())
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            FloatingPageHeader()
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
                .listRowBackground(Color.clear)
            }
        } header: {
            Text(title)
        }
        .task {
            items = (try? await session.library?.items(in: library)) ?? []
        }
    }
}

struct LibraryItemsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    let library: MediaLibrary
    @State private var items: [MediaItem] = []
    @State private var isLoading = true

    private var columns: [GridItem] {
        PosterGridLayout.columns(for: sidebarLayout)
    }

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().tint(.white).padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(items) { item in
                        NavigationLink {
                            ItemDetailView(item: item)
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
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(library.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            items = (try? await session.library?.items(in: library)) ?? []
            isLoading = false
        }
    }
}
