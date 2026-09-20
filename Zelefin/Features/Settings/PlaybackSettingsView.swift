import SwiftUI

struct PlaybackSettingsView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(PlaybackPreferences.useNativeVideoPlayerKey) private var useNativeVideoPlayer = false
    @AppStorage(PlaybackPreferences.preferFMP4InHLSKey) private var preferFMP4InHLS = true
    @AppStorage(PlaybackPreferences.skipBackwardKey) private var skipBackward = 10
    @AppStorage(PlaybackPreferences.skipForwardKey) private var skipForward = 10
    @AppStorage(PlaybackPreferences.maxBitrateKey) private var maxBitrate = 0
    @AppStorage(PlaybackPreferences.adaptiveBitrateKey) private var adaptiveBitrate = true
    @AppStorage(PlaybackPreferences.autoPlayNextEpisodeKey) private var autoPlayNextEpisode = true
    @AppStorage(PlaybackPreferences.defaultRateKey) private var defaultRate = 1.0

    @State private var isTesting = false
    @State private var testError: String?
    @State private var testResult: BitrateProbeResult?

    var body: some View {
        Form {
            Section {
                Toggle("Adaptive Bitrate", isOn: $adaptiveBitrate)
                    .tint(AccentPreferences.current)
                Picker(adaptiveBitrate ? "Maximum Quality" : "Default Quality", selection: $maxBitrate) {
                    ForEach(PlaybackQuality.allCases) { quality in
                        Text(quality.title).tag(quality.rawValue)
                    }
                }
                .tint(AccentPreferences.current)
            } header: {
                Text("Quality")
            } footer: {
                Text(qualityFooter)
            }

            Section {
                LabeledContent("Connection") {
                    Text(session.adaptiveBitrate.path.transport.title)
                        .foregroundStyle(.secondary)
                }
                if let testResult {
                    LabeledContent("Measured") {
                        Text(PlaybackStats.bitrateLabel(Int64(testResult.bitsPerSecond)))
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Recommended") {
                        Text(recommendedTitle(for: testResult))
                            .foregroundStyle(.secondary)
                    }
                    Text(recommendationDetail(for: testResult))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let testError {
                    Text(testError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Button {
                    Task { await runDemoTest() }
                } label: {
                    if isTesting {
                        HStack {
                            Text("Testing…")
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Text("Test with Demo File")
                    }
                }
                .disabled(isTesting || session.library == nil)
            } header: {
                Text("Connection Test")
            } footer: {
                Text(
                    session.usesSilo
                        ? "Downloads a sample from your Silo server to measure this Wi-Fi or cellular connection. Adaptive bitrate sends that result to Silo when you press Play."
                        : "Downloads a demo file from your Jellyfin server to measure this Wi-Fi or cellular connection. Adaptive bitrate uses that result, plus the title’s own bitrate, when you press Play."
                )
            }

            Section {
                Picker("Skip Backward", selection: $skipBackward) {
                    ForEach(PlaybackSkipInterval.allCases) { interval in
                        Text(interval.title).tag(interval.rawValue)
                    }
                }
                .tint(AccentPreferences.current)
                Picker("Skip Forward", selection: $skipForward) {
                    ForEach(PlaybackSkipInterval.allCases) { interval in
                        Text(interval.title).tag(interval.rawValue)
                    }
                }
                .tint(AccentPreferences.current)
            } header: {
                Text("Controls")
            } footer: {
                Text("How far the skip buttons jump during playback.")
            }

            Section {
                Toggle("Auto Play Next Episode", isOn: $autoPlayNextEpisode)
                    .tint(AccentPreferences.current)
            } header: {
                Text("Episodes")
            } footer: {
                Text("Starts the next episode when this one ends.")
            }

            Section {
                Picker("Playback Speed", selection: $defaultRate) {
                    ForEach(AVKitPlaybackSpeed.options, id: \.self) { rate in
                        Text(AVKitPlaybackSpeed.title(rate)).tag(Double(rate))
                    }
                }
                .tint(AccentPreferences.current)
                Toggle("Use Native Video Player", isOn: $useNativeVideoPlayer)
                    .tint(AccentPreferences.current)
                if !session.usesSilo {
                    Toggle("Prefer fMP4 in HLS", isOn: preferFMP4Binding)
                        .tint(AccentPreferences.current)
                        .disabled(!useNativeVideoPlayer)
                }
            } header: {
                Text("Player")
            } footer: {
                Text(playerFooter)
            }
        }
        .zelefinSettingsChrome(title: "Playback and Controls")
        .onChange(of: useNativeVideoPlayer) {
            if !useNativeVideoPlayer {
                preferFMP4InHLS = true
            }
        }
    }

    private var qualityFooter: String {
        if adaptiveBitrate {
            return session.usesSilo
                ? "Zelefin measures your connection and tells Silo the ceiling. During playback it steps down after a stall and back up when the buffer stays healthy. Maximum Quality is the cap."
                : "Zelefin measures your connection and only transcodes when the file is too large for it. During playback it steps down after a stall and back up when the buffer stays healthy. Maximum Quality is the ceiling."
        }
        return session.usesSilo
            ? "Auto lets Silo pick Direct Play when the file fits this device. Lower rates ask Silo to transcode."
            : "Auto keeps Direct Play when the file fits this device. Lower rates ask Jellyfin to transcode."
    }

    private var preferFMP4Binding: Binding<Bool> {
        Binding(
            get: {
                PlaybackPreferences.usesFMP4HLS(
                    nativePlayer: useNativeVideoPlayer,
                    preferFMP4: preferFMP4InHLS
                )
            },
            set: { newValue in
                guard useNativeVideoPlayer else { return }
                preferFMP4InHLS = newValue
            }
        )
    }

    private var playerFooter: String {
        if session.usesSilo {
            if useNativeVideoPlayer {
                return "AVPlayer plays Apple-compatible Direct Play and HLS from this Silo server."
            }
            return "Zelefin Direct Play opens the stream Silo returns for this device."
        }
        if useNativeVideoPlayer {
            return "AVPlayer plays Apple-compatible Direct Play and remuxed HLS. MKV and other files remux on the server first. Turn off Prefer fMP4 to ask Jellyfin for MPEG-TS instead of fragmented MP4."
        }
        return "Zelefin Direct Play opens every stream, including remuxed HLS. Fragmented MP4 packaging stays on."
    }

    private func recommendedTitle(for result: BitrateProbeResult) -> String {
        quality(for: result, sourceBitrate: nil).title
    }

    private func recommendationDetail(for result: BitrateProbeResult) -> String {
        let hd = quality(for: result, sourceBitrate: 8_000_000)
        let uhd = quality(for: result, sourceBitrate: 40_000_000)
        return "A typical 1080p file would use \(hd.title). A typical 4K file would use \(uhd.title)."
    }

    private func quality(for result: BitrateProbeResult, sourceBitrate: Int?) -> PlaybackQuality {
        let budget = AdaptiveBitratePolicy.budgetBitsPerSecond(
            measured: result.bitsPerSecond,
            path: session.adaptiveBitrate.path
        )
        return AdaptiveBitratePolicy.quality(
            enabled: true,
            selected: PlaybackQuality.resolved(maxBitrate),
            override: nil,
            budgetBitsPerSecond: budget,
            sourceBitsPerSecond: sourceBitrate
        )
    }

    private func runDemoTest() async {
        guard let library = session.library else {
            testError = "Sign in to test this connection."
            return
        }
        isTesting = true
        testError = nil
        do {
            testResult = try await session.adaptiveBitrate.runDemoTest(library: library)
        } catch {
            testResult = nil
            testError = error.localizedDescription
        }
        isTesting = false
    }
}
