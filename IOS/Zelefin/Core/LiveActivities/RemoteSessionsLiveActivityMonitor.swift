import Foundation

/// Opt-in observer for other devices' Now Playing sessions. Default off (privacy).
@MainActor
enum RemoteSessionsLiveActivityMonitor {
    private static var observer: NSObjectProtocol?
    private static var isRunning = false

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: RemoteSessionActivityPresenter.preferenceKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: RemoteSessionActivityPresenter.preferenceKey)
            if newValue {
                start()
            } else {
                stop()
            }
        }
    }

    static func startIfEnabled() {
        guard isEnabled else { return }
        start()
    }

    static func start() {
        guard !isRunning else { return }
        isRunning = true
        observer = NotificationCenter.default.addObserver(
            forName: .zelefinPlaybackSessions,
            object: nil,
            queue: .main
        ) { notification in
            let sessions = notification.object as? [PlaybackSession] ?? []
            Task { @MainActor in
                handle(sessions)
            }
        }
    }

    static func stop() {
        isRunning = false
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        RemoteSessionActivityPresenter.stop()
    }

    static func handle(_ sessions: [PlaybackSession], localDeviceID: String? = nil) {
        guard isEnabled else {
            RemoteSessionActivityPresenter.stop()
            return
        }
        let others = sessions.filter { session in
            guard session.isPlaying else { return false }
            return !session.isThisDevice(localDeviceID)
        }
        RemoteSessionActivityPresenter.startOrUpdate(
            otherCount: others.count,
            topTitle: others.first?.title
        )
    }
}
