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
            VStack(alignment: .leading, spacing: 0) {
                pluginStatusRow("Skip Intro / Outro", installed: session.introSkipperAvailable)
                SettingsCardDivider()
                Toggle("Automatically Skip Intros", isOn: $autoSkipIntro)
                    .tint(AccentPreferences.current)
                    .font(.body.weight(.semibold))
                SettingsCardDivider()
                Toggle("Automatically Skip Credits", isOn: $autoSkipCredits)
                    .tint(AccentPreferences.current)
                    .font(.body.weight(.semibold))
            }
            .settingsLoginCard()
            .settingsCardRow()
        } header: {
            Text("Intro Skipper")
        } footer: {
            Text("Skip buttons appear during playback when the plugin is installed on this Jellyfin server.")
        }

        Section {
            pluginStatusRow("Jellyfin Enhanced", installed: session.jellyfinEnhancedAvailable)
                .settingsLoginCard()
                .settingsCardRow()
        } header: {
            Text("Jellyfin Enhanced")
        } footer: {
            Text("When this plugin is installed, you can remove titles from Continue Watching or Next Up without losing progress, and write reviews or see awards on the title page.")
        }

        Section {
            pluginStatusRow("Zelefin", installed: session.companionAvailable)
                .settingsLoginCard()
                .settingsCardRow()
        } header: {
            Text("Notifications plugin")
        } footer: {
            if session.companionAvailable {
                Text("This server can push lock-screen alerts while Zelefin is closed. This iPhone also checks the library itself, so banners can still appear without the plugin when the app is open or after a background refresh. Restart Jellyfin after you install or remove the plugin.")
            } else {
                Text("Notifications still work from this iPhone. Zelefin checks Jellyfin while the app is open and when iOS allows a background refresh. The plugin is only for push while the app stays fully closed. After you uninstall it, restart Jellyfin so the server stops sending those pushes.")
            }
        }
    }

    private var openSubtitlesSection: some View {
        Section {
            pluginStatusRow("Open Subtitles", installed: session.openSubtitlesAvailable)
                .settingsLoginCard()
                .settingsCardRow()
        } header: {
            Text("Open Subtitles")
        } footer: {
            Text("When this plugin is installed, use More on a movie or episode to search Open Subtitles and save a file to the server.")
        }
    }

    private var siloRequestSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                pluginStatusRow("Seerr", installed: session.siloSeerrPluginAvailable)
                SettingsCardDivider()
                pluginStatusRow("Sonarr & Radarr", installed: session.siloArrPluginAvailable)
                if session.siloSeerrPluginAvailable && session.siloArrPluginAvailable {
                    SettingsCardDivider()
                    SettingsFieldLabel(title: "Discover with")
                        .padding(.bottom, 8)
                    Picker("Discover with", selection: siloRequestSource) {
                        ForEach(SiloRequestSource.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AccentPreferences.current)
                }
            }
            .settingsLoginCard()
            .settingsCardRow()
        } header: {
            Text("Requests")
        } footer: {
            Text(siloRequestFooter)
        }
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
            VStack(alignment: .leading, spacing: 0) {
                if isSeerrSignedIn {
                    SettingsInfoRow(label: "Server", value: seerrURL)
                    SettingsCardDivider()
                    SettingsInfoRow(label: "Signed in as", value: seerrDisplayName ?? "")
                    SettingsSecondaryButton(title: "Sign Out", role: .destructive) {
                        signOutSeerr()
                    }
                    .padding(.top, 16)
                } else {
                    SettingsLabeledField(label: "Server", systemImage: "link") {
                        TextField("https://seerr.example.com", text: $seerrURL)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    SettingsCardDivider()
                    SettingsLabeledField(label: "Username", systemImage: "person.fill") {
                        TextField("Username or email", text: $seerrUsername)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    SettingsCardDivider()
                    SettingsLabeledField(label: "Password", systemImage: "lock.fill") {
                        SecureField("Password", text: $seerrPassword)
                            .textContentType(.password)
                    }
                    SettingsPrimaryButton(
                        title: "Sign In",
                        isBusy: isSigningInToSeerr,
                        enabled: canSignInToSeerr
                    ) {
                        Task { await signInToSeerr() }
                    }
                    .padding(.top, 16)
                }
                if let seerrStatus {
                    SettingsStatusText(text: seerrStatus, isError: !seerrStatus.contains("Signed in"))
                        .padding(.top, 12)
                }
            }
            .settingsLoginCard()
            .settingsCardRow()
        } header: {
            Text("Seerr")
        } footer: {
            Text("Jellyseerr or Seerr lets you request movies and shows that are not on Jellyfin yet. Use your Jellyfin username and password. Search for a title, then tap Request.")
        }
    }

    private func pluginStatusRow(_ title: String, installed: Bool) -> some View {
        HStack {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(LoginPalette.primaryText)
            Spacer(minLength: 8)
            SettingsStatusValue(
                text: installed ? "Installed" : "Not on this server",
                isPositive: installed
            )
        }
        .accessibilityElement(children: .combine)
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
            PluginSettings.seerrSession = signedIn
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
        guard let client = PluginSettings.seerrClient else {
            seerrDisplayName = nil
            return
        }
        do {
            let user = try await client.currentUser()
            seerrDisplayName = user.displayLabel
            if var saved = PluginSettings.seerrSession {
                saved.displayName = user.displayLabel
                PluginSettings.seerrSession = saved
            }
        } catch {
            PluginSettings.clearSeerrSession()
            seerrDisplayName = nil
            seerrStatus = "Seerr session expired. Sign in again."
        }
    }
}
