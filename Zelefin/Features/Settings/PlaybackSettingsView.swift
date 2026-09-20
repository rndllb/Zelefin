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
            qualitySection
            watchingSection
            playerSection
        }
        .zelefinSettingsChrome(title: "Playback")
        .onChange(of: useNativeVideoPlayer) {
            if !useNativeVideoPlayer {
                preferFMP4InHLS = true
            }
        }
    }

    private var qualitySection: some View {
        Section {
            Toggle("Adaptive Bitrate", isOn: $adaptiveBitrate)
                .tint(AccentPreferences.current)
            Picker(adaptiveBitrate ? "Maximum Quality" : "Quality", selection: $maxBitrate) {
                ForEach(PlaybackQuality.allCases) { quality in
                    Text(quality.title).tag(quality.rawValue)
                }
            }
            .tint(AccentPreferences.current)

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
                        Text("Test Connection")
                        Spacer()
                        ProgressView()
                    }
                } else {
                    Text("Test Connection")
                }
            }
            .disabled(isTesting || session.library == nil)
        } header: {
            Text("Quality")
        } footer: {
            Text(qualityFooter)
        }
    }

    private var watchingSection: some View {
        Section {
            Picker("Playback Speed", selection: $defaultRate) {
                ForEach(AVKitPlaybackSpeed.options, id: \.self) { rate in
                    Text(AVKitPlaybackSpeed.title(rate)).tag(Double(rate))
                }
            }
            .tint(AccentPreferences.current)
            Toggle("Auto Play Next Episode", isOn: $autoPlayNextEpisode)
                .tint(AccentPreferences.current)
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
            Text("Watching")
        } footer: {
            Text("Speed, skip distance, and whether the next episode starts when this one ends.")
        }
    }

    private var playerSection: some View {
        Section {
            Toggle("Use Native Video Player", isOn: $useNativeVideoPlayer)
                .tint(AccentPreferences.current)
            if useNativeVideoPlayer {
                Toggle("Prefer fMP4 in HLS", isOn: preferFMP4Binding)
                    .tint(AccentPreferences.current)
            }
        } header: {
            Text("Player")
        } footer: {
            Text(playerFooter)
        }
    }

    private var qualityFooter: String {
        if adaptiveBitrate {
            return session.usesSilo
                ? "Auto Direct Plays the original file. A lower Maximum Quality is the only start cap. Test Connection measures this path if playback later stalls."
                : "Auto Direct Plays when the file fits this connection. Jellyfin transcodes when it does not. Test Connection measures this path."
        }
        return session.usesSilo
            ? "Auto Direct Plays when the file fits this device. Lower quality asks Silo to transcode."
            : "Auto Direct Plays when the file fits this device. Lower quality asks Jellyfin to transcode."
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
                return "Apple’s player opens MP4 and HLS. MKV still Direct Plays on this device. Turn off Prefer fMP4 to ask Silo for MPEG-TS when HLS is required."
            }
            return "Zelefin Direct Plays the original Silo file on this device, including HDR."
        }
        if useNativeVideoPlayer {
            return "Apple’s player opens MP4 and remuxed HLS. MKV remuxes on Jellyfin first. Turn off Prefer fMP4 to ask for MPEG-TS."
        }
        return "Zelefin Direct Plays every stream on this device, including remuxed HLS."
    }

    private func recommendedTitle(for result: BitrateProbeResult) -> String {
        quality(for: result, sourceBitrate: nil).title
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
