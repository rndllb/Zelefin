import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(LibraryAlertSettings.enabledKey) private var isEnabled = true
    @AppStorage(LibraryAlertSettings.libraryAddsKey) private var libraryAdds = true
    @AppStorage(LibraryAlertSettings.streamsKey) private var streams = true
    @AppStorage(LibraryAlertSettings.onlineKey) private var online = true
    @AppStorage(LibraryAlertSettings.requestsKey) private var requests = true
    @AppStorage(LibraryAlertSettings.scheduledTasksKey) private var scheduledTasks = true
    @State private var authorization: UNAuthorizationStatus = .notDetermined

    var body: some View {
        List {
            Section {
                Toggle("Notifications", isOn: $isEnabled)
                    .tint(AccentPreferences.current)
                    .font(.body.weight(.semibold))
                    .settingsLoginCard()
                    .settingsCardRow()
            } footer: {
                Text(permissionFooter)
            }

            Section {
                Toggle("New titles", isOn: $libraryAdds)
                    .tint(AccentPreferences.current)
                    .font(.body.weight(.semibold))
                    .disabled(!isEnabled)
                    .settingsLoginCard()
                    .settingsCardRow()
            } footer: {
                Text("Alerts for movies and episodes added after this device already knows the library. Tapping one opens that title.")
            }

            if session.isAdministrator {
                Section {
                    VStack(alignment: .leading, spacing: 0) {
                        if !session.usesSilo {
                            Toggle("Streams started", isOn: $streams)
                                .tint(AccentPreferences.current)
                                .font(.body.weight(.semibold))
                                .disabled(!isEnabled)
                            SettingsCardDivider()
                            Toggle("Users online", isOn: $online)
                                .tint(AccentPreferences.current)
                                .font(.body.weight(.semibold))
                                .disabled(!isEnabled)
                            SettingsCardDivider()
                        }
                        Toggle("Scheduled tasks", isOn: $scheduledTasks)
                            .tint(AccentPreferences.current)
                            .font(.body.weight(.semibold))
                            .disabled(!isEnabled)
                        if session.isDiscoverAvailable {
                            SettingsCardDivider()
                            Toggle(session.usesSilo ? "Media requests" : "Seerr requests", isOn: $requests)
                                .tint(AccentPreferences.current)
                                .font(.body.weight(.semibold))
                                .disabled(!isEnabled)
                        }
                    }
                    .settingsLoginCard()
                    .settingsCardRow()
                } header: {
                    Text("Administrators")
                } footer: {
                    Text(adminFooter)
                }
            }
        }
        .zelefinSettingsChrome(title: "Notifications")
        .task {
            await refreshAuthorization()
        }
        .onChange(of: isEnabled) { _, enabled in
            Task { await handleMasterToggle(enabled) }
        }
    }

    private var permissionFooter: String {
        if session.usesSilo {
            switch authorization {
            case .denied:
                return "Notifications are off in iOS Settings. Turn them on for Zelefin to see banners on this device."
            case .notDetermined:
                return "Zelefin asks iOS for permission when you turn this on. This device checks Silo itself while the app can run."
            default:
                return "Zelefin checks this Silo server from this device. iOS may wait until you open the app."
            }
        }
        switch authorization {
        case .denied:
            return "Notifications are off in iOS Settings. Turn them on for Zelefin to see banners on this device."
        case .notDetermined:
            return "Zelefin asks iOS for permission when you turn this on. This iPhone checks Jellyfin itself. The plugin is optional push while the app stays fully closed."
        case .authorized, .provisional, .ephemeral:
            return session.companionAvailable
                ? "The Zelefin plugin can push while the app stays closed. This iPhone also checks the server itself, so banners can still appear after you remove the plugin."
                : "This iPhone checks Jellyfin itself. You do not need the plugin for banners while the app is open or after a background refresh. The plugin is only for push when the app is fully closed."
        @unknown default:
            return "This iPhone checks Jellyfin itself. The Zelefin plugin is only for push while the app stays fully closed."
        }
    }

    private var adminFooter: String {
        if session.usesSilo {
            return session.isDiscoverAvailable
                ? "Task starts and media requests from this Silo server."
                : "Scheduled task starts on this Silo server."
        }
        if PluginSettings.isSeerrConfigured {
            return "Playback, who is online, scheduled tasks, and Seerr requests."
        }
        return "Playback, who is online, and scheduled tasks. Sign in to Seerr under Plugins for request alerts."
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
            }
        }
        LibraryAlertMonitor.shared.stop()
        if enabled, session.isSignedIn, !session.isReviewDemo {
            LibraryAlertMonitor.shared.start(session: session)
        }
    }
}
