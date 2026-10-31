import SwiftUI

struct IdentifySheet: View {
    let item: MediaItem
    var onClose: () -> Void

    @Environment(SessionStore.self) private var session
    @State private var hits: [RemoteIdentifyHit] = []
    @State private var loading = true
    @State private var applying: String?
    @State private var errorMessage: String?

    var body: some View {
        TitleSheet(title: "Identify", closeDisabled: applying != nil, onClose: onClose) {
            List {
                Section {
                    if loading {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Searching…").foregroundStyle(.secondary)
                        }
                    } else if let errorMessage {
                        SettingsStatusText(text: errorMessage, isError: true)
                    } else if hits.isEmpty {
                        Text("No matches found.").foregroundStyle(.secondary)
                    } else {
                        ForEach(hits) { hit in
                            Button {
                                Task { await apply(hit) }
                            } label: {
                                HStack(alignment: .center, spacing: 8) {
                                    TitleSheetRow(
                                        title: [hit.name, hit.year.map(String.init)].compactMap { $0 }.joined(separator: " · "),
                                        detail: hit.overview,
                                        imageURL: hit.imageURL,
                                        showsImage: true
                                    )
                                    if applying == hit.id {
                                        ProgressView()
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(applying != nil)
                        }
                    }
                } header: {
                    Text("Matches for \(item.name)")
                } footer: {
                    Text("Choosing a match replaces this title's metadata and artwork with the provider's.")
                        .font(TitleSheetFont.note)
                }
                .zelefinRowBackground()
            }
            .task { await load() }
        }
    }

    private func load() async {
        loading = true
        hits = await session.library?.identifyHits(for: item) ?? []
        loading = false
    }

    private func apply(_ hit: RemoteIdentifyHit) async {
        applying = hit.id
        do {
            try await session.library?.applyIdentify(itemID: item.id, hit: hit)
            onClose()
        } catch {
            errorMessage = error.localizedDescription
            applying = nil
        }
    }
}

struct EditMetadataSheet: View {
    let item: MediaItem
    var onClose: () -> Void

    @Environment(SessionStore.self) private var session
    @State private var draft: ItemMetadataDraft
    @State private var busy = false
    @State private var errorMessage: String?

    init(item: MediaItem, onClose: @escaping () -> Void) {
        self.item = item
        self.onClose = onClose
        _draft = State(initialValue: ItemMetadataDraft(item: item))
    }

    var body: some View {
        TitleSheet(
            title: "Edit Metadata",
            closeDisabled: busy,
            confirmTitle: busy ? "Saving…" : "Save",
            confirmDisabled: busy,
            onConfirm: { Task { await save() } },
            onClose: onClose
        ) {
            List {
                if let errorMessage {
                    Section {
                        SettingsStatusText(text: errorMessage, isError: true)
                    }
                    .zelefinRowBackground()
                }
                Section("Title") {
                    TitleSheetField(label: "Name", text: $draft.name)
                    TitleSheetField(label: "Year", text: $draft.year, prompt: "2021")
                    TitleSheetField(label: "Rating", text: $draft.officialRating, prompt: "PG-13")
                }
                .zelefinRowBackground()
                Section {
                    TitleSheetField(label: "Genres", text: $draft.genres, prompt: "Drama, Science Fiction")
                    TitleSheetField(label: "Tags", text: $draft.tags)
                } header: {
                    Text("Categories")
                } footer: {
                    Text("Separate genres and tags with commas.")
                        .font(TitleSheetFont.note)
                }
                .zelefinRowBackground()
                Section("Overview") {
                    TitleSheetField(label: "Description", text: $draft.overview, multiline: true)
                }
                .zelefinRowBackground()
            }
        }
    }

    private func save() async {
        busy = true
        do {
            try await session.library?.updateItemMetadata(itemID: item.id, draft: draft)
            onClose()
        } catch {
            errorMessage = error.localizedDescription
            busy = false
        }
    }
}
