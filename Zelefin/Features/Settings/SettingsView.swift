import SwiftUI

struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(HomeLayoutPreferences.mergeContinueAndNextUpKey) private var mergeContinueAndNextUp = false
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
                NavigationLink {
                    PlaybackSettingsView()
                } label: {
                    Label("Playback and Controls", systemImage: "play.rectangle.on.rectangle")
                }
            } footer: {
                Text("Skip intervals, quality, autoplay, and the video player.")
            }

            Section {
                Toggle("Combine Continue Watching and Next Up", isOn: $mergeContinueAndNextUp)
            } footer: {
                Text(footerCopy)
            }

            #if os(iOS)
            Section {
                NavigationLink {
                    TabCustomizationView()
                } label: {
                    Label("Tabs", systemImage: "rectangle.stack")
                }
            } footer: {
                Text("Hide or reorder Home, Movies, Shows, and Library. Search stays in the tab bar.")
            }
            #endif

            AccessGatewaySection()

            Section {
                ForEach(OpenSourceNotice.works) { work in
                    NavigationLink(work.name) {
                        ScrollView {
                            Text(OpenSourceNotice.text(for: work))
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .background(Color.black)
                        .navigationTitle(work.name)
                    }
                }
            } header: {
                Text("Open Source")
            } footer: {
                Text(OpenSourceNotice.summary)
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
                        .foregroundStyle(.white)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                    TextField("Username or email", text: $seerrUsername)
                        .textContentType(.username)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
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
        .zelefinSettingsChrome(title: "Settings")
        .onChange(of: mergeContinueAndNextUp) {
            Task { await session.refreshHome() }
        }
        .task {
            if seerrUsername.isEmpty {
                seerrUsername = session.session?.userName ?? ""
            }
            await refreshSeerrSession()
        }
    }

    private var canSignInToSeerr: Bool {
        !seerrURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !seerrUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !seerrPassword.isEmpty
    }

    private var footerCopy: String {
        if mergeContinueAndNextUp {
            "In-progress titles and the next episode after you finish one appear in a single Continue Watching row. Each title is still labeled CONTINUE or NEXT."
        } else {
            "Keep in-progress titles in Continue Watching and the next episode after you finish one in Next Up."
        }
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

extension View {
    func zelefinSettingsChrome(title: String) -> some View {
        self
            #if os(iOS)
            .scrollContentBackground(.hidden)
            #endif
            .background(Color.black)
            .preferredColorScheme(.dark)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
    }
}
