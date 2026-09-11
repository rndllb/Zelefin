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
                Text("Zelefin checks this Jellyfin server for newly added movies, shows, and episodes. Tapping a notification opens that title. No Jellyfin notification plugin is required.")
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
            "Zelefin asks iOS for permission when you turn this on. Alerts are created on this device by checking the server; they are not push from Jellyfin."
        case .authorized, .provisional, .ephemeral:
            "Alerts are created on this device by checking the server. iOS may also refresh in the background when it can."
        @unknown default:
            "Alerts are created on this device by checking the server. iOS may also refresh in the background when it can."
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
            }
        }
        LibraryAlertMonitor.shared.stop()
        if enabled, session.isSignedIn, !session.isReviewDemo {
            LibraryAlertMonitor.shared.start(session: session)
        }
    }
}
