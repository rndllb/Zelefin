import XCTest
@testable import Zelefin

final class PlaybackPipelineTests: XCTestCase {
    func testMP4DirectPlayUsesAppleNativeWhenNativePlayerIsOn() {
        let url = URL(string: "https://jellyfin.example.com/Videos/1/stream.mp4?static=true")
        guard let url else {
            return XCTFail("URL")
        }
        XCTAssertEqual(PlaybackPipelineResolver.pipeline(url: url, method: .directPlay), .appleNative)
        XCTAssertFalse(
            PlaybackPipelineResolver.needsServerRemuxForNativePlayer(
                url: url,
                method: .directPlay,
                container: "mp4",
                videoCodec: "h264"
            )
        )
    }

    func testHLSRemuxUsesAppleNative() {
        let url = URL(string: "https://jellyfin.example.com/Videos/1/master.m3u8?DeviceId=abc")
        guard let url else {
            return XCTFail("URL")
        }
        XCTAssertEqual(PlaybackPipelineResolver.pipeline(url: url, method: .remux), .appleNative)
        XCTAssertEqual(PlaybackPipelineResolver.pipeline(url: url, method: .transcode), .appleNative)
        XCTAssertFalse(
            PlaybackPipelineResolver.needsServerRemuxForNativePlayer(url: url, method: .remux)
        )
    }

    func testHLSRemuxUsesDirectDecodeWhenNativePlayerIsOff() {
        let url = URL(string: "https://jellyfin.example.com/Videos/1/master.m3u8?DeviceId=abc")
        guard let url else {
            return XCTFail("URL")
        }
        XCTAssertEqual(
            PlaybackPipelineResolver.pipeline(url: url, method: .remux, usesNativePlayer: false),
            .directDecode
        )
        XCTAssertEqual(
            PlaybackPipelineResolver.pipeline(url: url, method: .transcode, usesNativePlayer: false),
            .directDecode
        )
        XCTAssertFalse(
            PlaybackPipelineResolver.needsServerRemuxForNativePlayer(
                url: url,
                method: .remux,
                usesNativePlayer: false
            )
        )
    }

    func testFMP4HLSIsForcedWhenNativePlayerIsOff() {
        XCTAssertTrue(PlaybackPreferences.usesFMP4HLS(nativePlayer: false, preferFMP4: false))
        XCTAssertTrue(PlaybackPreferences.usesFMP4HLS(nativePlayer: false, preferFMP4: true))
        XCTAssertTrue(PlaybackPreferences.usesFMP4HLS(nativePlayer: true, preferFMP4: true))
        XCTAssertFalse(PlaybackPreferences.usesFMP4HLS(nativePlayer: true, preferFMP4: false))
    }

    func testMKVDirectPlayRemuxesForNativePlayer() {
        let url = URL(string: "https://jellyfin.example.com/Videos/1/stream.mkv?static=true")
        guard let url else {
            return XCTFail("URL")
        }
        XCTAssertTrue(
            PlaybackPipelineResolver.needsServerRemuxForNativePlayer(
                url: url,
                method: .directPlay,
                container: "mkv"
            )
        )
        XCTAssertEqual(PlaybackPipelineResolver.pipeline(url: url, method: .directPlay), .appleNative)
        XCTAssertEqual(
            PlaybackPipelineResolver.pipeline(url: url, method: .directPlay, usesNativePlayer: false),
            .directDecode
        )
        XCTAssertFalse(
            PlaybackPipelineResolver.needsServerRemuxForNativePlayer(
                url: url,
                method: .directPlay,
                container: "mkv",
                usesNativePlayer: false
            )
        )
    }

