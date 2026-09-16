import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(PlusEntitlement.self) private var plus
    @State private var showsLibraryScanConfirm = false
    @State private var libraryScanMessage: String?

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
        }
        .confirmationDialog(
            "Scan every library?",
            isPresented: $showsLibraryScanConfirm,
            titleVisibility: .visible
        ) {
            Button("Scan Libraries") {
                Task { await scanLibraries() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Jellyfin will look for new files and refresh metadata. This can take a while on a large server.")
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
            settingsRow("Sessions", systemImage: "play.tv", feature: .sessions) {
                SessionsView()
            }
            settingsRow("SyncPlay", systemImage: "person.2.wave.2", subtitle: syncPlaySubtitle, feature: .syncPlay) {
                SyncPlayView()
            }
            settingsRow("Notifications", systemImage: "bell", subtitle: notificationsSubtitle) {
                NotificationSettingsView()
            }
            if session.isAdministrator {
                settingsRow("Users", systemImage: "person.2", subtitle: "Permissions, libraries, and parental controls", feature: .adminTools) {
                    UserManagementView()
                }
                settingsRow("Scheduled Tasks", systemImage: "clock.arrow.2.circlepath", subtitle: "Start, cancel, and watch progress", feature: .adminTools) {
                    ScheduledTasksView()
                }
                settingsRow("Activity Log", systemImage: "list.bullet.rectangle", subtitle: "Who signed in, what scanned, what failed", feature: .adminTools) {
                    ActivityLogView()
                }
                settingsRow("Backups", systemImage: "externaldrive.badge.timemachine", subtitle: "Archive and restore this server", feature: .adminTools) {
                    ServerBackupsView()
                }
                settingsRow("Branding", systemImage: "paintbrush", subtitle: "Login disclaimer and splashscreen", feature: .adminTools) {
                    ServerBrandingView()
                }
                Button {
                    guard plus.require(.adminTools) else { return }
                    showsLibraryScanConfirm = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.tint)
                            .frame(width: 28, alignment: .center)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scan Libraries")
                            if let libraryScanMessage {
                                Text(libraryScanMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
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
            plusRow
            settingsRow("About", systemImage: "info.circle", subtitle: DeviceIdentity.version) {
                SettingsAboutView()
            }
        }
    }

    private var plusRow: some View {
        Button {
            plus.request(.downloads)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "star.circle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.tint)
                    .frame(width: 28, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Zelefin Plus")
                    Text(plus.status.settingsLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func settingsRow<Destination: View>(
        _ title: String,
        systemImage: String,
        subtitle: String? = nil,
        feature: PlusFeature? = nil,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        if let feature, !plus.isUnlocked {
            Button {
                plus.request(feature)
            } label: {
                settingsRowLabel(title, systemImage: systemImage, subtitle: subtitle, showsLock: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                destination()
            } label: {
                settingsRowLabel(title, systemImage: systemImage, subtitle: subtitle, showsLock: false)
            }
        }
    }

    private func settingsRowLabel(
        _ title: String,
        systemImage: String,
        subtitle: String?,
        showsLock: Bool
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(.tint)
                .frame(width: 28, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if showsLock {
                Spacer(minLength: 8)
                Image(systemName: "lock.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var accountDisplayName: String {
        let name = session.session?.userName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Account" : name
    }

    private var notificationsSubtitle: String? {
        guard LibraryAlertSettings.isEnabled else { return "Off" }
        let parts = [
            LibraryAlertSettings.libraryAdds ? "New titles" : nil,
            session.isAdministrator && LibraryAlertSettings.streams ? "Streams" : nil,
            session.isAdministrator && LibraryAlertSettings.online ? "Online" : nil,
            session.isAdministrator && LibraryAlertSettings.requests && PluginSettings.isSeerrConfigured ? "Requests" : nil,
            session.isAdministrator && LibraryAlertSettings.scheduledTasks ? "Tasks" : nil
        ].compactMap { $0 }
        return parts.isEmpty ? "On" : parts.joined(separator: " · ")
    }

    private var pluginsSubtitle: String? {
        var parts: [String] = []
        if session.introSkipperAvailable {
            parts.append("Intro Skipper")
        }
        if session.openSubtitlesAvailable {
            parts.append("Open Subtitles")
        }
        if session.jellyfinEnhancedAvailable {
            parts.append("Jellyfin Enhanced")
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

    private var syncPlaySubtitle: String? {
        session.syncPlayGroupName
    }

    private func scanLibraries() async {
        do {
            try await session.library?.scanLibraries()
            libraryScanMessage = "Scan started"
        } catch {
            libraryScanMessage = error.localizedDescription
        }
    }
}

struct SettingsAboutView: View {
    @Environment(PlusEntitlement.self) private var plus

    var body: some View {
        List {
            Section {
                LabeledContent("Zelefin", value: DeviceIdentity.version)
            } footer: {
                Text("A native Jellyfin client for iPhone and iPad.")
            }
            #if DEBUG
            Section {
                Picker("Plus", selection: Binding(
                    get: { plus.debugOverride },
                    set: { plus.debugOverride = $0 }
                )) {
                    ForEach(PlusDebugOverride.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } header: {
                Text("Debug")
            } footer: {
                Text("Locked makes Plus features ask you to pay. Then tap Live TV, a download, or an extra Home row. Fake Store is only for trying a pretend purchase.")
            }
            #endif
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
            .zelefinAccentTint()
    }
}

enum ZelefinSettingsChrome {
    static var canvas: Color {
        Color(uiColor: .systemGroupedBackground)
    }
}
