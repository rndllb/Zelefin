import XCTest
@testable import Zelefin

final class DownloadLayoutTests: XCTestCase {
    func testSeriesToolbarDownloadsTheHeroEpisode() {
        let show = sampleSeries()
        let episodes = [
            sampleEpisode(id: "e1", season: 1, number: 1, watched: true),
            sampleEpisode(id: "e2", season: 1, number: 2, watched: false),
        ]
        XCTAssertEqual(DownloadEligibility.playableItem(from: show, episodes: episodes)?.id, "e2")
        XCTAssertEqual(DownloadEligibility.playableItem(from: episodes[1])?.id, "e2")
        XCTAssertNil(DownloadEligibility.playableItem(from: show, episodes: []))
        XCTAssertNil(DownloadEligibility.playableItem(from: sampleGenre()))
    }

    func testShowDownloadPickerListsEachSeason() {
        let episodes = (1...5).flatMap { season in
            [
                sampleEpisode(id: "s\(season)e1", season: season, number: 1, watched: false),
                sampleEpisode(id: "s\(season)e2", season: season, number: 2, watched: false),
            ]
        }
        let choices = SeasonDownloadChoice.options(seasons: [], episodes: episodes)
        XCTAssertEqual(choices.map(\.title), ["Season 1", "Season 2", "Season 3", "Season 4", "Season 5"])
        let season3 = choices.first { $0.seasonIndex == 3 }!
        XCTAssertEqual(SeasonDownloadChoice.episodes(for: season3, in: episodes).map(\.id), ["s3e1", "s3e2"])
        XCTAssertEqual(
            SeasonDownloadChoice.episodes(in: episodes, indexes: [1, 3]).map(\.id),
            ["s1e1", "s1e2", "s3e1", "s3e2"]
        )
    }

    func testShowDownloadPickerHasOneChoiceForASingleSeason() {
        let episodes = [
            sampleEpisode(id: "e1", season: 3, number: 1, watched: false),
            sampleEpisode(id: "e2", season: 3, number: 2, watched: false),
        ]
        let choices = SeasonDownloadChoice.options(seasons: [], episodes: episodes)
        XCTAssertEqual(choices.map(\.title), ["Season 3"])
        XCTAssertEqual(choices.first?.seasonIndex, 3)
    }

    func testShowDownloadPickerListsSpecialsAfterNumberedSeasons() {
        let episodes = [
            sampleEpisode(id: "e1", season: 1, number: 1, watched: false),
            sampleEpisode(id: "sp", season: 0, number: 1, watched: false),
            sampleEpisode(id: "e2", season: 2, number: 1, watched: false),
        ]
        let choices = SeasonDownloadChoice.options(seasons: [], episodes: episodes)
        XCTAssertEqual(choices.map(\.title), ["Season 1", "Season 2", "Specials"])
    }

    func testCoverMarkBadgesAShowWhenAnyEpisodeIsDownloaded() {
        let records = [downloaded(sampleEpisode(id: "e2", season: 1, number: 2, watched: false))]
        XCTAssertEqual(DownloadCoverLogic.mark(for: sampleSeries(), records: records, progress: [:]), .downloaded)
        XCTAssertEqual(DownloadCoverLogic.mark(for: records[0].item, records: records, progress: [:]), .downloaded)
        XCTAssertEqual(
            DownloadCoverLogic.mark(for: sampleEpisode(id: "e1", season: 1, number: 1, watched: true), records: records, progress: [:]),
            .none
        )
        XCTAssertEqual(DownloadCoverLogic.mark(for: sampleMovie(), records: records, progress: [:]), .none)
    }

    func testCoverMarkShowsInFlightProgressOnTheShow() {
        let episode = sampleEpisode(id: "e2", season: 1, number: 2, watched: false)
        let progress = [
            "e2": DownloadProgress(fraction: 0.4, seriesID: "show-1", userID: "user-1", serverHost: "jellyfin.example.com")
        ]
        XCTAssertEqual(DownloadCoverLogic.mark(for: sampleSeries(), records: [], progress: progress), .downloading(0.4))
        XCTAssertEqual(DownloadCoverLogic.mark(for: episode, records: [], progress: progress), .downloading(0.4))
    }

