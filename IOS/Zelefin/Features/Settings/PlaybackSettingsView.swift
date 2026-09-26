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
    @AppStorage(PlaybackPreferences.audioLanguageKey) private var audioLanguage = PlaybackLanguage.automaticCode
    @AppStorage(PlaybackPreferences.subtitleLanguageKey) private var subtitleLanguage = PlaybackLanguage.automaticCode

    @State private var isTesting = false
    @State private var testError: String?
    @State private var testResult: BitrateProbeResult?

    var body: some View {
        Form {
            languageSection
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

    private var languageSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                SettingsFieldLabel(title: "Audio")
                    .padding(.bottom, 8)
                Picker("Audio", selection: $audioLanguage) {
                    ForEach(audioChoices, id: \.self) { code in
                        Text(PlaybackLanguage.displayName(for: code)).tag(code)
                    }
                }
                .pickerStyle(.menu)
                .tint(AccentPreferences.current)
                SettingsCardDivider()
                SettingsFieldLabel(title: "Subtitles")
                    .padding(.bottom, 8)
                Picker("Subtitles", selection: $subtitleLanguage) {
                    ForEach(subtitleChoices, id: \.self) { code in
                        Text(PlaybackLanguage.displayName(for: code)).tag(code)
                    }
                }
                .pickerStyle(.menu)
                .tint(AccentPreferences.current)
            }
            .settingsLoginCard()
            .settingsCardRow()
        } header: {
            Text("Languages")
        } footer: {
            Text("Automatic uses the title default. A language is used when that track exists.")
        }
        .onChange(of: audioLanguage) { _, code in
            Task { await session.applyPlaybackLanguages(audioCode: code, subtitleCode: subtitleLanguage) }
        }
        .onChange(of: subtitleLanguage) { _, code in
            Task { await session.applyPlaybackLanguages(audioCode: audioLanguage, subtitleCode: code) }
        }
    }

    private var audioChoices: [String] {
        [PlaybackLanguage.automaticCode] + SubtitleSearchLanguage.choices.map(\.code)
    }

    private var subtitleChoices: [String] {
        [PlaybackLanguage.automaticCode, PlaybackLanguage.offCode] + SubtitleSearchLanguage.choices.map(\.code)
    }

    private var qualitySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                Toggle("Adaptive Bitrate", isOn: $adaptiveBitrate)
                    .tint(AccentPreferences.current)
                    .font(.body.weight(.semibold))
                SettingsCardDivider()
                SettingsFieldLabel(title: adaptiveBitrate ? "Maximum Quality" : "Quality")
                    .padding(.bottom, 8)
                Picker(adaptiveBitrate ? "Maximum Quality" : "Quality", selection: $maxBitrate) {
                    ForEach(PlaybackQuality.allCases) { quality in
                        Text(quality.title).tag(quality.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(AccentPreferences.current)
                SettingsCardDivider()
                SettingsInfoRow(label: "Connection", value: session.adaptiveBitrate.path.transport.title)
                if let testResult {
                    SettingsCardDivider()
                    SettingsInfoRow(label: "Measured", value: PlaybackStats.bitrateLabel(Int64(testResult.bitsPerSecond)))
                    SettingsCardDivider()
                    SettingsInfoRow(label: "Recommended", value: recommendedTitle(for: testResult))
                }
                if let testError {
                    SettingsStatusText(text: testError, isError: true)
                        .padding(.top, 12)
                }
                SettingsPrimaryButton(
                    title: "Test Connection",
                    isBusy: isTesting,
                    enabled: session.library != nil
                ) {
                    Task { await runDemoTest() }
                }
                .padding(.top, 16)
            }
            .settingsLoginCard()
            .settingsCardRow()
        } header: {
            Text("Quality")
        } footer: {
            Text(qualityFooter)
        }
    }

    private var watchingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                SettingsFieldLabel(title: "Playback Speed")
                    .padding(.bottom, 8)
                Picker("Playback Speed", selection: $defaultRate) {
                    ForEach(AVKitPlaybackSpeed.options, id: \.self) { rate in
                        Text(AVKitPlaybackSpeed.title(rate)).tag(Double(rate))
                    }
                }
                .pickerStyle(.menu)
                .tint(AccentPreferences.current)
                SettingsCardDivider()
                Toggle("Auto Play Next Episode", isOn: $autoPlayNextEpisode)
                    .tint(AccentPreferences.current)
                    .font(.body.weight(.semibold))
                SettingsCardDivider()
                SettingsFieldLabel(title: "Skip Backward")
                    .padding(.bottom, 8)
                Picker("Skip Backward", selection: $skipBackward) {
                    ForEach(PlaybackSkipInterval.allCases) { interval in
                        Text(interval.title).tag(interval.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(AccentPreferences.current)
                SettingsCardDivider()
                SettingsFieldLabel(title: "Skip Forward")
                    .padding(.bottom, 8)
                Picker("Skip Forward", selection: $skipForward) {
                    ForEach(PlaybackSkipInterval.allCases) { interval in
                        Text(interval.title).tag(interval.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(AccentPreferences.current)
            }
            .settingsLoginCard()
            .settingsCardRow()
        } header: {
            Text("Watching")
        } footer: {
            Text("Speed, skip distance, and whether the next episode starts when this one ends.")
        }
    }

    private var playerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                Toggle("Use Native Video Player", isOn: $useNativeVideoPlayer)
                    .tint(AccentPreferences.current)
                    .font(.body.weight(.semibold))
                if useNativeVideoPlayer {
                    SettingsCardDivider()
                    Toggle("Prefer fMP4 in HLS", isOn: preferFMP4Binding)
                        .tint(AccentPreferences.current)
                        .font(.body.weight(.semibold))
                }
            }
            .settingsLoginCard()
            .settingsCardRow()
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
