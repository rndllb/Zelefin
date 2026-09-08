import SwiftUI

struct SeerrRequestView: View {
    let title: SeerrTitle
    var onRequested: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var servers: [SeerrServiceServer] = []
    @State private var details: SeerrServiceDetails?
    @State private var seasons: [SeerrSeason] = []
    @State private var occupiedSeasonNumbers: Set<Int> = []
    @State private var mediaSeasons: [SeerrMediaSeason] = []
    @State private var selectedSeasonNumbers: Set<Int> = []
    @State private var is4k = false
    @State private var serverID: Int?
    @State private var profileID: Int?
    @State private var rootFolder = ""
    @State private var languageProfileID: Int?
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var client: SeerrClient? { PluginSettings.seerrClient }

    private var regularSeasons: [SeerrSeason] {
        seasons.filter { !$0.isSpecials }
    }

    private var specials: [SeerrSeason] {
        seasons.filter(\.isSpecials)
    }

    private var requestableSeasonNumbers: Set<Int> {
        Set(regularSeasons.map(\.seasonNumber).filter { !occupiedSeasonNumbers.contains($0) })
    }

    private var canSubmit: Bool {
        guard !isSubmitting, serverID != nil, profileID != nil, !rootFolder.isEmpty else { return false }
        if title.kind == .movie, title.availability == .available, !is4k {
            return false
        }
        if title.kind == .tv {
            return !selectedSeasonNumbers.subtracting(occupiedSeasonNumbers).isEmpty
        }
        return true
    }

    var body: some View {
        Form {
            header

            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else {
                destinationSection
                if title.kind == .tv {
                    seasonSection
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .navigationTitle("Request")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Request") {
                    Task { await submit() }
                }
                .disabled(!canSubmit)
            }
        }
        .task { await load() }
        .onChange(of: is4k) { _, _ in
            refreshOccupiedSeasons()
            applyDefaultServer()
            applySeasonDefaults()
            Task { await loadDetails() }
        }
        .onChange(of: serverID) { _, _ in
            Task { await loadDetails() }
        }
    }

