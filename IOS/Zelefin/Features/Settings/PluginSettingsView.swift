import SwiftUI

struct PluginSettingsView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(PlaybackPreferences.autoSkipRecapKey) private var autoSkipRecap = false
    @AppStorage(PlaybackPreferences.autoSkipIntroKey) private var autoSkipIntro = false
    @AppStorage(PlaybackPreferences.autoSkipCreditsKey) private var autoSkipCredits = false
    @AppStorage(PlaybackPreferences.autoSkipPreviewKey) private var autoSkipPreview = false
    @AppStorage(PlaybackPreferences.theIntroDBKey) private var usesTheIntroDB = true
    @AppStorage(PluginSettings.seerrURLKey) private var seerrURL = ""
    @State private var seerrUsername = ""
    @State private var seerrPassword = ""
    @State private var seerrDisplayName = PluginSettings.seerrSession?.displayName
    @State private var seerrStatus: String?
    @State private var isSigningInToSeerr = false

    private var isSeerrSignedIn: Bool { seerrDisplayName != nil }

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
            skipPluginRow("Intro Skipper", session.introSkipperPresence, other: ("TheIntroDB", session.theIntroDBPresence))
            skipPluginRow("TheIntroDB", session.theIntroDBPresence, other: ("Intro Skipper", session.introSkipperPresence))
            skipToggles
        } header: {
            Text("Skip Recaps, Intros, Credits and Previews")
        } footer: {
            Text("Skip buttons come from Jellyfin's media segments, which Intro Skipper and the TheIntroDB plugin fill in once the Media Segment Scan task has run. For titles with none, Zelefin can ask TheIntroDB directly. Plugins only show as installed to an administrator.")
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
            if session.isEmbyServer {
                Text("When this Emby plugin is installed and signed in to an Open Subtitles account, use More on a movie or episode to search for subtitles and save a file to the server.")
            } else {
                Text("When this plugin is installed, use More on a movie or episode to search Open Subtitles and save a file to the server.")
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
            Text("TubeArchivist")
        } footer: {
            if rooms.isEmpty {
                Text("When this plugin fills a Shows library, Zelefin lists it as its own YouTube library, with channels and videos kept apart from your movies and shows.")
            } else {
                Text("\(rooms.map(\.name).joined(separator: ", ")) appears as its own YouTube library, with channels and videos kept apart from your movies and shows.")
            }
        }
    }

    /// Silo has no Jellyfin plugins, but it finds intros and credits itself and serves them as media segments.
    private var siloSkipSection: some View {
        Section {
            skipToggles
        } header: {
            Text("Skip Recaps, Intros, Credits and Previews")
        } footer: {
            Text("Skip buttons appear when Silo has found a recap, intro, credits or preview, including from its built-in TheIntroDB support. For titles with none, Zelefin can ask TheIntroDB directly.")
        }
        .zelefinRowBackground()
    }

    private var embySkipSection: some View {
        Section {
            skipToggles
        } header: {
            Text("Skip Recaps, Intros, Credits and Previews")
        } footer: {
            Text("Skip buttons appear when Emby has marked an intro or credits, or the file has chapters named Intro or Credits. Emby has no TheIntroDB plugin, so for everything else Zelefin can ask TheIntroDB directly.")
        }
        .zelefinRowBackground()
    }

    @ViewBuilder
    private var skipToggles: some View {
        Toggle("Automatically Skip Recaps", isOn: $autoSkipRecap)
        Toggle("Automatically Skip Intros", isOn: $autoSkipIntro)
        Toggle("Automatically Skip Credits", isOn: $autoSkipCredits)
        Toggle("Automatically Skip Previews", isOn: $autoSkipPreview)
        Toggle("Look Up Skip Times on TheIntroDB", isOn: $usesTheIntroDB)
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
