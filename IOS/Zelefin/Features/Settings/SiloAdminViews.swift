import SwiftUI
import UIKit

struct SiloUsersView: View {
    @Environment(SessionStore.self) private var session
    @State private var users: [SiloAdminUser] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showsCreate = false

    var body: some View {
        Group {
            if isLoading && users.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if users.isEmpty {
                ContentUnavailableView(
                    "No Accounts",
                    systemImage: "person.2",
                    description: Text(errorMessage ?? "This Silo server did not return any accounts.")
                )
            } else {
                List {
                    if let errorMessage {
                        Section {
                            SettingsStatusText(text: errorMessage, isError: true)
                        }
                    }
                    Section {
                        ForEach(users) { account in
                            NavigationLink {
                                SiloUserEditorView(account: account) {
                                    await reload()
                                }
                            } label: {
                                SettingsPersonRow(
                                    name: account.username,
                                    subtitle: account.subtitle,
                                    showsChevron: true
                                )
                            }
                        }
                    }
                }
                .refreshable { await reload(showProgress: false) }
            }
        }
        .zelefinSettingsChrome(title: "Accounts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add", systemImage: "plus") { showsCreate = true }
            }
        }
        .sheet(isPresented: $showsCreate) {
            NavigationStack {
                SiloCreateUserView {
                    showsCreate = false
                    await reload()
                }
            }
        }
        .task { await reload() }
    }

    private func reload(showProgress: Bool = true) async {
        if showProgress, users.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            users = try await session.siloAPI?.adminUsers() ?? []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SiloCreateUserView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    var onCreated: () async -> Void

    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isAdmin = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsLabeledField(label: "Username", systemImage: "person.fill") {
                        TextField("Username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    SettingsCardDivider()
                    SettingsLabeledField(label: "Email", systemImage: "envelope.fill") {
                        TextField("Email", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                    }
                    SettingsCardDivider()
                    SettingsLabeledField(label: "Password", systemImage: "lock.fill") {
                        SecureField("Password", text: $password)
                            .textContentType(.newPassword)
                    }
                    SettingsCardDivider()
                    Toggle("Administrator", isOn: $isAdmin)
                        .tint(AccentPreferences.current)
                        .font(.body.weight(.medium))
                }
            } footer: {
                Text("Silo requires at least 8 characters for a new password. A default household profile is created for this account.")
            }
            Section {
                SettingsPrimaryButton(title: "Create Account", isBusy: isSaving, enabled: canSave) {
                    Task { await save() }
                }
            }
            if let errorMessage {
                Section {
                    SettingsStatusText(text: errorMessage, isError: true)
                }
            }
        }
        .zelefinSettingsChrome(title: "Add Account")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private var canSave: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && email.contains("@")
            && password.count >= 8
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            guard let api = session.siloAPI else {
                throw ZelefinError.missingUser
            }
            try await api.createAdminUser(
                SiloAdminUserCreateRequest(
                    username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password,
                    role: isAdmin ? "admin" : "user",
                    createDefaultProfile: true
                )
            )
            await onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SiloUserEditorView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State var account: SiloAdminUser
    var onChange: () async -> Void

    @State private var isAdmin: Bool
    @State private var isEnabled: Bool
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var status: String?
    @State private var statusIsError = false
    @State private var isSaving = false
    @State private var showsDeleteConfirm = false

    init(account: SiloAdminUser, onChange: @escaping () async -> Void) {
        self.account = account
        self.onChange = onChange
        _isAdmin = State(initialValue: account.isAdmin)
        _isEnabled = State(initialValue: account.isEnabled)
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 14) {
                    SettingsHeroGlyph(systemImage: "person.fill")
                    Text(account.username)
                        .font(.title2.weight(.semibold))
                    SettingsChip(
                        icon: isAdmin ? "checkmark.shield.fill" : "person.fill",
                        leading: isEnabled ? (isAdmin ? "Administrator" : "User") : "Disabled",
                        trailing: account.email
                    )
                }
                .frame(maxWidth: .infinity)
                .settingsHeroRow()
            }

            Section {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsInfoRow(label: "Username", value: account.username)
                    if let email = account.email, !email.isEmpty {
                        SettingsCardDivider()
                        SettingsInfoRow(label: "Email", value: email)
                    }
                    SettingsCardDivider()
                    Toggle("Administrator", isOn: $isAdmin)
                        .tint(AccentPreferences.current)
                        .font(.body.weight(.medium))
                    SettingsCardDivider()
                    Toggle("Enabled", isOn: $isEnabled)
                        .tint(AccentPreferences.current)
                        .font(.body.weight(.medium))
                    SettingsPrimaryButton(title: "Save Access", isBusy: isSaving) {
                        Task { await saveAccess() }
                    }
                    .padding(.top, 16)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsLabeledField(label: "New", systemImage: "lock.fill") {
                        SecureField("New", text: $newPassword)
                            .textContentType(.newPassword)
                    }
                    SettingsCardDivider()
                    SettingsLabeledField(label: "Confirm", systemImage: "lock.fill") {
                        SecureField("Confirm", text: $confirmPassword)
                            .textContentType(.newPassword)
                    }
                    if !confirmPassword.isEmpty && newPassword != confirmPassword {
                        Text("The new passwords do not match.")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(LoginPalette.failure)
                            .padding(.top, 12)
                    }
                    SettingsPrimaryButton(
                        title: "Set Password",
                        isBusy: isSaving,
                        enabled: newPassword.count >= 8 && newPassword == confirmPassword
                    ) {
                        Task { await savePassword() }
                    }
                    .padding(.top, 16)
                }
            } footer: {
                Text("At least 8 characters. This replaces the password for \(account.username).")
            }

            if let status {
                Section {
                    SettingsStatusText(text: status, isError: statusIsError)
                }
            }

            Section {
                SettingsSecondaryButton(title: "Delete Account", role: .destructive, enabled: !isSaving) {
                    showsDeleteConfirm = true
                }
            }
        }
        .zelefinSettingsChrome(title: account.username)
        .confirmationDialog(
            "Delete \(account.username)?",
            isPresented: $showsDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task { await deleteUser() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the account and its household profiles from this Silo server.")
        }
    }

    private func saveAccess() async {
        isSaving = true
        status = nil
        defer { isSaving = false }
        do {
            guard let api = session.siloAPI else {
                throw ZelefinError.missingUser
            }
            try await api.updateAdminUser(
                id: account.id,
                SiloAdminUserUpdateRequest(
                    role: isAdmin ? "admin" : "user",
                    enabled: isEnabled
                )
            )
            statusIsError = false
            status = "Access updated."
            await onChange()
        } catch {
            statusIsError = true
            status = error.localizedDescription
        }
    }

    private func savePassword() async {
        guard newPassword == confirmPassword else {
            statusIsError = true
            status = "The new passwords do not match."
            return
        }
        isSaving = true
        status = nil
        defer { isSaving = false }
        do {
            guard let api = session.siloAPI else {
                throw ZelefinError.missingUser
            }
            try await api.updateAdminUser(
                id: account.id,
                SiloAdminUserUpdateRequest(password: newPassword)
            )
            newPassword = ""
            confirmPassword = ""
            statusIsError = false
            status = "Password updated."
        } catch {
            statusIsError = true
            status = error.localizedDescription
        }
    }

    private func deleteUser() async {
        isSaving = true
        status = nil
        defer { isSaving = false }
        do {
            guard let api = session.siloAPI else {
                throw ZelefinError.missingUser
            }
            try await api.deleteAdminUser(id: account.id)
            await onChange()
            dismiss()
        } catch {
            statusIsError = true
            status = error.localizedDescription
        }
    }
}

