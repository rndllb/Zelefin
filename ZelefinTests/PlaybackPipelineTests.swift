import XCTest
@testable import Zelefin

final class PlaybackPipelineTests: XCTestCase {
    func testMP4DirectPlayUsesAppleNative() {
        let url = URL(string: "https://jellyfin.example.com/Videos/1/stream.mp4?static=true")
        guard let url else {
            return XCTFail("URL")
        }
        XCTAssertEqual(PlaybackPipelineResolver.pipeline(url: url, method: .directPlay), .appleNative)
    }

    func testHLSRemuxUsesAppleNative() {
        let url = URL(string: "https://jellyfin.example.com/Videos/1/master.m3u8?DeviceId=abc")
        guard let url else {
            return XCTFail("URL")
        }
        XCTAssertEqual(PlaybackPipelineResolver.pipeline(url: url, method: .remux), .appleNative)
        XCTAssertEqual(PlaybackPipelineResolver.pipeline(url: url, method: .transcode), .appleNative)
    }

    func testMKVDirectPlayUsesDirectDecode() {
        let url = URL(string: "https://jellyfin.example.com/Videos/1/stream.mkv?static=true")
        guard let url else {
            return XCTFail("URL")
        }
        XCTAssertEqual(PlaybackPipelineResolver.pipeline(url: url, method: .directPlay), .directDecode)
    }

    func testMPEGTSDirectPlayUsesDirectDecode() {
        let url = URL(string: "https://jellyfin.example.com/Videos/1/stream.ts?static=true")
        guard let url else {
            return XCTFail("URL")
        }
        XCTAssertEqual(PlaybackPipelineResolver.pipeline(url: url, method: .directPlay), .directDecode)
    }
}

final class DirectPlayEngineTests: XCTestCase {
    func testMKVDirectPlayUsesSampleBufferDecode() {
        XCTAssertTrue(DirectPlayLoadOptions.usesSampleBufferDecode(for: .directDecode))
        XCTAssertFalse(DirectPlayLoadOptions.usesSampleBufferDecode(for: .appleNative))
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

    func testMissingContainerDefaultsToMP4() {
        XCTAssertEqual(StreamContainer.pathExtension(fromContainer: nil), "mp4")
    }

    func testFormatHintMapsExtensionsForDirectPlay() {
        let mkv = URL(string: "https://jellyfin.example.com/Videos/1/stream.mkv")
        let ts = URL(string: "https://jellyfin.example.com/Videos/1/stream.ts")
        let bare = URL(string: "https://jellyfin.example.com/Videos/1/stream")
        guard let mkv, let ts, let bare else {
            return XCTFail("URL")
        }
        XCTAssertEqual(StreamContainer.formatHint(from: mkv), "matroska")
        XCTAssertEqual(StreamContainer.formatHint(from: ts), "mpegts")
        XCTAssertNil(StreamContainer.formatHint(from: bare))
    }
}

final class DeviceProfileTests: XCTestCase {
    func testDirectPlayAdvertisesMatroska() {
        XCTAssertTrue(AVDeviceProfileFactory.videoDirectPlayContainers.contains("mkv"))
        XCTAssertTrue(AVDeviceProfileFactory.videoDirectPlayContainers.contains("matroska"))
        XCTAssertTrue(AVDeviceProfileFactory.videoDirectPlayCodecs.contains("hevc"))
        XCTAssertTrue(AVDeviceProfileFactory.audioDirectPlayCodecs.contains("eac3"))
        XCTAssertTrue(AVDeviceProfileFactory.audioDirectPlayCodecs.contains("dts"))
        XCTAssertTrue(AVDeviceProfileFactory.audioDirectPlayCodecs.contains("truehd"))
    }
}

final class OpenSourceNoticeTests: XCTestCase {
    func testCreditsCoverFFmpeg() {
        XCTAssertEqual(OpenSourceNotice.works.map(\.name), ["AetherEngine", "FFmpeg"])
        XCTAssertEqual(OpenSourceNotice.works.last?.bundledLicenses.map(\.name), ["dav1d", "libdovi", "libzvbi", "zimg"])
        XCTAssertFalse(OpenSourceNotice.summary.isEmpty)
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
