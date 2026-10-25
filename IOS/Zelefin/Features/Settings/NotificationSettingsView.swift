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
            if session.isEmbyServer {
                WebhookAlertSections(setup: .emby(session))
            } else if session.isSiloServer {
                WebhookAlertSections(setup: .silo(session))
            } else if session.companionAvailable {
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
            if session.isEmbyServer || session.isSiloServer || (enabled && !session.companionAvailable) { return }
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

/// What one server type tells the shared webhook alert screen.
struct WebhookAlertSetup {
    struct Category: Identifiable, Hashable {
        let id: String
        let title: String
    }

    struct Saved {
        var categoryIDs: Set<String>
        /// Set when only an administrator can add this phone's address on the server.
        var adminAddress: String?
    }

    enum Outcome {
        case on
        case needsAdmin(address: String)
    }

    var unavailableTitle: String
    var unavailableFooter: String
    var footer: String
    var adminFooter: String = ""
    var defaultCategories: Set<String>
    var isAvailable: () async -> Bool
    var categories: () async -> [Category]
    var saved: () -> Saved?
    var enable: (Set<String>) async throws -> Outcome
    var disable: () async -> Void
    var sendTest: () async -> String?
}

extension WebhookAlertSetup {
    /// Emby cannot run the Zelefin plugin. Its Webhooks notifier posts to an address Zelefin's push
    /// service gives this iPhone, and that address goes into the signed-in user's notifications in Emby.
    @MainActor
    static func emby(_ session: SessionStore) -> WebhookAlertSetup {
        WebhookAlertSetup(
            unavailableTitle: "Emby Webhooks",
            unavailableFooter: "Lock-screen alerts on Emby use its Webhooks notifier, which comes with Emby Premiere. When this server has it, turn on Notifications here and Zelefin sets it up.",
            footer: "Emby sends these through Zelefin's push service to this iPhone, also while Zelefin is closed. It only sends events this account is allowed to see.",
            adminFooter: "This server only lets administrators add notifications. In Emby, an admin opens your user's Settings → Notifications, adds Webhooks, pastes this address, and picks the events.",
            defaultCategories: EmbyAlertCategory.defaultIDs,
            isAvailable: { session.embyWebhooksAvailable },
            categories: {
                let offered = await session.embyLibrary?.availableAlertEvents() ?? []
                return EmbyAlertCategory.all
                    .filter { offered.isEmpty || $0.events.contains(where: offered.contains) }
                    .map { Category(id: $0.id, title: $0.title) }
            },
            saved: {
                session.embyAlertRegistration.map {
                    Saved(categoryIDs: Set($0.categoryIDs), adminAddress: $0.entryID == nil ? $0.url : nil)
                }
            },
            enable: { ids in
                do {
                    try await session.enableEmbyAlerts(categoryIDs: ids)
                    return .on
                } catch EmbyAlertError.notAllowed(let url) {
                    return .needsAdmin(address: url)
                }
            },
            disable: { await session.disableEmbyAlerts() },
            sendTest: { await session.sendEmbyTestAlert() }
        )
    }

    /// Silo's own push only reaches the Silo app, so its alerts come through a personal webhook on the
    /// active profile, which posts to an address Zelefin's push service gives this iPhone.
    @MainActor
    static func silo(_ session: SessionStore) -> WebhookAlertSetup {
        WebhookAlertSetup(
            unavailableTitle: "Silo Webhooks",
            unavailableFooter: session.hasSiloLink
                ? "This Silo server has personal webhooks turned off. An administrator can turn them on in Silo's notification settings."
                : "Notifications on Silo need your Silo account. Sign out and sign in with your Silo account to turn them on.",
            footer: "Silo alerts this iPhone when a show this profile follows gets a new episode, or a request changes. They arrive through Zelefin's push service, also while Zelefin is closed.",
            defaultCategories: SiloAlertCategory.defaultIDs,
            isAvailable: { await session.siloPersonalWebhooksAvailable() },
            categories: { SiloAlertCategory.all.map { Category(id: $0.id, title: $0.title) } },
            saved: { session.siloAlertRegistration.map { Saved(categoryIDs: Set($0.categoryIDs)) } },
            enable: { ids in
                try await session.enableSiloAlerts(categoryIDs: ids)
                return .on
            },
            disable: { await session.disableSiloAlerts() },
            sendTest: { await session.sendSiloTestAlert() }
        )
    }
}

/// Lock-screen alerts for servers that post webhooks instead of running the Zelefin plugin.
private struct WebhookAlertSections: View {
    let setup: WebhookAlertSetup
    @State private var isAvailable: Bool?
    @State private var isOn = false
    @State private var selected: Set<String> = []
    @State private var categories: [WebhookAlertSetup.Category] = []
    @State private var isWorking = false
    @State private var status: String?
    @State private var statusIsError = false
    @State private var adminAddress: String?

    var body: some View {
        Group {
            if isAvailable == false {
                Section {
                    LabeledContent(setup.unavailableTitle) {
                        Text("Not on this server").foregroundStyle(.red)
                    }
                } footer: {
                    Text(setup.unavailableFooter)
                }
                .zelefinRowBackground()
            } else if isAvailable == true {
                availableSections
            } else {
                Section { ProgressView() }.zelefinRowBackground()
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var availableSections: some View {
        Section {
            Toggle("Notifications", isOn: Binding(get: { isOn }, set: { next in Task { await setOn(next) } }))
                .disabled(isWorking)
            if isOn, adminAddress == nil {
                Button(isWorking ? "Sending…" : "Send Test Alert") {
                    Task { await sendTest() }
                }
                .disabled(isWorking)
            }
            if let status {
                SettingsStatusText(text: status, isError: statusIsError)
            }
        } footer: {
            Text(setup.footer)
        }
        .zelefinRowBackground()

        if let adminAddress {
            Section {
                Text(adminAddress)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                Button("Copy Address") { UIPasteboard.general.string = adminAddress }
            } header: {
                Text("Ask an Administrator")
            } footer: {
                Text(setup.adminFooter)
            }
            .zelefinRowBackground()
        }

        if isOn, adminAddress == nil, !categories.isEmpty {
            Section {
                ForEach(categories) { category in
                    Toggle(category.title, isOn: Binding(
                        get: { selected.contains(category.id) },
                        set: { next in Task { await setCategory(category.id, on: next) } }
                    ))
                    .disabled(isWorking)
                }
            } header: {
                Text("Alert Me About")
            }
            .zelefinRowBackground()
        }
    }

    private func load() async {
        guard isAvailable == nil else { return }
        selected = setup.defaultCategories
        if let saved = setup.saved() {
            isOn = true
            selected = saved.categoryIDs
            adminAddress = saved.adminAddress
        }
        isAvailable = await setup.isAvailable()
        categories = await setup.categories()
    }

    private func setOn(_ next: Bool) async {
        isWorking = true
        status = nil
        defer { isWorking = false }
        guard next else {
            await setup.disable()
            isOn = false
            adminAddress = nil
            return
        }
        _ = await LibraryAlertCenter.shared.requestAuthorization()
        guard await PushNotificationCenter.requestPermissionIfNeeded() else {
            show("Notifications are off in iOS Settings. Turn them on for Zelefin, then try again.", error: true)
            return
        }
        await waitForPushToken()
        isOn = true
        await save()
    }

    private func setCategory(_ id: String, on next: Bool) async {
        if next { selected.insert(id) } else { selected.remove(id) }
        isWorking = true
        defer { isWorking = false }
        await save()
    }

    private func save() async {
        do {
            switch try await setup.enable(selected) {
            case .on:
                adminAddress = nil
            case .needsAdmin(let address):
                adminAddress = address
            }
            show(nil, error: false)
        } catch {
            isOn = setup.saved() != nil
            show(error.localizedDescription, error: true)
        }
    }

    private func sendTest() async {
        isWorking = true
        defer { isWorking = false }
        let failure = await setup.sendTest()
        show(failure ?? "Sent. It should arrive in a few seconds.", error: failure != nil)
    }

    /// APNs hands the token over a moment after registering, the first time on this iPhone.
    private func waitForPushToken() async {
        for _ in 0 ..< 20 where PushNotificationCenter.storedToken == nil {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func show(_ message: String?, error: Bool) {
        status = message
        statusIsError = error
    }
}
