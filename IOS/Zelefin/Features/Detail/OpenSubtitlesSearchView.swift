import SwiftUI

struct OpenSubtitlesSearchView: View {
    let item: MediaItem
    var mediaSourceID: String? = nil
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var language = SubtitleSearchLanguage.preferred
    @State private var perfectMatch = false
    @State private var matches: [RemoteSubtitleMatch] = []
    @State private var isSearching = false
    @State private var downloadingID: String?
    @State private var errorMessage: String?
    @State private var didSave = false

    var body: some View {
        List {
            Section {
                Picker("Language", selection: $language) {
                    ForEach(SubtitleSearchLanguage.choices) { choice in
                        Text(choice.name).tag(choice)
                    }
                }
                Toggle("Perfect match only", isOn: $perfectMatch)
                    .tint(AccentPreferences.current)
            } footer: {
                Text("Downloads from Open Subtitles onto this Jellyfin server. Perfect match uses the file hash.")
            }
            .zelefinRowBackground()

            Section {
                if isSearching && matches.isEmpty {
                    HStack {
                        Spacer(minLength: 0)
                        ProgressView()
                        Spacer(minLength: 0)
                    }
                } else if matches.isEmpty {
                    Text(emptyCopy)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(matches) { match in
                        Button {
                            Task { await download(match) }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(match.title)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    if !match.detail.isEmpty {
                                        Text(match.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                Spacer(minLength: 8)
                                if downloadingID == match.id {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(downloadingID != nil)
                    }
                }
            } header: {
                Text("Results")
            }
            .zelefinRowBackground()
        }
        .zelefinSettingsChrome(title: "Add Subtitles")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .task(id: searchKey) { await search() }
        .alert("Subtitles", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Subtitles saved", isPresented: $didSave) {
            Button("OK") { dismiss() }
        } message: {
            Text("Jellyfin stored the file on the server. The subtitle list on this title is updated.")
        }
    }

    private var searchKey: String {
        "\(item.id)|\(mediaSourceID ?? "")|\(language.code)|\(perfectMatch)"
    }

    private var emptyCopy: String {
        if isSearching {
            "Searching Open Subtitles…"
        } else if perfectMatch {
            "No hash match for this file in \(language.name)."
        } else {
            "No \(language.name) subtitles for this title."
        }
    }

    private func search() async {
        isSearching = true
        matches = []
        defer { isSearching = false }
        do {
            guard let client = session.client else {
                errorMessage = ZelefinError.missingUser.localizedDescription
                return
            }
            matches = try await OpenSubtitlesClient(client: client).search(
                itemID: item.id,
                language: language.code,
                perfectMatch: perfectMatch
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func download(_ match: RemoteSubtitleMatch) async {
        downloadingID = match.id
        defer { downloadingID = nil }
        do {
            guard let client = session.client else {
                errorMessage = ZelefinError.missingUser.localizedDescription
                return
            }
            try await OpenSubtitlesClient(client: client).download(
                itemID: item.id,
                subtitleID: match.id,
                userID: session.session?.userID ?? ""
            )
            SubtitleCatalogRefresh.postSaved(itemID: item.id)
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension View {
    func openSubtitlesSearch(item: Binding<MediaItem?>, mediaSourceID: String? = nil) -> some View {
        sheet(item: item) { title in
            NavigationStack {
                OpenSubtitlesSearchView(item: title, mediaSourceID: mediaSourceID)
            }
        }
    }
}
