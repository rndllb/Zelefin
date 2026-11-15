import Foundation

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
import UIKit

/// Owns all Zelefin Live Activities. Keys by `kind` (+ optional `groupID`) and enforces one activity
/// per kind. When ActivityKit's cap is hit, lower-priority kinds (`catalog`, `remoteSession`) are
/// dropped first. Video playback intentionally has no Live Activity so Picture in Picture stays available.
@MainActor
final class ZelefinLiveActivityController {
    static let shared = ZelefinLiveActivityController()

    private struct Slot {
        var activity: Activity<ZelefinActivityAttributes>
        var groupID: String?
        var memberIDs: Set<String>
        var attributes: ZelefinActivityAttributes
        var lastState: ZelefinActivityAttributes.ContentState
    }

    private var slots: [ZelefinActivityKind: Slot] = [:]
    /// Stable member id → kind (and optional group) for update/finish routing.
    private var members: [String: (kind: ZelefinActivityKind, groupID: String?)] = [:]

    /// Kind priority when reclaiming a slot under the ActivityKit cap (lowest first).
    private static let dropOrder: [ZelefinActivityKind] = [
        .catalog, .remoteSession, .request, .syncPlay, .download
    ]

    // MARK: - Public API

    func start(
        kind: ZelefinActivityKind,
        id: String,
        groupID: String? = nil,
        title: String,
        subtitle: String,
        posterFileURL: URL? = nil,
        posterData: Data? = nil,
        fraction: Double? = nil,
        statusLine: String,
        isPaused: Bool = false,
        badgeLabel: String? = nil
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        members[id] = (kind, groupID)
        if var existing = slots[kind] {
            existing.memberIDs.insert(id)
            if let groupID { existing.groupID = groupID }
            // Refresh static title/subtitle when a new member arrives with richer copy.
            if !title.isEmpty {
                existing.attributes = ZelefinActivityAttributes(
                    kind: kind,
                    title: title,
                    subtitle: subtitle,
                    posterThumbnail: existing.attributes.posterThumbnail
                        ?? posterData
                        ?? posterFileURL.flatMap(Self.thumbnailData(from:))
                )
            }
            slots[kind] = existing
            update(
                id: id,
                fraction: fraction,
                statusLine: statusLine,
                isPaused: isPaused,
                badgeLabel: badgeLabel
            )
            return
        }

        let thumb = posterData ?? posterFileURL.flatMap(Self.thumbnailData(from:))
        let attributes = ZelefinActivityAttributes(
            kind: kind,
            title: title,
            subtitle: subtitle,
            posterThumbnail: thumb
        )
        let state = Self.contentState(
            fraction: fraction,
            statusLine: statusLine,
            isPaused: isPaused,
            isFinished: false,
            isFailed: false,
            badgeLabel: badgeLabel
        )
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil)
            )
            slots[kind] = Slot(
                activity: activity,
                groupID: groupID,
                memberIDs: [id],
                attributes: attributes,
                lastState: state
            )
        } catch {
            if reclaimSlot(preferring: kind) {
                start(
                    kind: kind,
                    id: id,
                    groupID: groupID,
                    title: title,
                    subtitle: subtitle,
                    posterFileURL: posterFileURL,
                    posterData: posterData,
                    fraction: fraction,
                    statusLine: statusLine,
                    isPaused: isPaused,
                    badgeLabel: badgeLabel
                )
                return
            }
            ZelefinLog.error("LiveActivity", "start \(kind.rawValue) failed: \(error.localizedDescription)")
        }
    }

    func update(
        id: String,
        fraction: Double? = nil,
        statusLine: String,
        isPaused: Bool = false,
        isFinished: Bool = false,
        isFailed: Bool = false,
        badgeLabel: String? = nil,
        title: String? = nil,
        subtitle: String? = nil
    ) {
        guard let route = members[id], var slot = slots[route.kind] else { return }
        if let title, !title.isEmpty {
            slot.attributes = ZelefinActivityAttributes(
                kind: slot.attributes.kind,
                title: title,
                subtitle: subtitle ?? slot.attributes.subtitle,
                posterThumbnail: slot.attributes.posterThumbnail
            )
        } else if let subtitle {
            slot.attributes = ZelefinActivityAttributes(
                kind: slot.attributes.kind,
                title: slot.attributes.title,
                subtitle: subtitle,
                posterThumbnail: slot.attributes.posterThumbnail
            )
        }
        let state = Self.contentState(
            fraction: fraction,
            statusLine: statusLine,
            isPaused: isPaused,
            isFinished: isFinished,
            isFailed: isFailed,
            badgeLabel: badgeLabel ?? slot.lastState.badgeLabel
        )
        slot.lastState = state
        slots[route.kind] = slot
        nonisolated(unsafe) let act = slot.activity
        Task { await act.update(ActivityContent(state: state, staleDate: nil)) }
    }

    /// Update by kind when the caller doesn't track a member id (e.g. remote sessions count).
    func updateKind(
        _ kind: ZelefinActivityKind,
        fraction: Double? = nil,
        statusLine: String,
        isPaused: Bool = false,
        badgeLabel: String? = nil,
        title: String? = nil,
        subtitle: String? = nil
    ) {
        guard var slot = slots[kind] else { return }
        if let title, !title.isEmpty {
            slot.attributes = ZelefinActivityAttributes(
                kind: kind,
                title: title,
                subtitle: subtitle ?? slot.attributes.subtitle,
                posterThumbnail: slot.attributes.posterThumbnail
            )
        } else if let subtitle {
            slot.attributes = ZelefinActivityAttributes(
                kind: kind,
                title: slot.attributes.title,
                subtitle: subtitle,
                posterThumbnail: slot.attributes.posterThumbnail
            )
        }
        let state = Self.contentState(
            fraction: fraction,
            statusLine: statusLine,
            isPaused: isPaused,
            isFinished: false,
            isFailed: false,
            badgeLabel: badgeLabel ?? slot.lastState.badgeLabel
        )
        slot.lastState = state
        slots[kind] = slot
        nonisolated(unsafe) let act = slot.activity
        Task { await act.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func finish(id: String, success: Bool, statusLine: String, dismissAfter: TimeInterval = 4) {
        guard let route = members.removeValue(forKey: id) else { return }
        guard var slot = slots[route.kind] else { return }
        slot.memberIDs.remove(id)
        if !slot.memberIDs.isEmpty {
            slots[route.kind] = slot
            return
        }
        slots[route.kind] = nil
        let state = Self.contentState(
            fraction: success ? 1 : nil,
            statusLine: statusLine,
            isPaused: false,
            isFinished: success,
            isFailed: !success,
            badgeLabel: slot.lastState.badgeLabel
        )
        nonisolated(unsafe) let act = slot.activity
        Task {
            await act.update(ActivityContent(state: state, staleDate: nil))
            await act.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(.now + dismissAfter)
            )
        }
    }

    func finishKind(_ kind: ZelefinActivityKind, success: Bool = true, statusLine: String, dismissAfter: TimeInterval = 4) {
        let memberIDs = members.filter { $0.value.kind == kind }.map(\.key)
        for id in memberIDs { members.removeValue(forKey: id) }
        guard let slot = slots.removeValue(forKey: kind) else { return }
        let state = Self.contentState(
            fraction: success ? (slot.lastState.fraction ?? 1) : nil,
            statusLine: statusLine,
            isPaused: false,
            isFinished: success,
            isFailed: !success,
            badgeLabel: slot.lastState.badgeLabel
        )
        nonisolated(unsafe) let act = slot.activity
        Task {
            await act.update(ActivityContent(state: state, staleDate: nil))
            await act.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(.now + dismissAfter)
            )
        }
    }

    func stop(id: String) {
        guard let route = members.removeValue(forKey: id) else { return }
        guard var slot = slots[route.kind] else { return }
        slot.memberIDs.remove(id)
        if !slot.memberIDs.isEmpty {
            slots[route.kind] = slot
            return
        }
        slots[route.kind] = nil
        nonisolated(unsafe) let act = slot.activity
        Task { await act.end(nil, dismissalPolicy: .immediate) }
    }

    func stopKind(_ kind: ZelefinActivityKind) {
        let memberIDs = members.filter { $0.value.kind == kind }.map(\.key)
        for id in memberIDs { members.removeValue(forKey: id) }
        guard let slot = slots.removeValue(forKey: kind) else { return }
        nonisolated(unsafe) let act = slot.activity
        Task { await act.end(nil, dismissalPolicy: .immediate) }
    }

    func hasActive(_ kind: ZelefinActivityKind) -> Bool {
        slots[kind] != nil
    }

    // MARK: - Cap reclaim

    /// Ends the lowest-priority active kind that is not `preferring`. Returns true if a slot was freed.
    @discardableResult
    private func reclaimSlot(preferring: ZelefinActivityKind) -> Bool {
        for candidate in Self.dropOrder where candidate != preferring {
            if slots[candidate] != nil {
                stopKind(candidate)
                return true
            }
        }
        return false
    }

    /// Dismiss leftover Now Playing / Live TV activities from older builds that blocked PiP.
    func endLegacyPlaybackActivities() {
        for activity in Activity<ZelefinActivityAttributes>.activities {
            switch activity.attributes.kind {
            case .playback, .liveTV:
                nonisolated(unsafe) let act = activity
                Task { await act.end(nil, dismissalPolicy: .immediate) }
            case .download, .syncPlay, .request, .catalog, .remoteSession:
                break
            }
        }
        slots[.playback] = nil
        slots[.liveTV] = nil
        members = members.filter { $0.value.kind != .playback && $0.value.kind != .liveTV }
    }

    /// Any Live Activity can make `AVPictureInPictureController.isPictureInPicturePossible`
    /// stay false for sample-buffer video. Clear the board before starting playback / PiP.
    /// Awaits dismissal so PiP is not created while an activity is still tearing down.
    func endAllActivities() async {
        members.removeAll()
        slots.removeAll()
        let existing = Activity<ZelefinActivityAttributes>.activities
        for activity in existing {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    // MARK: - Helpers

    private static func contentState(
        fraction: Double?,
        statusLine: String,
        isPaused: Bool,
        isFinished: Bool,
        isFailed: Bool,
        badgeLabel: String?
    ) -> ZelefinActivityAttributes.ContentState {
        ZelefinActivityAttributes.ContentState(
            fraction: fraction,
            statusLine: statusLine,
            isPaused: isPaused,
            isFinished: isFinished,
            isFailed: isFailed,
            accentHex: AccentPreferences.currentHex,
            badgeLabel: badgeLabel
        )
    }

    static func thumbnailData(from url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let image = UIImage(data: data) else { return nil }
        return thumbnailData(fromImage: image)
    }

    static func thumbnailData(fromImage image: UIImage) -> Data? {
        let budget = 2_000
        var best: Data?
        for maxDimension in [120.0, 96.0, 72.0, 56.0] {
            guard let scaled = image.downscaled(maxDimension: maxDimension) else { continue }
            for quality in [0.55, 0.4, 0.28, 0.18] {
                guard let jpeg = scaled.jpegData(compressionQuality: quality) else { continue }
                if jpeg.count <= budget { return jpeg }
                if best == nil || jpeg.count < best!.count { best = jpeg }
            }
        }
        if let best, best.count <= 3_500 { return best }
        return nil
    }
}

private extension UIImage {
    func downscaled(maxDimension: CGFloat) -> UIImage? {
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
#endif
