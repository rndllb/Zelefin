import Foundation
import JellyfinAPI

struct ScheduledTask: Identifiable, Equatable, Hashable, Sendable {
    enum State: String, Equatable, Sendable {
        case idle
        case running
        case cancelling

        var label: String {
            switch self {
            case .idle: "Idle"
            case .running: "Running"
            case .cancelling: "Cancelling"
            }
        }
    }

    enum LastStatus: String, Equatable, Sendable {
        case completed
        case failed
        case cancelled
        case aborted

        var label: String {
            switch self {
            case .completed: "Completed"
            case .failed: "Failed"
            case .cancelled: "Cancelled"
            case .aborted: "Aborted"
            }
        }
    }

    let id: String
    var name: String
    var category: String
    var summary: String
    var state: State
    var progressPercentage: Double?
    var isHidden: Bool
    var lastStatus: LastStatus?
    var lastStarted: Date?
    var lastEnded: Date?
    var lastError: String?

    var isActive: Bool { state == .running || state == .cancelling }
    var canStart: Bool { state == .idle }
    var canCancel: Bool { state == .running }

    var progressFraction: Double? {
        guard let progressPercentage else { return nil }
        return min(1, max(0, progressPercentage / 100))
    }

    var progressLabel: String? {
        guard let progressPercentage else { return nil }
        return "\(Int(progressPercentage.rounded(.towardZero)))%"
    }

    var stateSubtitle: String {
        switch state {
        case .running:
            if let progressLabel { return "Running · \(progressLabel)" }
            return "Running"
        case .cancelling:
            return "Cancelling"
        case .idle:
            return lastRunSubtitle ?? "Idle"
        }
    }

    var lastRunSubtitle: String? {
        guard let lastStatus else { return nil }
        var parts = [lastStatus.label]
        if let lastEnded {
            parts.append(lastEnded.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
        }
        return parts.joined(separator: " · ")
    }

    var lastDurationLabel: String? {
        guard let lastStarted, let lastEnded else { return nil }
        let seconds = lastEnded.timeIntervalSince(lastStarted)
        guard seconds >= 0 else { return nil }
        return PlaybackTimeFormatting.clock(seconds)
    }

    static func sorted(_ tasks: [ScheduledTask]) -> [ScheduledTask] {
        tasks.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive && !rhs.isActive }
            if lhs.category != rhs.category { return lhs.category.localizedCaseInsensitiveCompare(rhs.category) == .orderedAscending }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

extension ScheduledTask {
    init?(dto: TaskInfo) {
        guard let id = dto.id, !id.isEmpty else { return nil }
        let name = dto.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.init(
            id: id,
            name: name.isEmpty ? "Scheduled task" : name,
            category: dto.category?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Other",
            summary: dto.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            state: .init(dto.state),
            progressPercentage: dto.currentProgressPercentage,
            isHidden: dto.isHidden == true,
            lastStatus: dto.lastExecutionResult?.status.map(LastStatus.init),
            lastStarted: dto.lastExecutionResult?.startTimeUtc,
            lastEnded: dto.lastExecutionResult?.endTimeUtc,
            lastError: dto.lastExecutionResult?.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }
}

extension ScheduledTask.State {
    init(_ state: TaskState?) {
        switch state {
        case .running: self = .running
        case .cancelling: self = .cancelling
        default: self = .idle
        }
    }
}

extension ScheduledTask.LastStatus {
    init(_ status: TaskCompletionStatus) {
        switch status {
        case .completed: self = .completed
        case .failed: self = .failed
        case .cancelled: self = .cancelled
        case .aborted: self = .aborted
        @unknown default: self = .completed
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
