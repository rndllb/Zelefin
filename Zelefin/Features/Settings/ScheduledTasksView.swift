import SwiftUI

struct ScheduledTasksView: View {
    @Environment(SessionStore.self) private var session

    @State private var tasks: [ScheduledTask] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var busyIDs: Set<String> = []

    private var running: [ScheduledTask] { tasks.filter(\.isActive) }
    private var idleByCategory: [(category: String, tasks: [ScheduledTask])] {
        let idle = tasks.filter { !$0.isActive && !$0.isHidden }
        let grouped = Dictionary(grouping: idle, by: \.category)
        return grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .compactMap { category in
                grouped[category].map { (category, $0) }
            }
    }

    var body: some View {
        Group {
            if isLoading && tasks.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tasks.isEmpty {
                ContentUnavailableView(
                    "No Scheduled Tasks",
                    systemImage: "clock.arrow.2.circlepath",
                    description: Text(errorMessage ?? "This server did not return any scheduled tasks.")
                )
            } else {
                List {
                    if let errorMessage {
                        Section {
                            SettingsStatusText(text: errorMessage, isError: true)
                                .settingsLoginCard()
                                .settingsCardRow()
                        }
                    }
                    if !running.isEmpty {
                        Section("Running") {
                            ForEach(running) { task in
                                taskNavigation(task)
                            }
                        }
                    }
                    ForEach(idleByCategory, id: \.category) { group in
                        Section(group.category) {
                            ForEach(group.tasks) { task in
                                taskNavigation(task)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await load(showProgress: false) }
            }
        }
        .zelefinSettingsChrome(title: "Scheduled Tasks")
        .task { await monitor() }
    }

    private func taskNavigation(_ task: ScheduledTask) -> some View {
        NavigationLink {
            ScheduledTaskDetailView(taskID: task.id)
        } label: {
            ScheduledTaskRow(task: task, isBusy: busyIDs.contains(task.id)) {
                await run(task)
            } cancel: {
                await cancel(task)
            }
            .settingsLoginCard()
        }
        .settingsCardRow()
    }

    private func monitor() async {
        await load()
        while !Task.isCancelled {
            let interval: Duration = running.isEmpty ? .seconds(4) : .seconds(2)
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            await load(showProgress: false)
        }
    }

    private func load(showProgress: Bool = true) async {
        guard session.isAdministrator, let library = session.jellyfinLibrary else {
            isLoading = false
            errorMessage = "Sign in with an administrator to manage scheduled tasks."
            return
        }
        if showProgress, tasks.isEmpty { isLoading = true }
        do {
            tasks = try await library.scheduledTasks()
            errorMessage = nil
        } catch {
            if tasks.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    private func run(_ task: ScheduledTask) async {
        await perform(task.id) { try await session.jellyfinLibrary?.startScheduledTask(id: task.id) }
    }

    private func cancel(_ task: ScheduledTask) async {
        await perform(task.id) { try await session.jellyfinLibrary?.stopScheduledTask(id: task.id) }
    }

    private func perform(_ id: String, _ work: () async throws -> Void) async {
        busyIDs.insert(id)
        defer { busyIDs.remove(id) }
        do {
            try await work()
            try? await Task.sleep(for: .milliseconds(400))
            await load(showProgress: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ScheduledTaskRow: View {
    let task: ScheduledTask
    var isBusy: Bool
    var start: () async -> Void
    var cancel: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(LoginPalette.primaryText)
                    Text(task.stateSubtitle)
                        .font(.caption)
                        .foregroundStyle(task.lastStatus == .failed && !task.isActive ? LoginPalette.failure : LoginPalette.secondaryText)
                }
                Spacer(minLength: 8)
                if isBusy {
                    ProgressView()
                } else if task.canCancel {
                    Button("Cancel", role: .destructive) {
                        Task { await cancel() }
                    }
                    .buttonStyle(.borderless)
                } else if task.canStart {
                    Button("Start") {
                        Task { await start() }
                    }
                    .buttonStyle(.borderless)
                }
                SettingsChevron()
            }
            if task.isActive {
                if let fraction = task.progressFraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(AccentPreferences.current)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(AccentPreferences.current)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.name), \(task.stateSubtitle)")
    }
}

struct ScheduledTaskDetailView: View {
    @Environment(SessionStore.self) private var session
    let taskID: String

    @State private var task: ScheduledTask?
    @State private var errorMessage: String?
    @State private var isBusy = false

    var body: some View {
        Group {
            if let task {
                List {
                    if let errorMessage {
                        Section {
                            SettingsStatusText(text: errorMessage, isError: true)
                                .settingsLoginCard()
                                .settingsCardRow()
                        }
                    }
                    Section {
                        VStack(alignment: .leading, spacing: 0) {
                            SettingsInfoRow(label: "Status", value: task.state.label)
                            if let progress = task.progressLabel, task.isActive {
                                SettingsCardDivider()
                                SettingsInfoRow(label: "Progress", value: progress)
                            }
                            if task.isActive {
                                SettingsCardDivider()
                                if let fraction = task.progressFraction {
                                    ProgressView(value: fraction)
                                        .progressViewStyle(.linear)
                                        .tint(AccentPreferences.current)
                                } else {
                                    ProgressView()
                                        .progressViewStyle(.linear)
                                        .tint(AccentPreferences.current)
                                }
                            }
                        }
                        .settingsLoginCard()
                        .settingsCardRow()
                    }
                    if !task.summary.isEmpty {
                        Section {
                            Text(task.summary)
                                .font(.body.weight(.medium))
                                .foregroundStyle(LoginPalette.secondaryText)
                                .settingsLoginCard()
                                .settingsCardRow()
                        } header: {
                            Text("About")
                        }
                    }
                    if task.lastStatus != nil || task.lastEnded != nil {
                        Section {
                            VStack(alignment: .leading, spacing: 0) {
                                if let lastStatus = task.lastStatus {
                                    SettingsInfoRow(label: "Result", value: lastStatus.label)
                                }
                                if let lastEnded = task.lastEnded {
                                    if task.lastStatus != nil { SettingsCardDivider() }
                                    SettingsInfoRow(label: "Finished", value: lastEnded.formatted(date: .abbreviated, time: .shortened))
                                }
                                if let duration = task.lastDurationLabel {
                                    SettingsCardDivider()
                                    SettingsInfoRow(label: "Duration", value: duration)
                                }
                                if let lastError = task.lastError {
                                    SettingsStatusText(text: lastError, isError: true)
                                        .padding(.top, 12)
                                }
                            }
                            .settingsLoginCard()
                            .settingsCardRow()
                        } header: {
                            Text("Last run")
                        }
                    }
                    Section {
                        if task.canStart {
                            SettingsPrimaryButton(title: "Start Task", isBusy: isBusy) {
                                Task { await start() }
                            }
                            .settingsCardRow()
                        }
                        if task.canCancel {
                            SettingsSecondaryButton(title: "Cancel Task", role: .destructive, enabled: !isBusy) {
                                Task { await cancel() }
                            }
                            .settingsCardRow()
                        }
                    }
                }
            } else if errorMessage != nil {
                ContentUnavailableView(
                    "Can't Load Task",
                    systemImage: "clock.badge.exclamationmark",
                    description: Text(errorMessage ?? "")
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .zelefinSettingsChrome(title: task?.name ?? "Task")
        .task { await monitor() }
    }

    private func monitor() async {
        await load()
        while !Task.isCancelled {
            let interval: Duration = task?.isActive == true ? .seconds(2) : .seconds(4)
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    private func load() async {
        guard let library = session.jellyfinLibrary else {
            errorMessage = "Sign in with an administrator to manage scheduled tasks."
            return
        }
        do {
            let latest = try await library.scheduledTasks()
            if let match = latest.first(where: { $0.id == taskID }) {
                task = match
                errorMessage = nil
            } else if task == nil {
                errorMessage = "That scheduled task is not on this server."
            }
        } catch {
            if task == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func start() async {
        await perform { try await session.jellyfinLibrary?.startScheduledTask(id: taskID) }
    }

    private func cancel() async {
        await perform { try await session.jellyfinLibrary?.stopScheduledTask(id: taskID) }
    }

    private func perform(_ work: () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await work()
            try? await Task.sleep(for: .milliseconds(400))
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