    func testMPEG4InMP4RemuxesForNativePlayer() {
        let url = URL(string: "https://jellyfin.example.com/Videos/1/stream.mp4?static=true")
        guard let url else {
            return XCTFail("URL")
        }
        XCTAssertTrue(
            PlaybackPipelineResolver.needsServerRemuxForNativePlayer(
                url: url,
                method: .directPlay,
                container: "mp4",
                videoCodec: "mpeg4"
            )
        )
        XCTAssertTrue(
            PlaybackPipelineResolver.needsServerRemuxForNativePlayer(
                url: url,
                method: .directPlay,
                container: "mp4",
                videoCodec: "mpeg2video"
            )
        )
    }

    func testH264InMP4OpensNatively() {
        let url = URL(string: "https://jellyfin.example.com/Videos/1/stream.mp4?static=true")
        guard let url else {
            return XCTFail("URL")
        }
        XCTAssertEqual(
            PlaybackPipelineResolver.pipeline(url: url, method: .directPlay, container: "mp4", videoCodec: "h264"),
            .appleNative
        )
        XCTAssertFalse(
            PlaybackPipelineResolver.needsServerRemuxForNativePlayer(
                url: url,
                method: .directPlay,
                container: "mp4",
                videoCodec: "h264"
            )
        )
    }

    func testMPEGTSDirectPlayRemuxesForNativePlayer() {
        let url = URL(string: "https://jellyfin.example.com/Videos/1/stream.ts?static=true")
        guard let url else {
            return XCTFail("URL")
        }
        XCTAssertTrue(
            PlaybackPipelineResolver.needsServerRemuxForNativePlayer(
                url: url,
                method: .directPlay,
                container: "ts"
            )
        )
        XCTAssertEqual(
            PlaybackPipelineResolver.pipeline(url: url, method: .directPlay, usesNativePlayer: false),
            .directDecode
        )
    }
}

final class PlaybackSettingsPolicyTests: XCTestCase {
    func testAutoQualityUsesTheDeviceCeiling() {
        XCTAssertEqual(PlaybackQuality.auto.bitsPerSecond, AVDeviceProfileFactory.maxBitrate)
        XCTAssertEqual(PlaybackQuality.mbps8.bitsPerSecond, 8_000_000)
        XCTAssertEqual(PlaybackQuality.resolved(8_000_000), .mbps8)
        XCTAssertEqual(PlaybackQuality.resolved(99), .auto)
    }

    func testSkipIntervalFallsBackToTen() {
        XCTAssertEqual(PlaybackSkipInterval.resolved(15), .fifteen)
        XCTAssertEqual(PlaybackSkipInterval.resolved(7), .ten)
    }

    func testPlaybackSpeedSnapsToAKnownOption() {
        XCTAssertEqual(AVKitPlaybackSpeed.resolved(nil), 1)
        XCTAssertEqual(AVKitPlaybackSpeed.resolved(1.25), 1.25)
        XCTAssertEqual(AVKitPlaybackSpeed.resolved(1.3), 1.25)
    }

    func testAutoSkipRespectsKindToggles() {
        XCTAssertTrue(PlaybackPreferences.shouldAutoSkip(.intro, intro: true, credits: false))
        XCTAssertFalse(PlaybackPreferences.shouldAutoSkip(.outro, intro: true, credits: false))
        XCTAssertTrue(PlaybackPreferences.shouldAutoSkip(.outro, intro: false, credits: true))
        XCTAssertFalse(PlaybackPreferences.shouldAutoSkip(.intro, intro: false, credits: true))
    }

    func testQualityIsWrittenIntoTheDeviceProfile() {
        let profile = AVDeviceProfileFactory.make(preferFMP4InHLS: true, maxBitrate: 8_000_000)
        XCTAssertEqual(profile.maxStreamingBitrate, 8_000_000)
        XCTAssertEqual(profile.maxStaticBitrate, 8_000_000)
    }

