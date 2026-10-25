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
    @State private var isSendingTest = false
    @State private var testStatus: String?
    @State private var testFailed = false

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
            // Turning off must reach the plugin even before detection has finished.
            if enabled, !session.companionAvailable { return }
            Task { await handleMasterToggle(enabled) }
        }
    }

    private var configuredSection: some View {
        Section {
            Toggle("Notifications", isOn: $isEnabled)
            if canSendTest {
                Button(isSendingTest ? "Sending…" : "Send Test Alert") {
                    Task { await sendTestAlert() }
                }
                .disabled(isSendingTest)
            }
            if let testStatus {
                SettingsStatusText(text: testStatus, isError: testFailed)
            }
        } footer: {
            Text(permissionFooter)
        }
        .zelefinRowBackground()
    }

    private var pluginRequiredSection: some View {
        Section {
            LabeledContent("Zelefin plugin") {
                Text(pluginStatusLabel)
                    .foregroundStyle(pluginNeedsRestart ? Color.orange : Color.red)
            }
            if canInstallPlugin {
                Button(isInstallingPlugin ? "Installing…" : "Install Plugin") {
                    Task { await installPlugin() }
                }
                .disabled(isInstallingPlugin || pluginNeedsRestart)
                if pluginNeedsRestart {
                    Button(isRestarting ? "Restarting…" : "Restart Jellyfin") {
                        Task { await restartServer() }
                    }
                    .disabled(isRestarting)
                }
            } else if !session.lacksJellyfinOnlyFeatures, !session.isAdministrator, !session.isReviewDemo {
                Text("Ask a server administrator to install the Zelefin plugin from Settings → Notifications, or sign in with an admin account.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let pluginStatus {
                SettingsStatusText(text: pluginStatus, isError: pluginStatus.contains("could not"))
            }
        } footer: {
            Text(pluginRequiredCopy + " " + pluginRequiredFooter)
        }
        .zelefinRowBackground()
    }

    /// Only administrators can ask the plugin to push; it rejects test alerts from other users.
    private var canSendTest: Bool {
        isEnabled
            && session.isAdministrator
            && (authorization == .authorized || authorization == .provisional || authorization == .ephemeral)
    }

    private func sendTestAlert() async {
        isSendingTest = true
        testStatus = nil
        defer { isSendingTest = false }
        let error = await session.sendCompanionTestAlert()
        testFailed = error != nil
        testStatus = error ?? "Sent. It should arrive in a few seconds."
    }

    private var canInstallPlugin: Bool {
        session.isAdministrator && !session.isReviewDemo
    }

    private var pluginStatusLabel: String {
        if pluginNeedsRestart { return "Restart needed" }
        return "Not on this server"
    }

    private var pluginRequiredCopy: String {
        if session.isSiloServer {
            return "Lock-screen alerts need the Zelefin plugin on a Jellyfin server. This Silo server cannot install that plugin, so notifications are not available here."
        }
        if session.isEmbyServer {
            return "Lock-screen alerts need the Zelefin plugin on a Jellyfin server. Emby cannot run that plugin, so notifications are not available here."
        }
        if session.isReviewDemo {
            return "Lock-screen alerts need the Zelefin plugin on a Jellyfin server. Review Demo does not install plugins."
        }
        return "Install the Zelefin plugin on this Jellyfin server to get lock-screen alerts. The plugin watches the library and can notify this iPhone when titles are added, a stream starts, someone comes online, a scheduled task begins, or a Seerr request comes in — including while Zelefin is closed. This app no longer checks the server itself."
    }

    private var pluginRequiredFooter: String {
        if session.lacksJellyfinOnlyFeatures {
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
        } else {
            await session.unregisterCompanionPush()
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
