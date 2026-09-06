import AetherEngine
import Foundation
import UIKit

typealias DirectPlayEngine = AetherEngine
typealias DirectPlayPlayerView = AetherPlayerView
typealias DirectPlayByteSource = IOReader
typealias DirectPlayPiPSource = SoftwarePiPSource
typealias DirectPlayTrack = TrackInfo
typealias DirectPlaySubtitleCue = SubtitleCue
typealias DirectPlaySubtitlePlacement = SubtitleTextPlacement
typealias DirectPlaySubtitleImage = SubtitleImage
typealias DirectPlayVideoFormat = VideoFormat
typealias DirectPlayVideoRoute = VideoRoute
typealias DirectPlayAudioDelivery = AudioDelivery
typealias DirectPlayPlaybackPhase = PlaybackPhase
typealias DirectPlaySeekEvent = SeekEvent

/// Session options for Zelefin Direct Play: FFmpeg demux through `JellyfinByteRangeReader`,
/// VideoToolbox decode, `AVSampleBufferDisplayLayer` presentation.
enum DirectPlayLoadOptions {
    static func usesSampleBufferDecode(for pipeline: PlaybackPipeline) -> Bool {
        switch pipeline {
        case .directDecode:
            true
        case .appleNative:
            false
        }
    }

    @MainActor
    static func make(for plan: PlaybackPlan) -> LoadOptions {
        var headers = PlaybackHTTPHeaders.fields(for: plan.streamURL)
        for (name, value) in plan.extraHTTPHeaders {
            headers[name] = value
        }
        let selectedAudioLanguage = plan.audioTracks.first(where: \.isSelected)?.language
        let selectedSubtitleLanguage = plan.subtitleTracks.first(where: \.isSelected)?.language
        let duration = plan.item.runtime.flatMap { seconds in
            seconds > 0 ? seconds : nil
        }
        return LoadOptions(
            httpHeaders: headers,
            matchContentEnabled: true,
            panelIsInHDRMode: isPanelInHDRMode,
            prepareNativeSubtitles: false,
            eagerNativeSubtitleReaders: false,
            maxConcurrentSourceRequests: 2,
            declaredDurationSeconds: duration,
            preferredAudioLanguages: languageList(selectedAudioLanguage),
            preferredSubtitleLanguages: languageList(selectedSubtitleLanguage),
            preferredDecodePath: usesSampleBufferDecode(for: .directDecode) ? .software : .automatic
        )
    }

    private static func languageList(_ language: String?) -> [String] {
        guard let language else { return [] }
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "und" else { return [] }
        return [trimmed]
    }

    @MainActor
    private static var isPanelInHDRMode: Bool {
        UIScreen.main.currentEDRHeadroom > 1
    }
}
