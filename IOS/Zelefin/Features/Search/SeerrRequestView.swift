import SwiftUI

struct SeerrRequestView: View {
    let title: SeerrTitle
    var onRequested: () -> Void

    init(title: SeerrTitle, onRequested: @escaping () -> Void) {
        self.title = title
        self.onRequested = onRequested
        _current = State(initialValue: title)
    }

    /// The title as the server has it now. A Discover row or search result doesn't carry its request.
    @State private var current: SeerrTitle

    @Environment(\.dismiss) private var dismiss
    @Environment(\.zelefinSurfaces) private var surfaces
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
    @State private var canManageRequests = false
    @State private var isEditingRequest = false

    private var client: (any RequestServiceClient)? { PluginSettings.seerrClient }

    /// Seerr's requests pick a Radarr or Sonarr server, quality, and folder. In Ombi only admins and
    /// power users pick the quality and folder; everyone else gets Ombi's defaults.
    private var choosesServer: Bool {
        guard let client else { return true }
        return client.choosesDownloadServer && (client.service == .seerr || canManageRequests)
    }

    private var isAwaitingApproval: Bool {
        current.review == .pendingApproval && current.requestID != nil
    }

    /// Requested already, with nothing left to ask for: a movie on its way, or a show whose every season is.
    private var isAlreadyRequested: Bool {
        guard current.availability != .available else { return false }
        switch title.kind {
        case .movie:
            return current.availability.isRequested && !is4k
        case .tv:
            return !regularSeasons.isEmpty && requestableSeasonNumbers.isEmpty
        }
    }

    private var regularSeasons: [SeerrSeason] {
        seasons.filter { !$0.isSpecials }
    }

    private var specials: [SeerrSeason] {
        seasons.filter(\.isSpecials)
    }

    private var requestableSeasonNumbers: Set<Int> {
        Set(regularSeasons.map(\.seasonNumber).filter { !occupiedSeasonNumbers.contains($0) })
    }

    /// Seerr with no Sonarr or Radarr still records a request, so admins can see what people want;
    /// nothing downloads. Only once the list has loaded empty, not while it is still on its way.
    private var requestsWithoutDownloader: Bool {
        choosesServer && !isLoading && servers.isEmpty && errorMessage == nil
    }

    /// Ombi leaves the quality and folder unset to use its own defaults; Seerr needs both.
    private var usesServiceDefaults: Bool { client?.service == .ombi }