    func testLibraryGroupsEpisodesUnderTheShow() {
        let movie = downloaded(sampleMovie())
        let episodeA = downloaded(sampleEpisode(id: "e1", season: 1, number: 1, watched: false))
        let episodeB = downloaded(sampleEpisode(id: "e2", season: 1, number: 2, watched: false))
        let rows = DownloadLibraryLayout.rows(from: [movie, episodeA, episodeB])
        XCTAssertEqual(rows.map(\.kind), [.movie, .series])
        XCTAssertEqual(rows[0].title.id, "movie-1")
        XCTAssertEqual(rows[1].id, "show-1")
        XCTAssertEqual(rows[1].episodeCount, 2)
        XCTAssertEqual(rows[1].title.kind, .series)
    }

    func testContentDispositionMapsMatroskaFilenames() {
        XCTAssertEqual(
            DownloadHTTP.filenameExtension(fromContentDisposition: "attachment; filename=\"Dune.mkv\""),
            "mkv"
        )
        XCTAssertEqual(
            DownloadHTTP.filenameExtension(fromContentDisposition: "attachment; filename*=UTF-8''Silo%20S01E02.mp4"),
            "mp4"
        )
        XCTAssertNil(DownloadHTTP.filenameExtension(fromContentDisposition: "inline"))
    }

    func testRefusedDownloadsShowTheServersReason() {
        let silo = #"{"Error":"Forbidden","Message":"You are not allowed to download this item"}"#.data(using: .utf8)
        XCTAssertEqual(
            DownloadHTTP.failure(statusCode: 403, body: silo).errorDescription,
            "You are not allowed to download this item"
        )
        XCTAssertEqual(
            DownloadHTTP.failure(statusCode: 403, body: nil).errorDescription,
            "This server doesn't allow downloads for this account."
        )
        XCTAssertEqual(
            DownloadHTTP.failure(statusCode: 503, body: Data("<html></html>".utf8)).errorDescription,
            "Downloads aren't available on this server."
        )
        let problem = #"{"title":"Not Found","detail":"Media file not found"}"#.data(using: .utf8)
        XCTAssertEqual(DownloadHTTP.failure(statusCode: 404, body: problem).errorDescription, "Media file not found")
        XCTAssertEqual(
            DownloadHTTP.failure(statusCode: 500, body: nil).errorDescription,
            ZelefinError.downloadFailed.errorDescription
        )
    }

    func testByteCountUsesKnownSizeWhenHTTPOmitsLength() {
        XCTAssertEqual(DownloadByteCount.resolvedExpected(httpExpected: -1, knownSize: 1_000), 1_000)
        XCTAssertEqual(DownloadByteCount.resolvedExpected(httpExpected: 0, knownSize: 2_048), 2_048)
        XCTAssertEqual(DownloadByteCount.resolvedExpected(httpExpected: 4_000, knownSize: 1_000), 4_000)
        XCTAssertEqual(DownloadByteCount.resolvedExpected(httpExpected: 0, knownSize: 0), 0)
    }

    func testByteCountFractionAndLabels() {
        XCTAssertEqual(DownloadByteCount.fraction(written: 50, expected: 100), 0.5)
        XCTAssertEqual(DownloadByteCount.fraction(written: 150, expected: 100), 1)
        XCTAssertEqual(DownloadByteCount.fraction(written: 40, expected: 0), 0)
        XCTAssertEqual(DownloadByteCount.percentLabel(written: 50, expected: 100), "50%")
        XCTAssertNil(DownloadByteCount.percentLabel(written: 40, expected: 0))
        XCTAssertEqual(DownloadByteCount.sizeLabel(written: 0, expected: 0), "Starting…")
        XCTAssertFalse(DownloadByteCount.sizeLabel(written: 1_024, expected: 0).contains(" of "))
        XCTAssertTrue(DownloadByteCount.sizeLabel(written: 1_024, expected: 2_048).contains(" of "))
    }

