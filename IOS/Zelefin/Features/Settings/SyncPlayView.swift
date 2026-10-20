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
                    LabeledContent("Joined", value: name)
                    Button("Leave Group", role: .destructive) {
                        Task { await leave() }
                    }
                    .disabled(isWorking)
                } header: {
                    Text("This Device")
                }
                .zelefinRowBackground()
            }
            Section {
                TextField("Name", text: $newName)
                Button("Create") {
                    Task { await create() }
                }
                .disabled(isWorking || newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("New Group")
            }
            .zelefinRowBackground()
            Section {
                if isLoading && groups.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if groups.isEmpty {
                    SettingsStackedRow(title: "No SyncPlay groups are running.")
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
                Text("Groups")
            }
            .zelefinRowBackground()
        }
        .listStyle(.insetGrouped)
        .refreshable { await load(showProgress: false) }
        .zelefinSettingsChrome(title: "SyncPlay")
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
        NavigationStack {
            List {
                if let errorMessage {
                    SettingsStatusText(text: errorMessage, isError: true)
                }
                Section {
                    TextField("Name", text: $newName)
                    Button("Start") {
                        Task { await createAndPlay() }
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("New Group")
                }
                .zelefinRowBackground()
                Section {
                    if groups.isEmpty {
                        SettingsStackedRow(title: "No groups yet. Create one to watch together.")
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
                    Text("Join and Play")
                }
                .zelefinRowBackground()
            }
            .zelefinSettingsChrome(title: "SyncPlay")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                }
            }
            .task {
                groups = (try? await session.library?.syncPlayGroups()) ?? []
            }
        }
        .preferredColorScheme(.dark)
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
