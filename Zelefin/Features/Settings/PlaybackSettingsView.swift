import SwiftUI

struct PlaybackSettingsView: View {
    @AppStorage(PlaybackPreferences.useNativeVideoPlayerKey) private var useNativeVideoPlayer = false
    @AppStorage(PlaybackPreferences.preferFMP4InHLSKey) private var preferFMP4InHLS = true
    @AppStorage(PlaybackPreferences.skipBackwardKey) private var skipBackward = 10
    @AppStorage(PlaybackPreferences.skipForwardKey) private var skipForward = 10
    @AppStorage(PlaybackPreferences.maxBitrateKey) private var maxBitrate = 0
    @AppStorage(PlaybackPreferences.autoPlayNextEpisodeKey) private var autoPlayNextEpisode = true
    @AppStorage(PlaybackPreferences.defaultRateKey) private var defaultRate = 1.0

    var body: some View {
        Form {
            Section {
                Picker("Default Quality", selection: $maxBitrate) {
                    ForEach(PlaybackQuality.allCases) { quality in
                        Text(quality.title).tag(quality.rawValue)
                    }
                }
                .tint(Color.accentColor)
            } footer: {
                Text("Auto keeps Direct Play when the file fits this device. Lower rates ask Jellyfin to transcode.")
            }

            Section {
                Picker("Skip Backward", selection: $skipBackward) {
                    ForEach(PlaybackSkipInterval.allCases) { interval in
                        Text(interval.title).tag(interval.rawValue)
                    }
                }
                .tint(Color.accentColor)
                Picker("Skip Forward", selection: $skipForward) {
                    ForEach(PlaybackSkipInterval.allCases) { interval in
                        Text(interval.title).tag(interval.rawValue)
                    }
                }
                .tint(Color.accentColor)
            } header: {
                Text("Controls")
            } footer: {
                Text("How far the skip buttons jump during playback.")
            }

            Section {
                Toggle("Auto Play Next Episode", isOn: $autoPlayNextEpisode)
                    .tint(Color.accentColor)
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
                .tint(Color.accentColor)
                Toggle("Use Native Video Player", isOn: $useNativeVideoPlayer)
                    .tint(Color.accentColor)
                Toggle("Prefer fMP4 in HLS", isOn: preferFMP4Binding)
                    .tint(Color.accentColor)
                    .disabled(!useNativeVideoPlayer)
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
