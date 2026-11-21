import SwiftUI

struct SyncPlayView: View {
    @Environment(SessionStore.self) private var session
    @State private var groups: [SyncPlayGroupInfo] = []
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var newName = ""
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    SettingsStatusText(text: errorMessage, isError: true)
                }
                .zelefinRowBackground()
            }
            if let name = session.syncPlayGroupName, session.syncPlayGroupID != nil {
                Section {
                    LabeledContent(AppLanguage.string("ui.joined", default: "Joined"), value: name)
                    Button(AppLanguage.string("ui.leave_group", default: "Leave Group"), role: .destructive) {
                        Task { await leave() }
                    }
                    .disabled(isWorking)
                } header: {
                    Text(AppLanguage.string("settings.this_device", default: "This Device"))
                }
                .zelefinRowBackground()
            }
            Section {
                TextField(AppLanguage.string("ui.name", default: "Name"), text: $newName)
                Button(AppLanguage.string("common.create", default: "Create")) {
                    Task { await create() }
                }
                .disabled(isWorking || newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text(AppLanguage.string("ui.new_group", default: "New Group"))
            }
            .zelefinRowBackground()
            Section {
                if isLoading && groups.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if groups.isEmpty {
                    SettingsStackedRow(title: AppLanguage.string("ui.no_syncplay_groups_are_running", default: "No SyncPlay groups are running."))
                } else {
                    ForEach(groups) { group in
                        Button {
                            Task { await join(group) }
                        } label: {
                            SettingsStackedRow(title: group.name, subtitle: group.subtitle)
                        }
                        .buttonStyle(.plain)
                        .disabled(isWorking || session.syncPlayGroupID == group.id)
                        .opacity(session.syncPlayGroupID == group.id ? 0.55 : 1)
                    }
                }
            } header: {
                Text(AppLanguage.string("ui.groups", default: "Groups"))
            }
            .zelefinRowBackground()
        }
        .listStyle(.insetGrouped)
        .refreshable { await load(showProgress: false) }
        .zelefinSettingsChrome(title: AppLanguage.string("settings.syncplay", default: "SyncPlay"))
        .task { await load() }
    }

    private func load(showProgress: Bool = true) async {
        guard let library = session.library else {
            isLoading = false
            errorMessage = "Sign in to use SyncPlay."
            return
        }
        if showProgress, groups.isEmpty { isLoading = true }
        do {
            groups = try await library.syncPlayGroups()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func create() async {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await session.createSyncPlayGroup(name: name)
            newName = ""
            await load(showProgress: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func join(_ group: SyncPlayGroupInfo) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await session.joinSyncPlayGroup(group)
            await load(showProgress: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func leave() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await session.leaveSyncPlayGroup()
            await load(showProgress: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SyncPlayPlaySheet: View {
    let item: MediaItem
    var onClose: () -> Void

    @Environment(SessionStore.self) private var session
    @State private var groups: [SyncPlayGroupInfo] = []
    @State private var newName = ""
    @State private var errorMessage: String?

    var body: some View {
        TitleSheet(title: AppLanguage.string("settings.syncplay", default: "SyncPlay"), onClose: onClose) {
            List {
                if let errorMessage {
                    SettingsStatusText(text: errorMessage, isError: true)
                }
                Section {
                    TextField(AppLanguage.string("ui.name", default: "Name"), text: $newName)
                    Button(AppLanguage.string("ui.start", default: "Start")) {
                        Task { await createAndPlay() }
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text(AppLanguage.string("ui.new_group", default: "New Group"))
                }
                .zelefinRowBackground()
                Section {
                    if groups.isEmpty {
                        SettingsStackedRow(title: AppLanguage.string("ui.no_groups_yet_create_one_to_watch_together", default: "No groups yet. Create one to watch together."))
                    } else {
                        ForEach(groups) { group in
                            Button {
                                Task { await joinAndPlay(group) }
                            } label: {
                                SettingsStackedRow(title: group.name)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text(AppLanguage.string("ui.join_and_play", default: "Join and Play"))
                }
                .zelefinRowBackground()
            }
            .task {
                groups = (try? await session.library?.syncPlayGroups()) ?? []
            }
        }
    }

    private func createAndPlay() async {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            try await session.playInSyncPlay(item, createGroupNamed: name)
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func joinAndPlay(_ group: SyncPlayGroupInfo) async {
        do {
            try await session.joinSyncPlayGroup(group)
            try await session.playInSyncPlay(item)
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
