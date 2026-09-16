import Foundation
import JellyfinAPI

@MainActor
final class PlaybackReporter {
    private let client: JellyfinClient
    private let plan: PlaybackPlan
    private var lastReport: TimeInterval = 0

    init(client: JellyfinClient, plan: PlaybackPlan) {
        self.client = client
        self.plan = plan
    }

    func started(at position: TimeInterval) async {
        let body = PlaybackStartInfo(
            canSeek: !plan.isLive,
            isMuted: false,
            isPaused: false,
            itemID: plan.item.id,
            liveStreamID: plan.liveStreamID,
            mediaSourceID: plan.mediaSourceID,
            playMethod: playMethod,
            playSessionID: plan.playSessionID,
            positionTicks: TickClock.intTicks(from: position)
        )
        _ = try? await client.send(Paths.reportPlaybackStart(body))
        lastReport = position
    }

    func progress(at position: TimeInterval, isPaused: Bool) async {
        guard abs(position - lastReport) >= 10 || isPaused else { return }
        lastReport = position

        let body = PlaybackProgressInfo(
            canSeek: !plan.isLive,
            isPaused: isPaused,
            itemID: plan.item.id,
            liveStreamID: plan.liveStreamID,
            mediaSourceID: plan.mediaSourceID,
            playMethod: playMethod,
            playSessionID: plan.playSessionID,
            positionTicks: TickClock.intTicks(from: position)
        )
        _ = try? await client.send(Paths.reportPlaybackProgress(body))
    }

    func stopped(at position: TimeInterval) async {
        let body = PlaybackStopInfo(
            itemID: plan.item.id,
            liveStreamID: plan.liveStreamID,
            mediaSourceID: plan.mediaSourceID,
            playSessionID: plan.playSessionID,
            positionTicks: TickClock.intTicks(from: position)
        )
        _ = try? await client.send(Paths.reportPlaybackStopped(body))
        if let liveStreamID = plan.liveStreamID, !liveStreamID.isEmpty {
            _ = try? await client.send(Paths.closeLiveStream(liveStreamID: liveStreamID))
        }
    }

    private var playMethod: PlayMethod {
        switch plan.method {
        case .directPlay: .directPlay
        case .remux: .directStream
        case .transcode: .transcode
        }
    }
}
