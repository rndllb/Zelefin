import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        List {
            accountSection
            playbackSection
            deviceSection
            aboutSection
        }
        .zelefinSettingsChrome(title: "Settings")
        .task {
            await session.detectIntroSkipper()
            await session.refreshAdministratorStatus()
        }
    }

    private var accountSection: some View {
        Section {
            NavigationLink {
                ProfileView()
            } label: {
                HStack(spacing: 14) {
                    UserAvatarView(url: session.avatarURL, diameter: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(accountDisplayName)
                            .font(.body.weight(.semibold))
                        Text("Account info")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .accessibilityLabel("\(accountDisplayName), Account info")
            settingsRow("Sessions", systemImage: "play.tv") {
                SessionsView()
            }
            if session.isAdministrator {
                settingsRow("Users", systemImage: "person.2", subtitle: "Permissions, libraries, and parental controls") {
                    UserManagementView()
                }
            }
        }
    }

    private var playbackSection: some View {
        Section {
            settingsRow("Playback and Controls", systemImage: "play.rectangle.on.rectangle") {
                PlaybackSettingsView()
            }
            settingsRow("Plugins", systemImage: "puzzlepiece.extension", subtitle: pluginsSubtitle) {
                PluginSettingsView()
            }
        }
    }

    private var deviceSection: some View {
        Section {
            settingsRow("Network", systemImage: "network", subtitle: networkSubtitle) {
                NetworkSettingsView()
            }
            settingsRow("Cache", systemImage: "internaldrive", subtitle: cacheSubtitle) {
                CacheSettingsView()
            }
            settingsRow("Interface", systemImage: "rectangle.3.group") {
                TabCustomizationView()
            }
        }
    }

    private var aboutSection: some View {
        Section {
            settingsRow("About", systemImage: "info.circle", subtitle: DeviceIdentity.version) {
                SettingsAboutView()
            }
        }
    }

    private func settingsRow<Destination: View>(
        _ title: String,
        systemImage: String,
        subtitle: String? = nil,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var accountDisplayName: String {
        let name = session.session?.userName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Account" : name
    }

    private var pluginsSubtitle: String? {
        var parts: [String] = []
        if session.introSkipperAvailable {
            parts.append("Intro Skipper")
        }
        if PluginSettings.isSeerrConfigured {
            parts.append("Seerr")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var networkSubtitle: String? {
        let name = session.session?.displayServer ?? session.serverName ?? ""
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var cacheSubtitle: String? {
        let images = ArtworkCache.shared.usage().total.bytes
        let metadata = CacheInventory.metadataUsage().total.bytes
        let total = images + metadata
        guard total > 0 else { return nil }
        return CacheInventory.formatBytes(total)
    }
}

struct SettingsAboutView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("Zelefin", value: DeviceIdentity.version)
            } footer: {
                Text("A native Jellyfin client for iPhone and iPad.")
            }
        }
        .zelefinSettingsChrome(title: "About")
    }
}

extension View {
    func zelefinSettingsChrome(title: String) -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(ZelefinSettingsChrome.canvas)
            .preferredColorScheme(.dark)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(ZelefinSettingsChrome.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(Color.accentColor)
    }
}

enum ZelefinSettingsChrome {
    static var canvas: Color {
        Color(uiColor: .systemGroupedBackground)
    }
}
