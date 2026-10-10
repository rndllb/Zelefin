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
        NavigationStack {
            List {
                if loading {
                    Text("Searching…").foregroundStyle(.secondary)
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else if hits.isEmpty {
                    Text("No matches found.").foregroundStyle(.secondary)
                } else {
                    ForEach(hits) { hit in
                        Button {
                            Task { await apply(hit) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text([hit.name, hit.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                                    .foregroundStyle(.white)
                                if let overview = hit.overview, !overview.isEmpty {
                                    Text(overview).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                                }
                                if applying == hit.name {
                                    Text("Applying…").font(.footnote).foregroundStyle(AccentPreferences.current)
                                }
                            }
                        }
                        .disabled(applying != nil)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Identify")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
            .task { await load() }
        }
        .preferredColorScheme(.dark)
    }

    private func load() async {
        loading = true
        hits = await session.library?.identifyHits(for: item) ?? []
        loading = false
    }

    private func apply(_ hit: RemoteIdentifyHit) async {
        applying = hit.name
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
        NavigationStack {
            Form {
                TextField("Name", text: $draft.name)
                TextField("Year", text: $draft.year)
                TextField("Rating", text: $draft.officialRating)
                TextField("Genres", text: $draft.genres)
                TextField("Tags", text: $draft.tags)
                TextField("Overview", text: $draft.overview, axis: .vertical)
                    .lineLimit(4...8)
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Edit Metadata")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(busy)
                }
            }
        }
        .preferredColorScheme(.dark)
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
