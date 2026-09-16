import SwiftUI

struct LibraryItemRoute: View {
    let item: MediaItem

    var body: some View {
        switch item.kind {
        case .collection:
            CatalogGridView(title: item.name, query: .parent(item.id))
        case .playlist:
            PlaylistDetailView(playlist: item)
        case .photo:
            PhotoViewerView(item: item)
        default:
            ItemDetailView(item: item)
        }
    }
}

struct PlaylistDetailView: View {
    let playlist: MediaItem
    @Environment(SessionStore.self) private var session
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    @State private var entries: [PlaylistEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            if isLoading && entries.isEmpty {
                ProgressView().tint(.white).padding(.top, 80)
            } else if entries.isEmpty {
                ContentUnavailableView(
                    "Empty Playlist",
                    systemImage: "list.bullet.rectangle",
                    description: Text(errorMessage ?? "Add titles from a movie or show page.")
                )
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: PosterGridLayout.columns(for: sidebarLayout), spacing: 20) {
                    ForEach(entries) { entry in
                        NavigationLink {
                            LibraryItemRoute(item: entry.item)
                        } label: {
                            FillingPortraitPoster(
                                item: entry.item,
                                imageURL: session.library?.primaryURL(for: entry.item)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
    }

    private func load() async {
        do {
            entries = try await session.library?.playlistEntries(playlistID: playlist.id) ?? []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct PlaylistPickerSheet: View {
    let item: MediaItem
    var onClose: () -> Void

    @Environment(SessionStore.self) private var session
    @State private var playlists: [MediaItem] = []
    @State private var newName = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                Section("New Playlist") {
                    HStack {
                        TextField("Name", text: $newName)
                        Button("Create") {
                            Task { await create() }
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Section("Playlists") {
                    if playlists.isEmpty {
                        Text("No playlists yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(playlists) { playlist in
                            Button(playlist.name) {
                                Task { await add(to: playlist) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                }
            }
            .task { await load() }
        }
        .preferredColorScheme(.dark)
    }

    private func load() async {
        playlists = (try? await session.library?.playlists()) ?? []
    }

    private func create() async {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let library = session.library else { return }
        do {
            try await library.createPlaylist(name: name, itemIDs: [item.id])
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func add(to playlist: MediaItem) async {
        do {
            try await session.library?.addToPlaylist(playlistID: playlist.id, itemIDs: [item.id])
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PhotoViewerView: View {
    let item: MediaItem
    @Environment(SessionStore.self) private var session

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PosterImage(
                url: session.library?.primaryURL(for: item, maxHeight: 1600),
                aspectRatio: 1,
                contentMode: .fit,
                fill: .black
            )
            .padding(12)
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .background(Color.black.ignoresSafeArea())
    }
}

struct RemoteImagePickerView: View {
    let item: MediaItem
    var onClose: () -> Void

    @Environment(SessionStore.self) private var session
    @State private var images: [RemoteImageChoice] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var busyID: String?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 10)]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && images.isEmpty {
                    ProgressView()
                } else if images.isEmpty {
                    ContentUnavailableView(
                        "No Remote Art",
                        systemImage: "photo.on.rectangle",
                        description: Text(errorMessage ?? "Jellyfin did not return any poster options.")
                    )
                } else {
                    ScrollView {
                        if let errorMessage {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                                .font(.footnote)
                                .padding()
                        }
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(images) { image in
                                Button {
                                    Task { await choose(image) }
                                } label: {
                                    VStack(spacing: 6) {
                                        PosterImage(url: image.previewURL, aspectRatio: 2 / 3, contentMode: .fill)
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                            .overlay {
                                                if busyID == image.id {
                                                    Color.black.opacity(0.45)
                                                    ProgressView().tint(.white)
                                                }
                                            }
                                        Text(image.provider)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .disabled(busyID != nil)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Remote Image")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                }
            }
            .task { await load() }
        }
        .preferredColorScheme(.dark)
    }

    private func load() async {
        do {
            images = try await session.library?.remoteArtwork(for: item.id) ?? []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func choose(_ image: RemoteImageChoice) async {
        busyID = image.id
        defer { busyID = nil }
        do {
            try await session.library?.downloadRemoteArtwork(itemID: item.id, imageURL: image.imageURL)
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