    func testNextEpisodeFollowsSeasonOrder() {
        let current = episode(id: "s1e2", season: 1, number: 2)
        let episodes = [
            episode(id: "s1e1", season: 1, number: 1),
            current,
            episode(id: "s1e3", season: 1, number: 3),
            episode(id: "s2e1", season: 2, number: 1),
        ]
        XCTAssertEqual(PlaybackEpisodeAdvance.next(after: current, in: episodes)?.id, "s1e3")
        XCTAssertEqual(
            PlaybackEpisodeAdvance.next(after: episode(id: "s1e3", season: 1, number: 3), in: episodes)?.id,
            "s2e1"
        )
        XCTAssertNil(PlaybackEpisodeAdvance.next(after: episode(id: "s2e1", season: 2, number: 1), in: episodes))
    }

    func testMoviesHaveNoNextEpisode() {
        let movie = MediaItem(
            id: "m1",
            name: "Dune",
            kind: .movie,
            overview: nil,
            year: 2024,
            runtime: 100,
            officialRating: nil,
            genres: [],
            seriesName: nil,
            seasonIndex: nil,
            episodeIndex: nil,
            playbackPosition: 0,
            unplayedCount: nil,
            isPlayed: false,
            primaryImageTag: nil,
            thumbImageTag: nil,
            backdropImageTag: nil,
            backdropImageTags: [],
            logoImageTag: nil,
            parentBackdropItemID: nil,
            parentThumbItemID: nil,
            parentThumbImageTag: nil,
            parentLogoItemID: nil,
            parentLogoImageTag: nil,
            seriesThumbImageTag: nil,
            seriesID: nil,
            imageItemID: nil,
            queueKind: .resume,
            videoRange: .sdr,
            audioFormat: .stereo
        )
        XCTAssertNil(PlaybackEpisodeAdvance.next(after: movie, in: [movie]))
    }

    private func episode(id: String, season: Int, number: Int) -> MediaItem {
        MediaItem(
            id: id,
            name: id,
            kind: .episode,
            overview: nil,
            year: 2024,
            runtime: 3600,
            officialRating: nil,
            genres: [],
            seriesName: "Silo",
            seasonIndex: season,
            episodeIndex: number,
            playbackPosition: 0,
            unplayedCount: nil,
            isPlayed: false,
            primaryImageTag: nil,
            thumbImageTag: nil,
            backdropImageTag: nil,
            backdropImageTags: [],
            logoImageTag: nil,
            parentBackdropItemID: nil,
            parentThumbItemID: nil,
            parentThumbImageTag: nil,
            parentLogoItemID: nil,
            parentLogoImageTag: nil,
            seriesThumbImageTag: nil,
            seriesID: "silo",
            imageItemID: nil,
            queueKind: .nextUp,
            videoRange: .sdr,
            audioFormat: .stereo
        )
    }
}

final class DirectPlayEngineTests: XCTestCase {
    func testAudioOnlyProbeRetriesThroughTheHTTPURL() {
        XCTAssertTrue(DirectPlayLoadPolicy.shouldReloadAsURL(isAudioOnlyBackend: true, expectsVideo: true))
        XCTAssertFalse(DirectPlayLoadPolicy.shouldReloadAsURL(isAudioOnlyBackend: false, expectsVideo: true))
        XCTAssertFalse(DirectPlayLoadPolicy.shouldReloadAsURL(isAudioOnlyBackend: true, expectsVideo: false))
    }

    func testHLSOpensAsAnHTTPURLInsteadOfByteRangeIO() {
        XCTAssertTrue(DirectPlayLoadPolicy.shouldOpenAsHTTPURL(method: .remux, isHLS: true))
        XCTAssertTrue(DirectPlayLoadPolicy.shouldOpenAsHTTPURL(method: .transcode, isHLS: true))
        XCTAssertTrue(DirectPlayLoadPolicy.shouldOpenAsHTTPURL(method: .directPlay, isHLS: true))
        XCTAssertFalse(DirectPlayLoadPolicy.shouldOpenAsHTTPURL(method: .directPlay, isHLS: false))
    }

