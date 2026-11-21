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
        .zelefinSettingsChrome(title: AppLanguage.string("settings.title", default: "Settings"))
        .task {
            await session.detectIntroSkipper()
        }
        .task {
            cacheBytes = await Task.detached(priority: .utility) {
                ArtworkCache.shared.usage().total.bytes + CacheInventory.metadataUsage().total.bytes
            }.value
        }
        .confirmationDialog(
            AppLanguage.string("settings.scan_libraries_confirm", default: "Scan every library?"),
            isPresented: $showsLibraryScanConfirm,
            titleVisibility: .visible
        ) {
            Button(AppLanguage.string("settings.scan_libraries", default: "Scan Libraries")) {
                Task { await scanLibraries() }
            }
            Button(AppLanguage.string("common.cancel", default: "Cancel"), role: .cancel) {}
        } message: {
            Text(AppLanguage.string("settings.scan_libraries_message", default: "Jellyfin will look for new files and refresh metadata. This can take a while on a large server."))
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
                        Text(session.isSiloServer ? AppLanguage.string("settings.silo_account", default: "Silo account") : session.isEmbyServer ? AppLanguage.string("settings.emby_account", default: "Emby account") : AppLanguage.string("settings.jellyfin_account", default: "Jellyfin account"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .accessibilityLabel("\(accountDisplayName), \(AppLanguage.string("settings.account_info", default: "Account info"))")

            settingsRow(
                session.isSiloServer ? AppLanguage.string("settings.accounts", default: "Accounts") : AppLanguage.string("settings.users", default: "Users"),
                systemImage: "person.2",
                subtitle: session.isSiloServer
                    ? AppLanguage.string("settings.accounts_subtitle", default: "Switch or add a login on this device")
                    : AppLanguage.string("settings.users_subtitle", default: "Switch or add a user on this device")
            ) {
                DeviceAccountsView()
            }

            if !session.lacksJellyfinOnlyFeatures {
                settingsRow(AppLanguage.string("settings.syncplay", default: "SyncPlay"), systemImage: "person.3", subtitle: AppLanguage.string("settings.syncplay_subtitle", default: "Watch together in a group")) {
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
            Text(AppLanguage.string("connect.quick_connect", default: "Quick Connect"))
        } footer: {
            Text(String(format: AppLanguage.string("settings.quick_connect_footer", default: "Enter the code shown on another device to sign it in as %@."), accountDisplayName))
        }
        .zelefinRowBackground()
    }

    private var accountSection: some View {
        Section(AppLanguage.string("settings.account", default: "Account")) {
            settingsRow(AppLanguage.string("settings.notifications", default: "Notifications"), systemImage: "bell", subtitle: AppLanguage.string("settings.notifications_subtitle", default: "Alerts from your server")) {
                NotificationSettingsView()
            }
        }
        .zelefinRowBackground()
    }

    private var playbackSection: some View {
        Section(AppLanguage.string("settings.playback", default: "Playback")) {
            settingsRow(AppLanguage.string("settings.playback", default: "Playback"), systemImage: "play", subtitle: AppLanguage.string("settings.playback_subtitle", default: "Languages, quality, speed, skipping")) {
                PlaybackSettingsView()
            }
            settingsRow(AppLanguage.string("player.subtitles", default: "Subtitles"), systemImage: "captions.bubble", subtitle: AppLanguage.string("settings.subtitles_subtitle", default: "Size, color, and background")) {
                SubtitleAppearanceSettingsView()
            }
            settingsRow(AppLanguage.string("settings.plugins", default: "Plugins"), systemImage: "puzzlepiece.extension", subtitle: AppLanguage.string("settings.plugins_subtitle", default: "Intro Skipper, Seerr, Ombi, server plugins")) {
                PluginSettingsView()
            }
            settingsRow(AppLanguage.string("settings.metadata", default: "Metadata"), systemImage: "doc.text", subtitle: AppLanguage.string("settings.metadata_subtitle", default: "Ratings and title details")) {
                MetadataSettingsView()
            }
        }
        .zelefinRowBackground()
    }

    private var serverSection: some View {
        Section {
            if !session.isSiloServer {
                settingsRow(AppLanguage.string("settings.sessions", default: "Sessions"), systemImage: "laptopcomputer.and.iphone", subtitle: String(format: AppLanguage.string("settings.sessions_subtitle", default: "Devices signed in to %@"), serverProduct)) {
                    SessionsView()
                }
            }
            settingsRow(AppLanguage.string("settings.user_access", default: "User Access"), systemImage: "person.badge.key", subtitle: AppLanguage.string("settings.user_access_subtitle", default: "Permissions, libraries, and parental controls")) {
                UserManagementView()
            }
            settingsRow(AppLanguage.string("settings.scheduled_tasks", default: "Scheduled Tasks"), systemImage: "clock", subtitle: AppLanguage.string("settings.scheduled_tasks_subtitle", default: "Start, cancel, and watch progress")) {
                ScheduledTasksView()
            }
            settingsRow(AppLanguage.string("settings.activity_log", default: "Activity Log"), systemImage: "list.bullet", subtitle: AppLanguage.string("settings.activity_log_subtitle", default: "Sign-ins, scans, and failures")) {
                ActivityLogView()
            }
            if !session.isEmbyServer {
                settingsRow(AppLanguage.string("settings.backups", default: "Backups"), systemImage: "archivebox", subtitle: AppLanguage.string("settings.backups_subtitle", default: "Archive and restore this server")) {
                    ServerBackupsView()
                }
            }
            settingsRow(AppLanguage.string("settings.branding", default: "Branding"), systemImage: "paintbrush", subtitle: AppLanguage.string("settings.branding_subtitle", default: "Login disclaimer and splashscreen")) {
                ServerBrandingView()
            }
            scanLibrariesRow
        } header: {
            Text(AppLanguage.string("settings.server", default: "Server"))
        } footer: {
            Text(String(format: AppLanguage.string("settings.server_admin_footer", default: "Administer this %@ server."), serverProduct))
        }
        .zelefinRowBackground()
    }

    private var deviceSection: some View {
        Section(AppLanguage.string("settings.this_device", default: "This Device")) {
            settingsRow(AppLanguage.string("settings.server_info", default: "Server Info"), systemImage: "server.rack", subtitle: AppLanguage.string("settings.server_info_subtitle", default: "Name, version, OS, and address")) {
                ServerInfoView()
            }
            settingsRow(AppLanguage.string("settings.network", default: "Network"), systemImage: "wifi", subtitle: networkSubtitle) {
                NetworkSettingsView()
            }
            settingsRow(AppLanguage.string("settings.cache", default: "Cache"), systemImage: "internaldrive", subtitle: cacheSubtitle) {
                CacheSettingsView()
            }
            settingsRow(AppLanguage.string("settings.interface", default: "Interface"), systemImage: "rectangle.3.group", subtitle: interfaceSubtitle) {
                TabCustomizationView()
            }
            settingsRow(AppLanguage.string("settings.log", default: "Log"), systemImage: "doc.text", subtitle: AppLanguage.string("settings.log_subtitle", default: "What Zelefin did, to read or send")) {
                LogView()
            }
        }
        .zelefinRowBackground()
    }

    private var interfaceSubtitle: String {
        #if targetEnvironment(macCatalyst)
        AppLanguage.string("settings.interface_subtitle_mac", default: "Home, sidebar, accent color")
        #else
        AppLanguage.string("settings.interface_subtitle_phone", default: "Home, tabs, accent color")
        #endif
    }

    private var aboutSection: some View {
        Section(AppLanguage.string("settings.zelefin_section", default: "Zelefin")) {
            settingsRow(AppLanguage.string("settings.about", default: "About"), systemImage: "info.circle", subtitle: DeviceIdentity.versionAndBuild) {
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
                    Text(AppLanguage.string("settings.scan_libraries", default: "Scan Libraries"))
                        .foregroundStyle(.primary)
                    Text(libraryScanMessage ?? AppLanguage.string("settings.scan_libraries_subtitle", default: "Look for new files and refresh metadata"))
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
        return name.isEmpty ? AppLanguage.string("settings.account", default: "Account") : name
    }

    private var networkSubtitle: String {
        let name = session.session?.displayServer ?? session.serverName ?? ""
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppLanguage.string("settings.network_how", default: "How this device reaches the server") : trimmed
    }

    private var cacheSubtitle: String {
        guard let cacheBytes, cacheBytes > 0 else { return AppLanguage.string("settings.cache_posters", default: "Posters and saved home data") }
        return CacheInventory.formatBytes(cacheBytes)
    }

    private func scanLibraries() async {
        do {
            try await session.library?.scanLibraries()
            libraryScanMessage = AppLanguage.string("settings.scan_started", default: "Scan started")
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
        .navigationTitle(AppLanguage.string("detail.about", default: "About"))
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
                Text(AppLanguage.string("settings.zelefin_section", default: "Zelefin"))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                (
                    Text(AppLanguage.string("settings.about_tagline_prefix", default: "Your library, "))
                        .foregroundStyle(.white)
                    + Text(AppLanguage.string("settings.about_tagline_accent", default: "beautifully native."))
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

            Text(AppLanguage.string("settings.about_body", default: "A native client for Jellyfin, Silo, and Emby — free, with no subscription and no ads."))
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
            aboutStat(title: AppLanguage.string("settings.version", default: "Version"), value: DeviceIdentity.version)
            aboutStat(title: AppLanguage.string("settings.build", default: "Build"), value: DeviceIdentity.build)
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
            aboutLinkButton(title: AppLanguage.string("settings.support", default: "Support"), systemImage: "questionmark.circle") {
                openURL(ZelefinSite.support)
            }
            aboutLinkButton(title: AppLanguage.string("settings.privacy_policy", default: "Privacy Policy"), systemImage: "hand.raised") {
                legalPage = .privacy
            }
            aboutLinkButton(title: AppLanguage.string("settings.terms_of_use", default: "Terms of Use"), systemImage: "doc.text") {
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
            Text(AppLanguage.string("settings.credits", default: "Credits"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text(AppLanguage.string("settings.credits_body", default: "Tab icons are from Iconsax. Anime library icons are from PlainIcon’s Anime characters pack, licensed under CC BY 4.0."))
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
