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
                    ContentUnavailableView("No Titles", systemImage: "person", description: Text("Nothing for this person in your library."))
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
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(profile?.name ?? name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            PosterImage(url: profile?.imageURL ?? imageURL ?? session.library?.personImageURL(id: personID, tag: profile?.imageTag ?? imageTag))
                .frame(width: 110, height: 110)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(profile?.name ?? name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                if let year = profile?.birthYear {
                    Text("Born \(year)")
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
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
                Section("New Collection") {
                    HStack {
                        TextField("Name", text: $newName)
                        Button("Create") {
                            Task { await create() }
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Section("Collections") {
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
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onClose)
                }
            }
            .task { await load() }
        }
        .preferredColorScheme(.dark)
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

    @Environment(SessionStore.self) private var session
    private var plus: PlusEntitlement { PlusEntitlement.shared }

    var body: some View {
        Button {
            Task { await toggleFavorite() }
        } label: {
            Label(
                item.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: item.isFavorite ? "heart.fill" : "heart"
            )
        }
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
        if let onCollections {
            Button("Add to Collection…", systemImage: "folder.badge.plus", action: onCollections)
        }
        if let onPlaylists {
            Button("Add to Playlist…", systemImage: "list.bullet.rectangle", action: onPlaylists)
        }
        if let onPlayElsewhere, !session.usesSilo {
            Button("Play on Another Device…", systemImage: "tv.badge.wifi") {
                guard plus.require(.sessions) else { return }
                onPlayElsewhere()
            }
        }
        if let onSyncPlay, !session.usesSilo {
            Button("Play in SyncPlay…", systemImage: "person.2.wave.2") {
                guard plus.require(.syncPlay) else { return }
                onSyncPlay()
            }
        }
        if onRefreshMetadata != nil || onRemoteImage != nil || onDelete != nil {
            Divider()
        }
        if let onRefreshMetadata {
            Button("Refresh Metadata", systemImage: "arrow.clockwise") {
                guard plus.require(.adminTools) else { return }
                onRefreshMetadata()
            }
        }
        if let onRemoteImage {
            Button("Choose Remote Image…", systemImage: "photo.on.rectangle") {
                guard plus.require(.adminTools) else { return }
                onRemoteImage()
            }
        }
        if let onDelete {
            Button("Delete from Library…", systemImage: "trash", role: .destructive) {
                guard plus.require(.adminTools) else { return }
                onDelete()
            }
        }
    }

    private func toggleFavorite() async {
        guard let updated = try? await session.toggleFavorite(item) else { return }
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
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                if targets.isEmpty {
                    Text("No other devices are connected right now.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(targets) { target in
                        Button {
                            Task { await play(on: target) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(target.deviceLabel)
                                Text(target.userLabel)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Play On")
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
        sessions = (try? await session.jellyfinLibrary?.playbackSessions()) ?? []
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