    func testMKVDirectPlayUsesSampleBufferDecode() {
        XCTAssertTrue(DirectPlayLoadOptions.usesSampleBufferDecode(for: .directDecode))
        XCTAssertFalse(DirectPlayLoadOptions.usesSampleBufferDecode(for: .appleNative))
    }

    func testForegroundRestoreRunsAfterBackgroundNotControlCenter() {
        XCTAssertTrue(PlaybackForegroundRecovery.shouldRestore(wasBackgrounded: true, pictureInPictureActive: false))
        XCTAssertFalse(PlaybackForegroundRecovery.shouldRestore(wasBackgrounded: false, pictureInPictureActive: false))
        XCTAssertFalse(PlaybackForegroundRecovery.shouldRestore(wasBackgrounded: true, pictureInPictureActive: true))
    }

    func testPictureInPictureWaitsForAWindowedLayer() {
        XCTAssertTrue(PlaybackPictureInPicturePolicy.canCreateController(isSupported: true, layerIsInWindow: true))
        XCTAssertFalse(PlaybackPictureInPicturePolicy.canCreateController(isSupported: true, layerIsInWindow: false))
        XCTAssertFalse(PlaybackPictureInPicturePolicy.canCreateController(isSupported: false, layerIsInWindow: true))
    }

    func testPlaybackKeepsRunningWhenPictureInPictureStarts() {
        XCTAssertFalse(PlaybackPictureInPicturePolicy.shouldStopOnViewDismiss(pictureInPictureActive: true))
        XCTAssertTrue(PlaybackPictureInPicturePolicy.shouldStopOnViewDismiss(pictureInPictureActive: false))
    }

    func testDirectPlayResumeSeekStaysOnNativePath() {
        XCTAssertFalse(DirectPlaySeekPolicy.allowsAutomaticResumeSeek(.directDecode))
        XCTAssertTrue(DirectPlaySeekPolicy.allowsAutomaticResumeSeek(.appleNative))
    }

    func testDirectPlaySeeksKeepOnlyTheLatestTarget() {
        var pending: TimeInterval?
        XCTAssertTrue(DirectPlaySeekCoalesce.enqueue(pending: &pending, latest: 10, isDraining: false))
        XCTAssertEqual(pending, 10)
        XCTAssertFalse(DirectPlaySeekCoalesce.enqueue(pending: &pending, latest: 513, isDraining: true))
        XCTAssertEqual(pending, 513)
        XCTAssertFalse(DirectPlaySeekCoalesce.enqueue(pending: &pending, latest: 0, isDraining: true))
        XCTAssertEqual(pending, 0)
    }

    func testJellyfinProgressWaitsUntilThePictureLands() {
        XCTAssertFalse(DirectPlayProgressPolicy.shouldReport(playheadTrusted: false))
        XCTAssertTrue(DirectPlayProgressPolicy.shouldReport(playheadTrusted: true))
        XCTAssertFalse(DirectPlayProgressPolicy.playheadTrusted(after: .began))
        XCTAssertFalse(DirectPlayProgressPolicy.playheadTrusted(after: .stalled))
        XCTAssertFalse(DirectPlayProgressPolicy.playheadTrusted(after: .superseded))
        XCTAssertTrue(DirectPlayProgressPolicy.playheadTrusted(after: .landed(renderedTime: 513)))
        XCTAssertTrue(DirectPlayProgressPolicy.playheadTrusted(after: .rejected(.noActiveSession)))
    }
}

final class HTTPRangeSupportTests: XCTestCase {
    func testRangeHeaderSpansTheHalfOpenWindow() {
        XCTAssertEqual(HTTPRangeSupport.rangeHeader(offset: 0, length: 1), "bytes=0-0")
        XCTAssertEqual(HTTPRangeSupport.rangeHeader(offset: 2048, length: 4096), "bytes=2048-6143")
    }

