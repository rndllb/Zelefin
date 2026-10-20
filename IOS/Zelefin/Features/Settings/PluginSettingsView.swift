import SwiftUI

struct PluginSettingsView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(PlaybackPreferences.autoSkipIntroKey) private var autoSkipIntro = false
    @AppStorage(PlaybackPreferences.autoSkipCreditsKey) private var autoSkipCredits = false
    @AppStorage(PluginSettings.seerrURLKey) private var seerrURL = ""
    @AppStorage(PluginSettings.siloRequestSourceKey) private var siloRequestSourceRaw = SiloRequestSource.seerr.rawValue
    @State private var seerrUsername = ""
    @State private var seerrPassword = ""
    @State private var seerrDisplayName = PluginSettings.seerrSession?.displayName
    @State private var seerrStatus: String?
    @State private var isSigningInToSeerr = false

    private var isSeerrSignedIn: Bool { seerrDisplayName != nil }
    private var siloRequestSource: Binding<SiloRequestSource> {
        Binding(
            get: { SiloRequestSource(rawValue: siloRequestSourceRaw) ?? .seerr },
            set: { siloRequestSourceRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            if session.usesSilo {
                siloRequestSection
            } else {
                jellyfinPluginSections
                openSubtitlesSection
                tubeArchivistSection
                seerrSignInSection
            }
        }
        .zelefinSettingsChrome(title: "Plugins")
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
            pluginStatusRow("Skip Intro / Outro", installed: session.introSkipperAvailable)
            Toggle("Automatically Skip Intros", isOn: $autoSkipIntro)
            Toggle("Automatically Skip Credits", isOn: $autoSkipCredits)
        } header: {
            Text("Intro Skipper")
        } footer: {
            Text("Skip buttons appear during playback when the plugin is installed on this Jellyfin server.")
        }
        .zelefinRowBackground()

        Section {
            pluginStatusRow("Jellyfin Enhanced", installed: session.jellyfinEnhancedAvailable)
        } header: {
            Text("Jellyfin Enhanced")
        } footer: {
            Text("When this plugin is installed, you can remove titles from Continue Watching or Next Up without losing progress, and write reviews or see awards on the title page.")
        }
        .zelefinRowBackground()

        Section {
            pluginStatusRow("Zelefin", installed: session.companionAvailable)
        } header: {
            Text("Notifications plugin")
        } footer: {
            if session.companionAvailable {
                Text("This server can push lock-screen alerts while Zelefin is open or closed. Restart Jellyfin after you install or remove the plugin.")
            } else {
                Text("Notifications need this plugin. Open Settings → Notifications to install it on this server, or add the Zelefin catalog in Jellyfin. Restart Jellyfin after install.")
            }
        }
        .zelefinRowBackground()
    }

    private var openSubtitlesSection: some View {
        Section {
            pluginStatusRow("Open Subtitles", installed: session.openSubtitlesAvailable)
        } header: {
            Text("Open Subtitles")
        } footer: {
            Text("When this plugin is installed, use More on a movie or episode to search Open Subtitles and save a file to the server.")
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
            Text("TubeArchivist")
        } footer: {
            if rooms.isEmpty {
                Text("When this plugin fills a Shows library, Zelefin lists it as its own YouTube library, with channels and videos kept apart from your movies and shows.")
            } else {
                Text("\(rooms.map(\.name).joined(separator: ", ")) appears as its own YouTube library, with channels and videos kept apart from your movies and shows.")
            }
        }
    }

    private var siloRequestSection: some View {
        Section {
            pluginStatusRow("Seerr", installed: session.siloSeerrPluginAvailable)
            pluginStatusRow("Sonarr & Radarr", installed: session.siloArrPluginAvailable)
            if session.siloSeerrPluginAvailable && session.siloArrPluginAvailable {
                Picker("Discover with", selection: siloRequestSource) {
                    ForEach(SiloRequestSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
            }
        } header: {
            Text("Requests")
        } footer: {
            Text(siloRequestFooter)
        }
        .zelefinRowBackground()
    }

    private var siloRequestFooter: String {
        if session.siloSeerrPluginAvailable && session.siloArrPluginAvailable {
            return "Discover uses the plugin you pick. Sign-in to Seerr is not needed on Silo."
        }
        if session.siloArrPluginAvailable {
            return "Discover uses this Silo server’s Sonarr and Radarr requests plugin."
        }
        if session.siloSeerrPluginAvailable {
            return "Discover uses this Silo server’s Seerr plugin. You do not sign in to Seerr separately."
        }
        if session.siloRequestsEnabled {
            return "Requests are on for this Silo server. Discover is in Search."
        }
        return "Install the Seerr plugin or the Sonarr & Radarr requests plugin on this Silo server to request titles from Search."
    }

    @ViewBuilder
    private var seerrSignInSection: some View {
        Section {
            if isSeerrSignedIn {
                LabeledContent("Server", value: seerrURL)
                LabeledContent("Signed in as", value: seerrDisplayName ?? "")
                Button("Sign Out", role: .destructive, action: signOutSeerr)
            } else {
                TextField("Server", text: $seerrURL)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Username or email", text: $seerrUsername)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $seerrPassword)
                    .textContentType(.password)
                Button("Sign In") {
                    Task { await signInToSeerr() }
                }
                .disabled(!canSignInToSeerr || isSigningInToSeerr)
            }
            if let seerrStatus {
                SettingsStatusText(text: seerrStatus, isError: !seerrStatus.contains("Signed in"))
            }
        } header: {
            Text("Seerr")
        } footer: {
            Text("Jellyseerr or Seerr lets you request movies and shows that are not on Jellyfin yet. Use your Jellyfin username and password. Search for a title, then tap Request.")
        }
        .zelefinRowBackground()
    }

    private func pluginStatusRow(_ title: String, installed: Bool) -> some View {
        LabeledContent(title) {
            Text(installed ? "Installed" : "Not on this server")
                .foregroundStyle(installed ? Color.green : Color.red)
        }
        .accessibilityLabel("\(title), \(installed ? "Installed" : "Not on this server")")
    }

    private var canSignInToSeerr: Bool {
        !seerrURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !seerrUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !seerrPassword.isEmpty
    }

    private func signInToSeerr() async {
        PluginSettings.seerrURLString = seerrURL
        guard let url = PluginSettings.seerrURL else {
            seerrStatus = "Enter a valid Seerr URL."
            return
        }
        isSigningInToSeerr = true
        seerrStatus = nil
        defer { isSigningInToSeerr = false }
        do {
            let signedIn = try await SeerrClient.signIn(
                baseURL: url,
                username: seerrUsername,
                password: seerrPassword
            )
            PluginSettings.rememberSignIn(
                signedIn,
                username: seerrUsername,
                password: seerrPassword,
                ownerAccountID: session.session?.accountID
            )
            seerrDisplayName = signedIn.displayName
            seerrPassword = ""
            seerrStatus = "Signed in as \(signedIn.displayName)."
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
        guard !session.usesSilo else { return }
        guard PluginSettings.seerrClient != nil else {
            seerrDisplayName = nil
            return
        }
        if let user = await PluginSettings.refreshUser() {
            seerrDisplayName = user.displayLabel
            seerrStatus = nil
            return
        }
        if let saved = PluginSettings.seerrSession {
            seerrDisplayName = saved.displayName
            return
        }
        seerrDisplayName = nil
        seerrStatus = "Seerr session expired. Sign in again."
    }
}
