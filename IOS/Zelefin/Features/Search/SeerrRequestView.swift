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
    @State private var canManageRequests = false
    @State private var isEditingRequest = false

    private var client: SeerrClient? { PluginSettings.seerrClient }

    private var isAwaitingApproval: Bool {
        title.review == .pendingApproval && title.requestID != nil
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
        !isLoading && servers.isEmpty && errorMessage == nil
    }

    private var canSubmit: Bool {
        guard !isSubmitting else { return false }
        if !requestsWithoutDownloader {
            guard serverID != nil, profileID != nil, !rootFolder.isEmpty else { return false }
        }
        if title.kind == .movie, title.availability == .available, !is4k {
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
                if title.availability == .available {
                    EmptyView()
                } else if isLoading {
                    ProgressView()
                        .tint(.white)
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
                    } else {
                        requestSummary
                    }
                    reviewActions
                } else {
                    destinationSection
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
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .navigationTitle(isAwaitingApproval ? "Review" : "Request")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
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
                if let requestedByName = title.requestedByName {
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

    private var requestSummary: some View {
        VStack(spacing: 0) {
            summaryRow("Server", value: selectedServerName)
            summaryRow("Quality", value: selectedProfileName)
            summaryRow("Drive", value: rootFolder.isEmpty ? "Default" : rootFolder)
            if title.kind == .tv {
                summaryRow("Seasons", value: seasonSummary)
            }
        }
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    private func decisionLabel(_ title: String, filled: Bool, destructive: Bool = false) -> some View {
        Text(title)
            .font(.body.weight(.semibold))
            .foregroundStyle(filled ? Color.black : (destructive ? Color.red : Color.white))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background {
                if filled {
                    Capsule(style: .continuous).fill(Color.white)
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
                Text(title.kind == .movie
                     ? "No Radarr server is set up in Seerr. The request is still saved for an admin to see, but nothing downloads."
                     : "No Sonarr server is set up in Seerr. The request is still saved for an admin to see, but nothing downloads.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                VStack(spacing: 0) {
                    if servers.contains(where: \.uses4K) {
                        Toggle("4K", isOn: $is4k)
                            .tint(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        divider
                    }
                    menuRow("Server", value: selectedServerName) {
                        ForEach(visibleServers) { server in
                            Button(server.name) { serverID = server.id }
                        }
                    }
                    if let details, !details.profiles.isEmpty {
                        divider
                        menuRow("Quality", value: selectedProfileName) {
                            ForEach(details.profiles) { profile in
                                Button(profile.name) { profileID = profile.id }
                            }
                        }
                    }
                    if let details, !details.rootFolders.isEmpty {
                        divider
                        menuRow("Drive", value: rootFolder.isEmpty ? "Default" : rootFolder) {
                            ForEach(details.rootFolders) { folder in
                                Button(folder.pickerTitle) { rootFolder = folder.path }
                            }
                        }
                    }
                    if let languages = details?.languageProfiles, !languages.isEmpty {
                        divider
                        menuRow("Language", value: languages.first { $0.id == languageProfileID }?.name ?? "Default") {
                            ForEach(languages) { profile in
                                Button(profile.name) { languageProfileID = profile.id }
                            }
                        }
                    }
                }
                .tint(.white)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    .foregroundStyle(.white)
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
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.white, in: Capsule(style: .continuous))
                .opacity(canSubmit ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    private func seasonToggle(_ season: SeerrSeason) -> some View {
        let occupied = occupiedSeasonNumbers.contains(season.seasonNumber)
        return Toggle(season.title, isOn: seasonBinding(season.seasonNumber))
            .tint(.white)
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
            if let user = try? await client.currentUser() {
                canManageRequests = user.canManageRequests
            }
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
            if let requestID = title.requestID, isAwaitingApproval {
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

    private func decide(approve: Bool) async {
        guard let client, let requestID = title.requestID else { return }
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
                    languageProfileID: languageProfileID
                )
                try await client.approveRequest(id: requestID, draft: draft)
            } else {
                try await client.declineRequest(id: requestID)
            }
            onRequested()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