    func testContentRangeTotalIsParsed() {
        XCTAssertEqual(HTTPRangeSupport.parseContentRangeTotal("bytes 0-0/12345"), 12_345)
        XCTAssertEqual(HTTPRangeSupport.parseContentRangeTotal("bytes 2048-6143/34960244736"), 34_960_244_736)
        XCTAssertNil(HTTPRangeSupport.parseContentRangeTotal("bytes 0-0/*"))
        XCTAssertNil(HTTPRangeSupport.parseContentRangeTotal("garbage"))
    }

    func testReadAheadGrowsOnSequentialReads() {
        XCTAssertEqual(
            HTTPRangeSupport.nextChunkSize(position: 4096, lastFetchEnd: 4096, current: 4096, base: 4096, maxChunk: 32_768),
            8192
        )
        XCTAssertEqual(
            HTTPRangeSupport.nextChunkSize(position: 200_000, lastFetchEnd: 8192, current: 16_384, base: 4096, maxChunk: 32_768),
            4096
        )
    }

    func testFFmpegSizeQuerySurvivesForceFlag() {
        XCTAssertTrue(HTTPRangeSupport.reportsSize(HTTPRangeSupport.avSeekSize))
        XCTAssertTrue(HTTPRangeSupport.reportsSize(HTTPRangeSupport.avSeekSize | HTTPRangeSupport.avSeekForce))
        XCTAssertFalse(HTTPRangeSupport.reportsSize(SEEK_END))
        XCTAssertEqual(HTTPRangeSupport.seekWhence(SEEK_END | HTTPRangeSupport.avSeekForce), SEEK_END)
    }

    func testLibraryFileSizeWinsOverATruncatedHTTPProbe() {
        XCTAssertEqual(
            HTTPRangeSupport.preferredSize(known: 16_000_000_000, probed: 357_213_601),
            16_000_000_000
        )
        XCTAssertEqual(HTTPRangeSupport.preferredSize(known: nil, probed: 100), 100)
        XCTAssertNil(HTTPRangeSupport.preferredSize(known: 0, probed: nil))
    }

    func testRepositionedReadIsASeekFill() {
        XCTAssertTrue(HTTPRangeSupport.isSeekFill(position: 182_810_650, lastFetchEnd: 4096))
        XCTAssertTrue(HTTPRangeSupport.isSeekFill(position: 0, lastFetchEnd: -1))
    }

    func testSequentialReadIsNotASeekFill() {
        XCTAssertFalse(HTTPRangeSupport.isSeekFill(position: 4096, lastFetchEnd: 4096))
    }

    func testSeekFillFailsFastWithinTheRepositionBudget() {
        // A cold read after a seek must give up well under FFmpeg's ~8s Matroska window.
        XCTAssertEqual(
            HTTPRangeSupport.readTimeout(seekFill: true, sequentialTimeout: 30, seekFillTimeout: 6),
            6,
            accuracy: 0.001
        )
        // Never exceed the session's own (tighter) budget.
        XCTAssertEqual(
            HTTPRangeSupport.readTimeout(seekFill: true, sequentialTimeout: 4, seekFillTimeout: 6),
            4,
            accuracy: 0.001
        )
    }

    func testSequentialReadKeepsTheGenerousTimeout() {
        XCTAssertEqual(
            HTTPRangeSupport.readTimeout(seekFill: false, sequentialTimeout: 30, seekFillTimeout: 6),
            30,
            accuracy: 0.001
        )
    }
}

final class PlaybackHTTPHeadersTests: XCTestCase {
    func testStreamURLTokenIsSentAsEmbyHeaders() {
        let url = URL(string: "https://jellyfin.example.com/Videos/1/stream.mkv?static=true&api_key=secret")
        guard let url else {
            return XCTFail("URL")
        }
        let fields = PlaybackHTTPHeaders.fields(for: url)
        XCTAssertEqual(fields["X-Emby-Token"], "secret")
        XCTAssertEqual(fields["Authorization"], "MediaBrowser Token=\"secret\"")
    }

