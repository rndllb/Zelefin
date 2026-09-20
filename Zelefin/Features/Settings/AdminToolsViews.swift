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
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                            if !entry.subtitle.isEmpty {
                                Text(entry.subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            if let date = entry.date {
                                Text(date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
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
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                    Section {
                        Button {
                            Task { await create() }
                        } label: {
                            if isCreating {
                                ProgressView()
                            } else {
                                Label("Create Backup", systemImage: "plus.circle")
                            }
                        }
                        .disabled(isCreating)
                    } footer: {
                        Text("A backup archives this server’s database and metadata. Restoring one restarts Jellyfin.")
                    }
                    Section("Archives") {
                        if backups.isEmpty {
                            Text("No backups on this server yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(backups) { backup in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(backup.fileName)
                                    HStack {
                                        if let date = backup.dateCreated {
                                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                        }
                                        if let version = backup.serverVersion, !version.isEmpty {
                                            Text("Jellyfin \(version)")
                                        }
                                    }
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    Button("Restore…", role: .destructive) {
                                        restoreTarget = backup
                                    }
                                    .font(.footnote)
                                }
                            }
                        }
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
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            Section("Sign-In") {
                TextField("Login disclaimer", text: $branding.loginDisclaimer, axis: .vertical)
                    .lineLimit(3...8)
                Toggle("Show splashscreen", isOn: $branding.splashscreenEnabled)
            }
            Section("Custom CSS") {
                TextField("CSS", text: $branding.customCSS, axis: .vertical)
                    .lineLimit(4...12)
                    .font(.footnote.monospaced())
            }
            Section("Splash Image") {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Upload Splashscreen", systemImage: "photo")
                }
                Button("Remove Custom Splashscreen", role: .destructive) {
                    Task { await deleteSplash() }
                }
            }
            Section {
                Button("Save") {
                    Task { await save() }
                }
                .disabled(isSaving)
            }
        }
        .zelefinSettingsChrome(title: "Branding")
        .task { await load() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
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
