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
            }
            if let name = session.syncPlayGroupName, session.syncPlayGroupID != nil {
                Section {
                    VStack(alignment: .leading, spacing: 0) {
                        SettingsInfoRow(label: "Joined", value: name)
                        SettingsSecondaryButton(title: "Leave Group", role: .destructive, enabled: !isWorking) {
                            Task { await leave() }
                        }
                        .padding(.top, 16)
                    }
                } header: {
                    Text("This Device")
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsLabeledField(label: "Name", systemImage: "person.2.fill") {
                        TextField("Name", text: $newName)
                    }
                    SettingsPrimaryButton(
                        title: "Create",
                        isBusy: isWorking,
                        enabled: !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        Task { await create() }
                    }
                    .padding(.top, 16)
                }
            } header: {
                Text("New Group")
            }
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
                    VStack(alignment: .leading, spacing: 0) {
                        SettingsLabeledField(label: "Name", systemImage: "person.2.fill") {
                            TextField("Name", text: $newName)
                        }
                        SettingsPrimaryButton(
                            title: "Start",
                            enabled: !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ) {
                            Task { await createAndPlay() }
                        }
                        .padding(.top, 16)
                    }
                } header: {
                    Text("New Group")
                }
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
