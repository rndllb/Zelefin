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
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            if let name = session.syncPlayGroupName, session.syncPlayGroupID != nil {
                Section("This Device") {
                    LabeledContent("Joined", value: name)
                    Button("Leave Group", role: .destructive) {
                        Task { await leave() }
                    }
                    .disabled(isWorking)
                }
            }
            Section("New Group") {
                HStack {
                    TextField("Name", text: $newName)
                    Button("Create") {
                        Task { await create() }
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
                }
            }
            Section("Groups") {
                if isLoading && groups.isEmpty {
                    ProgressView()
                } else if groups.isEmpty {
                    Text("No SyncPlay groups are running.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(groups) { group in
                        Button {
                            Task { await join(group) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.name)
                                Text(group.subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(isWorking || session.syncPlayGroupID == group.id)
                    }
                }
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
                    Text(errorMessage).foregroundStyle(.red)
                }
                Section("New Group") {
                    HStack {
                        TextField("Name", text: $newName)
                        Button("Start") {
                            Task { await createAndPlay() }
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Section("Join and Play") {
                    if groups.isEmpty {
                        Text("No groups yet. Create one to watch together.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(groups) { group in
                            Button(group.name) {
                                Task { await joinAndPlay(group) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("SyncPlay")
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
