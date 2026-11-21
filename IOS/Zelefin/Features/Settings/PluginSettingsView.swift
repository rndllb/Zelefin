import SwiftUI

struct PluginSettingsView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(PlaybackPreferences.autoSkipRecapKey) private var autoSkipRecap = false
    @AppStorage(PlaybackPreferences.autoSkipIntroKey) private var autoSkipIntro = false
    @AppStorage(PlaybackPreferences.autoSkipCreditsKey) private var autoSkipCredits = false
    @AppStorage(PlaybackPreferences.autoSkipPreviewKey) private var autoSkipPreview = false
    @AppStorage(PlaybackPreferences.theIntroDBKey) private var usesTheIntroDB = true
    @AppStorage(PluginSettings.seerrURLKey) private var seerrURL = ""
    @AppStorage(PluginSettings.requestServiceKey) private var requestServiceRaw = RequestService.seerr.rawValue
    @State private var seerrUsername = ""
    @State private var seerrPassword = ""
    @State private var seerrDisplayName = PluginSettings.requestDisplayName
    @State private var seerrStatus: String?
    @State private var isSigningInToSeerr = false
    @State private var tmdbKey = PluginSettings.tmdbAPIKey ?? ""
    @State private var savedTMDBKey = PluginSettings.tmdbAPIKey ?? ""
    @State private var tmdbStatus: String?
    @State private var isCheckingTMDBKey = false

    private var isSeerrSignedIn: Bool { seerrDisplayName != nil }

    private var requestService: RequestService {
        RequestService(rawValue: requestServiceRaw) ?? .seerr
    }

    var body: some View {
        Form {
            if session.isSiloServer {
                siloSkipSection
            } else if session.isEmbyServer {
                embySkipSection
                openSubtitlesSection
            } else {
                jellyfinPluginSections
                openSubtitlesSection
                tubeArchivistSection
            }
            seerrSignInSection
            tmdbSection
        }
        .zelefinSettingsChrome(title: AppLanguage.string("settings.plugins", default: "Plugins"))
        .task {
            if seerrUsername.isEmpty {
                seerrUsername = session.session?.userName ?? ""
            }
            await session.detectIntroSkipper()
            await refreshSeerrSession()
        }
    }

    @ViewBuilder
    private var jellyfinPluginSections: some View {
        Section {
            skipPluginRow("Intro Skipper", session.introSkipperPresence, other: ("TheIntroDB", session.theIntroDBPresence))
            skipPluginRow("TheIntroDB", session.theIntroDBPresence, other: ("Intro Skipper", session.introSkipperPresence))
            skipToggles
        } header: {
            Text(AppLanguage.string("Skip Recaps, Intros, Credits and Previews", default: "Skip Recaps, Intros, Credits and Previews"))
        } footer: {
            Text(AppLanguage.string("Skip buttons come from Jellyfin's media segments, which Intro Skipper and the TheIntroDB plugin fill in once the Media Segment Scan task has run. For titles with none, Zelefin can ask TheIntroDB directly.", default: "Skip buttons come from Jellyfin's media segments, which Intro Skipper and the TheIntroDB plugin fill in once the Media Segment Scan task has run. For titles with none, Zelefin can ask TheIntroDB directly."))
        }
        .zelefinRowBackground()

        Section {
            pluginStatusRow("Jellyfin Enhanced", installed: session.jellyfinEnhancedAvailable)
        } header: {
            Text(AppLanguage.string("Jellyfin Enhanced", default: "Jellyfin Enhanced"))
        } footer: {
            Text(AppLanguage.string("When this plugin is installed, you can remove titles from Continue Watching or Next Up without losing progress, and write reviews or see awards on the title page.", default: "When this plugin is installed, you can remove titles from Continue Watching or Next Up without losing progress, and write reviews or see awards on the title page."))
        }
        .zelefinRowBackground()

        Section {
            pluginStatusRow("Zelefin", installed: session.companionAvailable)
        } header: {
            Text(AppLanguage.string("Notifications plugin", default: "Notifications plugin"))
        } footer: {
            if session.companionAvailable {
                Text(AppLanguage.string("This server can push lock-screen alerts while Zelefin is open or closed. Restart Jellyfin after you install or remove the plugin.", default: "This server can push lock-screen alerts while Zelefin is open or closed. Restart Jellyfin after you install or remove the plugin."))
            } else {
                Text(AppLanguage.string("Notifications need this plugin. Open Settings → Notifications to install it on this server, or add the Zelefin catalog in Jellyfin. Restart Jellyfin after install.", default: "Notifications need this plugin. Open Settings → Notifications to install it on this server, or add the Zelefin catalog in Jellyfin. Restart Jellyfin after install."))
            }
        }
        .zelefinRowBackground()
    }

    private var openSubtitlesSection: some View {
        Section {
            pluginStatusRow("Open Subtitles", installed: session.openSubtitlesAvailable)
        } header: {
            Text(AppLanguage.string("Open Subtitles", default: "Open Subtitles"))
        } footer: {
            if session.isEmbyServer {
                Text(AppLanguage.string("When this Emby plugin is installed and signed in to an Open Subtitles account, use More on a movie or episode to search for subtitles and save a file to the server.", default: "When this Emby plugin is installed and signed in to an Open Subtitles account, use More on a movie or episode to search for subtitles and save a file to the server."))
            } else {
                Text(AppLanguage.string("When this plugin is installed, use More on a movie or episode to search Open Subtitles and save a file to the server.", default: "When this plugin is installed, use More on a movie or episode to search Open Subtitles and save a file to the server."))
            }
        }
        .zelefinRowBackground()
    }

    private var youTubeLibraries: [MediaLibrary] {
        session.libraries.filter { $0.libraryKind == .youTube }
    }

    private var tubeArchivistSection: some View {
        let rooms = youTubeLibraries
        let installed = !rooms.isEmpty || session.libraries.contains {
            $0.name.localizedCaseInsensitiveContains("TubeArchivist")
        }
        return Section {
            pluginStatusRow("TubeArchivist Metadata", installed: installed)
        } header: {
            Text(AppLanguage.string("TubeArchivist", default: "TubeArchivist"))
        } footer: {
            if rooms.isEmpty {
                Text(AppLanguage.string("When this plugin fills a Shows library, Zelefin lists it as its own YouTube library, with channels and videos kept apart from your movies and shows.", default: "When this plugin fills a Shows library, Zelefin lists it as its own YouTube library, with channels and videos kept apart from your movies and shows."))
            } else {
                Text("\(rooms.map(\.name).joined(separator: ", ")) appears as its own YouTube library, with channels and videos kept apart from your movies and shows.")
            }
        }
        .zelefinRowBackground()
    }

    /// Silo has no Jellyfin plugins, but it finds intros and credits itself and serves them as media segments.
    private var siloSkipSection: some View {
        Section {
            skipToggles
        } header: {
            Text(AppLanguage.string("Skip Recaps, Intros, Credits and Previews", default: "Skip Recaps, Intros, Credits and Previews"))
        } footer: {
            Text(AppLanguage.string("Skip buttons appear when Silo has found a recap, intro, credits or preview, including from its built-in TheIntroDB support. For titles with none, Zelefin can ask TheIntroDB directly.", default: "Skip buttons appear when Silo has found a recap, intro, credits or preview, including from its built-in TheIntroDB support. For titles with none, Zelefin can ask TheIntroDB directly."))
        }
        .zelefinRowBackground()
    }

    private var embySkipSection: some View {
        Section {
            skipToggles
        } header: {
            Text(AppLanguage.string("Skip Recaps, Intros, Credits and Previews", default: "Skip Recaps, Intros, Credits and Previews"))
        } footer: {
            Text(AppLanguage.string("Skip buttons appear when Emby has marked an intro or credits, or the file has chapters named Intro or Credits. Emby has no TheIntroDB plugin, so for everything else Zelefin can ask TheIntroDB directly.", default: "Skip buttons appear when Emby has marked an intro or credits, or the file has chapters named Intro or Credits. Emby has no TheIntroDB plugin, so for everything else Zelefin can ask TheIntroDB directly."))
        }
        .zelefinRowBackground()
    }

    @ViewBuilder
    private var skipToggles: some View {
        Toggle(AppLanguage.string("ui.automatically_skip_recaps", default: "Automatically Skip Recaps"), isOn: $autoSkipRecap)
        Toggle(AppLanguage.string("ui.automatically_skip_intros", default: "Automatically Skip Intros"), isOn: $autoSkipIntro)
        Toggle(AppLanguage.string("ui.automatically_skip_credits", default: "Automatically Skip Credits"), isOn: $autoSkipCredits)
        Toggle(AppLanguage.string("ui.automatically_skip_previews", default: "Automatically Skip Previews"), isOn: $autoSkipPreview)
        Toggle(AppLanguage.string("ui.look_up_skip_times_on_theintrodb", default: "Look Up Skip Times on TheIntroDB"), isOn: $usesTheIntroDB)
    }

    @ViewBuilder
    private var seerrSignInSection: some View {
        Section {
            if isSeerrSignedIn {
                LabeledContent("Service", value: requestService.name)
                LabeledContent("Server", value: seerrURL)
                LabeledContent(AppLanguage.string("ui.signed_in_as", default: "Signed in as"), value: seerrDisplayName ?? "")
                Button(AppLanguage.string("common.sign_out", default: "Sign Out"), role: .destructive, action: signOutSeerr)
            } else {
                Picker(AppLanguage.string("connect.service", default: "Service"), selection: $requestServiceRaw) {
                    ForEach(RequestService.allCases) { service in
                        Text(service.name).tag(service.rawValue)
                    }
                }
                TextField(AppLanguage.string("settings.server", default: "Server"), text: $seerrURL)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField(AppLanguage.string("connect.username_or_email", default: "Username or email"), text: $seerrUsername)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(AppLanguage.string("connect.password", default: "Password"), text: $seerrPassword)
                    .textContentType(.password)
                Button(AppLanguage.string("connect.sign_in", default: "Sign In")) {
                    Task { await signInToSeerr() }
                }
                .disabled(!canSignInToSeerr || isSigningInToSeerr)
            }
            if let seerrStatus {
                SettingsStatusText(text: seerrStatus, isError: !seerrStatus.contains(AppLanguage.string("ui.signed_in", default: "Signed in")))
            }
        } header: {
            Text(AppLanguage.string("ui.requests", default: "Requests"))
        } footer: {
            Text(requestFooter)
        }
        .zelefinRowBackground()
    }

    private var tmdbSection: some View {
        Section {
            SecureField(AppLanguage.string("ui.api_key_or_read_access_token", default: "API Key or Read Access Token"), text: $tmdbKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { Task { await saveTMDBKey() } }
            Button(tmdbKey.isEmpty && !savedTMDBKey.isEmpty ? "Remove Key" : "Save Key") {
                Task { await saveTMDBKey() }
            }
            .disabled(isCheckingTMDBKey || tmdbKey.trimmingCharacters(in: .whitespacesAndNewlines) == savedTMDBKey)
            if let tmdbStatus {
                SettingsStatusText(text: tmdbStatus, isError: !tmdbStatus.hasPrefix("Saved") && !tmdbStatus.hasPrefix("Removed"))
            }
        } header: {
            Text(AppLanguage.string("TMDB", default: "TMDB"))
        } footer: {
            Text(AppLanguage.string("Discover title pages show a title's logo when it's in your library. With a free TMDB key, from Settings → API on themoviedb.org, every other title shows its logo too.", default: "Discover title pages show a title's logo when it's in your library. With a free TMDB key, from Settings → API on themoviedb.org, every other title shows its logo too."))
        }
        .zelefinRowBackground()
    }

    private func saveTMDBKey() async {
        let key = tmdbKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            PluginSettings.tmdbAPIKey = nil
            savedTMDBKey = ""
            tmdbStatus = "Removed the TMDB key."
            return
        }
        isCheckingTMDBKey = true
        defer { isCheckingTMDBKey = false }
        guard await TMDBLogos.accepts(key) else {
            tmdbStatus = "TMDB didn't accept that key."
            return
        }
        PluginSettings.tmdbAPIKey = key
        savedTMDBKey = key
        tmdbKey = key
        tmdbStatus = "Saved. Discover titles show their logos."
    }

    private func skipPluginRow(
        _ title: String,
        _ presence: PluginPresence,
        other: (name: String, presence: PluginPresence)
    ) -> some View {
        let greyed = SkipPluginChoice.isGreyedOut(presence, other: other.presence)
        return VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                Text(presence.label)
                    .foregroundStyle(greyed ? Color.secondary : presenceColor(presence))
            }
            if greyed {
                Text("Only one skip plugin can be enabled at a time. \(other.name) is enabled.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(greyed ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }

    private func presenceColor(_ presence: PluginPresence) -> Color {
        switch presence {
        case .enabled: .green
        case .disabled: .orange
        case .notInstalled: .red
        }
    }

    private func pluginStatusRow(_ title: String, installed: Bool) -> some View {
        LabeledContent(title) {
            Text(installed ? "Installed" : AppLanguage.string("ui.not_on_this_server", default: "Not on this server"))
                .foregroundStyle(installed ? Color.green : Color.red)
        }
        .accessibilityLabel("\(title), \(installed ? "Installed" : "Not on this server")")
    }

    private var requestFooter: String {
        switch requestService {
        case .seerr:
            "Jellyseerr or Seerr lets you request movies and shows that are not on Jellyfin yet. Use your Jellyfin username and password. Search for a title, then tap Request."
        case .ombi:
            "Ombi lets you request movies and shows that are not on the server yet. Use your Ombi username and password, or your Jellyfin or Emby ones if Ombi imported your account. Search for a title, then tap Request."
        }
    }

    private var canSignInToSeerr: Bool {
        !seerrURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !seerrUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !seerrPassword.isEmpty
    }

    private func signInToSeerr() async {
        PluginSettings.seerrURLString = seerrURL
        guard PluginSettings.seerrURL != nil else {
            seerrStatus = "Enter a valid \(requestService.name) URL."
            return
        }
        isSigningInToSeerr = true
        seerrStatus = nil
        defer { isSigningInToSeerr = false }
        do {
            let name = try await PluginSettings.signIn(
                username: seerrUsername,
                password: seerrPassword,
                ownerAccountID: session.session?.accountID
            )
            seerrDisplayName = name
            seerrPassword = ""
            seerrStatus = "Signed in as \(name)."
        } catch {
            seerrStatus = error.localizedDescription
        }
    }

    private func signOutSeerr() {
        PluginSettings.clearSeerrSession()
        seerrDisplayName = nil
        seerrPassword = ""
        seerrStatus = nil
    }

    private func refreshSeerrSession() async {
        guard PluginSettings.seerrClient != nil else {
            seerrDisplayName = nil
            return
        }
        if let user = await PluginSettings.refreshUser() {
            seerrDisplayName = user.displayLabel
            seerrStatus = nil
            return
        }
        if let name = PluginSettings.requestDisplayName {
            seerrDisplayName = name
            return
        }
        seerrDisplayName = nil
        seerrStatus = "\(requestService.name) session expired. Sign in again."
    }
}