    func testFileURLsDoNotCarryGatewayHeaders() {
        let url = URL(fileURLWithPath: "/tmp/Zelefin/media.mkv")
        XCTAssertEqual(PlaybackHTTPHeaders.fields(for: url), [:])
    }
}

final class StreamContainerTests: XCTestCase {
    func testMatroskaMapsToMKV() {
        XCTAssertEqual(StreamContainer.pathExtension(fromContainer: "matroska"), "mkv")
        XCTAssertEqual(StreamContainer.pathExtension(fromContainer: "mkv"), "mkv")
    }

    func testMPEGTSMapsToTS() {
        XCTAssertEqual(StreamContainer.pathExtension(fromContainer: "mpegts"), "ts")
        XCTAssertEqual(StreamContainer.pathExtension(fromContainer: "mpegts,ts"), "ts")
    }

    func testMPEGProgramStreamMapsToMPG() {
        XCTAssertEqual(StreamContainer.pathExtension(fromContainer: "mpegps"), "mpg")
        XCTAssertEqual(StreamContainer.pathExtension(fromContainer: "mpg"), "mpg")
    }

    func testMissingContainerDefaultsToMKVForDirectPlay() {
        XCTAssertNil(StreamContainer.pathExtension(fromContainer: nil))
        XCTAssertEqual(StreamContainer.pathExtension(container: nil, path: nil), "mkv")
    }

    func testContainerFallsBackToFilePath() {
        XCTAssertEqual(
            StreamContainer.pathExtension(container: nil, path: "/mnt/media/Futurama/S01E01.mkv"),
            "mkv"
        )
    }

    func testFormatHintMapsExtensionsForDirectPlay() {
        let mkv = URL(string: "https://jellyfin.example.com/Videos/1/stream.mkv")
        let ts = URL(string: "https://jellyfin.example.com/Videos/1/stream.ts")
        let mpg = URL(string: "https://jellyfin.example.com/Videos/1/stream.mpg")
        let bare = URL(string: "https://jellyfin.example.com/Videos/1/stream")
        guard let mkv, let ts, let mpg, let bare else {
            return XCTFail("URL")
        }
        XCTAssertEqual(StreamContainer.formatHint(from: mkv), "matroska")
        XCTAssertEqual(StreamContainer.formatHint(from: ts), "mpegts")
        XCTAssertEqual(StreamContainer.formatHint(from: mpg), "mpeg")
        XCTAssertNil(StreamContainer.formatHint(from: bare))
    }
}

final class DeviceProfileTests: XCTestCase {
    func testDirectPlayAdvertisesMatroska() {
        XCTAssertTrue(AVDeviceProfileFactory.videoDirectPlayContainers.contains("mkv"))
        XCTAssertTrue(AVDeviceProfileFactory.videoDirectPlayContainers.contains("matroska"))
        XCTAssertTrue(AVDeviceProfileFactory.videoDirectPlayContainers.contains("mpegps"))
        XCTAssertTrue(AVDeviceProfileFactory.videoDirectPlayCodecs.contains("hevc"))
        XCTAssertTrue(AVDeviceProfileFactory.videoDirectPlayCodecs.contains("mpeg2video"))
        XCTAssertTrue(AVDeviceProfileFactory.audioDirectPlayCodecs.contains("eac3"))
        XCTAssertTrue(AVDeviceProfileFactory.audioDirectPlayCodecs.contains("dts"))
        XCTAssertTrue(AVDeviceProfileFactory.audioDirectPlayCodecs.contains("truehd"))
    }

    func testHLSTranscodeContainerFollowsFMP4Preference() {
        let fmp4 = AVDeviceProfileFactory.make(preferFMP4InHLS: true)
            .transcodingProfiles?
            .first { $0.type == .video }
        let mpegTS = AVDeviceProfileFactory.make(preferFMP4InHLS: false)
            .transcodingProfiles?
            .first { $0.type == .video }
        XCTAssertEqual(fmp4?.container, "mp4")
        XCTAssertEqual(mpegTS?.container, "ts")
    }
}