    func testDownloadCopyAndBannerTitles() {
        XCTAssertEqual(DownloadControlCopy.title(for: .idle), "Download")
        XCTAssertEqual(DownloadControlCopy.title(for: .downloading(0)), "Cancel Download")
        XCTAssertEqual(DownloadControlCopy.title(for: .downloading(0.42)), "Cancel Download · 42%")
        XCTAssertEqual(DownloadControlCopy.title(for: .downloaded), "Remove Download")
        XCTAssertEqual(DownloadControlCopy.symbol(for: .idle), "arrow.down.to.line")

        let movieProgress = DownloadProgress(
            fraction: 0.5,
            bytesWritten: 50,
            bytesExpected: 100,
            userID: "user-1",
            serverHost: "jellyfin.example.com"
        )
        XCTAssertEqual(movieProgress.bannerTitle, "Downloading 50%")

        let episodeProgress = DownloadProgress(
            item: sampleEpisode(id: "e2", season: 1, number: 2, watched: false),
            fraction: 0.4,
            bytesWritten: 40,
            bytesExpected: 100,
            seriesID: "show-1",
            userID: "user-1",
            serverHost: "jellyfin.example.com"
        )
        XCTAssertEqual(episodeProgress.bannerTitle, "Downloading Episode 2 · 40%")
    }

    func testCancellationDetection() {
        XCTAssertTrue(DownloadFailure.isCancellation(CancellationError()))
        XCTAssertTrue(DownloadFailure.isCancellation(URLError(.cancelled)))
        XCTAssertTrue(DownloadFailure.isCancellation(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
        XCTAssertFalse(DownloadFailure.isCancellation(ZelefinError.downloadFailed))
    }

    func testRemovalPromptAsksBeforeDeleting() {
        let movie = DownloadRemovalPrompt.make(item: sampleMovie())
        XCTAssertEqual(movie.title, "Delete Download?")
        XCTAssertTrue(movie.message.contains("Are you sure"))
        XCTAssertTrue(movie.message.contains("Dune"))

        let episode = DownloadRemovalPrompt.make(item: sampleEpisode(id: "e2", season: 1, number: 2, watched: false))
        XCTAssertTrue(episode.message.contains("Silo"))
        XCTAssertTrue(episode.message.contains("Are you sure"))
    }

    func testCoverAccessibilityNamesInFlightProgress() {
        XCTAssertEqual(DownloadCoverMark.downloaded.accessibilityCaption, "Downloaded")
        XCTAssertEqual(DownloadCoverMark.downloading(0).accessibilityCaption, "Downloading")
        XCTAssertEqual(DownloadCoverMark.downloading(0.42).accessibilityCaption, "Downloading 42 percent")
        XCTAssertNil(DownloadCoverMark.none.accessibilityCaption)
    }

    func testRelatedPlaybackPicksADownloadedEpisodeForTheShow() {
        let episode = downloaded(sampleEpisode(id: "e2", season: 1, number: 2, watched: false))
        XCTAssertNil(DownloadPlaybackSelection.record(for: sampleSeries(), in: [episode]))
        XCTAssertEqual(DownloadPlaybackSelection.relatedRecord(for: sampleSeries(), in: [episode])?.item.id, "e2")
        XCTAssertEqual(
            DownloadPlaybackSelection.relatedRecord(for: sampleEpisode(id: "e1", season: 1, number: 1, watched: true), in: [episode])?.item.id,
            "e2"
        )
        XCTAssertEqual(DownloadPlaybackSelection.record(for: episode.item, in: [episode])?.item.id, "e2")
        XCTAssertNil(DownloadPlaybackSelection.relatedRecord(for: sampleMovie(), in: [episode]))
    }

    func testRelatedPlaybackPrefersInProgressEpisode() {
        let watched = downloaded(sampleEpisode(id: "e1", season: 1, number: 1, watched: true))
        let resumable = downloaded(sampleEpisode(id: "e2", season: 1, number: 2, watched: false, position: 120))
        let later = downloaded(sampleEpisode(id: "e3", season: 1, number: 3, watched: false))
        XCTAssertEqual(
            DownloadPlaybackSelection.relatedRecord(for: sampleSeries(), in: [watched, later, resumable])?.item.id,
            "e2"
        )
    }
}

final class DownloadStoreTests: XCTestCase {
    @MainActor
    func testCatalogRoundTripKeepsOfflineFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZelefinDownloads-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let relative = "files/jellyfin.example.com/user-1/movie-1/media.mkv"
        let media = directory.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: media.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("offline".utf8).write(to: media)

        let record = downloaded(sampleMovie(), relativeMediaPath: relative)
        let catalog = DownloadCatalog(version: DownloadCatalog.currentVersion, records: [record])
        let data = try SnapshotCoding.encoder.encode(catalog)
        try data.write(to: directory.appendingPathComponent("catalog.json"))

        let store = DownloadStore(directory: directory)
        XCTAssertEqual(store.records.map(\.item.id), ["movie-1"])

        guard let server = URL(string: "https://jellyfin.example.com") else {
            return XCTFail("Server URL should parse")
        }
        let account = SavedSession(
            serverURL: server,
            accessToken: "token",
            userID: "user-1",
            userName: "Ada",
            deviceID: "device"
        )
        let plan = store.playbackPlan(for: sampleMovie(), account: account)
        XCTAssertEqual(plan?.streamURL.isFileURL, true)
        XCTAssertEqual(plan?.container, "mkv")
        XCTAssertEqual(plan?.method, .directPlay)
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan?.streamURL.path ?? ""))
    }

    @MainActor
    func testPlaybackPlanUsesRelatedEpisodeForAShow() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZelefinDownloads-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let relative = "files/jellyfin.example.com/user-1/e2/media.mkv"
        let media = directory.appending(path: relative)
        try FileManager.default.createDirectory(at: media.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("episode".utf8).write(to: media)

        let catalog = DownloadCatalog(
            version: DownloadCatalog.currentVersion,
            records: [downloaded(sampleEpisode(id: "e2", season: 1, number: 2, watched: false), relativeMediaPath: relative)]
        )
        try SnapshotCoding.encoder.encode(catalog).write(to: directory.appendingPathComponent("catalog.json"))
        let store = DownloadStore(directory: directory)

        guard let server = URL(string: "https://jellyfin.example.com") else {
            return XCTFail("Server URL should parse")
        }
        let account = SavedSession(
            serverURL: server,
            accessToken: "token",
            userID: "user-1",
            userName: "Ada",
            deviceID: "device"
        )
        XCTAssertNil(store.playbackPlan(for: sampleSeries(), account: account))
        let related = store.playbackPlan(for: sampleSeries(), allowRelated: true, account: account)
        XCTAssertEqual(related?.item.id, "e2")
        XCTAssertEqual(related?.streamURL.isFileURL, true)
        XCTAssertEqual(
            store.playableItem(for: sampleSeries(), allowRelated: true, account: account)?.id,
            "e2"
        )
    }

    @MainActor
    func testMissingMediaFileIsDropped() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZelefinDownloads-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let catalog = DownloadCatalog(
            version: DownloadCatalog.currentVersion,
            records: [downloaded(sampleMovie(), relativeMediaPath: "files/missing.mkv")]
        )
        let data = try SnapshotCoding.encoder.encode(catalog)
        try data.write(to: directory.appendingPathComponent("catalog.json"))
        let store = DownloadStore(directory: directory)
        XCTAssertTrue(store.records.isEmpty)
    }
}

