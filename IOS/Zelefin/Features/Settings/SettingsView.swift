import SafariServices
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @State private var showsLibraryScanConfirm = false
    @State private var libraryScanMessage: String?
    @State private var cacheBytes: Int64?

    var body: some View {
        List {
            profileSection
            accountSection
            playbackSection
            if canAdminister {
                serverSection
            }
            deviceSection
            aboutSection
        }
        .zelefinSettingsChrome(title: "Settings")
        .task {
            await session.detectIntroSkipper()
        }
        .task {
            cacheBytes = await Task.detached(priority: .utility) {
                ArtworkCache.shared.usage().total.bytes + CacheInventory.metadataUsage().total.bytes
            }.value
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

    private var profileSection: some View {
        Section {
            NavigationLink {
                ProfileView()
            } label: {
                HStack(spacing: 14) {
                    UserAvatarView(url: session.avatarURL, diameter: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(accountDisplayName)
                            .font(.body.weight(.semibold))
                        Text(session.usesSilo ? "Silo account" : "Jellyfin account")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .accessibilityLabel("\(accountDisplayName), Account info")
        }
        .zelefinRowBackground()
    }

    private var accountSection: some View {
        Section("Account") {
            settingsRow("Notifications", systemImage: "bell", subtitle: "Alerts from your server") {
                NotificationSettingsView()
            }
            if !session.usesSilo {
                settingsRow("Sessions", systemImage: "laptopcomputer.and.iphone", subtitle: "Devices signed in to Jellyfin") {
                    SessionsView()
                }
                settingsRow("SyncPlay", systemImage: "person.3", subtitle: "Watch together in a group") {
                    SyncPlayView()
                }
            }
        }
        .zelefinRowBackground()
    }

    private var playbackSection: some View {
        Section("Playback") {
            settingsRow("Playback", systemImage: "play", subtitle: "Languages, quality, speed, skipping") {
                PlaybackSettingsView()
            }
            settingsRow("Subtitles", systemImage: "captions.bubble", subtitle: "Size, color, and background") {
                SubtitleAppearanceSettingsView()
            }
            settingsRow("Plugins", systemImage: "puzzlepiece.extension", subtitle: "Intro Skipper, Seerr, server plugins") {
                PluginSettingsView()
            }
            settingsRow("Metadata", systemImage: "doc.text", subtitle: "Ratings and title details") {
                MetadataSettingsView()
            }
        }
        .zelefinRowBackground()
    }

    private var serverSection: some View {
        Section {
            if session.canAdministerSilo {
                settingsRow("Accounts", systemImage: "person.2", subtitle: "People who can sign in to Silo") {
                    SiloUsersView()
                }
                settingsRow("Invitations", systemImage: "envelope.badge", subtitle: "Invite links for new accounts") {
                    SiloInvitationsView()
                }
                settingsRow("Sessions", systemImage: "laptopcomputer.and.iphone", subtitle: "Who is watching right now") {
                    SiloSessionsView()
                }
                settingsRow("Devices", systemImage: "iphone", subtitle: "Signed-in devices") {
                    SiloDevicesView()
                }
                settingsRow("Libraries", systemImage: "rectangle.stack", subtitle: "Folders and library types") {
                    SiloLibrariesAdminView()
                }
                settingsRow("Nodes", systemImage: "server.rack", subtitle: "Storage and transcoding nodes") {
                    SiloNodesView()
                }
                settingsRow("Scheduled Tasks", systemImage: "clock", subtitle: "Start, cancel, and watch progress") {
                    SiloTasksView()
                }
                settingsRow("Activity Log", systemImage: "list.bullet", subtitle: "Sign-ins, scans, and failures") {
                    SiloAuditLogView()
                }
                settingsRow("Server Logs", systemImage: "scroll", subtitle: "Diagnostics from the server") {
                    SiloOperationalLogView()
                }
            } else {
                settingsRow("Users", systemImage: "person.2", subtitle: "Permissions, libraries, and parental controls") {
                    UserManagementView()
                }
                settingsRow("Scheduled Tasks", systemImage: "clock", subtitle: "Start, cancel, and watch progress") {
                    ScheduledTasksView()
                }
                settingsRow("Activity Log", systemImage: "list.bullet", subtitle: "Sign-ins, scans, and failures") {
                    ActivityLogView()
                }
                settingsRow("Backups", systemImage: "archivebox", subtitle: "Archive and restore this server") {
                    ServerBackupsView()
                }
                settingsRow("Branding", systemImage: "paintbrush", subtitle: "Login disclaimer and splashscreen") {
                    ServerBrandingView()
                }
            }
            scanLibrariesRow
        } header: {
            Text("Server")
        } footer: {
            Text(session.usesSilo ? "Administer this Silo server." : "Administer this Jellyfin server.")
        }
        .zelefinRowBackground()
    }

    private var deviceSection: some View {
        Section("This Device") {
            settingsRow("Network", systemImage: "wifi", subtitle: networkSubtitle) {
                NetworkSettingsView()
            }
            settingsRow("Cache", systemImage: "internaldrive", subtitle: cacheSubtitle) {
                CacheSettingsView()
            }
            settingsRow("Interface", systemImage: "rectangle.3.group", subtitle: "Home rows and tabs") {
                TabCustomizationView()
            }
            settingsRow("Appearance", systemImage: "paintpalette", subtitle: "Accent color") {
                AppearanceSettingsView()
            }
        }
        .zelefinRowBackground()
    }

    private var aboutSection: some View {
        Section("Zelefin") {
            settingsRow("About", systemImage: "info.circle", subtitle: DeviceIdentity.versionAndBuild) {
                SettingsAboutView()
            }
        }
        .zelefinRowBackground()
    }

    private var scanLibrariesRow: some View {
        Button {
            showsLibraryScanConfirm = true
        } label: {
            HStack(spacing: 14) {
                settingsIcon("arrow.clockwise")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scan Libraries")
                        .foregroundStyle(.primary)
                    Text(libraryScanMessage ?? "Look for new files and refresh metadata")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func settingsRow<Destination: View>(
        _ title: String,
        systemImage: String,
        subtitle: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 14) {
                settingsIcon(systemImage)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func settingsIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.body.weight(.medium))
            .foregroundStyle(Color.accentColor)
            .frame(width: 28, alignment: .center)
    }

    private var canAdminister: Bool {
        session.canAdministerSilo || (session.isAdministrator && !session.usesSilo)
    }

    private var accountDisplayName: String {
        let name = session.session?.userName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Account" : name
    }

    private var networkSubtitle: String {
        let name = session.session?.displayServer ?? session.serverName ?? ""
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "How this device reaches the server" : trimmed
    }

    private var cacheSubtitle: String {
        guard let cacheBytes, cacheBytes > 0 else { return "Posters and saved home data" }
        return CacheInventory.formatBytes(cacheBytes)
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
    @State private var legalPage: LegalPage?

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    ConnectBrandMark(size: 88)
                    Text("Zelefin")
                        .font(.title2.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                LabeledContent("Version", value: DeviceIdentity.version)
                LabeledContent("Build", value: DeviceIdentity.build)
            } footer: {
                Text("A native Jellyfin and Silo client for iPhone and iPad. Tab icons are from Iconsax.")
            }

            Section {
                Button("Privacy Policy") { legalPage = .privacy }
                Button("Terms of Use") { legalPage = .terms }
            }
            .zelefinRowBackground()
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

private struct SettingsSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

extension View {
    func zelefinSettingsCanvas() -> some View {
        self
            .preferredColorScheme(.dark)
            .zelefinAccentTint()
    }

    func zelefinSettingsChrome(title: String) -> some View {
        modifier(ZelefinSettingsListChrome())
            .zelefinSettingsCanvas()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ZelefinSettingsListChrome: ViewModifier {
    @Environment(\.zelefinSurfaces) private var surfaces

    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(surfaces.canvas.ignoresSafeArea())
    }
}
