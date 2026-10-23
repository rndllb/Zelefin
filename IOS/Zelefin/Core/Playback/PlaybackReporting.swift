import Foundation

/// Progress sink the player talks to.
protocol PlaybackReporting: AnyObject, Sendable {
    func started(at position: TimeInterval) async
    func progress(at position: TimeInterval, isPaused: Bool) async
    func stopped(at position: TimeInterval) async
}