final class OfflinePlaybackPipelineTests: XCTestCase {
    func testLocalMKVUsesDirectPlayEvenWhenNativePlayerIsOn() {
        let url = URL(fileURLWithPath: "/tmp/Zelefin/media.mkv")
        XCTAssertEqual(
            PlaybackPipelineResolver.pipeline(
                url: url,
                method: .directPlay,
                container: "mkv",
                usesNativePlayer: true
            ),
            .directDecode
        )
        XCTAssertFalse(
            PlaybackPipelineResolver.needsServerRemuxForNativePlayer(
                url: url,
                method: .directPlay,
                container: "mkv",
                usesNativePlayer: true
            )
        )
        XCTAssertTrue(
            DirectPlayLoadPolicy.shouldOpenAsURL(url: url, method: .directPlay, isHLS: false)
        )
    }

    func testLocalMP4CanStayOnAppleNative() {
        let url = URL(fileURLWithPath: "/tmp/Zelefin/media.mp4")
        XCTAssertEqual(
            PlaybackPipelineResolver.pipeline(
                url: url,
                method: .directPlay,
                container: "mp4",
                videoCodec: "h264",
                usesNativePlayer: true
            ),
            .appleNative
        )
    }

    func testOfflinePlaybackSkipsNetworkWork() {
        XCTAssertFalse(OfflinePlaybackPolicy.shouldFetchSkipSegments(isLocalFile: true))
        XCTAssertTrue(OfflinePlaybackPolicy.shouldFetchSkipSegments(isLocalFile: false))
        XCTAssertFalse(OfflinePlaybackPolicy.shouldReportToServer(isLocalFile: true))
        XCTAssertTrue(OfflinePlaybackPolicy.shouldReportToServer(isLocalFile: false))
        XCTAssertFalse(OfflinePlaybackPolicy.shouldFallBackToRemux(isLocalFile: true))
        XCTAssertTrue(OfflinePlaybackPolicy.shouldFallBackToRemux(isLocalFile: false))
    }