struct SiloTasksView: View {
    @Environment(SessionStore.self) private var session
    @State private var tasks: [SiloAdminTask] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var busyIDs: Set<String> = []

    var body: some View {
        Group {
            if isLoading && tasks.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tasks.isEmpty {
                ContentUnavailableView(
                    "No Tasks",
                    systemImage: "clock.arrow.2.circlepath",
                    description: Text(errorMessage ?? "This Silo server did not return any administrator tasks.")
                )
            } else {
                List {
                    if let errorMessage {
                        SettingsStatusText(text: errorMessage, isError: true)
                    }
                    ForEach(tasks) { task in
                        VStack(alignment: .leading, spacing: 0) {
                            SettingsStackedRow(
                                title: task.displayName,
                                subtitle: task.description ?? "",
                                caption: task.state?.capitalized ?? "Idle"
                            )
                            if busyIDs.contains(task.id) {
                                ProgressView()
                                    .padding(.top, 16)
                            } else if task.isRunning {
                                SettingsSecondaryButton(title: "Cancel") {
                                    Task { await cancel(task) }
                                }
                                .padding(.top, 16)
                            } else {
                                SettingsPrimaryButton(title: "Run") {
                                    Task { await run(task) }
                                }
                                .padding(.top, 16)
                            }
                        }
                    }
                }
                .refreshable { await load(showProgress: false) }
            }
        }
        .zelefinSettingsChrome(title: "Scheduled Tasks")
        .task { await load() }
    }

