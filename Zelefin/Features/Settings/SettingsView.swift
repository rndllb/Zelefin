import SafariServices
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(PlusEntitlement.self) private var plus
    @State private var showsLibraryScanConfirm = false
    @State private var libraryScanMessage: String?

    var body: some View {
        List {
            identitySection
            accountSection
            playbackSection
            serverSection
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
            Text(
                session.usesSilo
                    ? "Silo will refresh metadata for every library. This can take a while on a large server."
                    : "Jellyfin will look for new files and refresh metadata. This can take a while on a large server."
            )
        }
    }

    private var identitySection: some View {
        Section {
            NavigationLink {
                ProfileView()
            } label: {
                SettingsPersonRow(
                    name: accountDisplayName,
                    subtitle: session.usesSilo ? "Silo account" : "Jellyfin account",
                    avatarURL: session.avatarURL,
                    showsChevron: true
                )
                .settingsLoginCard()
            }
            .settingsCardRow()
            .accessibilityLabel("\(accountDisplayName), Account info")
        }
    }

    private var accountSection: some View {
        Section {
            settingsRow("Notifications", systemImage: "bell", subtitle: notificationsSubtitle) {
                NotificationSettingsView()
            }
            if !session.usesSilo {
                settingsRow("Sessions", systemImage: "play.tv", feature: .sessions) {
                    SessionsView()
                }
                settingsRow("SyncPlay", systemImage: "person.2.wave.2", subtitle: syncPlaySubtitle, feature: .syncPlay) {
                    SyncPlayView()
                }
            }
        } header: {
            Text("Account")
        }
    }

    private var playbackSection: some View {
        Section {
            settingsRow("Playback", systemImage: "play.rectangle.on.rectangle") {
                PlaybackSettingsView()
            }
            settingsRow("Plugins", systemImage: "puzzlepiece.extension", subtitle: pluginsSubtitle) {
                PluginSettingsView()
            }
        } header: {
            Text("Playback")
        }
    }

    @ViewBuilder
    private var serverSection: some View {
        if session.canAdministerSilo {
            Section {
                settingsRow("Accounts", systemImage: "person.2", subtitle: "Logins, roles, and passwords", feature: .adminTools) {
                    SiloUsersView()
                }
                settingsRow("Invitations", systemImage: "envelope.badge", subtitle: "Invite people to this server", feature: .adminTools) {
                    SiloInvitationsView()
                }
                settingsRow("Sessions", systemImage: "play.tv", subtitle: "Who is playing right now", feature: .adminTools) {
                    SiloSessionsView()
                }
                settingsRow("Devices", systemImage: "iphone", subtitle: "Signed-in devices", feature: .adminTools) {
                    SiloDevicesView()
                }
                settingsRow("Libraries", systemImage: "rectangle.stack", subtitle: "Scan one library or all of them", feature: .adminTools) {
                    SiloLibrariesAdminView()
                }
                settingsRow("Nodes", systemImage: "server.rack", subtitle: "Stream and transcode workers", feature: .adminTools) {
                    SiloNodesView()
                }
                settingsRow("Scheduled Tasks", systemImage: "clock.arrow.2.circlepath", subtitle: "Start, cancel, and watch progress", feature: .adminTools) {
                    SiloTasksView()
                }
                settingsRow("Activity Log", systemImage: "list.bullet.rectangle", subtitle: "Administrator audit trail", feature: .adminTools) {
                    SiloAuditLogView()
                }
                settingsRow("Server Logs", systemImage: "scroll", subtitle: "Operational output", feature: .adminTools) {
                    SiloOperationalLogView()
                }
                scanLibrariesRow
            } header: {
                Text("Server")
            } footer: {
                Text("Administer this Silo server.")
            }
        } else if session.isAdministrator, !session.usesSilo {
            Section {
                settingsRow("Users", systemImage: "person.2", subtitle: "Permissions, libraries, and parental controls", feature: .adminTools) {
                    UserManagementView()
                }
                settingsRow("Scheduled Tasks", systemImage: "clock.arrow.2.circlepath", subtitle: "Start, cancel, and watch progress", feature: .adminTools) {
                    ScheduledTasksView()
                }
                settingsRow("Activity Log", systemImage: "list.bullet.rectangle", subtitle: "Sign-ins, scans, and failures", feature: .adminTools) {
                    ActivityLogView()
                }
                settingsRow("Backups", systemImage: "externaldrive.badge.timemachine", subtitle: "Archive and restore this server", feature: .adminTools) {
                    ServerBackupsView()
                }
                settingsRow("Branding", systemImage: "paintbrush", subtitle: "Login disclaimer and splashscreen", feature: .adminTools) {
                    ServerBrandingView()
                }
                scanLibrariesRow
            } header: {
                Text("Server")
            } footer: {
                Text("Administer this Jellyfin server.")
            }
        }
    }

    private var scanLibrariesRow: some View {
        Button {
            guard plus.require(.adminTools) else { return }
            showsLibraryScanConfirm = true
        } label: {
            settingsRowLabel(
                "Scan Libraries",
                systemImage: "arrow.triangle.2.circlepath",
                subtitle: libraryScanMessage,
                trailing: .none
            )
            .settingsLoginCard()
        }
        .buttonStyle(.plain)
        .settingsCardRow()
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
        } header: {
            Text("This Device")
        }
    }

    private var aboutSection: some View {
        Section {
            plusRow
            settingsRow("About", systemImage: "info.circle", subtitle: DeviceIdentity.versionAndBuild) {
                SettingsAboutView()
            }
        } header: {
            Text("Zelefin")
        }
    }

    private var plusRow: some View {
        Button {
            plus.request(.downloads)
        } label: {
            settingsRowLabel(
                "Zelefin Plus",
                systemImage: "star.circle",
                subtitle: plus.status.settingsLabel,
                trailing: .chevron
            )
            .settingsLoginCard()
        }
        .buttonStyle(.plain)
        .settingsCardRow()
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
                settingsRowLabel(title, systemImage: systemImage, subtitle: subtitle, trailing: .lock)
                    .settingsLoginCard()
            }
            .buttonStyle(.plain)
            .settingsCardRow()
        } else {
            NavigationLink {
                destination()
            } label: {
                settingsRowLabel(title, systemImage: systemImage, subtitle: subtitle, trailing: .chevron)
                    .settingsLoginCard()
            }
            .settingsCardRow()
        }
    }

    private enum SettingsRowTrailing {
        case none
        case chevron
        case lock
    }

    private func settingsRowLabel(
        _ title: String,
        systemImage: String,
        subtitle: String?,
        trailing: SettingsRowTrailing
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(.tint)
                .frame(width: 28, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LoginPalette.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(LoginPalette.secondaryText)
                }
            }
            Spacer(minLength: 8)
            switch trailing {
            case .none:
                EmptyView()
            case .chevron:
                SettingsChevron()
            case .lock:
                Image(systemName: "lock.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(LoginPalette.captionText)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
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
            session.isAdministrator && LibraryAlertSettings.requests && session.isDiscoverAvailable ? "Requests" : nil,
            session.isAdministrator && LibraryAlertSettings.scheduledTasks ? "Tasks" : nil
        ].compactMap { $0 }
        return parts.isEmpty ? "On" : parts.joined(separator: " · ")
    }

    private var pluginsSubtitle: String? {
        var parts: [String] = []
        if session.introSkipperAvailable {
            parts.append("Intro Skipper")
        }
        if session.openSubtitlesAvailable, !session.usesSilo {
            parts.append("Open Subtitles")
        }
        if session.jellyfinEnhancedAvailable {
            parts.append("Jellyfin Enhanced")
        }
        if session.usesSilo {
            if session.siloSeerrPluginAvailable { parts.append("Seerr") }
            if session.siloArrPluginAvailable { parts.append("Sonarr & Radarr") }
        } else if PluginSettings.isSeerrConfigured {
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

enum ZelefinSite {
    static let privacy = URL(string: "https://zelefin.app/privacy")!
    static let terms = URL(string: "https://zelefin.app/terms")!
}

struct SettingsAboutView: View {
    @Environment(PlusEntitlement.self) private var plus
    @State private var legalPage: LegalPage?

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    SettingsHeroGlyph(systemImage: "sparkles.tv.fill")
                    Text("Zelefin")
                        .font(.title2.weight(.semibold))
                    SettingsChip(
                        leading: "Version \(DeviceIdentity.version)",
                        trailing: "Build \(DeviceIdentity.build)"
                    )
                }
                .frame(maxWidth: .infinity)
                .settingsHeroRow()
            } footer: {
                Text("A native Jellyfin and Silo client for iPhone and iPad.")
            }

            Section {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsLegalRow("Privacy Policy") {
                        legalPage = .privacy
                    }
                    SettingsCardDivider()
                    SettingsLegalRow("Terms of Use") {
                        legalPage = .terms
                    }
                }
                .settingsLoginCard()
                .settingsCardRow()
            }

            #if DEBUG
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsFieldLabel(title: "Plus")
                    Picker("Plus", selection: Binding(
                        get: { plus.debugOverride },
                        set: { plus.debugOverride = $0 }
                    )) {
                        ForEach(PlusDebugOverride.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AccentPreferences.current)
                }
                .settingsLoginCard()
                .settingsCardRow()
            } header: {
                Text("Debug")
            } footer: {
                Text("Locked makes Plus features ask you to pay. Then tap Live TV, a download, or an extra Home row. Fake Store is only for trying a pretend purchase.")
            }
            #endif
        }
        .zelefinSettingsChrome(title: "About")
        .sheet(item: $legalPage) { page in
            SettingsSafariView(url: page.url)
        }
    }
}

private enum LegalPage: String, Identifiable {
    case privacy
    case terms

    var id: String { rawValue }

    var url: URL {
        switch self {
        case .privacy: ZelefinSite.privacy
        case .terms: ZelefinSite.terms
        }
    }
}

private struct SettingsLegalRow: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LoginPalette.primaryText)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LoginPalette.captionText)
            }
        }
    }
}

private struct SettingsSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
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
            .navigationLinkIndicatorVisibility(.hidden)
            .settingsListWidth()
    }

    @ViewBuilder
    private func settingsListWidth() -> some View {
        if #available(iOS 26, *) {
            self.listSectionMargins(.horizontal, 10)
        } else {
            self.contentMargins(.horizontal, 10, for: .scrollContent)
        }
    }
}

enum ZelefinSettingsChrome {
    static var canvas: Color {
        Color(uiColor: .systemGroupedBackground)
    }
}
