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
            if showsQuickConnect {
                quickConnectSection
            }
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
            Text("Jellyfin will look for new files and refresh metadata. This can take a while on a large server.")
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
                        Text(session.isSiloServer ? "Silo account" : session.isEmbyServer ? "Emby account" : "Jellyfin account")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .accessibilityLabel("\(accountDisplayName), Account info")

            settingsRow(
                session.isSiloServer ? "Accounts" : "Users",
                systemImage: "person.2",
                subtitle: session.isSiloServer
                    ? "Switch or add a login on this device"
                    : "Switch or add a user on this device"
            ) {
                DeviceAccountsView()
            }

            if !session.lacksJellyfinOnlyFeatures {
                settingsRow("SyncPlay", systemImage: "person.3", subtitle: "Watch together in a group") {
                    SyncPlayView()
                }
            }
        }
        .zelefinRowBackground()
    }

    private var showsQuickConnect: Bool {
        !session.isEmbyServer
    }

    private var quickConnectSection: some View {
        Section {
            QuickConnectAuthorizeRows()
        } header: {
            Text("Quick Connect")
        } footer: {
            Text("Enter the code shown on another device to sign it in as \(accountDisplayName).")
        }
        .zelefinRowBackground()
    }

    private var accountSection: some View {
        Section("Account") {
            settingsRow("Notifications", systemImage: "bell", subtitle: "Alerts from your server") {
                NotificationSettingsView()
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
            settingsRow("Plugins", systemImage: "puzzlepiece.extension", subtitle: "Intro Skipper, Seerr, Ombi, server plugins") {
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
            if !session.isSiloServer {
                settingsRow("Sessions", systemImage: "laptopcomputer.and.iphone", subtitle: "Devices signed in to \(serverProduct)") {
                    SessionsView()
                }
            }
            settingsRow("User Access", systemImage: "person.badge.key", subtitle: "Permissions, libraries, and parental controls") {
                UserManagementView()
            }
            settingsRow("Scheduled Tasks", systemImage: "clock", subtitle: "Start, cancel, and watch progress") {
                ScheduledTasksView()
            }
            settingsRow("Activity Log", systemImage: "list.bullet", subtitle: "Sign-ins, scans, and failures") {
                ActivityLogView()
            }
            if !session.isEmbyServer {
                settingsRow("Backups", systemImage: "archivebox", subtitle: "Archive and restore this server") {
                    ServerBackupsView()
                }
            }
            settingsRow("Branding", systemImage: "paintbrush", subtitle: "Login disclaimer and splashscreen") {
                ServerBrandingView()
            }
            scanLibrariesRow
        } header: {
            Text("Server")
        } footer: {
            Text("Administer this \(serverProduct) server.")
        }
        .zelefinRowBackground()
    }

    private var deviceSection: some View {
        Section("This Device") {
            settingsRow("Server Info", systemImage: "server.rack", subtitle: "Name, version, OS, and address") {
                ServerInfoView()
            }
            settingsRow("Network", systemImage: "wifi", subtitle: networkSubtitle) {
                NetworkSettingsView()
            }
            settingsRow("Cache", systemImage: "internaldrive", subtitle: cacheSubtitle) {
                CacheSettingsView()
            }
            settingsRow("Interface", systemImage: "rectangle.3.group", subtitle: interfaceSubtitle) {
                TabCustomizationView()
            }
            settingsRow("Log", systemImage: "doc.text", subtitle: "What Zelefin did, to read or send") {
                LogView()
            }
        }
        .zelefinRowBackground()
    }

    private var interfaceSubtitle: String {
        #if targetEnvironment(macCatalyst)
        "Home, sidebar, accent color"
        #else
        "Home, tabs, accent color"
        #endif
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
            .foregroundStyle(.tint)
            .frame(width: 28, alignment: .center)
    }

    private var serverProduct: String {
        session.isEmbyServer ? "Emby" : "Jellyfin"
    }

    private var canAdminister: Bool {
        session.isAdministrator
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
    static let home = URL(string: "https://zelefin.app")!
    static let privacy = URL(string: "https://zelefin.app/privacy")!
    static let terms = URL(string: "https://zelefin.app/terms")!
    static let support = URL(string: "https://zelefin.app/support")!
}

struct SettingsAboutView: View {
    @Environment(\.zelefinSurfaces) private var surfaces
    @Environment(\.openURL) private var openURL
    @State private var legalPage: LegalPage?

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                aboutHero
                aboutVersionCard
                aboutLinks
                aboutCredits
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .background {
            ZStack {
                surfaces.canvas.ignoresSafeArea()
                LoginCanvasGlow(isRegularWidth: false)
                    .opacity(0.85)
            }
        }
        .zelefinSettingsCanvas()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $legalPage) { page in
            SettingsSafariView(url: page.url)
        }
    }

    private var aboutHero: some View {
        VStack(spacing: 18) {
            ConnectBrandMark(size: 112)
                .shadow(color: LoginPalette.lavender.opacity(0.35), radius: 28, y: 10)

            VStack(spacing: 10) {
                Text("Zelefin")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                (
                    Text("Your library, ")
                        .foregroundStyle(.white)
                    + Text("beautifully native.")
                        .foregroundStyle(
                            LinearGradient(
                                colors: [LoginPalette.lavender, LoginPalette.sky],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            }

            Text("A native client for Jellyfin, Silo, and Emby — free, with no subscription and no ads.")
                .font(.subheadline)
                .foregroundStyle(LoginPalette.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var aboutVersionCard: some View {
        HStack(spacing: 12) {
            aboutStat(title: "Version", value: DeviceIdentity.version)
            aboutStat(title: "Build", value: DeviceIdentity.build)
        }
    }

    private func aboutStat(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(LoginPalette.captionText)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(.tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(surfaces.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var aboutLinks: some View {
        VStack(spacing: 12) {
            aboutLinkButton(title: "zelefin.app", systemImage: "safari") {
                openURL(ZelefinSite.home)
            }
            aboutLinkButton(title: "Support", systemImage: "questionmark.circle") {
                openURL(ZelefinSite.support)
            }
            aboutLinkButton(title: "Privacy Policy", systemImage: "hand.raised") {
                legalPage = .privacy
            }
            aboutLinkButton(title: "Terms of Use", systemImage: "doc.text") {
                legalPage = .terms
            }
        }
    }

    private func aboutLinkButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tint)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(surfaces.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var aboutCredits: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Credits")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text("Tab icons are from Iconsax. Anime library icons are from PlainIcon’s Anime characters pack, licensed under CC BY 4.0.")
                .font(.footnote)
                .foregroundStyle(LoginPalette.captionText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(surfaces.raised.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