    private func load(showProgress: Bool = true) async {
        if showProgress, tasks.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            tasks = try await session.siloAPI?.adminTasks() ?? []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func run(_ task: SiloAdminTask) async {
        busyIDs.insert(task.id)
        defer { busyIDs.remove(task.id) }
        do {
            guard let api = session.siloAPI else {
                throw ZelefinError.missingUser
            }
            try await api.runAdminTask(key: task.id)
            await load(showProgress: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancel(_ task: SiloAdminTask) async {
        busyIDs.insert(task.id)
        defer { busyIDs.remove(task.id) }
        do {
            guard let api = session.siloAPI else {
                throw ZelefinError.missingUser
            }
            try await api.cancelAdminTask(key: task.id)
            await load(showProgress: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SiloDevicesView: View {
    @Environment(SessionStore.self) private var session
    @State private var devices: [SiloAdminDevice] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && devices.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if devices.isEmpty {
                ContentUnavailableView(
                    "No Devices",
                    systemImage: "iphone",
                    description: Text(errorMessage ?? "No devices have checked in on this Silo server.")
                )
            } else {
                List {
                    if let errorMessage {
                        SettingsStatusText(text: errorMessage, isError: true)
                    }
                    ForEach(devices) { device in
                        SettingsStackedRow(
                            title: device.displayName,
                            subtitle: [device.username, device.devicePlatform]
                                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                                .joined(separator: " · "),
                            caption: device.lastUpdated?.formatted(date: .abbreviated, time: .shortened) ?? ""
                        )
                    }
                }
                .refreshable { await load(showProgress: false) }
            }
        }
        .zelefinSettingsChrome(title: "Devices")
        .task { await load() }
    }

    private func load(showProgress: Bool = true) async {
        if showProgress, devices.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            devices = try await session.siloAPI?.adminDevices() ?? []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SiloAuditLogView: View {
    @Environment(SessionStore.self) private var session
    @State private var entries: [SiloAuditLog] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && entries.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "list.bullet.rectangle",
                    description: Text(errorMessage ?? "This Silo server has not logged recent administrator activity.")
                )
            } else {
                List {
                    if let errorMessage {
                        SettingsStatusText(text: errorMessage, isError: true)
                    }
                    ForEach(entries) { entry in
                        SettingsStackedRow(
                            title: entry.title,
                            subtitle: [
                                entry.statusCode.map(String.init),
                                entry.clientIP
                            ].compactMap { $0 }.joined(separator: " · "),
                            caption: entry.timestamp?.formatted(date: .abbreviated, time: .shortened) ?? ""
                        )
                    }
                }
                .refreshable { await load(showProgress: false) }
            }
        }
        .zelefinSettingsChrome(title: "Activity Log")
        .task { await load() }
    }

    private func load(showProgress: Bool = true) async {
        if showProgress, entries.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            entries = try await session.siloAPI?.adminAuditLogs() ?? []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SiloLibrariesAdminView: View {
    @Environment(SessionStore.self) private var session
    @State private var libraries: [SiloAdminLibrary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var busyIDs: Set<String> = []
    @State private var isScanningAll = false

    var body: some View {
        Group {
            if isLoading && libraries.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if libraries.isEmpty {
                ContentUnavailableView(
                    "No Libraries",
                    systemImage: "rectangle.stack",
                    description: Text(errorMessage ?? "This Silo server did not return any libraries.")
                )
            } else {
                List {
                    if let errorMessage {
                        SettingsStatusText(text: errorMessage, isError: true)
                    }
                    ForEach(libraries) { library in
                        VStack(alignment: .leading, spacing: 0) {
                            SettingsStackedRow(title: library.name, subtitle: library.subtitle)
                            if busyIDs.contains(library.id) {
                                ProgressView()
                                    .padding(.top, 16)
                            } else {
                                SettingsPrimaryButton(title: "Scan") {
                                    Task { await scan(library) }
                                }
                                .padding(.top, 16)
                            }
                        }
                    }
                }
                .refreshable { await load(showProgress: false) }
            }
        }
        .zelefinSettingsChrome(title: "Libraries")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isScanningAll {
                    ProgressView()
                } else {
                    Button("Scan All") {
                        Task { await scanAll() }
                    }
                    .disabled(libraries.isEmpty)
                }
            }
        }
        .task { await load() }
    }

    private func load(showProgress: Bool = true) async {
        if showProgress, libraries.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            libraries = try await session.siloAPI?.adminLibraries() ?? []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scan(_ library: SiloAdminLibrary) async {
        busyIDs.insert(library.id)
        defer { busyIDs.remove(library.id) }
        do {
            guard let api = session.siloAPI else { throw ZelefinError.missingUser }
            try await api.refreshLibraryMetadata(libraryID: library.id, full: false)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scanAll() async {
        isScanningAll = true
        defer { isScanningAll = false }
        do {
            try await session.library?.scanLibraries()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SiloInvitationsView: View {
    @Environment(SessionStore.self) private var session
    @State private var invitations: [SiloAdminInvitation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var status: String?
    @State private var showsCreate = false
    @State private var busyIDs: Set<String> = []

    var body: some View {
        Group {
            if isLoading && invitations.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if invitations.isEmpty {
                ContentUnavailableView(
                    "No Invitations",
                    systemImage: "envelope.badge",
                    description: Text(errorMessage ?? "Invite someone with an email address to join this Silo server.")
                )
            } else {
                List {
                    if let errorMessage {
                        SettingsStatusText(text: errorMessage, isError: true)
                    }
                    if let status {
                        SettingsStatusText(text: status)
                    }
                    ForEach(invitations) { invite in
                        VStack(alignment: .leading, spacing: 0) {
                            SettingsStackedRow(title: invite.email, subtitle: invite.subtitle)
                            if invite.isPending {
                                HStack(spacing: 10) {
                                    SettingsPrimaryButton(title: "Resend", enabled: !busyIDs.contains(invite.id)) {
                                        Task { await resend(invite) }
                                    }
                                    SettingsSecondaryButton(title: "Revoke", role: .destructive, enabled: !busyIDs.contains(invite.id)) {
                                        Task { await revoke(invite) }
                                    }
                                }
                                .padding(.top, 16)
                            }
                        }
                    }
                }
                .refreshable { await load(showProgress: false) }
            }
        }
        .zelefinSettingsChrome(title: "Invitations")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Invite", systemImage: "plus") { showsCreate = true }
            }
        }
        .sheet(isPresented: $showsCreate) {
            NavigationStack {
                SiloCreateInvitationView {
                    await load(showProgress: false)
                }
            }
        }
        .task { await load() }
    }

    private func load(showProgress: Bool = true) async {
        if showProgress, invitations.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            invitations = try await session.siloAPI?.adminInvitations() ?? []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resend(_ invite: SiloAdminInvitation) async {
        busyIDs.insert(invite.id)
        defer { busyIDs.remove(invite.id) }
        do {
            guard let api = session.siloAPI else { throw ZelefinError.missingUser }
            let delivery = try await api.resendInvitation(id: invite.id)
            copyClaim(delivery)
            await load(showProgress: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func revoke(_ invite: SiloAdminInvitation) async {
        busyIDs.insert(invite.id)
        defer { busyIDs.remove(invite.id) }
        do {
            guard let api = session.siloAPI else { throw ZelefinError.missingUser }
            try await api.revokeInvitation(id: invite.id)
            await load(showProgress: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func copyClaim(_ delivery: SiloInvitationDelivery) {
        if let url = delivery.claimURL {
            UIPasteboard.general.string = url.absoluteString
            status = "Invite link copied."
        } else if let state = delivery.deliveryStatus, !state.isEmpty {
            status = "Invite \(state.replacingOccurrences(of: "_", with: " "))."
        }
    }
}

struct SiloCreateInvitationView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    var onCreated: () async -> Void

    @State private var email = ""
    @State private var isAdmin = false
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var claimURL: URL?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsLabeledField(label: "Email", systemImage: "envelope.fill") {
                        TextField("Email", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                    }
                    SettingsCardDivider()
                    Toggle("Administrator", isOn: $isAdmin)
                        .tint(AccentPreferences.current)
                        .font(.body.weight(.medium))
                    SettingsCardDivider()
                    SettingsLabeledField(label: "Note", systemImage: "text.quote") {
                        TextField("Note (optional)", text: $note)
                    }
                }
            } footer: {
                Text("Silo emails the invite when mail is configured. The claim link is also copied so you can send it yourself.")
            }
            if let claimURL {
                Section {
                    VStack(alignment: .leading, spacing: 0) {
                        SettingsInfoRow(label: "Claim link", value: claimURL.absoluteString)
                        SettingsPrimaryButton(title: "Copy Link") {
                            UIPasteboard.general.string = claimURL.absoluteString
                        }
                        .padding(.top, 16)
                    }
                }
            }
            Section {
                SettingsPrimaryButton(title: "Send Invite", isBusy: isSaving, enabled: email.contains("@")) {
                    Task { await save() }
                }
            }
            if let errorMessage {
                Section {
                    SettingsStatusText(text: errorMessage, isError: true)
                }
            }
        }
        .zelefinSettingsChrome(title: "Invite")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            guard let api = session.siloAPI else { throw ZelefinError.missingUser }
            let delivery = try await api.createInvitation(
                SiloInvitationCreateRequest(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    role: isAdmin ? "admin" : "user",
                    note: {
                        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? nil : trimmed
                    }(),
                    createProfile: true,
                    showTour: true
                )
            )
            if let url = delivery.claimURL {
                claimURL = url
                UIPasteboard.general.string = url.absoluteString
                await onCreated()
            } else {
                await onCreated()
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SiloSessionsView: View {
    @Environment(SessionStore.self) private var session
    @State private var sessions: [SiloAdminSession] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var busyIDs: Set<String> = []

    var body: some View {
        Group {
            if isLoading && sessions.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sessions.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "play.tv",
                    description: Text(errorMessage ?? "Nobody is playing anything on this Silo server right now.")
                )
            } else {
                List {
                    if let errorMessage {
                        Section {
                            SettingsStatusText(text: errorMessage, isError: true)
                        }
                    }
                    Section {
                        ForEach(sessions) { playback in
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(alignment: .top, spacing: 14) {
                                    Image(systemName: "play.rectangle.fill")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(LoginPalette.iconTint)
                                        .frame(width: 48, height: 48)
                                        .background(Color.white.opacity(0.08))
                                        .clipShape(Circle())
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(playback.title)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(LoginPalette.primaryText)
                                        if !playback.subtitle.isEmpty {
                                            Text(playback.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(LoginPalette.secondaryText)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                }
                                if busyIDs.contains(playback.id) {
                                    ProgressView()
                                        .tint(LoginPalette.actionLabel)
                                        .padding(.top, 16)
                                } else {
                                    SettingsSecondaryButton(title: "Stop", role: .destructive) {
                                        Task { await stop(playback) }
                                    }
                                    .padding(.top, 16)
                                }
                            }
                        }
                    }
                }
                .refreshable { await load(showProgress: false) }
            }
        }
        .zelefinSettingsChrome(title: "Sessions")
        .task { await load() }
    }

    private func load(showProgress: Bool = true) async {
        if showProgress, sessions.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            sessions = try await session.siloAPI?.adminSessions() ?? []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stop(_ playback: SiloAdminSession) async {
        busyIDs.insert(playback.id)
        defer { busyIDs.remove(playback.id) }
        do {
            guard let api = session.siloAPI else { throw ZelefinError.missingUser }
            try await api.terminateAdminSession(id: playback.id)
            await load(showProgress: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SiloNodesView: View {
    @Environment(SessionStore.self) private var session
    @State private var nodes: [SiloAdminNode] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var busyIDs: Set<String> = []

    var body: some View {
        Group {
            if isLoading && nodes.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if nodes.isEmpty {
                ContentUnavailableView(
                    "No Nodes",
                    systemImage: "server.rack",
                    description: Text(errorMessage ?? "This Silo server is not using extra stream or transcode nodes.")
                )
            } else {
                List {
                    if let errorMessage {
                        SettingsStatusText(text: errorMessage, isError: true)
                    }
                    ForEach(nodes) { node in
                        VStack(alignment: .leading, spacing: 0) {
                            SettingsStackedRow(
                                title: node.name,
                                subtitle: node.subtitle,
                                caption: node.url ?? ""
                            )
                            if busyIDs.contains(node.id) {
                                ProgressView()
                                    .padding(.top, 16)
                            } else {
                                SettingsPrimaryButton(title: "Check") {
                                    Task { await check(node) }
                                }
                                .padding(.top, 16)
                            }
                        }
                    }
                }
                .refreshable { await load(showProgress: false) }
            }
        }
        .zelefinSettingsChrome(title: "Nodes")
        .task { await load() }
    }

    private func load(showProgress: Bool = true) async {
        if showProgress, nodes.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            nodes = try await session.siloAPI?.adminNodes() ?? []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func check(_ node: SiloAdminNode) async {
        busyIDs.insert(node.id)
        defer { busyIDs.remove(node.id) }
        do {
            guard let api = session.siloAPI else { throw ZelefinError.missingUser }
            try await api.checkAdminNode(id: node.id)
            await load(showProgress: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SiloOperationalLogView: View {
    @Environment(SessionStore.self) private var session
    @State private var entries: [SiloOperationalLog] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && entries.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                ContentUnavailableView(
                    "No Logs",
                    systemImage: "scroll",
                    description: Text(errorMessage ?? "This Silo server did not return operational logs.")
                )
            } else {
                List {
                    if let errorMessage {
                        SettingsStatusText(text: errorMessage, isError: true)
                    }
                    ForEach(entries) { entry in
                        SettingsStackedRow(
                            title: entry.title,
                            subtitle: [entry.level, entry.component]
                                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                                .joined(separator: " · "),
                            caption: entry.timestamp?.formatted(date: .abbreviated, time: .shortened) ?? ""
                        )
                    }
                }
                .refreshable { await load(showProgress: false) }
            }
        }
        .zelefinSettingsChrome(title: "Server Logs")
        .task { await load() }
    }

    private func load(showProgress: Bool = true) async {
        if showProgress, entries.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            entries = try await session.siloAPI?.adminOperationalLogs() ?? []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