final class PlaybackMethodTests: XCTestCase {
    func testDirectPlayWinsWhenJellyfinAlsoReturnsATranscodeURL() {
        XCTAssertEqual(
            ItemMapper.playbackMethod(
                supportsDirectPlay: true,
                supportsDirectStream: true,
                transcodingURL: "/Videos/1/master.m3u8"
            ),
            .directPlay
        )
    }

    func testTranscodeURLIsUsedWhenDirectPlayIsNotSupported() {
        XCTAssertEqual(
            ItemMapper.playbackMethod(
                supportsDirectPlay: false,
                supportsDirectStream: true,
                transcodingURL: "/Videos/1/master.m3u8"
            ),
            .remux
        )
        XCTAssertEqual(
            ItemMapper.playbackMethod(
                supportsDirectPlay: false,
                supportsDirectStream: false,
                transcodingURL: "/Videos/1/master.m3u8"
            ),
            .transcode
        )
    }
}

final class PlaybackTimeFormattingTests: XCTestCase {
    func testElapsedUsesMinutesUntilAnHour() {
        XCTAssertEqual(PlaybackTimeFormatting.elapsed(0), "0:00")
        XCTAssertEqual(PlaybackTimeFormatting.elapsed(5), "0:05")
        XCTAssertEqual(PlaybackTimeFormatting.elapsed(125), "2:05")
    }

    func testElapsedIncludesHours() {
        XCTAssertEqual(PlaybackTimeFormatting.elapsed(3600), "1:00:00")
        XCTAssertEqual(PlaybackTimeFormatting.elapsed(3723), "1:02:03")
    }

    func testRemainingIsNegativeClock() {
        XCTAssertEqual(PlaybackTimeFormatting.remaining(125, duration: 3723), "-59:58")
        XCTAssertEqual(PlaybackTimeFormatting.remaining(0, duration: 3661), "-1:01:01")
    }
}

final class DirectPlayPictureLayoutTests: XCTestCase {
    func testUltrawidePictureLetterboxesInsideAnIPadFrame() {
        let video = DirectPlayPictureLayout.fittedRect(
            picture: CGSize(width: 3840, height: 1716),
            in: CGSize(width: 1180, height: 820)
        )
        XCTAssertEqual(video.minX, 0, accuracy: 0.5)
        XCTAssertEqual(video.width, 1180, accuracy: 0.5)
        XCTAssertEqual(video.height, 1180 * 1716 / 3840, accuracy: 0.5)
        XCTAssertGreaterThan(video.minY, 100)
        XCTAssertLessThan(video.maxY, 720)
    }

    func testSixteenByNineFillsTopToBottomOnSixteenByTen() {
        let video = DirectPlayPictureLayout.filledRect(
            picture: CGSize(width: 1920, height: 1080),
            in: CGSize(width: 1920, height: 1200)
        )
        XCTAssertEqual(video.minY, 0, accuracy: 0.5)
        XCTAssertEqual(video.height, 1200, accuracy: 0.5)
        XCTAssertLessThan(video.minX, 0)
        XCTAssertGreaterThan(video.width, 1920)
    }

    func testFourByThreeFillsSideToSideOnSixteenByNine() {
        let video = DirectPlayPictureLayout.filledRect(
            picture: CGSize(width: 1440, height: 1080),
            in: CGSize(width: 1920, height: 1080)
        )
        XCTAssertEqual(video.minX, 0, accuracy: 0.5)
        XCTAssertEqual(video.width, 1920, accuracy: 0.5)
        XCTAssertLessThan(video.minY, 0)
        XCTAssertGreaterThan(video.height, 1080)
    }

