import XCTest
import JellyfinAPI
@testable import Zelefin

final class PlaybackSessionTests: XCTestCase {
    func testEpisodeTitleIncludesSeriesAndNumber() {
        let session = Self.playing(
            item: MediaItem.previewEpisode(seriesID: "show-1", seriesName: "Andor")
        )
        XCTAssertEqual(session.title, "Andor · S1:E10 · One Way Out")
        XCTAssertTrue(session.isPlaying)
    }

    func testMovieTitleIncludesYear() {
        let session = Self.playing(
            item: MediaItem.previewMovie(id: "m1", name: "Dune", year: 2021)
        )
        XCTAssertEqual(session.title, "Dune (2021)")
    }

    func testProgressAndPositionUseRuntime() {
        var session = Self.playing(
            item: MediaItem.previewMovie(id: "m1", name: "Dune", year: 2021),
            position: 3_600,
            runtime: 7_200
        )
        XCTAssertEqual(session.progressFraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(session.positionLabel, "1:00:00 / 2:00:00")
        session.runtime = nil
        XCTAssertEqual(session.progressFraction, 0)
        XCTAssertEqual(session.positionLabel, "1:00:00")
    }

    func testPlayingSessionsSortAheadOfIdle() {
        let idle = Self.idle(id: "idle", activity: Date(timeIntervalSince1970: 200))
        let playing = Self.playing(id: "play", checkIn: Date(timeIntervalSince1970: 50))
        XCTAssertEqual(PlaybackSession.sorted([idle, playing]).map(\.id), ["play", "idle"])
    }

    func testTranscodeLabels() {
        let summary = TranscodingSummary(
            videoCodec: "h264",
            audioCodec: "aac",
            container: "ts",
            width: 1920,
            height: 1080,
            bitrate: 12_400_000,
            audioChannels: 6,
            isVideoDirect: false,
            isAudioDirect: true,
            hardwareAcceleration: "NVENC",
            completionPercentage: 40,
            reasons: ["container not supported"]
        )
        XCTAssertEqual(summary.resolutionLabel, "1920×1080")
        XCTAssertEqual(summary.bitrateLabel, "12.4 Mbps")
        XCTAssertEqual(summary.codecLine, "TS · H264 · AAC 6ch direct · NVENC")
        XCTAssertEqual(summary.reasonsLabel, "container not supported")
        XCTAssertEqual(PlayMethodKind.directPlay.label, "Direct Play")
        XCTAssertEqual(PlayMethodKind.transcode.label, "Transcode")
        XCTAssertEqual(TranscodingSummary.reasonLabel(.containerBitrateExceedsLimit), "container bitrate exceeds limit")
        XCTAssertEqual(TranscodingSummary.hardwareLabel(.videotoolbox), "VideoToolbox")
    }

    func testThisDeviceMatchesLocalID() {
        let session = Self.idle(id: "s1", deviceID: "iphone-1")
        XCTAssertTrue(session.isThisDevice("iphone-1"))
        XCTAssertFalse(session.isThisDevice("tv-9"))
        XCTAssertFalse(session.isThisDevice(nil))
    }
}

private extension PlaybackSessionTests {
    static func playing(
        id: String = "s-play",
        item: MediaItem = MediaItem.previewMovie(id: "m1", name: "Dune", year: 2021),
        position: TimeInterval = 120,
        runtime: TimeInterval? = 7_200,
        checkIn: Date = Date()
    ) -> PlaybackSession {
        PlaybackSession(
            id: id,
            userID: "u1",
            userName: "Sam",
            userImageTag: nil,
            client: "Infuse",
            deviceName: "Living Room",
            deviceType: "Apple TV",
            deviceID: "tv-1",
            applicationVersion: "8.0",
            remoteEndPoint: "10.0.0.12",
            isActive: true,
            supportsRemoteControl: true,
            supportsMediaControl: true,
            nowPlaying: item,
            nowPlayingName: nil,
            nowViewingName: nil,
            position: position,
            runtime: runtime ?? item.runtime,
            isPaused: false,
            isMuted: false,
            canSeek: true,
            volumeLevel: 80,
            playMethod: .directPlay,
            transcoding: nil,
            lastActivity: checkIn,
            lastPlaybackCheckIn: checkIn,
            supportedCommands: ["VolumeUp", "Mute"]
        )
    }

    static func idle(
        id: String,
        deviceID: String = "tv-1",
        activity: Date = Date()
    ) -> PlaybackSession {
        PlaybackSession(
            id: id,
            userID: "u1",
            userName: "Sam",
            userImageTag: nil,
            client: "Zelefin",
            deviceName: "iPhone",
            deviceType: "Phone",
            deviceID: deviceID,
            applicationVersion: "0.1.0",
            remoteEndPoint: nil,
            isActive: true,
            supportsRemoteControl: false,
            supportsMediaControl: false,
            nowPlaying: nil,
            nowPlayingName: nil,
            nowViewingName: "Movies",
            position: 0,
            runtime: nil,
            isPaused: false,
            isMuted: false,
            canSeek: false,
            volumeLevel: nil,
            playMethod: .unknown,
            transcoding: nil,
            lastActivity: activity,
            lastPlaybackCheckIn: nil,
            supportedCommands: []
        )
    }
}

private extension MediaItem {
    static func previewMovie(id: String, name: String, year: Int) -> MediaItem {
        MediaItem(
            id: id, name: name, kind: .movie, overview: nil, year: year, runtime: 7_200,
            officialRating: nil, genres: [], seriesName: nil, seasonIndex: nil, episodeIndex: nil,
            playbackPosition: 0, unplayedCount: nil, isPlayed: false, primaryImageTag: nil,
            thumbImageTag: nil, backdropImageTag: nil, backdropImageTags: [], logoImageTag: nil,
            parentBackdropItemID: nil, parentThumbItemID: nil, parentThumbImageTag: nil,
            parentLogoItemID: nil, parentLogoImageTag: nil, seriesThumbImageTag: nil, seriesID: nil,
            imageItemID: nil, queueKind: .resume, videoRange: .sdr, audioFormat: .unknown
        )
    }

    static func previewEpisode(seriesID: String, seriesName: String) -> MediaItem {
        MediaItem(
            id: "ep-9", name: "One Way Out", kind: .episode, overview: nil, year: 2022, runtime: 2_400,
            officialRating: nil, genres: [], seriesName: seriesName, seasonIndex: 1, episodeIndex: 10,
            playbackPosition: 0, unplayedCount: nil, isPlayed: false, primaryImageTag: nil,
            thumbImageTag: nil, backdropImageTag: nil, backdropImageTags: [], logoImageTag: nil,
            parentBackdropItemID: nil, parentThumbItemID: nil, parentThumbImageTag: nil,
            parentLogoItemID: nil, parentLogoImageTag: nil, seriesThumbImageTag: nil, seriesID: seriesID,
            imageItemID: nil, queueKind: .resume, videoRange: .sdr, audioFormat: .unknown
        )
    }
}
