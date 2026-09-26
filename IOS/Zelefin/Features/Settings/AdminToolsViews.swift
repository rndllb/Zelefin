import PhotosUI
import SwiftUI

struct ActivityLogView: View {
    @Environment(SessionStore.self) private var session
    @State private var entries: [ActivityLogItem] = []
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
                    description: Text(errorMessage ?? "This server has not logged any recent activity.")
                )
            } else {
                List {
                    if let errorMessage {
                        SettingsStatusText(text: errorMessage, isError: true)
                            .settingsLoginCard()
                            .settingsCardRow()
                    }
                    ForEach(entries) { entry in
                        SettingsStackedRow(
                            title: entry.title,
                            subtitle: entry.subtitle,
                            caption: entry.date?.formatted(date: .abbreviated, time: .shortened) ?? ""
                        )
                        .settingsLoginCard()
                        .settingsCardRow()
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await load(showProgress: false) }
            }
        }
        .zelefinSettingsChrome(title: "Activity Log")
        .task { await load() }
    }

    private func load(showProgress: Bool = true) async {
        guard let library = session.jellyfinLibrary else {
            isLoading = false
            errorMessage = "Sign in to see the activity log."
            return
        }
        if showProgress, entries.isEmpty { isLoading = true }
        do {
            entries = try await library.activityLog()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct ServerBackupsView: View {
    @Environment(SessionStore.self) private var session
    @State private var backups: [ServerBackup] = []
    @State private var isLoading = true
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var restoreTarget: ServerBackup?

    var body: some View {
        Group {
            if isLoading && backups.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if let errorMessage {
                        SettingsStatusText(text: errorMessage, isError: true)
                            .settingsLoginCard()
                            .settingsCardRow()
                    }
                    Section {
                        SettingsPrimaryButton(title: "Create Backup", isBusy: isCreating) {
                            Task { await create() }
                        }
                        .settingsCardRow()
                    } footer: {
                        Text("A backup archives this server’s database and metadata. Restoring one restarts Jellyfin.")
                    }
                    Section {
                        if backups.isEmpty {
                            SettingsStackedRow(title: "No backups on this server yet.")
                                .settingsLoginCard()
                                .settingsCardRow()
                        } else {
                            ForEach(backups) { backup in
                                VStack(alignment: .leading, spacing: 0) {
                                    SettingsStackedRow(
                                        title: backup.fileName,
                                        subtitle: [
                                            backup.dateCreated?.formatted(date: .abbreviated, time: .shortened),
                                            backup.serverVersion.flatMap { $0.isEmpty ? nil : "Jellyfin \($0)" }
                                        ].compactMap { $0 }.joined(separator: " · ")
                                    )
                                    SettingsSecondaryButton(title: "Restore…", role: .destructive) {
                                        restoreTarget = backup
                                    }
                                    .padding(.top, 16)
                                }
                                .settingsLoginCard()
                                .settingsCardRow()
                            }
                        }
                    } header: {
                        Text("Archives")
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await load(showProgress: false) }
            }
        }
        .zelefinSettingsChrome(title: "Backups")
        .task { await load() }
        .confirmationDialog(
            "Restore this backup?",
            isPresented: Binding(
                get: { restoreTarget != nil },
                set: { if !$0 { restoreTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore and Restart Server", role: .destructive) {
                guard let restoreTarget else { return }
                Task { await restore(restoreTarget) }
            }
            Button("Cancel", role: .cancel) { restoreTarget = nil }
        } message: {
            Text("Jellyfin will restart and replace the current database with this archive. This cannot be undone from the app.")
        }
    }

    private func load(showProgress: Bool = true) async {
        guard let library = session.jellyfinLibrary else {
            isLoading = false
            errorMessage = "Sign in as an administrator to manage backups."
            return
        }
        if showProgress, backups.isEmpty { isLoading = true }
        do {
            backups = try await library.serverBackups()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func create() async {
        guard let library = session.jellyfinLibrary else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            _ = try await library.createServerBackup()
            await load(showProgress: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore(_ backup: ServerBackup) async {
        restoreTarget = nil
        do {
            try await session.jellyfinLibrary?.restoreServerBackup(backup)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ServerBrandingView: View {
    @Environment(SessionStore.self) private var session
    @State private var branding = ServerBranding(loginDisclaimer: "", customCSS: "", splashscreenEnabled: true)
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        Form {
            Section {
                VStack(spacing: 14) {
                    SettingsHeroGlyph(systemImage: "paintbrush.fill")
                    Text("Branding")
                        .font(.title2.weight(.semibold))
                    SettingsChip(
                        icon: "play.tv.fill",
                        leading: "Jellyfin",
                        trailing: serverLabel
                    )
                }
                .frame(maxWidth: .infinity)
                .settingsHeroRow()
            }

            if let errorMessage {
                Section {
                    SettingsStatusText(text: errorMessage, isError: true)
                        .settingsLoginCard()
                        .settingsCardRow()
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsLabeledField(label: "Login disclaimer", systemImage: "text.quote") {
                        TextField("Shown on the sign-in screen", text: $branding.loginDisclaimer, axis: .vertical)
                            .lineLimit(3...8)
                    }
                    SettingsCardDivider()
                    Toggle("Show splashscreen", isOn: $branding.splashscreenEnabled)
                        .tint(AccentPreferences.current)
                        .font(.body.weight(.semibold))
                }
                .settingsLoginCard()
                .settingsCardRow()
            } header: {
                Text("Sign-In")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsFieldLabel(title: "CSS")
                    TextField("CSS", text: $branding.customCSS, axis: .vertical)
                        .lineLimit(4...12)
                        .font(.footnote.monospaced())
                        .foregroundStyle(LoginPalette.fieldValue)
                }
                .settingsLoginCard()
                .settingsCardRow()
            } header: {
                Text("Custom CSS")
            }

            Section {
                VStack(alignment: .leading, spacing: 0) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        HStack {
                            Spacer(minLength: 0)
                            Text("Upload Splashscreen")
                                .font(.caption.weight(.bold))
                                .tracking(0.8)
                            Spacer(minLength: 0)
                        }
                        .modifier(LoginActionButtonStyle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Upload Splashscreen")
                    SettingsSecondaryButton(title: "Remove Custom Splashscreen", role: .destructive) {
                        Task { await deleteSplash() }
                    }
                    .padding(.top, 10)
                }
                .settingsLoginCard()
                .settingsCardRow()
            } header: {
                Text("Splash Image")
            }

            Section {
                SettingsPrimaryButton(title: "Save Branding", isBusy: isSaving, enabled: !isLoading) {
                    Task { await save() }
                }
                .settingsCardRow()
            }
        }
        .zelefinSettingsChrome(title: "Branding")
        .task { await load() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    private var serverLabel: String {
        let name = session.session?.displayServer ?? session.serverName ?? ""
        return name.isEmpty ? "This server" : name
    }

    private func load() async {
        guard let library = session.jellyfinLibrary else {
            isLoading = false
            errorMessage = "Sign in as an administrator to edit branding."
            return
        }
        do {
            branding = try await library.serverBranding()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func save() async {
        guard let library = session.jellyfinLibrary else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await library.updateServerBranding(branding)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func upload(_ item: PhotosPickerItem) async {
        pickerItem = nil
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            errorMessage = "Could not read that image."
            return
        }
        do {
            try await session.jellyfinLibrary?.uploadSplashscreen(data)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSplash() async {
        do {
            try await session.jellyfinLibrary?.deleteSplashscreen()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
