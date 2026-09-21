import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(LibraryAlertSettings.enabledKey) private var isEnabled = true
    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @State private var isInstallingPlugin = false
    @State private var isRestarting = false
    @State private var pluginNeedsRestart = false
    @State private var pluginStatus: String?

    var body: some View {
        List {
            if session.companionAvailable {
                configuredSection
            } else {
                pluginRequiredSection
            }
        }
        .zelefinSettingsChrome(title: "Notifications")
        .task {
            await session.detectPlugins()
            await refreshAuthorization()
        }
        .onChange(of: isEnabled) { _, enabled in
            guard session.companionAvailable else { return }
            Task { await handleMasterToggle(enabled) }
        }
    }

    private var configuredSection: some View {
        Section {
            Toggle("Notifications", isOn: $isEnabled)
                .tint(AccentPreferences.current)
                .font(.body.weight(.semibold))
                .settingsLoginCard()
                .settingsCardRow()
        } footer: {
            Text(permissionFooter)
        }
    }

    private var pluginRequiredSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Zelefin plugin")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(LoginPalette.primaryText)
                    Spacer(minLength: 8)
                    SettingsStatusValue(
                        text: pluginStatusLabel,
                        isPositive: pluginNeedsRestart
                    )
                }

                Text(pluginRequiredCopy)
                    .font(.subheadline)
                    .foregroundStyle(LoginPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if canInstallPlugin {
                    SettingsPrimaryButton(
                        title: isInstallingPlugin ? "Installing…" : "Install Plugin",
                        isBusy: isInstallingPlugin,
                        enabled: !isInstallingPlugin && !pluginNeedsRestart
                    ) {
                        Task { await installPlugin() }
                    }
                    if pluginNeedsRestart {
                        SettingsSecondaryButton(
                            title: isRestarting ? "Restarting…" : "Restart Jellyfin",
                            enabled: !isRestarting
                        ) {
                            Task { await restartServer() }
                        }
                    }
                } else if !session.usesSilo, !session.isAdministrator, !session.isReviewDemo {
                    SettingsStatusText(
                        text: "Ask a server administrator to install the Zelefin plugin from Settings → Notifications, or sign in with an admin account."
                    )
                }

                if let pluginStatus {
                    SettingsStatusText(text: pluginStatus, isError: pluginStatus.contains("could not"))
                }
            }
            .settingsLoginCard()
            .settingsCardRow()
        } footer: {
            Text(pluginRequiredFooter)
        }
    }

    private var canInstallPlugin: Bool {
        session.isAdministrator && !session.usesSilo && !session.isReviewDemo
    }

    private var pluginStatusLabel: String {
        if pluginNeedsRestart { return "Restart needed" }
        return "Not on this server"
    }

    private var pluginRequiredCopy: String {
        if session.usesSilo {
            return "Lock-screen alerts need the Zelefin plugin on a Jellyfin server. This Silo server cannot install that plugin, so notifications are not available here."
        }
        if session.isReviewDemo {
            return "Lock-screen alerts need the Zelefin plugin on a Jellyfin server. Review Demo does not install plugins."
        }
        return "Install the Zelefin plugin on this Jellyfin server to get lock-screen alerts. The plugin watches the library and can notify this iPhone when titles are added, a stream starts, someone comes online, a scheduled task begins, or a Seerr request comes in — including while Zelefin is closed. This app no longer checks the server itself."
    }

    private var pluginRequiredFooter: String {
        if session.usesSilo {
            return "Connect a Jellyfin server with the Zelefin plugin to receive notifications."
        }
        if session.isReviewDemo {
            return "Sign in to a Jellyfin server to install the plugin."
        }
        return "After install, restart Jellyfin so the plugin can load. You do not paste an Apple key on the server."
    }

    private var permissionFooter: String {
        switch authorization {
        case .denied:
            return "Notifications are off in iOS Settings. Turn them on for Zelefin so the plugin can deliver banners for new titles, streams, users online, scheduled tasks, and Seerr requests."
        case .notDetermined:
            return "Zelefin asks iOS for permission when you turn this on. The plugin then pushes new titles, streams, users online, scheduled tasks, and Seerr requests."
        default:
            return "The Zelefin plugin pushes lock-screen alerts for new titles, streams, users online, scheduled tasks, and Seerr requests while the app is open or closed. Restart Jellyfin after you install or remove the plugin."
        }
    }

    private func refreshAuthorization() async {
        authorization = await LibraryAlertCenter.shared.authorizationStatus()
    }

    private func handleMasterToggle(_ enabled: Bool) async {
        if enabled {
            _ = await LibraryAlertCenter.shared.requestAuthorization()
            await refreshAuthorization()
            if authorization == .denied {
                isEnabled = false
            } else {
                _ = await PushNotificationCenter.requestPermissionIfNeeded()
                await session.registerCompanionPushIfNeeded()
            }
        }
    }

    private func installPlugin() async {
        isInstallingPlugin = true
        pluginStatus = nil
        defer { isInstallingPlugin = false }
        do {
            try await session.installZelefinPlugin()
            pluginNeedsRestart = !session.companionAvailable
            pluginStatus = pluginNeedsRestart
                ? "Installed. Restart Jellyfin so the plugin can load."
                : "Installed."
            if session.companionAvailable {
                await handleMasterToggle(isEnabled)
            }
        } catch {
            pluginStatus = error.localizedDescription
        }
    }

    private func restartServer() async {
        isRestarting = true
        defer { isRestarting = false }
        do {
            try await session.restartJellyfinAfterPluginInstall()
            pluginStatus = "Jellyfin is restarting. Reopen Zelefin in a minute if the library does not load."
        } catch {
            pluginStatus = error.localizedDescription
        }
    }
}
