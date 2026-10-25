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
                    }
                    ForEach(entries) { entry in
                        SettingsStackedRow(
                            title: entry.title,
                            subtitle: entry.subtitle,
                            caption: entry.date?.formatted(date: .abbreviated, time: .shortened) ?? ""
                        )
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
        guard let library = session.serverAdmin else {
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
                    }
                    Section {
                        SettingsPrimaryButton(title: "Create Backup", isBusy: isCreating) {
                            Task { await create() }
                        }
                    } footer: {
                        Text("A backup archives this server’s database and metadata. Restoring one restarts Jellyfin.")
                    }
                    .zelefinRowBackground()
                    Section {
                        if backups.isEmpty {
                            SettingsStackedRow(title: "No backups on this server yet.")
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
                            }
                        }
                    } header: {
                        Text("Archives")
                    }
                    .zelefinRowBackground()
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
                LabeledContent("Server", value: serverLabel)
            }
            .zelefinRowBackground()

            if let errorMessage {
                Section {
                    SettingsStatusText(text: errorMessage, isError: true)
                }
                .zelefinRowBackground()
            }

            Section {
                TextField("Login Disclaimer", text: $branding.loginDisclaimer, axis: .vertical)
                    .lineLimit(3...8)
                if canEdit {
                    Toggle("Show Splashscreen", isOn: $branding.splashscreenEnabled)
                }
            } header: {
                Text("Sign-In")
            } footer: {
                if !canEdit {
                    Text("Emby's branding is read-only here. Change it in Emby's web dashboard.")
                }
            }
            .zelefinRowBackground()
            .disabled(!canEdit)

            Section {
                TextField("CSS", text: $branding.customCSS, axis: .vertical)
                    .lineLimit(4...12)
                    .font(.footnote.monospaced())
            } header: {
                Text("Custom CSS")
            }
            .zelefinRowBackground()
            .disabled(!canEdit)

            if canEdit {
                Section {
                    PhotosPicker("Upload Splashscreen", selection: $pickerItem, matching: .images)
                    Button("Remove Custom Splashscreen", role: .destructive) {
                        Task { await deleteSplash() }
                    }
                } header: {
                    Text("Splash Image")
                }
                .zelefinRowBackground()

                Section {
                    Button("Save Branding") {
                        Task { await save() }
                    }
                    .disabled(isSaving || isLoading)
                }
                .zelefinRowBackground()
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

    private var canEdit: Bool {
        session.serverAdmin?.canEditBranding ?? false
    }

    private func load() async {
        guard let library = session.serverAdmin else {
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
        guard let library = session.serverAdmin else { return }
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
            try await session.serverAdmin?.uploadSplashscreen(data)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSplash() async {
        do {
            try await session.serverAdmin?.deleteSplashscreen()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
