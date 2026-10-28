import JellyfinAPI
import SwiftUI

struct PlaybackSettingsView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(PlaybackPreferences.playerEngineKey) private var playerEngine = PlaybackPreferences.playerEngine
    @AppStorage(PlaybackPreferences.preferFMP4InHLSKey) private var preferFMP4InHLS = true
    @AppStorage(PlaybackPreferences.skipBackwardKey) private var skipBackward = 10
    @AppStorage(PlaybackPreferences.skipForwardKey) private var skipForward = 10
    @AppStorage(PlaybackPreferences.maxBitrateKey) private var maxBitrate = 0
    @AppStorage(PlaybackPreferences.adaptiveBitrateKey) private var adaptiveBitrate = true
    @AppStorage(PlaybackPreferences.autoPlayNextEpisodeKey) private var autoPlayNextEpisode = true
    @AppStorage(PlaybackPreferences.themeSongsKey) private var themeSongs = false
    @AppStorage(PlaybackPreferences.themeVideosKey) private var themeVideos = false
    @AppStorage(PlaybackPreferences.themeVideoSoundKey) private var themeVideoSound = false
    @AppStorage(PlaybackPreferences.defaultRateKey) private var defaultRate = 1.0
    @AppStorage(PlaybackPreferences.preferSDHKey) private var preferSDH = false
    @AppStorage(PlaybackPreferences.downloadWifiOnlyKey) private var downloadWifiOnly = false

    @State private var isTesting = false
    @State private var testError: String?
    @State private var testResult: BitrateProbeResult?

    @State private var serverPreferences: JellyfinPlaybackPreferences?
    @State private var isLoadingServerPreferences = false
    @State private var serverPreferencesError: String?

    var body: some View {
        Form {
            serverAudioSection
            serverSubtitleSection
            qualitySection
            watchingSection
            themeMediaSection
        }
        .zelefinSettingsChrome(title: "Playback")
        .task { await loadServerPreferences() }
        .onChange(of: useNativeVideoPlayer) {
            if !useNativeVideoPlayer {
                preferFMP4InHLS = true
            }
        }
    }

    // MARK: Jellyfin user settings

    private var serverProduct: String {
        session.isEmbyServer ? "Emby" : "Jellyfin"
    }

    private var serverAudioSection: some View {
        Section {
            Picker("Preferred Language", selection: serverBinding(\.audioLanguage)) {
                ForEach(serverLanguageChoices(including: serverPreferences?.audioLanguage), id: \.self) { code in
                    Text(PlaybackLanguage.displayName(for: code)).tag(code)
                }
            }
            Toggle("Play Default Audio Track", isOn: serverBinding(\.playDefaultAudioTrack))
            if let serverPreferencesError {
                SettingsStatusText(text: serverPreferencesError, isError: true)
            }
        } header: {
            HStack {
                Text("Audio")
                if isLoadingServerPreferences {
                    ProgressView().controlSize(.mini)
                }
            }
        } footer: {
            Text(
                serverPreferences?.playDefaultAudioTrack == true
                    ? "The file’s default audio track plays even when a track in your preferred language exists. Saved to your \(serverProduct) account."
                    : "Titles start on the audio track in your preferred language when the file has one. Saved to your \(serverProduct) account."
            )
        }
        .zelefinRowBackground()
        .disabled(serverPreferences == nil)
    }

    private var serverSubtitleSection: some View {
        Section {
            Picker("Preferred Language", selection: serverBinding(\.subtitleLanguage)) {
                ForEach(serverLanguageChoices(including: serverPreferences?.subtitleLanguage), id: \.self) { code in
                    Text(PlaybackLanguage.displayName(for: code)).tag(code)
                }
            }
            Picker("Subtitle Mode", selection: serverBinding(\.subtitleMode)) {
                ForEach(SubtitlePlaybackMode.choices, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Toggle("Prefer SDH Subtitles", isOn: $preferSDH)
            NavigationLink {
                SubtitleAppearanceSettingsView()
            } label: {
                LabeledContent("Style & Sync") {
                    Text(SubtitleAppearance.size.title)
                }
            }
        } header: {
            Text("Subtitles")
        } footer: {
            Text((serverPreferences?.subtitleMode ?? .default).summary + " SDH prefers captions that describe music and sound. Style & Sync change how captions look and when they appear.")
        }
        .zelefinRowBackground()
        .disabled(serverPreferences == nil)
    }

    private func serverBinding<Value>(_ keyPath: WritableKeyPath<JellyfinPlaybackPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { (serverPreferences ?? JellyfinPlaybackPreferences())[keyPath: keyPath] },
            set: { newValue in
                guard var updated = serverPreferences else { return }
                updated[keyPath: keyPath] = newValue
                guard updated != serverPreferences else { return }
                serverPreferences = updated
                Task { await saveServerPreferences(updated) }
            }
        )
    }

    /// A code the server already holds stays selectable even when the picker list lacks it.
    private func serverLanguageChoices(including current: String?) -> [String] {
        var codes = [JellyfinPlaybackPreferences.anyLanguage] + SubtitleSearchLanguage.choices.map(\.code)
        if let current, !current.isEmpty, !codes.contains(current) {
            codes.append(current)
        }
        return codes
    }

    private func loadServerPreferences() async {
        isLoadingServerPreferences = true
        defer { isLoadingServerPreferences = false }
        do {
            serverPreferences = try await session.jellyfinPlaybackPreferences()
            serverPreferencesError = nil
        } catch {
            serverPreferencesError = "Zelefin could not load your \(serverProduct) playback settings. \(error.localizedDescription)"
        }
    }

    private func saveServerPreferences(_ preferences: JellyfinPlaybackPreferences) async {
        do {
            try await session.saveJellyfinPlaybackPreferences(preferences)
            serverPreferencesError = nil
        } catch {
            serverPreferencesError = "\(serverProduct) did not save that change. \(error.localizedDescription)"
            await loadServerPreferences()
        }
    }

    private var qualitySection: some View {
        Section {
            Toggle("Adaptive Bitrate", isOn: $adaptiveBitrate)
            Picker(adaptiveBitrate ? "Maximum Quality" : "Quality", selection: $maxBitrate) {
                ForEach(PlaybackQuality.allCases) { quality in
                    Text(quality.title).tag(quality.rawValue)
                }
            }
            LabeledContent("Connection", value: session.adaptiveBitrate.path.transport.title)
            if let testResult {
                LabeledContent("Measured", value: PlaybackStats.bitrateLabel(Int64(testResult.bitsPerSecond)))
                LabeledContent("Recommended", value: recommendedTitle(for: testResult))
            }
            if let testError {
                SettingsStatusText(text: testError, isError: true)
            }
            Button("Test Connection") {
                Task { await runDemoTest() }
            }
            .disabled(isTesting || session.library == nil)
        } header: {
            Text("Quality")
        } footer: {
            Text(qualityFooter)
        }
        .zelefinRowBackground()
    }

    private var themeMediaSection: some View {
        Section {
            Toggle("Theme Songs", isOn: $themeSongs)
            // Silo's Jellyfin-compatible API serves theme songs but never theme videos.
            if !session.isSiloServer {
                Toggle("Theme Videos", isOn: $themeVideos)
                if themeVideos {
                    Toggle("Theme Video Sound", isOn: $themeVideoSound)
                }
            }
        } header: {
            Text("Theme Media")
        } footer: {
            Text(session.isSiloServer
                 ? "Plays a title's theme song on its page."
                 : "Plays a title's \(serverProduct) theme video in place of the backdrop, or its theme song when it has no video. Theme videos are muted unless Theme Video Sound is on.")
        }
        .zelefinRowBackground()
    }

    private var watchingSection: some View {
        Section {
            Picker("Playback Speed", selection: $defaultRate) {
                ForEach(AVKitPlaybackSpeed.options, id: \.self) { rate in
                    Text(AVKitPlaybackSpeed.title(rate)).tag(Double(rate))
                }
            }
            Toggle("Auto Play Next Episode", isOn: $autoPlayNextEpisode)
            Picker("Skip Backward", selection: $skipBackward) {
                ForEach(PlaybackSkipInterval.allCases) { interval in
                    Text(interval.title).tag(interval.rawValue)
                }
            }
            Picker("Skip Forward", selection: $skipForward) {
                ForEach(PlaybackSkipInterval.allCases) { interval in
                    Text(interval.title).tag(interval.rawValue)
                }
            }
            Picker("Player Engine", selection: $playerEngine) {
                ForEach(PlayerEngineChoice.available) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.menu)
            if useNativeVideoPlayer {
                Toggle("Prefer fMP4 in HLS", isOn: preferFMP4Binding)
            }
            Toggle("Wi-Fi Only Downloads", isOn: $downloadWifiOnly)
        } header: {
            Text("Watching")
        } footer: {
            Text("Speed, skip distance, and whether the next episode starts when this one ends. " + playerFooter)
        }
        .zelefinRowBackground()
    }

    private var qualityFooter: String {
        if adaptiveBitrate {
            return "Auto Direct Plays when the file fits this connection. The server transcodes when it does not. Test Connection measures this path."
        }
        return "Auto Direct Plays when the file fits this device. Lower quality asks the server to transcode."
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

    private var useNativeVideoPlayer: Bool {
        playerEngine == .native
    }

    private var playerFooter: String {
        switch playerEngine {
        case .native:
            return "Apple’s player opens MP4 and remuxed HLS. MKV remuxes on Jellyfin first. Turn off Prefer fMP4 to ask for MPEG-TS."
        case .mpv:
            return "MPV Direct Plays every stream on this device and lists every audio and subtitle track in the file, including styled subtitles."
        case .aether:
            return "AetherEngine Direct Plays every stream on this device, including remuxed HLS."
        }
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
