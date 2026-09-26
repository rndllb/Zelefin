import Foundation

@MainActor
final class SiloPlaybackReporter: PlaybackReporting {
    private let api: SiloAPIClient
    private let sessionID: String
    private var lastReport: TimeInterval = 0

    init(api: SiloAPIClient, sessionID: String) {
        self.api = api
        self.sessionID = sessionID
    }

    func started(at position: TimeInterval) async {
        try? await api.reportProgress(sessionID: sessionID, position: position, isPaused: false)
        lastReport = position
    }

    func progress(at position: TimeInterval, isPaused: Bool) async {
        guard abs(position - lastReport) >= 10 || isPaused else { return }
        lastReport = position
        try? await api.reportProgress(sessionID: sessionID, position: position, isPaused: isPaused)
    }

    func stopped(at position: TimeInterval) async {
        try? await api.reportProgress(sessionID: sessionID, position: position, isPaused: true)
        try? await api.stopPlayback(sessionID: sessionID)
    }
}
