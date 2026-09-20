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
    @State private var kind: RemoteArtworkKind = .poster
    @State private var images: [RemoteImageChoice] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var busyID: String?

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: CGFloat(kind.gridMinimum)), spacing: 10)]
    }

    var body: some View {
        NavigationStack {
            List {
                heroSection
                kindSection
                artworkSection
            }
            .zelefinSettingsChrome(title: "Edit Images")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                        .disabled(busyID != nil)
                }
            }
            .task(id: kind) { await load() }
        }
    }

    private var heroSection: some View {
        Section {
            VStack(spacing: 14) {
                SettingsHeroGlyph(systemImage: "photo.on.rectangle")
                Text(item.name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(LoginPalette.primaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                SettingsChip(icon: kind.systemImage, leading: kind.title)
            }
            .frame(maxWidth: .infinity)
            .settingsHeroRow()
        }
    }

    private var kindSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                SettingsFieldLabel(title: "Artwork")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(RemoteArtworkKind.allCases) { option in
                        Button {
                            kind = option
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: option.systemImage)
                                    .font(.caption.weight(.bold))
                                Text(option.title)
                                    .font(.caption.weight(.bold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(kind == option ? LoginPalette.actionLabel : LoginPalette.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(kind == option ? Color.accentColor : Color.white.opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(busyID != nil)
                        .accessibilityAddTraits(kind == option ? .isSelected : [])
                    }
                }
            }
            .settingsLoginCard()
            .settingsCardRow()
        } header: {
            Text("Type")
        }
    }

    @ViewBuilder
    private var artworkSection: some View {
        Section {
            if isLoading && images.isEmpty {
                VStack(spacing: 16) {
                    ConnectBrandMark(size: 72)
                    Text("Loading \(kind.title.lowercased())s")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LoginPalette.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .settingsLoginCard()
                .settingsCardRow()
            } else if images.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsFieldLabel(title: kind.emptyTitle)
                    SettingsStatusText(
                        text: errorMessage ?? "Jellyfin did not return any \(kind.title.lowercased()) options.",
                        isError: errorMessage != nil
                    )
                }
                .settingsLoginCard()
                .settingsCardRow()
            } else {
                if let errorMessage {
                    SettingsStatusText(text: errorMessage, isError: true)
                        .settingsLoginCard()
                        .settingsCardRow()
                }
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(images) { image in
                        artworkTile(image)
                    }
                }
                .listRowInsets(SettingsChrome.cardInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        } header: {
            Text(kind.title)
        }
    }

    private func artworkTile(_ image: RemoteImageChoice) -> some View {
        Button {
            Task { await choose(image) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                PosterImage(
                    url: image.previewURL,
                    aspectRatio: kind.previewAspectRatio,
                    contentMode: kind == .logo ? .fit : .fill
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    if busyID == image.id {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.45))
                        ProgressView()
                            .tint(.white)
                    }
                }
                Text(image.provider)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LoginPalette.primaryText)
                    .lineLimit(1)
                if let size = image.sizeLabel {
                    Text(size)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LoginPalette.captionText)
                }
            }
            .padding(10)
            .modifier(LoginCardBackground())
        }
        .buttonStyle(.plain)
        .disabled(busyID != nil)
        .accessibilityLabel(image.sizeLabel.map { "\(image.provider), \($0)" } ?? image.provider)
    }

    private func load() async {
        isLoading = true
        busyID = nil
        images = []
        do {
            images = try await session.library?.remoteArtwork(for: item.id, kind: kind) ?? []
            errorMessage = nil
        } catch {
            images = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func choose(_ image: RemoteImageChoice) async {
        busyID = image.id
        defer { busyID = nil }
        do {
            try await session.library?.downloadRemoteArtwork(itemID: item.id, kind: kind, imageURL: image.imageURL)
            let refreshed = try? await session.library?.item(id: item.id)
            session.noteLibraryArtworkChanged(for: item, refreshed: refreshed)
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
