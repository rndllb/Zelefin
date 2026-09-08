import SwiftUI

struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(HomeLayoutPreferences.mergeContinueAndNextUpKey) private var mergeContinueAndNextUp = false

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
                NavigationLink {
                    PluginSettingsView()
                } label: {
                    Label("Plugins", systemImage: "puzzlepiece.extension")
                }
            } footer: {
                Text("Intro Skipper and Seerr.")
            }

            Section {
                NavigationLink {
                    NetworkSettingsView()
                } label: {
                    Label("Network", systemImage: "network")
                }
            } footer: {
                Text("Local and remote addresses, and access gateway tokens.")
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
                Text("Hide or reorder Home, Movies, Shows, Collections, and Library. Search stays in the tab bar.")
            }
            #endif
        }
        .zelefinSettingsChrome(title: "Settings")
        .onChange(of: mergeContinueAndNextUp) {
            Task { await session.refreshHome() }
        }
    }

    private var footerCopy: String {
        if mergeContinueAndNextUp {
            "In-progress titles and the next episode after you finish one appear in a single Continue Watching row. Each title is still labeled CONTINUE or NEXT."
        } else {
            "Keep in-progress titles in Continue Watching and the next episode after you finish one in Next Up."
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