    func testAspectNameRecognizesCommonRatios() {
        XCTAssertEqual(PlaybackStats.aspectName(width: 1920, height: 1080), "16:9")
        XCTAssertEqual(PlaybackStats.aspectName(width: 1920, height: 1200), "16:10")
        XCTAssertEqual(PlaybackStats.aspectName(width: 1440, height: 1080), "4:3")
    }

    func testBitmapCueUsesCanvasMappingInsideThePicture() {
        let picture = CGRect(x: 40, y: 80, width: 1280, height: 720)
        let frame = DirectPlayPictureLayout.imageFrame(
            position: CGRect(x: 660.0 / 1920.0, y: 1100.0 / 1280.0, width: 600.0 / 1920.0, height: 100.0 / 1280.0),
            canvasSize: CGSize(width: 1920, height: 1280),
            in: picture
        )
        XCTAssertEqual(frame.width, 400, accuracy: 0.5)
        XCTAssertEqual(frame.minX, 480, accuracy: 0.5)
        XCTAssertEqual(frame.minY, 80 + 666.67, accuracy: 1.0)
    }

    func testPrefetchWindowDoesNotDrawFutureCues() {
        let retained = [
            cue(id: 1, start: 55.298, end: 57.600),
            cue(id: 2, start: 57.667, end: 59.235),
            cue(id: 3, start: 62.605, end: 65.141),
        ]
        XCTAssertTrue(DirectPlayPictureLayout.visibleCues(in: retained, at: 3.233).isEmpty)
        XCTAssertEqual(DirectPlayPictureLayout.visibleCues(in: retained, at: 55.298).map(\.id), [1])
        XCTAssertEqual(DirectPlayPictureLayout.visibleCues(in: retained, at: 57.599).map(\.id), [1])
        XCTAssertTrue(DirectPlayPictureLayout.visibleCues(in: retained, at: 57.600).isEmpty)
        XCTAssertEqual(DirectPlayPictureLayout.visibleCues(in: retained, at: 57.667).map(\.id), [2])
    }

    func testSeekPrefetchDoesNotDrawCuesAMinuteAhead() {
        let retained = [
            cue(id: 10, start: 4310.315, end: 4314.019),
            cue(id: 11, start: 4316.088, end: 4319.091),
            cue(id: 12, start: 4390.629, end: 4391.897),
        ]
        XCTAssertEqual(DirectPlayPictureLayout.visibleCues(in: retained, at: 4310.097).map(\.id), [])
        XCTAssertEqual(DirectPlayPictureLayout.visibleCues(in: retained, at: 4310.400).map(\.id), [10])
        XCTAssertTrue(DirectPlayPictureLayout.visibleCues(in: retained, at: 4314.019).isEmpty)
        XCTAssertTrue(DirectPlayPictureLayout.visibleCues(in: retained, at: 4330.847).isEmpty)
        XCTAssertEqual(DirectPlayPictureLayout.visibleCues(in: retained, at: 4390.700).map(\.id), [12])
    }

    func testOverlappingCuesStayStacked() {
        let retained = [
            cue(id: 1, start: 10, end: 14),
            cue(id: 2, start: 12, end: 16),
        ]
        XCTAssertEqual(DirectPlayPictureLayout.visibleCues(in: retained, at: 11).map(\.id), [1])
        XCTAssertEqual(DirectPlayPictureLayout.visibleCues(in: retained, at: 13).map(\.id), [1, 2])
        XCTAssertEqual(DirectPlayPictureLayout.visibleCues(in: retained, at: 15).map(\.id), [2])
        XCTAssertTrue(DirectPlayPictureLayout.visibleCues(in: retained, at: 16).isEmpty)
    }

    private func cue(id: Int, start: TimeInterval, end: TimeInterval) -> DirectPlaySubtitleCue {
        DirectPlaySubtitleCue(id: id, startTime: start, endTime: end, body: .text("\(id)"))
    }
}
