import SwiftUI

struct PlaybackSettingsView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(PlaybackPreferences.useNativeVideoPlayerKey) private var useNativeVideoPlayer = true
    @AppStorage(PlaybackPreferences.preferFMP4InHLSKey) private var preferFMP4InHLS = true
    @AppStorage(PlaybackPreferences.skipBackwardKey) private var skipBackward = 10
    @AppStorage(PlaybackPreferences.skipForwardKey) private var skipForward = 10
    @AppStorage(PlaybackPreferences.maxBitrateKey) private var maxBitrate = 0
    @AppStorage(PlaybackPreferences.autoPlayNextEpisodeKey) private var autoPlayNextEpisode = true
    @AppStorage(PlaybackPreferences.autoSkipIntroKey) private var autoSkipIntro = false
    @AppStorage(PlaybackPreferences.autoSkipCreditsKey) private var autoSkipCredits = false
    @AppStorage(PlaybackPreferences.defaultRateKey) private var defaultRate = 1.0

    var body: some View {
        Form {
            Section {
                Picker("Default Quality", selection: $maxBitrate) {
                    ForEach(PlaybackQuality.allCases) { quality in
                        Text(quality.title).tag(quality.rawValue)
                    }
                }
            } footer: {
                Text("Auto keeps Direct Play when the file fits this device. Lower rates ask Jellyfin to transcode.")
            }

            Section {
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
            } header: {
                Text("Controls")
            } footer: {
                Text("How far the skip buttons jump during playback.")
            }

            Section {
                Toggle("Auto Play Next Episode", isOn: $autoPlayNextEpisode)
                Toggle("Automatically Skip Intros", isOn: $autoSkipIntro)
                Toggle("Automatically Skip Credits", isOn: $autoSkipCredits)
            } header: {
                Text("Episodes")
            } footer: {
                Text("Skip Intro and Skip Outro need the Intro Skipper plugin on Jellyfin. Auto play starts the next episode when this one ends.")
            }

            Section {
                Picker("Playback Speed", selection: $defaultRate) {
                    ForEach(AVKitPlaybackSpeed.options, id: \.self) { rate in
                        Text(AVKitPlaybackSpeed.title(rate)).tag(Double(rate))
                    }
                }
                Toggle("Use Native Video Player", isOn: $useNativeVideoPlayer)
                Toggle("Prefer fMP4 in HLS", isOn: preferFMP4Binding)
                    .disabled(!useNativeVideoPlayer)
            } header: {
                Text("Player")
            } footer: {
                Text(playerFooter)
            }

            Section {
                HStack {
                    Text("Skip Intro / Outro")
                    Spacer()
                    Text(session.introSkipperAvailable ? "Installed" : "Not on this server")
                        .foregroundStyle(session.introSkipperAvailable ? .green : .secondary)
                }
            } header: {
                Text("Intro Skipper")
            } footer: {
                Text("Skip buttons appear during playback when the plugin is installed.")
            }
        }
        .zelefinSettingsChrome(title: "Playback and Controls")
        .onChange(of: useNativeVideoPlayer) {
            if !useNativeVideoPlayer {
                preferFMP4InHLS = true
            }
        }
        .task {
            await session.detectIntroSkipper()
        }
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
        if useNativeVideoPlayer {
            "AVPlayer plays Apple-compatible Direct Play and remuxed HLS. MKV and other files remux on the server first. Turn off Prefer fMP4 to ask Jellyfin for MPEG-TS instead of fragmented MP4."
        } else {
            "Zelefin Direct Play opens every stream, including remuxed HLS. Fragmented MP4 packaging stays on."
        }
    }
}
