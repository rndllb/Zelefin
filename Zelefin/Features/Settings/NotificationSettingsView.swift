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
            } footer: {
                Text(permissionFooter)
            }

            Section {
                Toggle("New titles", isOn: $libraryAdds)
                    .disabled(!isEnabled)
            } footer: {
                Text("Zelefin checks this Jellyfin server for movies, shows, and episodes added after this device already knows the library. Signing out does not replay titles that were already there. Tapping a notification opens that title.")
            }

            if session.isAdministrator {
                Section {
                    Toggle("Streams started", isOn: $streams)
                    Toggle("Users online", isOn: $online)
                    Toggle("Scheduled tasks", isOn: $scheduledTasks)
                    if PluginSettings.isSeerrConfigured {
                        Toggle("Seerr requests", isOn: $requests)
                    }
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
        switch authorization {
        case .denied:
            "Notifications are off in iOS Settings. Turn them on for Zelefin to see banners on this device."
        case .notDetermined:
            "Zelefin asks iOS for permission when you turn this on. With the Zelefin Jellyfin plugin, alerts are push from your server. Without it, this device checks Jellyfin itself."
        case .authorized, .provisional, .ephemeral:
            "When the Zelefin plugin is on this Jellyfin server, alerts arrive even if the app stays closed. Otherwise Zelefin checks the server from this device, and iOS may wait until you open the app."
        @unknown default:
            "When the Zelefin plugin is on this Jellyfin server, alerts arrive even if the app stays closed. Otherwise Zelefin checks the server from this device, and iOS may wait until you open the app."
        }
    }

    private var adminFooter: String {
        if PluginSettings.isSeerrConfigured {
            return "You also see when someone starts playback, comes online on another device, a scheduled task starts, or someone requests a title in Seerr."
        }
        return "You also see when someone starts playback, comes online on another device, or a scheduled task starts. Sign in to Seerr under Plugins to be notified about requests."
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