    func testLocalFileReaderRejectsEmptyFiles() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zelefin-empty-\(UUID().uuidString).mkv")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(LocalMediaByteReader(url: url))

        let media = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zelefin-media-\(UUID().uuidString).mkv")
        try Data("offline-bytes".utf8).write(to: media)
        defer { try? FileManager.default.removeItem(at: media) }
        XCTAssertNotNil(LocalMediaByteReader(url: media))
    }
}

private func downloaded(
    _ item: MediaItem,
    relativeMediaPath: String = "files/media.mkv"
) -> DownloadedItem {
    DownloadedItem(
        item: item,
        relativeMediaPath: relativeMediaPath,
        relativeArtworkPath: nil,
        relativeShowArtworkPath: nil,
        container: "mkv",
        videoCodec: "hevc",
        videoRange: .sdr,
        audioFormat: .stereo,
        byteSize: 1_024,
        userID: "user-1",
        serverHost: "jellyfin.example.com",
        downloadedAt: Date(timeIntervalSince1970: 1_720_000_000)
    )
}

private func sampleMovie() -> MediaItem {
    MediaItem(
        id: "movie-1",
        name: "Dune",
        kind: .movie,
        overview: nil,
        year: 2024,
        runtime: 9_000,
        officialRating: "PG-13",
        genres: ["Action"],
        seriesName: nil,
        seasonIndex: nil,
        episodeIndex: nil,
        playbackPosition: 40,
        unplayedCount: nil,
        isPlayed: false,
        primaryImageTag: "tag",
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
        videoRange: .dolbyVision,
        audioFormat: .atmos
    )
}

private func sampleSeries() -> MediaItem {
    MediaItem(
        id: "show-1",
        name: "Silo",
        kind: .series,
        overview: nil,
        year: 2023,
        runtime: nil,
        officialRating: "TV-MA",
        genres: ["Drama"],
        seriesName: "Silo",
        seasonIndex: nil,
        episodeIndex: nil,
        playbackPosition: 0,
        unplayedCount: 2,
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
        seriesID: "show-1",
        imageItemID: nil,
        queueKind: .nextUp,
        videoRange: .sdr,
        audioFormat: .unknown
    )
}

private func sampleEpisode(
    id: String,
    season: Int,
    number: Int,
    watched: Bool,
    position: TimeInterval? = nil
) -> MediaItem {
    MediaItem(
        id: id,
        name: id,
        kind: .episode,
        overview: nil,
        year: 2023,
        runtime: 3_600,
        officialRating: nil,
        genres: [],
        seriesName: "Silo",
        seasonIndex: season,
        episodeIndex: number,
        playbackPosition: position ?? (watched ? 3_600 : 0),
        unplayedCount: nil,
        isPlayed: watched,
        primaryImageTag: nil,
        thumbImageTag: nil,
        backdropImageTag: nil,
        backdropImageTags: [],
        logoImageTag: nil,
        parentBackdropItemID: "show-1",
        parentThumbItemID: "show-1",
        parentThumbImageTag: nil,
        parentLogoItemID: nil,
        parentLogoImageTag: nil,
        seriesThumbImageTag: nil,
        seriesID: "show-1",
        imageItemID: nil,
        queueKind: .nextUp,
        videoRange: .sdr,
        audioFormat: .stereo
    )
}

private func sampleGenre() -> MediaItem {
    MediaItem(
        id: "genre-1",
        name: "Action",
        kind: .genre,
        overview: nil,
        year: nil,
        runtime: nil,
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
        audioFormat: .unknown
    )
}
