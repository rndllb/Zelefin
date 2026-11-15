import CoreTransferable
import Foundation
import GroupActivities
import Observation
import UIKit

/// Watch a title together over FaceTime. Each device streams from its own account on the
/// same server; the activity carries the server id along with the title.
nonisolated struct WatchTogetherActivity: GroupActivity, Hashable, Codable {
    let itemId: String
    let serverId: String
    let title: String

    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.type = .watchTogether
        metadata.title = title
        metadata.supportsContinuationOnTV = true
        return metadata
    }
}

#if !os(tvOS)
/// Lets the share sheet start SharePlay outside an active FaceTime call.
struct WatchTogetherItem: Transferable {
    let activity: WatchTogetherActivity

    static var transferRepresentation: some TransferRepresentation {
        GroupActivityTransferRepresentation { $0.activity }
    }
}
#endif

nonisolated struct SharePlayCommand: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case play, pause, seek
        /// Playback speed (1.0, 1.25, …) — applied on every peer.
        case rate
        /// Sent by a player that just opened, so peers answer with where they are.
        case hello
    }

    var kind: Kind
    var itemId: String
    var positionSeconds: Double
    /// Included on every command so a late joiner / play-pause also picks up speed.
    var rate: Float = 1
    var id = UUID()
}

/// FaceTime SharePlay coordination. Unlike SyncPlay, a sent command is not echoed back.
@MainActor
@Observable
final class SharePlayManager {
    private(set) var isActive = false
    private(set) var participantCount = 0
    private(set) var activityItemId: String?
    var incomingCommand: SharePlayCommand?
    var notice: String?
    private(set) var playingItemId: String?
    var hasOpenPlayer: Bool { playingItemId != nil }

    /// Opens a title when SharePlay starts without a local player.
    var openItem: ((String) -> Void)?

    @ObservationIgnored private var session: GroupSession<WatchTogetherActivity>?
    @ObservationIgnored private var messenger: GroupSessionMessenger?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored var currentServerId: () -> String = { "" }
    @ObservationIgnored private var isObserving = false

    func observeSessions() async {
        guard !isObserving else { return }
        isObserving = true
        defer { isObserving = false }
        for await session in WatchTogetherActivity.sessions() {
            configure(session)
        }
    }

    func activity(for item: MediaItem) -> WatchTogetherActivity {
        WatchTogetherActivity(
            itemId: item.id,
            serverId: currentServerId(),
            title: Self.title(for: item)
        )
    }

    /// In a FaceTime call: activate immediately. Otherwise: Apple's people picker (starts FaceTime).
    func start(_ item: MediaItem) {
        let activity = activity(for: item)
        Task {
            switch await activity.prepareForActivation() {
            case .activationPreferred:
                do {
                    _ = try await activity.activate()
                } catch {
                    notice = error.localizedDescription
                }
            case .activationDisabled:
                presentSharingPicker(for: activity)
            default:
                // Not already in a call — present the system SharePlay invite UI.
                presentSharingPicker(for: activity)
            }
        }
    }

    private func presentSharingPicker(for activity: WatchTogetherActivity) {
        #if !os(tvOS)
        guard let host = Self.topViewController() else {
            notice = "Couldn't open SharePlay. Try again from the player."
            return
        }
        do {
            let picker = try GroupActivitySharingController(activity)
            host.present(picker, animated: true)
        } catch {
            notice = error.localizedDescription
        }
        #else
        notice = "Start a FaceTime call first, then choose SharePlay."
        #endif
    }

    private static func topViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let root = windows.first(where: \.isKeyWindow)?.rootViewController
            ?? windows.first?.rootViewController
        var top = root
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    func leave() {
        session?.leave()
        reset()
    }

    func playerOpened(_ item: MediaItem) {
        playingItemId = item.id
        guard isActive else { return }
        if activityItemId != item.id {
            session?.activity = activity(for: item)
            activityItemId = item.id
        }
        send(.hello, itemId: item.id, positionSeconds: 0)
    }

    func playerClosed(_ itemId: String) {
        if playingItemId == itemId { playingItemId = nil }
    }

    func send(
        _ kind: SharePlayCommand.Kind,
        itemId: String,
        positionSeconds: Double,
        rate: Float = 1
    ) {
        guard let messenger else { return }
        let command = SharePlayCommand(
            kind: kind,
            itemId: itemId,
            positionSeconds: positionSeconds,
            rate: rate
        )
        Task { try? await messenger.send(command) }
    }

    /// Host (+port) identity for SharePlay — shared by every account on that server.
    static func serverIdentity(from url: URL) -> String {
        let host = (url.host ?? url.absoluteString).lowercased()
        if let port = url.port {
            return "\(host):\(port)"
        }
        return host
    }

    private func configure(_ session: GroupSession<WatchTogetherActivity>) {
        reset()
        let localServer = currentServerId()
        let activityServer = session.activity.serverId
        // Empty on either side: older sessions / race before login — don't false-reject.
        let serversMatch = localServer.isEmpty
            || activityServer.isEmpty
            || activityServer == localServer
        guard serversMatch else {
            notice = "\(session.activity.title) is on a server you're not signed in to here."
            session.leave()
            return
        }
        self.session = session
        let messenger = GroupSessionMessenger(session: session)
        self.messenger = messenger
        isActive = true
        activityItemId = session.activity.itemId

        tasks.append(Task { [weak self] in
            for await state in session.$state.values {
                if case .invalidated = state { self?.reset() }
            }
        })
        tasks.append(Task { [weak self] in
            for await activity in session.$activity.values {
                self?.follow(activity)
            }
        })
        tasks.append(Task { [weak self] in
            for await participants in session.$activeParticipants.values {
                self?.participantCount = participants.count
            }
        })
        tasks.append(Task { [weak self] in
            for await (command, _) in messenger.messages(of: SharePlayCommand.self) {
                self?.incomingCommand = command
            }
        })
        session.join()
        if playingItemId == nil {
            openItem?(session.activity.itemId)
        }
    }

    private func follow(_ activity: WatchTogetherActivity) {
        guard activityItemId != activity.itemId else { return }
        activityItemId = activity.itemId
        if playingItemId == nil {
            openItem?(activity.itemId)
        }
    }

    private func reset() {
        tasks.forEach { $0.cancel() }
        tasks = []
        session = nil
        messenger = nil
        isActive = false
        participantCount = 0
        activityItemId = nil
    }

    private static func title(for item: MediaItem) -> String {
        guard item.kind == .episode, let series = item.seriesName else { return item.name }
        return "\(series) – \(item.name)"
    }
}
