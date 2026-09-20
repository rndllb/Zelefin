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
            if !session.usesSilo {
                jellyfinPluginSections
                openSubtitlesSection
            }
            if session.usesSilo {
                siloRequestSection
            } else {
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
            HStack {
                Text("Skip Intro / Outro")
                Spacer()
                Text(session.introSkipperAvailable ? "Installed" : "Not on this server")
                    .foregroundStyle(session.introSkipperAvailable ? .green : .secondary)
            }
            Toggle("Automatically Skip Intros", isOn: $autoSkipIntro)
                .tint(AccentPreferences.current)
            Toggle("Automatically Skip Credits", isOn: $autoSkipCredits)
                .tint(AccentPreferences.current)
        } header: {
            Text("Intro Skipper")
        } footer: {
            Text("Skip buttons appear during playback when the plugin is installed on this Jellyfin server.")
        }

        Section {
            HStack {
                Text("Jellyfin Enhanced")
                Spacer()
                Text(session.jellyfinEnhancedAvailable ? "Installed" : "Not on this server")
                    .foregroundStyle(session.jellyfinEnhancedAvailable ? .green : .secondary)
            }
        } header: {
            Text("Jellyfin Enhanced")
        } footer: {
            Text("When this plugin is installed, you can remove titles from Continue Watching or Next Up without losing progress, and write reviews or see awards on the title page.")
        }

        Section {
            HStack {
                Text("Zelefin")
                Spacer()
                Text(session.companionAvailable ? "Installed" : "Not on this server")
                    .foregroundStyle(session.companionAvailable ? .green : .secondary)
            }
        } header: {
            Text("Notifications plugin")
        } footer: {
            if session.companionAvailable {
                Text("This server can push lock-screen alerts while Zelefin is closed. Allow notifications on this iPhone after sign-in.")
            } else {
                Text("Install the Zelefin plugin on Jellyfin if you want new titles and streams while the app is closed. Without it, this iPhone only checks when you open Zelefin.")
            }
        }
    }

    private var openSubtitlesSection: some View {
        Section {
            HStack {
                Text("Open Subtitles")
                Spacer()
                Text(openSubtitlesStatus)
                    .foregroundStyle(session.openSubtitlesAvailable ? .green : .secondary)
            }
        } header: {
            Text("Open Subtitles")
        } footer: {
            Text("When this plugin is installed, use More on a movie or episode to search Open Subtitles and save a file to the server.")
        }
    }

    private var siloRequestSection: some View {
        Section {
            HStack {
                Text("Seerr")
                Spacer()
                Text(session.siloSeerrPluginAvailable ? "Installed" : "Not on this server")
                    .foregroundStyle(session.siloSeerrPluginAvailable ? .green : .secondary)
            }
            HStack {
                Text("Sonarr & Radarr")
                Spacer()
                Text(session.siloArrPluginAvailable ? "Installed" : "Not on this server")
                    .foregroundStyle(session.siloArrPluginAvailable ? .green : .secondary)
            }
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
                LabeledContent("Server") {
                    Text(seerrURL)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                LabeledContent("Signed in as") {
                    Text(seerrDisplayName ?? "")
                        .foregroundStyle(.secondary)
                }
                Button("Sign Out", role: .destructive) {
                    signOutSeerr()
                }
            } else {
                TextField("https://seerr.example.com", text: $seerrURL)
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
                Button {
                    Task { await signInToSeerr() }
                } label: {
                    if isSigningInToSeerr {
                        ProgressView()
                    } else {
                        Text("Sign In")
                    }
                }
                .disabled(!canSignInToSeerr || isSigningInToSeerr)
            }
            if let seerrStatus {
                Text(seerrStatus)
                    .foregroundStyle(seerrStatus.contains("Signed in") ? .green : .red)
            }
        } header: {
            Text("Seerr")
        } footer: {
            Text("Jellyseerr or Seerr lets you request movies and shows that are not on Jellyfin yet. Use your Jellyfin username and password. Search for a title, then tap Request.")
        }
    }

    private var openSubtitlesStatus: String {
        session.openSubtitlesAvailable ? "Installed" : "Not on this server"
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