    private var canSubmit: Bool {
        guard !isSubmitting else { return false }
        if choosesServer, !usesServiceDefaults, !requestsWithoutDownloader {
            guard serverID != nil, profileID != nil, !rootFolder.isEmpty else { return false }
        }
        if title.kind == .movie, current.availability == .available || current.availability.isRequested, !is4k {
            return false
        }
        if title.kind == .tv {
            return !selectedSeasonNumbers.subtracting(occupiedSeasonNumbers).isEmpty
        }
        return true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if current.availability == .available {
                    EmptyView()
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                } else if isAwaitingApproval && !canManageRequests {
                    reviewMessage
                } else if isAwaitingApproval {
                    if isEditingRequest {
                        destinationSection
                        if title.kind == .tv {
                            seasonSection
                        }
                    } else if choosesServer || title.kind == .tv {
                        requestSummary
                    }
                    reviewActions
                } else if isAlreadyRequested {
                    requestedMessage
                } else {
                    if choosesServer {
                        destinationSection
                    }
                    if title.kind == .tv {
                        seasonSection
                    }
                    requestButton
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(surfaces.canvas.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .navigationTitle(isAwaitingApproval ? "Review" : "Request")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(surfaces.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .zelefinAccentTint()
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
        HStack(alignment: .top, spacing: 14) {
            PosterImage(url: title.posterURL)
                .frame(width: 84, height: 126)
                .posterCard(cornerRadius: 10)
            VStack(alignment: .leading, spacing: 8) {
                Text(title.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                if let requestedByName = current.requestedByName {
                    Text("Requested by \(requestedByName)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                if let overview = title.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reviewMessage: some View {
        Text("Waiting for approval.")
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.7))
    }

    private var requestedMessage: some View {
        Text(current.review == .approved || current.availability == .processing
             ? "Approved. It appears in your library once it downloads."
             : "Requested. Waiting for approval.")
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.7))
    }

    private var requestSummary: some View {
        VStack(spacing: 0) {
            if choosesServer {
                summaryRow("Server", value: selectedServerName)
                summaryRow("Quality", value: selectedProfileName)
                summaryRow("Drive", value: rootFolder.isEmpty ? "Default" : rootFolder)
            }
            if title.kind == .tv {
                summaryRow("Seasons", value: seasonSummary)
            }
        }
        .background(surfaces.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 16)
            Text(value)
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
        .font(.body)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var selectedServerName: String {
        servers.first { $0.id == serverID }?.name ?? "Default"
    }

    private var selectedProfileName: String {
        details?.profiles.first { $0.id == profileID }?.name ?? "Default"
    }

    private var seasonSummary: String {
        let numbers = selectedSeasonNumbers.subtracting(occupiedSeasonNumbers).sorted()
        if numbers.isEmpty { return "None" }
        return numbers.map { "Season \($0)" }.joined(separator: ", ")
    }

    private var reviewActions: some View {
        VStack(spacing: 10) {
            Button {
                Task { await decide(approve: true) }
            } label: {
                decisionLabel(isSubmitting ? "Approving…" : "Approve", filled: true)
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting || (isEditingRequest && !canSubmit))
            Button {
                Task { await decide(approve: false) }
            } label: {
                decisionLabel("Decline", filled: false, destructive: true)
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
            if choosesServer {
                Button {
                    withAnimation(.smooth(duration: 0.22)) {
                        isEditingRequest.toggle()
                    }
                } label: {
                    decisionLabel(isEditingRequest ? "Done Editing" : "Edit Request", filled: false)
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
            }
        }
    }

    private func decisionLabel(_ title: String, filled: Bool, destructive: Bool = false) -> some View {
        Text(title)
            .font(.body.weight(.semibold))
            .foregroundStyle(filled ? LoginPalette.actionLabel : (destructive ? Color.red : Color.white))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background {
                if filled {
                    Capsule(style: .continuous).fill(.tint)
                } else {
                    Capsule(style: .continuous).fill(destructive ? Color.red.opacity(0.16) : Color.white.opacity(0.14))
                }
            }
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Download")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            if servers.isEmpty {
                Text("No \(title.kind == .movie ? "Radarr" : "Sonarr") server is set up in \(client?.service.name ?? "Seerr"). The request is still saved for an admin to see, but nothing downloads.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                VStack(spacing: 0) {
                    if servers.contains(where: \.uses4K) {
                        Toggle("4K", isOn: $is4k)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        divider
                    }
                    if !usesServiceDefaults {
                        menuRow("Server", value: selectedServerName) {
                            ForEach(visibleServers) { server in
                                Button(server.name) { serverID = server.id }
                            }
                        }
                    }
                    if let details, !details.profiles.isEmpty {
                        if !usesServiceDefaults { divider }
                        menuRow("Quality", value: selectedProfileName) {
                            if usesServiceDefaults {
                                Button("Default") { profileID = nil }
                            }
                            ForEach(details.profiles) { profile in
                                Button(profile.name) { profileID = profile.id }
                            }
                        }
                    }
                    if let details, !details.rootFolders.isEmpty {
                        divider
                        menuRow("Drive", value: rootFolder.isEmpty ? "Default" : rootFolder) {
                            if usesServiceDefaults {
                                Button("Default") { rootFolder = "" }
                            }
                            ForEach(details.rootFolders) { folder in
                                Button(folder.pickerTitle) { rootFolder = folder.path }
                            }
                        }
                    }
                    if let languages = details?.languageProfiles, !languages.isEmpty {
                        divider
                        menuRow("Language", value: languages.first { $0.id == languageProfileID }?.name ?? "Default") {
                            if usesServiceDefaults {
                                Button("Default") { languageProfileID = nil }
                            }
                            ForEach(languages) { profile in
                                Button(profile.name) { languageProfileID = profile.id }
                            }
                        }
                    }
                }
                .background(surfaces.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func menuRow<MenuContent: View>(_ title: String, value: String, @ViewBuilder content: () -> MenuContent) -> some View {
        Menu {
            content()
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.white)
                Spacer(minLength: 12)
                Text(value)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 0.5)
            .padding(.leading, 16)
    }

    private var seasonSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Seasons")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                if !requestableSeasonNumbers.isEmpty {
                    Button(selectedSeasonNumbers.isSuperset(of: requestableSeasonNumbers) ? "Deselect All" : "Select All") {
                        if selectedSeasonNumbers.isSuperset(of: requestableSeasonNumbers) {
                            selectedSeasonNumbers.subtract(requestableSeasonNumbers)
                        } else {
                            selectedSeasonNumbers.formUnion(requestableSeasonNumbers)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                    .buttonStyle(.plain)
                }
            }
            VStack(spacing: 0) {
                ForEach(regularSeasons) { season in
                    seasonToggle(season)
                }
                ForEach(specials) { season in
                    seasonToggle(season)
                }
            }
            .background(surfaces.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text("Already requested or available seasons stay off. Specials stay off unless you turn them on.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var requestButton: some View {
        Button {
            Task { await submit() }
        } label: {
            Text(isSubmitting ? "Requesting…" : "Request")
                .font(.body.weight(.semibold))
                .foregroundStyle(LoginPalette.actionLabel)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(.tint, in: Capsule(style: .continuous))
                .opacity(canSubmit ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    private func seasonToggle(_ season: SeerrSeason) -> some View {
        let occupied = occupiedSeasonNumbers.contains(season.seasonNumber)
        return Toggle(season.title, isOn: seasonBinding(season.seasonNumber))
            .disabled(occupied)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
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
        parts.append(current.availability.buttonTitle)
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
            errorMessage = "Sign in to \(PluginSettings.requestService.name) in Settings."
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            async let user = try? client.currentUser()
            async let refreshed = try? client.requestStatus(for: title)
            if let user = await user {
                canManageRequests = user.canManageRequests
            }
            if let refreshed = await refreshed {
                current = refreshed
            }
            if title.kind == .tv {
                let show = try await client.tvDetails(id: title.tmdbID)
                seasons = show.seasons
                mediaSeasons = show.mediaInfo?.seasons ?? []
                refreshOccupiedSeasons()
                applySeasonDefaults()
            }
            if choosesServer {
                servers = title.kind == .movie ? try await client.radarrServers() : try await client.sonarrServers()
                applyDefaultServer()
                await loadDetails()
            }
            if let requestID = current.requestID, isAwaitingApproval {
                await applyStoredRequest(id: requestID)
            }
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

    private func applyStoredRequest(id: Int) async {
        guard let client, let stored = try? await client.requestDetails(id: id) else { return }
        if stored.is4k == true {
            is4k = true
        }
        if let serverId = stored.serverId {
            serverID = serverId
        }
        await loadDetails()
        if let profileId = stored.profileId {
            profileID = profileId
        }
        if let folder = stored.rootFolder, !folder.isEmpty {
            rootFolder = folder
        }
        if let languageID = stored.languageProfileId {
            languageProfileID = languageID
        }
        if let numbers = stored.seasons?.map(\.seasonNumber), !numbers.isEmpty {
            selectedSeasonNumbers = Set(numbers).subtracting(occupiedSeasonNumbers)
        }
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
            // Ombi starts on its own defaults; an admin picks something else only to override them.
            guard !usesServiceDefaults else { return }
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
            languageProfileID: languageProfileID,
            rootFolderID: selectedRootFolderID
        )
        do {
            try await client.request(draft)
            onRequested()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Ombi names the folder by ID.
    private var selectedRootFolderID: Int? {
        details?.rootFolders.first { $0.path == rootFolder }?.folderID
    }

    private func decide(approve: Bool) async {
        guard let client, let requestID = current.requestID else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            if approve {
                let draft = SeerrRequestDraft(
                    kind: title.kind,
                    tmdbID: title.tmdbID,
                    seasons: title.kind == .tv ? .numbers(selectedSeasonNumbers.subtracting(occupiedSeasonNumbers).sorted()) : nil,
                    is4k: is4k,
                    serverID: serverID,
                    profileID: profileID,
                    rootFolder: rootFolder,
                    languageProfileID: languageProfileID,
                    rootFolderID: selectedRootFolderID,
                    parentRequestID: current.parentRequestID
                )
                var approved = draft
                if usesServiceDefaults, !isEditingRequest {
                    approved.profileID = nil
                    approved.rootFolderID = nil
                    approved.languageProfileID = nil
                }
                try await client.approveRequest(id: requestID, draft: approved)
            } else {
                try await client.declineRequest(id: requestID, kind: title.kind)
            }
            onRequested()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
