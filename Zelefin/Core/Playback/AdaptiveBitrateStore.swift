import Foundation
import Network
import Observation

@MainActor
@Observable
final class AdaptiveBitrateStore {
    private(set) var path = NetworkPathSnapshot.unknown
    private(set) var lastProbe: BitrateProbeResult?
    private var monitor: NWPathMonitor?

    init() {
        start()
    }

    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] nwPath in
            let snapshot = NetworkPathSnapshot(nwPath)
            Task { @MainActor in
                self?.apply(snapshot)
            }
        }
        monitor.start(queue: DispatchQueue(label: "app.zelefin.adaptive-bitrate"))
        self.monitor = monitor
    }

    var cachedBudgetBitsPerSecond: Int {
        let measured = AdaptiveBitratePolicy.isCacheValid(result: lastProbe, path: path)
            ? lastProbe?.bitsPerSecond
            : nil
        return AdaptiveBitratePolicy.budgetBitsPerSecond(measured: measured, path: path)
    }

    func refreshIfNeeded(library: JellyfinLibraryClient?) async {
        guard PlaybackPreferences.adaptiveBitrateEnabled else { return }
        guard let library else { return }
        if AdaptiveBitratePolicy.isCacheValid(result: lastProbe, path: path) { return }
        lastProbe = await library.measureStreamingBitrate(
            size: AdaptiveBitratePolicy.playbackSampleBytes,
            timeout: 4,
            transport: path.transport
        )
    }

    func runDemoTest(library: JellyfinLibraryClient) async throws -> BitrateProbeResult {
        guard let result = await library.measureStreamingBitrate(
            size: AdaptiveBitratePolicy.settingsSampleBytes,
            timeout: 20,
            transport: path.transport
        ) else {
            throw ZelefinError.bitrateTestFailed
        }
        lastProbe = result
        return result
    }

    func resolvedBitsPerSecond(
        sourceBitrate: Int?,
        launch: PlaybackLaunchOptions
    ) -> Int {
        AdaptiveBitratePolicy.bitsPerSecond(
            enabled: PlaybackPreferences.adaptiveBitrateEnabled,
            selected: PlaybackPreferences.selectedQuality,
            override: launch.quality,
            budgetBitsPerSecond: cachedBudgetBitsPerSecond,
            sourceBitsPerSecond: sourceBitrate
        )
    }

    func recommendedQuality(sourceBitrate: Int? = nil) -> PlaybackQuality {
        AdaptiveBitratePolicy.quality(
            enabled: true,
            selected: PlaybackPreferences.selectedQuality,
            override: nil,
            budgetBitsPerSecond: cachedBudgetBitsPerSecond,
            sourceBitsPerSecond: sourceBitrate
        )
    }

    private func apply(_ snapshot: NetworkPathSnapshot) {
        if path.transport != snapshot.transport {
            lastProbe = nil
        }
        path = snapshot
    }
}

extension NetworkPathSnapshot {
    init(_ path: NWPath) {
        let transport: NetworkTransport
        if path.usesInterfaceType(.wiredEthernet) {
            transport = .wired
        } else if path.usesInterfaceType(.wifi) {
            transport = .wifi
        } else if path.usesInterfaceType(.cellular) {
            transport = .cellular
        } else {
            transport = .other
        }
        self.init(
            transport: transport,
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained,
            isSatisfied: path.status == .satisfied
        )
    }
}