    private var header: some View {
        Section {
            HStack(alignment: .top, spacing: 14) {
                PosterImage(url: title.posterURL)
                    .frame(width: 72, height: 108)
                    .posterCard(cornerRadius: 8)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                    if let overview = title.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(4)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var destinationSection: some View {
        Section {
            if servers.isEmpty {
                Text(title.kind == .movie
                     ? "No Radarr server is set up in Seerr."
                     : "No Sonarr server is set up in Seerr.")
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                if servers.contains(where: \.uses4K) {
                    Toggle("4K", isOn: $is4k)
                }
                Picker("Server", selection: $serverID) {
                    ForEach(visibleServers) { server in
                        Text(server.name).tag(Optional(server.id))
                    }
                }
                if let details, !details.profiles.isEmpty {
                    Picker("Quality", selection: $profileID) {
                        ForEach(details.profiles) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }
                }
                if let details, !details.rootFolders.isEmpty {
                    Picker("Drive", selection: $rootFolder) {
                        ForEach(details.rootFolders) { folder in
                            Text(folder.pickerTitle).tag(folder.path)
                        }
                    }
                }
                if let languages = details?.languageProfiles, !languages.isEmpty {
                    Picker("Language", selection: $languageProfileID) {
                        ForEach(languages) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }
                }
            }
        } header: {
            Text("Download")
        } footer: {
            Text("Quality and drive default to this Seerr server’s active profile and folder.")
        }
    }

    private var seasonSection: some View {
        Section {
            if !requestableSeasonNumbers.isEmpty {
                Button(selectedSeasonNumbers.isSuperset(of: requestableSeasonNumbers) ? "Deselect All" : "Select All") {
                    if selectedSeasonNumbers.isSuperset(of: requestableSeasonNumbers) {
                        selectedSeasonNumbers.subtract(requestableSeasonNumbers)
                    } else {
                        selectedSeasonNumbers.formUnion(requestableSeasonNumbers)
                    }
                }
            }
            ForEach(regularSeasons) { season in
                seasonToggle(season)
            }
            if !specials.isEmpty {
                ForEach(specials) { season in
                    seasonToggle(season)
                }
            }
        } header: {
            Text("Seasons")
        } footer: {
            Text("Already requested or available seasons stay off. Specials are off unless you turn them on.")
        }
    }

    private func seasonToggle(_ season: SeerrSeason) -> some View {
        let occupied = occupiedSeasonNumbers.contains(season.seasonNumber)
        return Toggle(season.title, isOn: seasonBinding(season.seasonNumber))
            .disabled(occupied)
    }

    private var visibleServers: [SeerrServiceServer] {
        let matching = servers.filter { $0.uses4K == is4k }
        return matching.isEmpty ? servers : matching
    }

    private var subtitle: String {
        var parts = [title.kind == .movie ? "Movie" : "Show"]
        if let year = title.year {
            parts.append("\(year)")
        }
        parts.append(title.availability.buttonTitle)
        return parts.joined(separator: " · ")
    }

    private func seasonBinding(_ number: Int) -> Binding<Bool> {
        Binding(
            get: { occupiedSeasonNumbers.contains(number) || selectedSeasonNumbers.contains(number) },
            set: { isOn in
                guard !occupiedSeasonNumbers.contains(number) else { return }
                if isOn {
                    selectedSeasonNumbers.insert(number)
                } else {
                    selectedSeasonNumbers.remove(number)
                }
            }
        )
    }

    private func load() async {
        guard let client else {
            errorMessage = "Sign in to Seerr in Settings."
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            if title.kind == .movie {
                servers = try await client.radarrServers()
            } else {
                async let fetchedServers = client.sonarrServers()
                async let fetchedShow = client.tvDetails(id: title.tmdbID)
                servers = try await fetchedServers
                let show = try await fetchedShow
                seasons = show.seasons
                mediaSeasons = show.mediaInfo?.seasons ?? []
                refreshOccupiedSeasons()
                applySeasonDefaults()
            }
            applyDefaultServer()
            await loadDetails()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshOccupiedSeasons() {
        occupiedSeasonNumbers = Set(
            mediaSeasons.filter { $0.isOccupied(is4k: is4k) }.map(\.seasonNumber)
        )
    }

    private func applySeasonDefaults() {
        selectedSeasonNumbers = requestableSeasonNumbers
        selectedSeasonNumbers.subtract(occupiedSeasonNumbers)
        if let special = specials.first?.seasonNumber {
            selectedSeasonNumbers.remove(special)
        }
    }

    private func applyDefaultServer() {
        let preferred = SeerrRequestDefaults.preferredServer(from: servers, is4k: is4k)
        serverID = preferred?.id
    }

    private func loadDetails() async {
        guard let client, let serverID else { return }
        do {
            let loaded: SeerrServiceDetails
            if title.kind == .movie {
                loaded = try await client.radarrDetails(id: serverID)
            } else {
                loaded = try await client.sonarrDetails(id: serverID)
            }
            details = loaded
            let server = loaded.server
            if loaded.profiles.contains(where: { $0.id == server.activeProfileId }) {
                profileID = server.activeProfileId
            } else {
                profileID = loaded.profiles.first?.id
            }
            if loaded.rootFolders.contains(where: { $0.path == server.activeDirectory }) {
                rootFolder = server.activeDirectory ?? loaded.rootFolders.first?.path ?? ""
            } else {
                rootFolder = loaded.rootFolders.first?.path ?? server.activeDirectory ?? ""
            }
            if let languages = loaded.languageProfiles, !languages.isEmpty {
                languageProfileID = server.activeLanguageProfileId ?? languages.first?.id
            } else {
                languageProfileID = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submit() async {
        guard let client else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let draft = SeerrRequestDraft(
            kind: title.kind,
            tmdbID: title.tmdbID,
            seasons: title.kind == .tv ? .numbers(selectedSeasonNumbers.subtracting(occupiedSeasonNumbers).sorted()) : nil,
            is4k: is4k,
            serverID: serverID,
            profileID: profileID,
            rootFolder: rootFolder,
            languageProfileID: languageProfileID
        )
        do {
            try await client.request(draft)
            onRequested()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
