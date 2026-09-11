import SwiftUI

struct PluginSettingsView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(PlaybackPreferences.autoSkipIntroKey) private var autoSkipIntro = false
    @AppStorage(PlaybackPreferences.autoSkipCreditsKey) private var autoSkipCredits = false
    @AppStorage(PluginSettings.seerrURLKey) private var seerrURL = ""
    @State private var seerrUsername = ""
    @State private var seerrPassword = ""
    @State private var seerrDisplayName = PluginSettings.seerrSession?.displayName
    @State private var seerrStatus: String?
    @State private var isSigningInToSeerr = false

    private var isSeerrSignedIn: Bool { seerrDisplayName != nil }

    var body: some View {
        Form {
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
                    Text("Open Subtitles")
                    Spacer()
                    Text(session.openSubtitlesAvailable ? "Installed" : "Not on this server")
                        .foregroundStyle(session.openSubtitlesAvailable ? .green : .secondary)
                }
            } header: {
                Text("Open Subtitles")
            } footer: {
                Text("When this plugin is installed, use More on a movie or episode to search Open Subtitles and save a file to the server.")
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
        .zelefinSettingsChrome(title: "Plugins")
        .task {
            if seerrUsername.isEmpty {
                seerrUsername = session.session?.userName ?? ""
            }
            await session.detectIntroSkipper()
            await refreshSeerrSession()
        }
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
