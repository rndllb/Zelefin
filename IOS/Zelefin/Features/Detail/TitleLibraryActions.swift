import SwiftUI

struct PersonDetailView: View {
    let personID: String
    let name: String
    let imageTag: String?
    var imageURL: URL? = nil

    @Environment(SessionStore.self) private var session
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    @State private var profile: CreditPerson?
    @State private var items: [MediaItem] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let overview = profile?.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 16)
                }
                if items.isEmpty, !isLoading {
                    ContentUnavailableView(AppLanguage.string("detail.no_titles", default: "No Titles"), systemImage: "person", description: Text(AppLanguage.string("detail.no_titles_person", default: "Nothing for this person in your library.")))
                        .padding(.top, 24)
                } else {
                    LazyVGrid(columns: PosterGridLayout.columns(for: sidebarLayout), spacing: 20) {
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
            .padding(.bottom, 32)
        }
        .background(Color.zelefinPage.ignoresSafeArea())
        // Name lives in the page header beside the photo — not again in the nav bar.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Color.zelefinPage, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            PosterImage(
                url: profile?.portraitURL(library: session.library)
                    ?? CreditPerson(
                        id: personID,
                        name: name,
                        roleLabel: "",
                        imageTag: imageTag,
                        rank: 0,
                        imageURL: imageURL
                    ).portraitURL(library: session.library)
            )
            .frame(width: 110, height: 110)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(profile?.name ?? name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                if let year = profile?.birthYear {
                    Text("Born \(String(year))")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private func load() async {
        let library = session.library
        async let fetched = library?.person(id: personID)
        let titles = (try? await library?.items(personID: personID)) ?? []
        profile = await fetched ?? CreditPerson(
            id: personID,
            name: name,
            roleLabel: "Cast & Crew",
            imageTag: imageTag,
            rank: 0,
            imageURL: imageURL
        )
        items = titles
        isLoading = false
    }
}

struct CollectionEditSheet: View {
    let item: MediaItem
    var onClose: () -> Void

    @Environment(SessionStore.self) private var session
    @State private var collections: [MediaItem] = []
    @State private var membershipIDs: Set<String> = []
    @State private var newName = ""
    @State private var errorMessage: String?

    var body: some View {
        TitleSheet(title: AppLanguage.string("library.collections", default: "Collections"), onClose: onClose) {
            List {
                if let errorMessage {
                    Section {
                        SettingsStatusText(text: errorMessage, isError: true)
                    }
                    .zelefinRowBackground()
                }
                Section(AppLanguage.string("ui.new_collection", default: "New Collection")) {
                    HStack {
                        TextField(AppLanguage.string("ui.name", default: "Name"), text: $newName)
                            .textFieldStyle(.plain)
                        Button(AppLanguage.string("common.create", default: "Create")) {
                            Task { await create() }
                        }
                        .fontWeight(.semibold)
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .zelefinRowBackground()
                Section {
                    if collections.isEmpty {
                        Text(AppLanguage.string("detail.no_collections", default: "No collections yet.")).foregroundStyle(.secondary)
                    }
                    ForEach(collections) { collection in
                        Button {
                            Task { await toggle(collection) }
                        } label: {
                            HStack {
                                Text(collection.browsingCardTitle)
                                    .foregroundStyle(.white)
                                Spacer()
                                if membershipIDs.contains(collection.id) {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(AppLanguage.string("library.collections", default: "Collections"))
                } footer: {
                    Text("Checked collections include \(item.name).")
                        .font(TitleSheetFont.note)
                }
                .zelefinRowBackground()
            }
            .task { await load() }
        }
    }

    private func load() async {
        guard let library = session.library else { return }
        collections = await library.boxSets()
        let memberships = await library.collections(containing: item.id)
        membershipIDs = Set(memberships.map(\.id))
    }

    private func toggle(_ collection: MediaItem) async {
        guard let library = session.library else { return }
        do {
            if membershipIDs.contains(collection.id) {
                try await library.removeFromCollection(collectionID: collection.id, itemIDs: [item.id])
                membershipIDs.remove(collection.id)
            } else {
                try await library.addToCollection(collectionID: collection.id, itemIDs: [item.id])
                membershipIDs.insert(collection.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func create() async {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let library = session.library else { return }
        do {
            try await library.createCollection(name: name, itemIDs: [item.id])
            newName = ""
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TitleUserActions: View {
    let item: MediaItem
    var onChange: (MediaItem) -> Void
    var onCollections: (() -> Void)? = nil
    var onPlaylists: (() -> Void)? = nil
    var onPlayElsewhere: (() -> Void)? = nil
    var onSyncPlay: (() -> Void)? = nil
    var onRefreshMetadata: (() -> Void)? = nil
    var onRemoteImage: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onIdentify: (() -> Void)? = nil
    var onEditMetadata: (() -> Void)? = nil

    @Environment(SessionStore.self) private var session

    var body: some View {
        Button {
            Task { await toggleFavorite() }
        } label: {
            Label(
                item.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: item.isFavorite ? "heart.fill" : "heart"
            )
        }
        // Silo's Jellyfin-compatible API serves no playlists (the watchlist is one) and rejects likes.
        if !session.isSiloServer {
            Button {
                Task { await toggleWatchlist() }
            } label: {
                Label(
                    item.isWatchlisted ? "Remove from Watchlist" : "Add to Watchlist",
                    systemImage: item.isWatchlisted ? "text.badge.minus" : "text.badge.plus"
                )
            }
            // Emby 4.10 answers rating calls but never stores a like.
            if !session.isEmbyServer {
                Button {
                    Task { await setLikes(item.likes == true ? nil : true) }
                } label: {
                    Label(
                        item.likes == true ? "Liked" : "Like",
                        systemImage: item.likes == true ? "hand.thumbsup.fill" : "hand.thumbsup"
                    )
                }
                Button {
                    Task { await setLikes(item.likes == false ? nil : false) }
                } label: {
                    Label(
                        item.likes == false ? "Disliked" : "Dislike",
                        systemImage: item.likes == false ? "hand.thumbsdown.fill" : "hand.thumbsdown"
                    )
                }
            }
        }
        if let onCollections {
            Button(AppLanguage.string("ui.add_to_collection", default: "Add to Collection…"), systemImage: "folder.badge.plus", action: onCollections)
        }
        if let onPlaylists {
            Button(AppLanguage.string("ui.add_to_playlist_2", default: "Add to Playlist…"), systemImage: "list.bullet.rectangle", action: onPlaylists)
        }
        if let onPlayElsewhere, !session.isSiloServer {
            Button(AppLanguage.string("ui.play_on_another_device", default: "Play on Another Device…"), systemImage: "tv.badge.wifi", action: onPlayElsewhere)
        }
        if let onSyncPlay, !session.lacksJellyfinOnlyFeatures {
            Button(AppLanguage.string("ui.play_in_syncplay", default: "Play in SyncPlay…"), systemImage: "person.2.wave.2", action: onSyncPlay)
        }
        if onRefreshMetadata != nil || onRemoteImage != nil || onDelete != nil {
            Divider()
        }
        if let onRefreshMetadata {
            Button(AppLanguage.string("ui.refresh_metadata", default: "Refresh Metadata"), systemImage: "arrow.clockwise", action: onRefreshMetadata)
        }
        if let onIdentify {
            Button(AppLanguage.string("ui.identify_2", default: "Identify…"), systemImage: "magnifyingglass", action: onIdentify)
        }
        if let onEditMetadata {
            Button(AppLanguage.string("ui.edit_metadata_2", default: "Edit Metadata…"), systemImage: "pencil", action: onEditMetadata)
        }
        if let onRemoteImage {
            Button(AppLanguage.string("ui.edit_images_2", default: "Edit Images…"), systemImage: "photo.on.rectangle", action: onRemoteImage)
        }
        if let onDelete {
            Button(AppLanguage.string("ui.delete_from_library", default: "Delete from Library…"), systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private func toggleFavorite() async {
        guard let updated = try? await session.toggleFavorite(item) else { return }
        onChange(updated)
    }

    private func toggleWatchlist() async {
        guard let updated = try? await session.toggleWatchlist(item) else { return }
        onChange(updated)
    }

    private func setLikes(_ likes: Bool?) async {
        guard let updated = try? await session.setLikes(item, likes: likes) else { return }
        onChange(updated)
    }
}

struct PlayOnDeviceSheet: View {
    let item: MediaItem
    var onClose: () -> Void

    @Environment(SessionStore.self) private var session
    @State private var sessions: [PlaybackSession] = []
    @State private var errorMessage: String?

    private var targets: [PlaybackSession] {
        sessions.filter { !$0.isThisDevice(session.session?.deviceID) && $0.canControl }
    }

    var body: some View {
        TitleSheet(title: AppLanguage.string("ui.play_on", default: "Play On"), onClose: onClose) {
            List {
                if let errorMessage {
                    Section {
                        SettingsStatusText(text: errorMessage, isError: true)
                    }
                    .zelefinRowBackground()
                }
                Section {
                    if targets.isEmpty {
                        Text(AppLanguage.string("detail.no_devices", default: "No other devices are connected right now."))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(targets) { target in
                            Button {
                                Task { await play(on: target) }
                            } label: {
                                TitleSheetRow(title: target.deviceLabel, detail: target.userLabel)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text(AppLanguage.string("detail.devices", default: "Devices"))
                }
                .zelefinRowBackground()
            }
            .task { await load() }
        }
    }

    private func load() async {
        sessions = (try? await session.remoteSessions?.playbackSessions()) ?? []
    }

    private func play(on target: PlaybackSession) async {
        do {
            try await session.playOnSession(sessionID: target.id, item: item)
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
