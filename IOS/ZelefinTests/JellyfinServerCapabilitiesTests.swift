import JellyfinAPI
import XCTest
@testable import Zelefin

final class JellyfinServerCapabilitiesTests: XCTestCase {
    func testParsesJellyfin12AndReleaseCandidates() {
        for version in ["12.0.0", "12.0.0-rc7", "12.1.2"] {
            let caps = JellyfinServerCapabilities(version: version)
            XCTAssertEqual(caps.generation, .jellyfin12Plus, version)
            XCTAssertEqual(caps.itemCollectionsAvailability, true, version)
            XCTAssertTrue(caps.prefersPlaybackInfoBody, version)
        }
    }

    func testParsesJellyfin10Family() {
        for version in ["10.11.11", "10.10.7", "10.9.11"] {
            let caps = JellyfinServerCapabilities(version: version)
            XCTAssertEqual(caps.generation, .jellyfin10, version)
            XCTAssertEqual(caps.itemCollectionsAvailability, false, version)
            XCTAssertFalse(caps.prefersPlaybackInfoBody, version)
        }
    }

    func testUnknownWhenVersionMissing() {
        for version in [nil, "", "dev", "x.y"] as [String?] {
            let caps = JellyfinServerCapabilities(version: version)
            XCTAssertEqual(caps.generation, .unknown)
            XCTAssertNil(caps.itemCollectionsAvailability)
            XCTAssertFalse(caps.prefersPlaybackInfoBody)
        }
    }

    func testSavedSessionDecodesWithoutServerVersion() throws {
        let json = """
        {
          "serverURL": "https://jellyfin.example",
          "accessToken": "token",
          "userID": "user",
          "userName": "Ada",
          "deviceID": "device"
        }
        """.data(using: .utf8)!
        let saved = try JSONDecoder().decode(SavedSession.self, from: json)
        XCTAssertNil(saved.serverVersion)
    }

    func testAccountBoxMigratesALegacySingleSession() throws {
        let json = """
        {
          "serverURL": "https://jellyfin.example",
          "accessToken": "token",
          "userID": "user",
          "userName": "Ada",
          "deviceID": "device"
        }
        """.data(using: .utf8)!
        let box = try SavedAccountBox.decode(from: json)
        XCTAssertEqual(box.accounts.count, 1)
        XCTAssertEqual(box.current?.userName, "Ada")
        XCTAssertEqual(box.currentID, box.current?.accountID)
    }

    func testAccountBoxUpsertsAndRemovesUsers() {
        var box = SavedAccountBox(accounts: [], currentID: "")
        let ada = SavedSession(
            serverURL: URL(string: "https://jellyfin.example")!,
            accessToken: "a",
            userID: "1",
            userName: "Ada",
            deviceID: "device"
        )
        let bob = SavedSession(
            serverURL: URL(string: "https://jellyfin.example")!,
            accessToken: "b",
            userID: "2",
            userName: "Bob",
            deviceID: "device"
        )
        box.upsert(ada)
        box.upsert(bob)
        XCTAssertEqual(box.current?.userName, "Bob")
        XCTAssertEqual(box.accounts.map(\.userName), ["Ada", "Bob"])
        box.upsert(
            SavedSession(
                serverURL: ada.serverURL,
                accessToken: "a2",
                userID: ada.userID,
                userName: ada.userName,
                deviceID: ada.deviceID
            ),
            select: false
        )
        XCTAssertEqual(box.current?.userName, "Bob")
        XCTAssertEqual(box.accounts.first { $0.userID == "1" }?.accessToken, "a2")
        XCTAssertEqual(box.remove(id: bob.accountID)?.userName, "Ada")
        XCTAssertEqual(box.accounts.map(\.userName), ["Ada"])
    }

    func testAccountBoxDropsRetiredSiloNativeSignIns() throws {
        let json = """
        {
          "currentID": "silo.example|7",
          "accounts": [
            {
              "serverURL": "https://silo.example",
              "accessToken": "silo-token",
              "userID": "7",
              "userName": "Ada",
              "deviceID": "device",
              "backend": "silo",
              "profileID": "p1",
              "isPrimaryProfile": true
            },
            {
              "serverURL": "https://jellyfin.example",
              "accessToken": "token",
              "userID": "user",
              "userName": "Bob",
              "deviceID": "device",
              "backend": "jellyfin"
            }
          ]
        }
        """.data(using: .utf8)!
        let box = try SavedAccountBox.decode(from: json)
        XCTAssertEqual(box.retiredSiloAccounts, 1)
        XCTAssertEqual(box.accounts.map(\.userName), ["Bob"])
        XCTAssertEqual(box.current?.userName, "Bob")
        XCTAssertEqual(box.current?.isSiloServer, false)
    }

    func testSiloServerFlagRoundTrips() throws {
        let saved = SavedSession(
            serverURL: URL(string: "https://silo.example:8097")!,
            accessToken: "token",
            userID: "user",
            userName: "Kids",
            deviceID: "device",
            isSiloServer: true
        )
        let decoded = try JSONDecoder().decode(SavedSession.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(decoded, saved)
        XCTAssertTrue(decoded.isSiloServer)
    }

    func testSiloUsersShowOnlyTheProfileName() throws {
        XCTAssertEqual(SavedSession.displayName("ada#Kids", isSiloServer: true), "Kids")
        XCTAssertEqual(SavedSession.displayName("ada", isSiloServer: true), "ada")
        XCTAssertEqual(SavedSession.displayName("ada#", isSiloServer: true), "ada#")
        XCTAssertEqual(SavedSession.displayName("ada#Kids", isSiloServer: false), "ada#Kids")
        let saved = try JSONDecoder().decode(SavedSession.self, from: Data("""
        {"serverURL":"https://silo.example:8097","accessToken":"t","userID":"u","userName":"ada#Kids","deviceID":"d","isSiloServer":true}
        """.utf8))
        XCTAssertEqual(saved.userName, "Kids")
    }

    func testSiloIsRecognizedByItsLoginDisclaimer() {
        XCTAssertTrue(ServerProbe.isSiloDisclaimer(
            "Silo provides Jellyfin-compatible app support. Silo is not affiliated with or endorsed by the Jellyfin project."
        ))
        XCTAssertFalse(ServerProbe.isSiloDisclaimer(""))
        XCTAssertFalse(ServerProbe.isSiloDisclaimer("Welcome to the family media server."))
    }
}

final class EmbyTests: XCTestCase {
    private let serverURL = URL(string: "http://emby.example:8096")!
    private let token = "test-token"

    func testEmbyIsRecognizedFromPublicInfo() throws {
        let emby = try EmbyPublicInfo(data: Data("""
        {"LocalAddress":"http://192.168.1.10:8096","ServerName":"emby","Version":"4.10.2.0","Id":"0f1e2d3c4b5a69788796a5b4c3d2e1f0"}
        """.utf8))
        XCTAssertTrue(emby.isEmby)
        XCTAssertEqual(emby.serverName, "emby")
        XCTAssertEqual(emby.version, "4.10.2.0")

        let jellyfin = EmbyPublicInfo(json: [
            "ServerName": "Home", "Version": "10.11.2", "ProductName": "Jellyfin Server", "Id": "abc"
        ])
        XCTAssertFalse(jellyfin.isEmby)
        let jellyfin12 = EmbyPublicInfo(json: ["Version": "12.0.0", "ProductName": "Jellyfin Server"])
        XCTAssertFalse(jellyfin12.isEmby)
        XCTAssertFalse(EmbyPublicInfo(json: ["ServerName": "Unknown"]).isEmby)
        XCTAssertFalse(EmbyPublicInfo(json: ["Version": "10.9.0"]).isEmby)
    }

    func testSavedSessionServerKindRoundTripsAndDefaultsToJellyfin() throws {
        let emby = SavedSession(
            serverURL: serverURL,
            accessToken: "t",
            userID: "8f3c",
            userName: "Alex",
            deviceID: "device",
            serverVersion: "4.10.2.0",
            serverKind: .emby
        )
        let encoded = try JSONEncoder().encode(emby)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["serverKind"] as? String, "emby")
        XCTAssertNil(object["backend"])
        let decoded = try JSONDecoder().decode(SavedSession.self, from: encoded)
        XCTAssertEqual(decoded, emby)
        XCTAssertTrue(decoded.isEmbyServer)

        let legacy = try JSONDecoder().decode(SavedSession.self, from: Data("""
        {"serverURL":"https://jellyfin.example","accessToken":"t","userID":"u","userName":"Bob","deviceID":"d"}
        """.utf8))
        XCTAssertEqual(legacy.serverKind, .jellyfin)
        XCTAssertFalse(legacy.isEmbyServer)

        let unknown = try JSONDecoder().decode(SavedSession.self, from: Data("""
        {"serverURL":"https://media.example","accessToken":"t","userID":"u","userName":"Bob","deviceID":"d","serverKind":"plex"}
        """.utf8))
        XCTAssertEqual(unknown.serverKind, .jellyfin)

        let box = try SavedAccountBox.decode(from: JSONEncoder().encode(
            SavedAccountBox(accounts: [emby], currentID: emby.accountID)
        ))
        XCTAssertEqual(box.retiredSiloAccounts, 0)
        XCTAssertEqual(box.current?.serverKind, .emby)
    }

    func testEmbyMovieMapsLikeAJellyfinMovie() throws {
        let dto = try EmbyJSON.decode(BaseItemDto.self, from: Data(Self.movieJSON.utf8))
        let item = try XCTUnwrap(ItemMapper.mediaItem(from: dto))
        XCTAssertEqual(item.id, "1093")
        XCTAssertEqual(item.name, "Halloween Kills")
        XCTAssertEqual(item.kind, .movie)
        XCTAssertEqual(item.year, 2021)
        XCTAssertEqual(item.officialRating, "R")
        XCTAssertEqual(item.genres, ["Horror"])
        XCTAssertEqual(try XCTUnwrap(item.runtime), 6388.992, accuracy: 0.001)
        XCTAssertEqual(item.tmdbID, 610253)
        XCTAssertTrue(item.isFavorite)
        XCTAssertEqual(item.videoResolution, .hd)
        XCTAssertEqual(item.audioFormat, .surround)
        XCTAssertEqual(item.videoRange, .sdr)
        XCTAssertNil(item.primaryImageTag)
        XCTAssertEqual(dto.studios?.first?.id, "3798")
        XCTAssertEqual(dto.genreItems?.first?.id, "2070")
        XCTAssertEqual(ItemMapper.credits(from: dto.people).map(\.name), ["Jamie Lee Curtis", "David Gordon Green"])
        XCTAssertEqual(ItemMapper.versions(from: dto.mediaSources).map(\.id), ["mediasource_1093"])
    }

    func testEmbySeriesAndEpisodesMapWithArtworkAndHDR() throws {
        let series = try XCTUnwrap(ItemMapper.mediaItem(from: EmbyJSON.decode(BaseItemDto.self, from: Data("""
        {"Name":"Sample Series","ServerId":"s","Id":"36488","Type":"Series","IsFolder":true,"ProductionYear":2007,
         "ImageTags":{"Primary":"e716_1","Logo":"26e3_1","Thumb":"709f_1"},"BackdropImageTags":["e945_1"],
         "UserData":{"UnplayedItemCount":22,"PlaybackPositionTicks":0,"PlayCount":0,"IsFavorite":false,"Played":false}}
        """.utf8))))
        XCTAssertEqual(series.kind, .series)
        XCTAssertEqual(series.primaryImageTag, "e716_1")
        XCTAssertEqual(series.logoImageTag, "26e3_1")
        XCTAssertEqual(series.backdropImageTag, "e945_1")
        XCTAssertEqual(series.unplayedCount, 22)
        let artwork = ArtworkURLBuilder(serverURL: serverURL, accessToken: token)
        let poster = try XCTUnwrap(artwork.primary(for: series))
        XCTAssertEqual(poster.path, "/Items/36488/Images/Primary")
        XCTAssertTrue(poster.absoluteString.contains("tag=e716_1"))
        XCTAssertTrue(poster.absoluteString.contains("api_key=\(token)"))

        let page = try EmbyJSON.decode(BaseItemDtoQueryResult.self, from: Data(Self.episodesJSON.utf8))
        let episodes = (page.items ?? []).compactMap(ItemMapper.mediaItem(from:))
        XCTAssertEqual(episodes.map(\.id), ["40968", "40969"])
        let pilot = try XCTUnwrap(episodes.first)
        XCTAssertEqual(pilot.kind, .episode)
        XCTAssertEqual(pilot.seriesID, "40944")
        XCTAssertEqual(pilot.seriesName, "Pretty Little Liars")
        XCTAssertEqual(pilot.seasonIndex, 1)
        XCTAssertEqual(pilot.episodeIndex, 1)
        XCTAssertEqual(pilot.videoRange, .dolbyVision)
        XCTAssertEqual(pilot.audioFormat, .surround)
        XCTAssertEqual(episodes[1].videoRange, .sdr)
    }

    func testThemeMediaWithNumericOwnerIdsDecodes() throws {
        let result = try EmbyJSON.decode(AllThemeMediaResult.self, from: Data("""
        {"ThemeVideosResult":{"OwnerId":1,"Items":[],"TotalRecordCount":0},
         "ThemeSongsResult":{"OwnerId":1,"Items":[{"Name":"Theme","Id":"501","Type":"Audio"}],"TotalRecordCount":1},
         "SoundtrackSongsResult":{"OwnerId":0,"Items":[],"TotalRecordCount":0}}
        """.utf8))
        XCTAssertEqual(result.themeSongsResult?.ownerID, "1")
        XCTAssertEqual(result.themeSongsResult?.items?.first?.id, "501")
    }

    func testPlaybackInfoPicksTheSourceAndBuildsStreamURLs() throws {
        let response = try EmbyJSON.decode(PlaybackInfoResponse.self, from: Data(Self.playbackInfoJSON.utf8))
        let sources = response.mediaSources ?? []
        XCTAssertEqual(EmbyPlayback.selectSource(sources, requested: nil)?.id, "mediasource_1093")
        XCTAssertEqual(EmbyPlayback.selectSource(sources, requested: "mediasource_2000")?.id, "mediasource_2000")
        XCTAssertEqual(EmbyPlayback.selectSource(sources, requested: "1093")?.id, "mediasource_1093")
        XCTAssertNil(EmbyPlayback.selectSource([], requested: nil))

        let extras = try EmbyJSON.decode(EmbyPlaybackExtras.self, from: Data(Self.playbackInfoJSON.utf8))
        let direct = try EmbyPlayback.streamURL(
            itemID: "1093",
            source: sources[0],
            directStreamPath: extras.source(id: "mediasource_1093")?.directStreamURL,
            serverURL: serverURL,
            token: token
        )
        XCTAssertEqual(direct.host, "emby.example")
        XCTAssertEqual(direct.path, "/videos/1093/original.mkv")
        let directQuery = URLComponents(url: direct, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(directQuery.first { $0.name == "MediaSourceId" }?.value, "mediasource_1093")
        XCTAssertEqual(directQuery.first { $0.name == "PlaySessionId" }?.value, "psid")
        XCTAssertEqual(directQuery.filter { $0.name == "api_key" }.map(\.value), [token])

        XCTAssertEqual(ItemMapper.playbackMethod(from: sources[1]), .transcode)
        let transcode = try EmbyPlayback.streamURL(
            itemID: "1093",
            source: sources[1],
            directStreamPath: nil,
            serverURL: serverURL,
            token: token
        )
        XCTAssertEqual(transcode.path, "/videos/1093/master.m3u8")
        XCTAssertFalse(transcode.absoluteString.contains("StartTimeTicks"))
        XCTAssertEqual(
            URLComponents(url: transcode, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == "api_key" }.count,
            1
        )

        let fallback = try EmbyPlayback.streamURL(
            itemID: "1093",
            source: sources[0],
            directStreamPath: nil,
            serverURL: serverURL,
            token: token
        )
        XCTAssertEqual(fallback.path, "/Videos/1093/stream.mkv")
        XCTAssertTrue(fallback.absoluteString.contains("MediaSourceId=mediasource_1093"))
    }

    func testPlaybackPlanFromEmbyPlaybackInfo() throws {
        let item = try XCTUnwrap(ItemMapper.mediaItem(from: EmbyJSON.decode(BaseItemDto.self, from: Data(Self.movieJSON.utf8))))
        let data = Data(Self.playbackInfoJSON.utf8)
        let response = try EmbyJSON.decode(PlaybackInfoResponse.self, from: data)
        let source = try XCTUnwrap(EmbyPlayback.selectSource(response.mediaSources ?? [], requested: nil))
        let extras = try EmbyJSON.decode(EmbyPlaybackExtras.self, from: data)
        let plan = try EmbyLibraryClient.plan(
            item: item,
            response: response,
            source: source,
            extras: extras.source(id: source.id),
            resume: 42,
            audioIndex: nil,
            subtitleIndex: nil,
            preferences: JellyfinPlaybackPreferences(),
            api: EmbyAPI(serverURL: serverURL, accessToken: token, deviceID: "device"),
            streams: StreamURLBuilder(serverURL: serverURL, accessToken: token)
        )
        XCTAssertEqual(plan.mediaSourceID, "mediasource_1093")
        XCTAssertEqual(plan.playSessionID, "psid")
        XCTAssertEqual(plan.method, .directPlay)
        XCTAssertEqual(plan.container, "mkv")
        XCTAssertEqual(plan.byteSize, 8_517_199_843)
        XCTAssertEqual(plan.startTime, 42)
        XCTAssertEqual(plan.streamURL.path, "/videos/1093/original.mkv")
        XCTAssertEqual(plan.audioTracks.map(\.id), [1, 2])
        XCTAssertEqual(plan.audioTracks.first(where: \.isSelected)?.id, 1)
        XCTAssertEqual(plan.subtitleTracks.map(\.id), [3, 4, 5])
        XCTAssertEqual(plan.externalSubtitles.count, 1)
        let sidecar = try XCTUnwrap(plan.externalSubtitles.first?.url)
        XCTAssertEqual(sidecar.path, "/Videos/1093/mediasource_1093/Subtitles/5/0/Stream.subrip")
        XCTAssertEqual(URLComponents(url: sidecar, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == "api_key" }.count, 1)
        XCTAssertEqual(plan.chapters.map(\.name), ["Chapter 1", "Chapter 2"])
        XCTAssertEqual(plan.chapters.map(\.index), [0, 3])
        XCTAssertEqual(plan.skipSegments.map(\.kind), [.intro, .outro])
        XCTAssertEqual(plan.skipSegments.first?.start, 90)
        XCTAssertEqual(plan.skipSegments.first?.end, 180)
        XCTAssertEqual(try XCTUnwrap(plan.skipSegments.last?.end), 6388.992, accuracy: 0.001)
        XCTAssertNil(plan.trickplay)
        let bif = try XCTUnwrap(plan.bifPreviewURL)
        XCTAssertEqual(bif.path, "/Videos/1093/index.bif")
        XCTAssertTrue(bif.absoluteString.contains("Width=320"))

        let body = EmbyPlaybackReporter.body(plan: plan, position: 61, isPaused: true)
        XCTAssertEqual(body["ItemId"] as? String, "1093")
        XCTAssertEqual(body["MediaSourceId"] as? String, "mediasource_1093")
        XCTAssertEqual(body["PlaySessionId"] as? String, "psid")
        XCTAssertEqual(body["PlayMethod"] as? String, "DirectPlay")
        XCTAssertEqual(body["PositionTicks"] as? Int, 610_000_000)
        XCTAssertEqual(body["IsPaused"] as? Bool, true)
        XCTAssertEqual(body["AudioStreamIndex"] as? Int, 1)
    }

    func testDeviceProfileBodyDropsJellyfinOnlyCodecConditions() throws {
        let body = try EmbyPlayback.deviceProfileBody(maxBitrate: 20_000_000)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let profile = try XCTUnwrap(object["DeviceProfile"] as? [String: Any])
        XCTAssertNil(profile["CodecProfiles"])
        XCTAssertEqual(profile["MaxStreamingBitrate"] as? Int, 20_000_000)
        XCTAssertFalse((profile["DirectPlayProfiles"] as? [Any] ?? []).isEmpty)
        let transcoding = try XCTUnwrap((profile["TranscodingProfiles"] as? [[String: Any]])?.first)
        XCTAssertEqual(transcoding["Protocol"] as? String, "hls")
    }

    func testChapterMarkersBecomeSkipSegments() {
        func chapter(_ seconds: Double, _ name: String, _ marker: String = "Chapter") -> EmbyChapter {
            EmbyChapter(startPositionTicks: TickClock.ticks(from: seconds), name: name, markerType: marker)
        }
        let markers = EmbyPlayback.skipSegments(
            from: [
                chapter(0, "Chapter 1"),
                chapter(1200, "Credits", "CreditsStart"),
                chapter(30, "Intro", "IntroStart"),
                chapter(95, "Intro End", "IntroEnd")
            ],
            runtime: 1320
        )
        XCTAssertEqual(markers, [
            SkipSegment(kind: .intro, start: 30, end: 95),
            SkipSegment(kind: .outro, start: 1200, end: 1320)
        ])

        let named = EmbyPlayback.skipSegments(
            from: [
                chapter(0, "Chapter 1"),
                chapter(412.162, "Intro"),
                chapter(432.016, "Chapter 2"),
                chapter(2648, "Credits")
            ],
            runtime: 2676.341
        )
        XCTAssertEqual(named.map(\.kind), [.intro, .outro])
        XCTAssertEqual(named[0].start, 412.162, accuracy: 0.001)
        XCTAssertEqual(named[0].end, 432.016, accuracy: 0.001)
        XCTAssertEqual(named[1].end, 2676.341, accuracy: 0.001)

        XCTAssertTrue(EmbyPlayback.skipSegments(from: [chapter(0, "Chapter 1"), chapter(300, "Chapter 2")], runtime: 600).isEmpty)
        XCTAssertTrue(EmbyPlayback.skipSegments(from: [chapter(10, "Intro", "IntroStart")], runtime: 600).isEmpty)
        XCTAssertEqual(
            EmbyPlayback.chapters(from: [chapter(0, ""), chapter(30, "Intro", "IntroStart")]).map(\.name),
            ["Chapter 1"]
        )
    }

    func testBIFIndexFindsFramesByTime() throws {
        let frames: [[UInt8]] = [[0xFF, 0xD8, 0x01], [0xFF, 0xD8, 0x02, 0x02], [0xFF, 0xD8, 0x03]]
        var data = Data(BIFIndex.magic)
        func append32(_ value: UInt32) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        append32(0)
        append32(UInt32(frames.count))
        append32(1000)
        data.append(Data(repeating: 0, count: 64 - data.count))
        var offset = UInt32(64 + (frames.count + 1) * 8)
        for (position, frame) in frames.enumerated() {
            append32(UInt32(position * 10))
            append32(offset)
            offset += UInt32(frame.count)
        }
        append32(0xFFFF_FFFF)
        append32(offset)
        for frame in frames { data.append(contentsOf: frame) }

        let index = try XCTUnwrap(BIFIndex(data: data))
        XCTAssertEqual(index.interval, 1)
        XCTAssertEqual(index.frames.map(\.time), [0, 10, 20])
        XCTAssertEqual(index.frameIndex(at: 0), 0)
        XCTAssertEqual(index.frameIndex(at: 15), 1)
        XCTAssertEqual(index.frameIndex(at: 9999), 2)
        XCTAssertEqual(data.subdata(in: index.frames[1].bytes), Data([0xFF, 0xD8, 0x02, 0x02]))

        var empty = Data(BIFIndex.magic)
        empty.append(Data(repeating: 0, count: 8))
        empty.append(contentsOf: [0x10, 0x27, 0, 0])
        empty.append(Data(repeating: 0, count: 64 - empty.count))
        empty.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF, 0x48, 0, 0, 0])
        let none = try XCTUnwrap(BIFIndex(data: empty))
        XCTAssertTrue(none.frames.isEmpty)
        XCTAssertEqual(none.interval, 10)
        XCTAssertNil(none.frameIndex(at: 5))

        XCTAssertNil(BIFIndex(data: Data("not a bif".utf8)))
        XCTAssertNil(BIFIndex(data: data.prefix(70)))
    }

    func testCatalogQueryUsesEmbyParameters() {
        var query = CatalogBrowseQuery()
        query.statuses = [.unplayed, .favorite]
        query.features = [.subtitles]
        query.genres = ["Horror", "Comedy"]
        query.officialRatings = ["R", "PG-13"]
        query.years = [2021, 1999]
        query.studios = ["Miramax"]
        query.sort = .dateAdded
        query.sortAscending = false
        let items = Dictionary(EmbyCatalogQuery.items(for: query, isHd: true, is4K: nil).map { ($0.0, $0.1) }) { first, _ in first }
        XCTAssertEqual(items["Filters"], "IsUnplayed,IsFavorite")
        XCTAssertEqual(items["HasSubtitles"], "true")
        XCTAssertEqual(items["IsHD"], "true")
        XCTAssertNil(items["Is4K"] ?? nil)
        XCTAssertEqual(items["Genres"], "Comedy|Horror")
        XCTAssertEqual(items["OfficialRatings"], "PG-13|R")
        XCTAssertEqual(items["Years"], "1999,2021")
        XCTAssertEqual(items["Studios"], "Miramax")
        XCTAssertEqual(items["SortBy"], "DateCreated")
        XCTAssertEqual(items["SortOrder"], "Descending")
    }

    private static let movieJSON = """
    {"Name":"Halloween Kills","ServerId":"0f1e2d3c4b5a69788796a5b4c3d2e1f0","Id":"1093",
     "DateCreated":"2026-10-21T17:11:11.0000000Z","Container":"mkv","PremiereDate":"2021-10-14T00:00:00.0000000Z",
     "CriticRating":38,"OfficialRating":"R","CommunityRating":6.4,"RunTimeTicks":63889920000,"ProductionYear":2021,
     "ProviderIds":{"Imdb":"tt10665338","Tvdb":"132891","Tmdb":"610253"},"IsFolder":false,"Type":"Movie",
     "Genres":["Horror"],"GenreItems":[{"Name":"Horror","Id":2070}],"Studios":[{"Name":"Miramax","Id":3798}],
     "TagItems":[{"Name":"halloween","Id":2075}],
     "People":[{"Name":"David Gordon Green","Id":"3778","Type":"Director"},
               {"Name":"Jamie Lee Curtis","Id":"3780","Role":"Laurie Strode","Type":"Actor","PrimaryImageTag":"c3ca_0"}],
     "UserData":{"PlaybackPositionTicks":0,"PlayCount":0,"IsFavorite":true,"Played":false},
     "MediaSources":[{"Id":"mediasource_1093","Protocol":"File","Type":"Default","Container":"mkv","Size":8517199843,
                      "Name":"Halloween Kills (2021) WEBDL-1080p","SupportsDirectPlay":true,"Bitrate":10664843}],
     "MediaStreams":[{"Codec":"h264","Type":"Video","Index":0,"Width":1920,"Height":800,"VideoRange":"SDR",
                      "ExtendedVideoType":"None","IsDefault":true},
                     {"Codec":"eac3","Language":"eng","Type":"Audio","Index":1,"Channels":6,
                      "DisplayTitle":"English EAC3 5.1 (Default)","IsDefault":true}],
     "ImageTags":{},"BackdropImageTags":[],
     "Chapters":[{"StartPositionTicks":0,"Name":"Chapter 1","MarkerType":"Chapter","ChapterIndex":0}],
     "MediaType":"Video","Width":1920,"Height":800}
    """

    private static let episodesJSON = """
    {"Items":[
      {"Name":"Pretty Little Liars - S01E01 - Pilot WEBDL-1080p","ServerId":"s","Id":"40968","Container":"mkv",
       "RunTimeTicks":26763410000,"IndexNumber":1,"ParentIndexNumber":1,"IsFolder":false,"Type":"Episode",
       "VideoType":"Hologram","SeriesName":"Pretty Little Liars","SeriesId":"40944","SeasonId":"40948","SeasonName":"Season 1",
       "MediaStreams":[{"Codec":"hevc","Type":"Video","Index":0,"Width":1920,"Height":1080,"VideoRange":"HDR",
                        "ExtendedVideoType":"DolbyVision","IsDefault":true},
                       {"Codec":"ac3","Language":"eng","Type":"Audio","Index":1,"Channels":6,"DisplayTitle":"English AC3 5.1"}],
       "UserData":{"PlaybackPositionTicks":0,"PlayCount":0,"IsFavorite":false,"Played":false},"ImageTags":{},"BackdropImageTags":[]},
      {"Name":"Pretty Little Liars - S01E02","ServerId":"s","Id":"40969","IndexNumber":2,"ParentIndexNumber":1,
       "IsFolder":false,"Type":"Episode","VideoType":"Hologram","SeriesId":"40944","SeriesName":"Pretty Little Liars",
       "MediaStreams":[{"Codec":"h264","Type":"Video","Index":0,"Width":1920,"Height":1080,"VideoRange":"SDR",
                        "ExtendedVideoType":"None"}],
       "UserData":{"PlaybackPositionTicks":0,"PlayCount":0,"IsFavorite":false,"Played":false}}
    ],"TotalRecordCount":22}
    """

    private static let playbackInfoJSON = """
    {"MediaSources":[
      {"Chapters":[{"StartPositionTicks":0,"Name":"Chapter 1","MarkerType":"Chapter","ChapterIndex":0},
                   {"StartPositionTicks":900000000,"Name":"Intro","MarkerType":"IntroStart","ChapterIndex":1},
                   {"StartPositionTicks":1800000000,"Name":"Intro End","MarkerType":"IntroEnd","ChapterIndex":2},
                   {"StartPositionTicks":3000000000,"Name":"Chapter 2","MarkerType":"Chapter","ChapterIndex":3},
                   {"StartPositionTicks":60000000000,"Name":"Credits","MarkerType":"CreditsStart","ChapterIndex":4}],
       "Protocol":"File","Id":"mediasource_1093","Type":"Default","Container":"mkv","Size":8517199843,
       "Name":"Halloween Kills (2021) WEBDL-1080p","IsRemote":false,"RunTimeTicks":63889920000,
       "SupportsTranscoding":true,"SupportsDirectStream":true,"SupportsDirectPlay":true,"IsInfiniteStream":false,
       "MediaStreams":[
         {"Codec":"h264","Type":"Video","Index":0,"Width":1920,"Height":800,"VideoRange":"SDR","IsDefault":true},
         {"Codec":"eac3","Language":"eng","Type":"Audio","Index":1,"Channels":6,"DisplayTitle":"English EAC3 5.1 (Default)","IsDefault":true},
         {"Codec":"eac3","Language":"tur","Type":"Audio","Index":2,"Channels":6,"DisplayTitle":"Turkish EAC3 5.1"},
         {"Codec":"subrip","Language":"tur","Type":"Subtitle","Index":3,"DisplayTitle":"Turkish (Default SUBRIP)","IsDefault":true,
          "IsExternal":false,"DeliveryMethod":"External","DeliveryUrl":"/Videos/1093/mediasource_1093/Subtitles/3/0/Stream.subrip?api_key=test-token"},
         {"Codec":"subrip","Language":"eng","Type":"Subtitle","Index":4,"DisplayTitle":"English (SUBRIP)","IsExternal":false},
         {"Codec":"subrip","Language":"eng","Type":"Subtitle","Index":5,"DisplayTitle":"English (SDH)","IsExternal":true,
          "DeliveryMethod":"External","DeliveryUrl":"/Videos/1093/mediasource_1093/Subtitles/5/0/Stream.subrip?api_key=test-token"}],
       "Formats":[],"Bitrate":10664843,"RequiredHttpHeaders":{},
       "DirectStreamUrl":"/videos/1093/original.mkv?DeviceId=device&MediaSourceId=mediasource_1093&PlaySessionId=psid",
       "AddApiKeyToDirectStreamUrl":false,"DefaultAudioStreamIndex":1,"ItemId":"1093"},
      {"Id":"mediasource_2000","Protocol":"File","Type":"Default","Container":"mkv","SupportsDirectPlay":false,
       "SupportsDirectStream":false,"SupportsTranscoding":true,"TranscodingSubProtocol":"hls","TranscodingContainer":"ts",
       "TranscodingUrl":"/videos/1093/master.m3u8?MediaSourceId=mediasource_2000&PlaySessionId=psid&StartTimeTicks=0&api_key=test-token",
       "MediaStreams":[],"ItemId":"1093"}
    ],"PlaySessionId":"psid"}
    """
}

/// Records every request an `EmbyAPI` sends and answers from canned JSON, so write paths are
/// checked without touching a server.
private final class EmbyRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let responder: @Sendable (URLRequest) -> String

    init(_ responder: @escaping @Sendable (URLRequest) -> String = { _ in "{}" }) {
        self.responder = responder
    }

    var requests: [URLRequest] { lock.withLock { recorded } }
    var last: URLRequest? { requests.last }

    func api(token: String = "test-token") -> EmbyAPI {
        EmbyAPI(serverURL: URL(string: "http://emby.example:8096")!, accessToken: token, deviceID: "device") { request in
            self.lock.withLock { self.recorded.append(request) }
            return Data(self.responder(request).utf8)
        }
    }
}

private extension URLRequest {
    var path: String { url?.path ?? "" }

    func query(_ name: String) -> String? {
        URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    var json: [String: Any] {
        (httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
    }
}

final class EmbyPhase2Tests: XCTestCase {
    private let userID = "u1"

    private func library(_ recorder: EmbyRecorder) -> EmbyLibraryClient {
        EmbyLibraryClient(api: recorder.api(), userID: userID)
    }

    func testAccountRequests() async throws {
        let recorder = EmbyRecorder()
        let lib = library(recorder)
        try await lib.changePassword(current: "old", new: "new")
        var request = try XCTUnwrap(recorder.last)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.path, "/Users/u1/Password")
        XCTAssertEqual(request.json["CurrentPw"] as? String, "old")
        XCTAssertEqual(request.json["NewPw"] as? String, "new")
        XCTAssertEqual(request.json["ResetPassword"] as? Bool, false)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Emby-Token"), "test-token")
        XCTAssertTrue(request.value(forHTTPHeaderField: "X-Emby-Authorization")?.hasPrefix("MediaBrowser Client=\"Zelefin\"") == true)

        try await lib.uploadUserImage(userID: "u2", jpeg: Data([0xFF, 0xD8, 0xFF]))
        request = try XCTUnwrap(recorder.last)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.path, "/Users/u2/Images/Primary")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
        XCTAssertEqual(request.httpBody, Data([0xFF, 0xD8, 0xFF]).base64EncodedData())

        try await lib.deleteUserImage(userID: "u2")
        XCTAssertEqual(recorder.last?.httpMethod, "DELETE")
        XCTAssertEqual(recorder.last?.path, "/Users/u2/Images/Primary")
    }

    func testDisplayPreferencesKeepEmbyFieldsOnWrite() async throws {
        let recorder = EmbyRecorder { _ in
            #"{"Id":"zelefin","CustomPrefs":{"tabOrder":"home,library"},"SortOrder":"Ascending","Client":"Zelefin"}"#
        }
        let lib = library(recorder)
        let prefs = try await lib.displayPreferenceCustomPrefs()
        XCTAssertEqual(prefs, ["tabOrder": "home,library"])
        XCTAssertEqual(recorder.last?.path, "/DisplayPreferences/zelefin")
        XCTAssertEqual(recorder.last?.query("UserId"), "u1")
        XCTAssertEqual(recorder.last?.query("Client"), "Zelefin")

        try await lib.updateDisplayPreferenceCustomPrefs(["tabOrder": "search"])
        let write = try XCTUnwrap(recorder.last)
        XCTAssertEqual(write.httpMethod, "POST")
        XCTAssertEqual(write.path, "/DisplayPreferences/zelefin")
        XCTAssertEqual(write.query("UserId"), "u1")
        XCTAssertEqual(write.json["CustomPrefs"] as? [String: String], ["tabOrder": "search"])
        XCTAssertEqual(write.json["SortOrder"] as? String, "Ascending")
        XCTAssertEqual(write.json["Client"] as? String, "Zelefin")
    }

    func testLikesPlaylistsAndCollections() async throws {
        let recorder = EmbyRecorder { request in
            switch (request.httpMethod ?? "", request.path) {
            case ("POST", "/Users/u1/Items/1093/Rating"): #"{"Likes":true,"IsFavorite":false,"Played":false}"#
            case ("POST", "/Playlists"), ("POST", "/Collections"): #"{"Id":4242}"#
            case ("GET", "/Playlists/4242/Items"):
                #"{"Items":[{"Name":"Halloween Kills","Id":"1093","Type":"Movie","PlaylistItemId":7}],"TotalRecordCount":1}"#
            default: "{}"
            }
        }
        let lib = library(recorder)
        let liked = try await lib.setLikes(itemID: "1093", likes: true)
        XCTAssertEqual(liked, true)
        XCTAssertEqual(recorder.last?.query("Likes"), "true")
        _ = try await lib.setLikes(itemID: "1093", likes: false)
        XCTAssertEqual(recorder.last?.query("Likes"), "false")
        let cleared = try await lib.setLikes(itemID: "1093", likes: nil)
        XCTAssertNil(cleared)
        XCTAssertEqual(recorder.last?.httpMethod, "DELETE")
        XCTAssertEqual(recorder.last?.path, "/Users/u1/Items/1093/Rating")

        let playlist = try await lib.createPlaylistID(name: "Zelefin Test", itemIDs: [])
        XCTAssertEqual(playlist, "4242")
        XCTAssertEqual(recorder.last?.query("Name"), "Zelefin Test")
        XCTAssertEqual(recorder.last?.query("MediaType"), "Video")
        XCTAssertNil(recorder.last?.query("Ids"))
        try await lib.addToPlaylist(playlistID: playlist, itemIDs: ["1093", "1094"])
        XCTAssertEqual(recorder.last?.httpMethod, "POST")
        XCTAssertEqual(recorder.last?.path, "/Playlists/4242/Items")
        XCTAssertEqual(recorder.last?.query("Ids"), "1093,1094")
        XCTAssertEqual(recorder.last?.query("UserId"), "u1")
        let entries = try await lib.playlistEntries(playlistID: playlist)
        XCTAssertEqual(entries.map(\.id), ["7"])
        XCTAssertEqual(entries.first?.item.id, "1093")
        try await lib.removeFromPlaylist(playlistID: playlist, entryIDs: entries.map(\.id))
        XCTAssertEqual(recorder.last?.httpMethod, "DELETE")
        XCTAssertEqual(recorder.last?.query("EntryIds"), "7")

        let collection = try await lib.createCollectionID(name: "Zelefin Test", itemIDs: ["1093"])
        XCTAssertEqual(collection, "4242")
        XCTAssertEqual(recorder.last?.path, "/Collections")
        XCTAssertEqual(recorder.last?.query("Ids"), "1093")
        XCTAssertEqual(recorder.last?.query("IsLocked"), "false")
        try await lib.addToCollection(collectionID: collection, itemIDs: ["1094"])
        XCTAssertEqual(recorder.last?.httpMethod, "POST")
        XCTAssertEqual(recorder.last?.path, "/Collections/4242/Items")
        XCTAssertEqual(recorder.last?.query("Ids"), "1094")
        try await lib.removeFromCollection(collectionID: collection, itemIDs: ["1094"])
        XCTAssertEqual(recorder.last?.httpMethod, "DELETE")
        XCTAssertEqual(recorder.last?.path, "/Collections/4242/Items")
    }

    func testWatchlistIsOnlyCreatedWhenSomethingIsAdded() async throws {
        let recorder = EmbyRecorder { request in
            switch (request.httpMethod ?? "", request.path) {
            case ("GET", "/Users/u1/Items"): #"{"Items":[],"TotalRecordCount":0}"#
            case ("POST", "/Playlists"): #"{"Id":"55"}"#
            default: "{}"
            }
        }
        let lib = library(recorder)
        let items = await lib.watchlistItems()
        XCTAssertTrue(items.isEmpty)
        XCTAssertFalse(recorder.requests.contains { $0.httpMethod == "POST" })

        try await lib.setWatchlisted(itemID: "1093", watchlisted: true)
        let posts = recorder.requests.filter { $0.httpMethod == "POST" }
        XCTAssertEqual(posts.map(\.path), ["/Playlists", "/Playlists/55/Items"])
        XCTAssertEqual(posts.first?.query("Name"), "Watchlist")
        XCTAssertEqual(posts.last?.query("Ids"), "1093")
    }

    func testItemAdministrationRequests() async throws {
        let recorder = EmbyRecorder { request in
            switch (request.httpMethod ?? "", request.path) {
            case ("GET", "/Users/u1/Items/1093"):
                #"{"Name":"Old","Id":"1093","Type":"Movie","LockedFields":["Name"],"Genres":["Horror"],"ProductionYear":2021}"#
            case ("GET", "/Items/1093/RemoteImages"):
                #"{"Images":[{"ProviderName":"TheMovieDb","Url":"https://image.tmdb.org/t/p/original/a.jpg","ThumbnailUrl":"https://image.tmdb.org/t/p/w500/a.jpg","Height":3000,"Width":2000,"Type":"Primary","RatingType":"Score"}],"TotalRecordCount":1,"Providers":["TheMovieDb"]}"#
            case ("POST", "/Items/RemoteSearch/Movie"):
                #"[{"Name":"Halloween Kills","ProductionYear":2021,"ProviderIds":{"Tmdb":"610253"},"SearchProviderName":"TheMovieDb","ImageUrl":"https://image.tmdb.org/t/p/original/b.jpg"}]"#
            default: "{}"
            }
        }
        let lib = library(recorder)
        try await lib.refreshItemMetadata(itemID: "1093", replaceImages: true)
        XCTAssertEqual(recorder.last?.path, "/Items/1093/Refresh")
        XCTAssertEqual(recorder.last?.query("MetadataRefreshMode"), "FullRefresh")
        XCTAssertEqual(recorder.last?.query("ImageRefreshMode"), "FullRefresh")
        XCTAssertEqual(recorder.last?.query("ReplaceAllImages"), "true")
        try await lib.deleteLibraryItem(itemID: "1093")
        XCTAssertEqual(recorder.last?.httpMethod, "DELETE")
        XCTAssertEqual(recorder.last?.path, "/Items/1093")
        try await lib.scanLibraries()
        XCTAssertEqual(recorder.last?.httpMethod, "POST")
        XCTAssertEqual(recorder.last?.path, "/Library/Refresh")

        var draft = ItemMetadataDraft(item: try XCTUnwrap(ItemMapper.mediaItem(from: BaseItemDto(id: "1093", name: "Old", type: .movie))))
        draft.name = " New Name "
        draft.year = "2022"
        draft.genres = "Horror, Thriller"
        draft.tags = "slasher"
        try await lib.updateItemMetadata(itemID: "1093", draft: draft)
        let update = try XCTUnwrap(recorder.last)
        XCTAssertEqual(update.httpMethod, "POST")
        XCTAssertEqual(update.path, "/Items/1093")
        XCTAssertEqual(update.json["Name"] as? String, "New Name")
        XCTAssertEqual(update.json["ProductionYear"] as? Int, 2022)
        XCTAssertEqual(update.json["Genres"] as? [String], ["Horror", "Thriller"])
        XCTAssertEqual((update.json["TagItems"] as? [[String: String]])?.map { $0["Name"] }, ["slasher"])
        XCTAssertEqual(update.json["LockedFields"] as? [String], ["Name"])

        let artwork = try await lib.remoteArtwork(for: "1093", kind: .backdrop)
        XCTAssertEqual(recorder.requests.last { $0.path == "/Items/1093/RemoteImages" }?.query("Type"), "Backdrop")
        XCTAssertEqual(artwork.first?.provider, "TheMovieDb")
        XCTAssertEqual(artwork.first?.width, 2000)
        try await lib.downloadRemoteArtwork(itemID: "1093", kind: .poster, imageURL: URL(string: "https://image.tmdb.org/t/p/original/a.jpg")!)
        XCTAssertEqual(recorder.last?.path, "/Items/1093/RemoteImages/Download")
        XCTAssertEqual(recorder.last?.query("Type"), "Primary")
        XCTAssertEqual(recorder.last?.query("ImageUrl"), "https://image.tmdb.org/t/p/original/a.jpg")

        let movie = try XCTUnwrap(ItemMapper.mediaItem(from: BaseItemDto(id: "1093", name: "Halloween Kills", productionYear: 2021, providerIDs: ["Tmdb": "610253"], type: .movie)))
        let hits = await lib.identifyHits(for: movie)
        let search = try XCTUnwrap(recorder.requests.last { $0.path == "/Items/RemoteSearch/Movie" })
        XCTAssertEqual(search.httpMethod, "POST")
        XCTAssertEqual(search.json["ItemId"] as? String, "1093")
        XCTAssertEqual((search.json["SearchInfo"] as? [String: Any])?["Year"] as? Int, 2021)
        XCTAssertEqual(((search.json["SearchInfo"] as? [String: Any])?["ProviderIds"] as? [String: String])?["Tmdb"], "610253")
        XCTAssertEqual(hits.first?.name, "Halloween Kills")
        try await lib.applyIdentify(itemID: "1093", hit: try XCTUnwrap(hits.first))
        let apply = try XCTUnwrap(recorder.last)
        XCTAssertEqual(apply.path, "/Items/RemoteSearch/Apply/1093")
        XCTAssertEqual(apply.query("ReplaceAllImages"), "true")
        XCTAssertEqual(apply.json["SearchProviderName"] as? String, "TheMovieDb")
        XCTAssertEqual((apply.json["ProviderIds"] as? [String: String])?["Tmdb"], "610253")
    }

    func testUserAdministrationKeepsEmbyOnlyPolicyFields() async throws {
        let user = #"""
        {"Name":"Kid","Id":"u2","HasPassword":true,"Configuration":{"SubtitleMode":"Smart"},
         "Policy":{"IsAdministrator":false,"IsDisabled":false,"EnableAllFolders":true,"EnabledFolders":[],
                   "BlockUnratedItems":["Game"],"EnableContentDeletion":true,"SimultaneousStreamLimit":2,
                   "AuthenticationProviderId":"Emby.Server.Implementations.Library.DefaultAuthenticationProvider",
                   "RemoteClientBitrateLimit":0,"EnableSubtitleManagement":false}}
        """#
        let recorder = EmbyRecorder { request in
            switch (request.httpMethod ?? "", request.path) {
            case ("GET", "/Users/Query"): #"{"Items":[\#(user)],"TotalRecordCount":1}"#
            case ("GET", "/Users/u2"): user
            case ("GET", "/Localization/ParentalRatings"): #"[{"Name":"PG","Value":5},{"Name":"PG","Value":5},{"Name":"R","Value":9}]"#
            case ("GET", "/Library/MediaFolders"): #"{"Items":[{"Name":"Movies","Id":"3","Type":"CollectionFolder"}]}"#
            default: "{}"
            }
        }
        let admin = EmbyUserAdminClient(api: recorder.api())
        let users = try await admin.users()
        XCTAssertEqual(users.map(\.name), ["Kid"])
        let policy = try XCTUnwrap(users.first?.policy)
        XCTAssertEqual(policy.enableAllFolders, true)
        let ratings = try await admin.parentalRatings()
        let folders = try await admin.mediaFolders()
        XCTAssertEqual(ratings.map(\.name), ["PG", "R"])
        XCTAssertEqual(folders.map(\.id), ["3"])

        var draft = UserPolicyDraft(policy: policy)
        draft.isAdministrator = true
        draft.enableAllFolders = false
        draft.enabledFolders = ["3"]
        draft.maxParentalRating = 9
        try await admin.updatePolicy(userID: "u2", policy: draft.applying(to: policy))
        let write = try XCTUnwrap(recorder.last)
        XCTAssertEqual(write.httpMethod, "POST")
        XCTAssertEqual(write.path, "/Users/u2/Policy")
        XCTAssertEqual(write.json["IsAdministrator"] as? Bool, true)
        XCTAssertEqual(write.json["EnableAllFolders"] as? Bool, false)
        XCTAssertEqual(write.json["EnabledFolders"] as? [String], ["3"])
        XCTAssertEqual(write.json["MaxParentalRating"] as? Int, 9)
        XCTAssertEqual(write.json["EnableContentDeletion"] as? Bool, true)
        XCTAssertEqual(write.json["SimultaneousStreamLimit"] as? Int, 2)
        XCTAssertNil(write.json["PasswordResetProviderId"])
        XCTAssertEqual(write.json["BlockUnratedItems"] as? [String], ["Game"])

        try await admin.renameUser(try XCTUnwrap(users.first), name: " Kiddo ")
        XCTAssertEqual(recorder.last?.path, "/Users/u2")
        XCTAssertEqual(recorder.last?.json["Name"] as? String, "Kiddo")
        XCTAssertEqual(recorder.last?.json["HasPassword"] as? Bool, true)
        try await admin.resetPassword(userID: "u2")
        XCTAssertEqual(recorder.last?.path, "/Users/u2/Password")
        XCTAssertEqual(recorder.last?.json["ResetPassword"] as? Bool, true)
        try await admin.setPassword(userID: "u2", newPassword: "secret")
        XCTAssertEqual(recorder.last?.json["NewPw"] as? String, "secret")
        XCTAssertEqual(recorder.last?.json["ResetPassword"] as? Bool, false)
    }

    func testServerAdministrationRequestsAndDecoding() async throws {
        let recorder = EmbyRecorder { request in
            switch request.path {
            case "/ScheduledTasks":
                #"[{"Name":"Scan media library","State":"Running","CurrentProgressPercentage":42.5,"Id":"abc","Category":"Library","Description":"Scans","IsHidden":false,"Key":"RefreshLibrary","Triggers":[{"Type":"IntervalTrigger","IntervalTicks":432000000000}],"LastExecutionResult":{"Status":"Completed","Name":"Scan media library","Id":"abc"}}]"#
            case "/System/ActivityLog/Entries":
                #"{"Items":[{"Id":35,"Name":"Alex stopped playing","Type":"playback.stop","Date":"2026-10-24T00:47:06.0530000Z","Severity":"Info"},{"Id":34,"Name":"Alex started playing","Type":"playback.start","Date":"2026-10-24T00:42:46.7250000Z","Severity":"Info"}],"TotalRecordCount":2}"#
            case "/Branding/Configuration": #"{"LoginDisclaimer":"Family only","CustomCss":""}"#
            default: "{}"
            }
        }
        let lib = library(recorder)
        let tasks = try await lib.scheduledTasks()
        XCTAssertEqual(recorder.last?.query("IsHidden"), "false")
        XCTAssertEqual(tasks.map(\.id), ["abc"])
        XCTAssertEqual(tasks.first?.state, .running)
        try await lib.startScheduledTask(id: "abc")
        XCTAssertEqual(recorder.last?.httpMethod, "POST")
        XCTAssertEqual(recorder.last?.path, "/ScheduledTasks/Running/abc")
        try await lib.stopScheduledTask(id: "abc")
        XCTAssertEqual(recorder.last?.httpMethod, "DELETE")
        XCTAssertEqual(recorder.last?.path, "/ScheduledTasks/Running/abc")

        let activity = try await lib.activityLog(limit: 2)
        XCTAssertEqual(activity.map(\.id), ["35", "34"])
        XCTAssertEqual(activity.first?.type, "playback.stop")
        XCTAssertNotNil(activity.first?.date)

        XCTAssertFalse(lib.canEditBranding)
        let branding = try await lib.serverBranding()
        XCTAssertEqual(branding.loginDisclaimer, "Family only")
        do {
            try await lib.updateServerBranding(ServerBranding(loginDisclaimer: "", customCSS: "", splashscreenEnabled: false))
            XCTFail("Emby has no branding write route")
        } catch {}
    }

    func testRemoteSessionRequests() async throws {
        let recorder = EmbyRecorder { request in
            guard request.path == "/Sessions" else { return "{}" }
            return #"""
            [{"PlayState":{"PositionTicks":600000000,"CanSeek":true,"IsPaused":true,"IsMuted":false,"RepeatMode":"RepeatNone","SleepTimerMode":"None","PlaybackRate":1},
              "PlayableMediaTypes":["Audio","Video"],"Id":"s1","UserId":"u1","UserName":"Alex","Client":"Emby Web",
              "LastActivityDate":"2099-01-01T00:00:00.0000000Z","DeviceName":"Firefox macOS","DeviceId":"d1",
              "ApplicationVersion":"4.10.2.0","SupportedCommands":["MoveUp","DisplayMessage","VolumeUp","SetRepeatMode"],
              "SupportsRemoteControl":true,
              "NowPlayingItem":{"Name":"Halloween Kills","Id":"1093","Type":"Movie","RunTimeTicks":63889920000}},
             {"Id":"s2","UserName":"Old","Client":"Zelefin","DeviceName":"iPad","LastActivityDate":"2000-01-01T00:00:00.0000000Z","SupportsRemoteControl":false}]
            """#
        }
        let lib = library(recorder)
        let sessions = try await lib.playbackSessions(activeWithinSeconds: 960)
        XCTAssertEqual(sessions.map(\.id), ["s1"])
        let session = try XCTUnwrap(sessions.first)
        XCTAssertTrue(session.canControl)
        XCTAssertTrue(session.isPaused)
        XCTAssertEqual(session.nowPlaying?.id, "1093")
        XCTAssertTrue(session.supportedCommands.contains("DisplayMessage"))

        try await lib.playOnSession(sessionID: "s1", itemIDs: ["1093"], startPosition: 60)
        XCTAssertEqual(recorder.last?.path, "/Sessions/s1/Playing")
        XCTAssertEqual(recorder.last?.query("ItemIds"), "1093")
        XCTAssertEqual(recorder.last?.query("PlayCommand"), "PlayNow")
        XCTAssertEqual(recorder.last?.query("StartPositionTicks"), "600000000")
        try await lib.sendPlaystate(sessionID: "s1", command: .seek, seekPosition: 30)
        XCTAssertEqual(recorder.last?.path, "/Sessions/s1/Playing/Seek")
        XCTAssertEqual(recorder.last?.json["SeekPositionTicks"] as? Int, 300_000_000)
        try await lib.sendPlaystate(sessionID: "s1", command: .pause)
        XCTAssertEqual(recorder.last?.path, "/Sessions/s1/Playing/Pause")
        XCTAssertNil(recorder.last?.json["SeekPositionTicks"])
        try await lib.sendSessionCommand(sessionID: "s1", command: .volumeUp)
        XCTAssertEqual(recorder.last?.path, "/Sessions/s1/Command/VolumeUp")
        try await lib.sendSessionMessage(sessionID: "s1", text: "  Dinner  ")
        XCTAssertEqual(recorder.last?.path, "/Sessions/s1/Message")
        XCTAssertEqual(recorder.last?.query("Text"), "Dinner")
        XCTAssertEqual(recorder.last?.query("Header"), "Zelefin")
    }

    func testLiveTVRequests() async throws {
        let recorder = EmbyRecorder { request in
            switch request.path {
            case "/LiveTv/Info": #"{"IsEnabled":false,"EnabledUsers":[]}"#
            case "/LiveTv/Channels":
                #"{"Items":[{"Name":"News 24","Id":"ch1","Type":"TvChannel","Number":"24","ChannelType":"TV","ImageTags":{"Primary":"t1"}}],"TotalRecordCount":1}"#
            default: #"{"Items":[],"TotalRecordCount":0}"#
            }
        }
        let lib = library(recorder)
        let enabled = try await lib.liveTVInfoEnabled()
        XCTAssertFalse(enabled)
        let channels = try await lib.liveTVChannels()
        XCTAssertEqual(channels.map(\.item.id), ["ch1"])
        XCTAssertEqual(channels.first?.number, "24")
        XCTAssertEqual(recorder.last?.query("AddCurrentProgram"), "true")
        try await lib.deleteLiveTVRecording(id: "r1")
        XCTAssertEqual(recorder.last?.httpMethod, "DELETE")
        XCTAssertEqual(recorder.last?.path, "/LiveTv/Recordings/r1")
        _ = try await lib.liveTVGuide(
            channelIDs: ["ch1", "ch2"],
            from: Date(timeIntervalSince1970: 1_800_000_000),
            to: Date(timeIntervalSince1970: 1_800_010_800)
        )
        let guide = try XCTUnwrap(recorder.last)
        XCTAssertEqual(guide.path, "/LiveTv/Programs")
        XCTAssertEqual(guide.query("ChannelIds"), "ch1,ch2")
        XCTAssertEqual(guide.query("MaxStartDate"), "2027-01-15T11:00:00.000Z")
        XCTAssertEqual(guide.query("SortBy"), "StartDate")
        let flags = Dictionary(uniqueKeysWithValues: EmbyLiveTVQuery.flags(.sports).map { ($0.0, $0.1) })
        XCTAssertEqual(flags["IsSports"], "true")
    }

    func testSubtitleSearchAndDownload() async throws {
        final class Downloaded: @unchecked Sendable {
            var value = false
        }
        let downloaded = Downloaded()
        let recorder = EmbyRecorder { request in
            if request.path.contains("/RemoteSearch/Subtitles/eng") {
                return #"[{"ThreeLetterISOLanguageName":"eng","Id":"opensubtitles_123","ProviderName":"Open Subtitles","Name":"Halloween.Kills.2021.WEBRip","Format":"srt","DownloadCount":1200,"IsHashMatch":true,"IsForced":false}]"#
            }
            if request.httpMethod == "POST" {
                downloaded.value = true
                return ""
            }
            let streams = downloaded.value ? #"[{"Type":"Subtitle","Index":3,"Codec":"srt","IsExternal":true}]"# : "[]"
            return #"{"Name":"Halloween Kills","Id":"1093","Type":"Movie","MediaStreams":\#(streams)}"#
        }
        let client = EmbySubtitleClient(api: recorder.api(), userID: userID)
        let matches = try await client.search(itemID: "1093", language: "eng", perfectMatch: true)
        XCTAssertEqual(matches.map(\.id), ["opensubtitles_123"])
        XCTAssertTrue(matches.first?.isHashMatch == true)
        XCTAssertEqual(recorder.last?.query("IsPerfectMatch"), "true")
        _ = try? await client.search(itemID: "1093", language: "eng", perfectMatch: false)
        XCTAssertNil(recorder.last?.query("IsPerfectMatch"))
        try await client.download(itemID: "1093", subtitleID: "opensubtitles_123", userID: userID)
        let download = try XCTUnwrap(recorder.requests.first { $0.httpMethod == "POST" })
        XCTAssertEqual(download.path, "/Items/1093/RemoteSearch/Subtitles/opensubtitles_123")
        XCTAssertEqual(recorder.last?.path, "/Users/u1/Items/1093")
    }

    func testSessionSocketURLAndMessages() throws {
        let url = try XCTUnwrap(EmbySocket.url(base: URL(string: "https://media.example/emby/")!, token: "t", deviceID: "d"))
        XCTAssertEqual(url.scheme, "wss")
        XCTAssertEqual(url.path, "/emby/embywebsocket")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name), ["api_key", "deviceId"])
        XCTAssertEqual(EmbySocket.url(base: URL(string: "http://192.168.1.10:8096")!, token: "t", deviceID: "d")?.scheme, "ws")

        let capabilities = EmbySocket.capabilities
        XCTAssertEqual(capabilities["PlayableMediaTypes"] as? [String], ["Video"])
        XCTAssertEqual(capabilities["SupportsMediaControl"] as? Bool, true)
        XCTAssertTrue((capabilities["SupportedCommands"] as? [String])?.contains("DisplayMessage") == true)

        func event(_ json: String) -> EmbySocketEvent? { EmbySocketEvent.parse(Data(json.utf8)) }
        let display = #"{"MessageType":"GeneralCommand","Data":{"Name":"DisplayMessage","ControllingUserId":"u1","Arguments":{"Header":"Zelefin","Text":"probe","TimeoutMs":"1000"}}}"#
        XCTAssertEqual(event(display), .generalCommand(name: "DisplayMessage", arguments: ["Header": "Zelefin", "Text": "probe", "TimeoutMs": "1000"]))
        XCTAssertEqual(SessionDisplayMessage.parse(json: Data(display.utf8))?.text, "probe")
        XCTAssertEqual(
            event(#"{"MessageType":"Playstate","Data":{"Command":"Seek","SeekPositionTicks":600000000,"ControllingUserId":"u1"}}"#),
            .playstate(command: "Seek", seekPositionTicks: 600_000_000)
        )
        XCTAssertEqual(
            event(#"{"MessageType":"Play","Data":{"ItemIds":["1093",1094],"PlayCommand":"PlayNow","StartIndex":1,"StartPositionTicks":0}}"#),
            .play(itemIDs: ["1093", "1094"], startIndex: 1, startPositionTicks: 0)
        )
        XCTAssertEqual(event(#"{"MessageType":"ForceKeepAlive","Data":60}"#), .forceKeepAlive(seconds: 60))
        XCTAssertEqual(event(#"{"MessageType":"KeepAlive"}"#), .keepAlive)
        XCTAssertEqual(event(#"{"MessageType":"UserDataChanged","Data":{"UserId":"u1","UserDataList":[]}}"#), .userDataChanged)
        XCTAssertEqual(event(#"{"MessageType":"LibraryChanged","Data":{"ItemsAdded":["1"]}}"#), .libraryChanged)
        XCTAssertEqual(event(#"{"MessageType":"ScheduledTasksInfo","Data":[]}"#), .other("ScheduledTasksInfo"))
        guard case let .sessions(list)? = event(
            #"{"MessageType":"Sessions","Data":[{"Id":"s1","Client":"Emby Web","DeviceName":"Firefox","SupportsRemoteControl":true,"PlayState":{"RepeatMode":"RepeatNone"}}]}"#
        ) else { return XCTFail("Sessions message did not parse") }
        XCTAssertEqual(list.map(\.id), ["s1"])
        XCTAssertNil(event("not json"))
        XCTAssertNil(event(#"{"MessageType":"Playstate","Data":{}}"#))
        XCTAssertEqual(RemotePlaybackAction.playstate(.seek, seekTicks: 600_000_000), .seek(60))
    }
}

final class UserViewsDecodingTests: XCTestCase {
    func testUnknownCollectionTypeKeepsTheOtherLibraries() throws {
        let json = """
        {
          "Items": [
            {"Id": "a1", "Name": "Movies", "Type": "CollectionFolder", "CollectionType": "movies"},
            {"Id": "b2", "Name": "Shows", "Type": "CollectionFolder", "CollectionType": "tvshows"},
            {"Id": "c3", "Name": "Everything", "Type": "CollectionFolder", "CollectionType": "mixed"}
          ],
          "TotalRecordCount": 3,
          "StartIndex": 0
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(BaseItemDtoQueryResult.self, from: json))
        let result = try ItemMapper.decodeViews(json)
        XCTAssertEqual(result.items?.map(\.name), ["Movies", "Shows", "Everything"])
        XCTAssertEqual(result.items?.map(\.collectionType), [.movies, .tvshows, nil])
        let kinds = (result.items ?? []).compactMap(ItemMapper.library(from:)).map(\.libraryKind)
        XCTAssertEqual(kinds, [.movies, .shows, .other])
    }
}

final class SiloAccountTests: XCTestCase {
    func testDecodesSiloSignInReplies() throws {
        let pair = try JSONDecoder().decode(SiloTokenPair.self, from: Data("""
        {"access_token":"a","refresh_token":"r","expires_in":900,
         "user":{"id":"7","username":"ada","email":"","role":"user","permissions":[],"download_allowed":true,"password_change_required":false}}
        """.utf8))
        XCTAssertEqual(pair.accessToken, "a")
        XCTAssertEqual(pair.refreshToken, "r")

        let profiles = try JSONDecoder().decode(SiloProfileCollection.self, from: Data("""
        {"avatar_upload_enabled":true,"max_advisory_age_supported":true,"require_advisory_age_supported":true,
         "items":[{"id":"p1","name":"Ada","avatar":"","avatar_source":"upload","avatar_url":"/api/v2/profiles/p1/avatar?v=2",
                   "has_pin":true,"is_child":false,"is_primary":true},
                  {"id":"p2","name":"Kids","avatar":"fox","avatar_source":"preset","has_pin":false,"is_child":true,"is_primary":false}]}
        """.utf8))
        XCTAssertTrue(profiles.avatarUploadEnabled)
        let ada = profiles.items[0].resolved(against: URL(string: "https://silo.example")!)
        XCTAssertEqual(ada.avatarURL?.absoluteString, "https://silo.example/api/v2/profiles/p1/avatar?v=2")
        XCTAssertTrue(ada.hasPin)
        XCTAssertTrue(ada.hasUploadedAvatar)
        XCTAssertTrue(profiles.items[1].isChild)
        XCTAssertNil(profiles.items[1].avatarURL)

        let preset = SiloProfile(
            id: "p3", name: "Fox", avatar: "preset:dicebear:fun-emoji:mango-otter",
            avatarURL: URL(string: "https://api.dicebear.com/9.x/fun-emoji/svg?seed=mango-otter&size=128"),
            hasPin: false, isChild: false, isPrimary: false, avatarSource: "preset"
        ).resolved(against: URL(string: "https://silo.example")!)
        XCTAssertEqual(preset.avatarURL?.path, "/9.x/fun-emoji/png")
        XCTAssertTrue(preset.hasAvatar)
        XCTAssertEqual(SiloProfileAvatars.presetRef("dicebear:fun-emoji:mango-otter"), "preset:dicebear:fun-emoji:mango-otter")

        let verified = try JSONDecoder().decode(SiloProfileVerification.self, from: Data("""
        {"valid":true,"profile_token":"pt","expires_at":"2026-10-23T05:00:00Z"}
        """.utf8))
        XCTAssertEqual(verified.profileToken, "pt")
    }

    func testConnectInfoGatesTheJellyfinCompatibleAddress() throws {
        func info(enabled: Bool, restart: Bool, url: String) throws -> SiloConnectInfo {
            try JSONDecoder().decode(SiloConnectInfo.self, from: Data("""
            {"jellyfin":{"enabled":\(enabled),"pending_restart":\(restart),"public_url":"\(url)","server_name":"Home"},
             "account":{"password_login_available":true}}
            """.utf8))
        }
        XCTAssertEqual(try info(enabled: true, restart: false, url: "https://silo.example:8097").compatibleURL().absoluteString,
                       "https://silo.example:8097")
        XCTAssertThrowsError(try info(enabled: false, restart: false, url: "https://silo.example:8097").compatibleURL()) {
            XCTAssertTrue($0.localizedDescription.contains("Turn on"))
        }
        XCTAssertThrowsError(try info(enabled: true, restart: true, url: "https://silo.example:8097").compatibleURL()) {
            XCTAssertTrue($0.localizedDescription.contains("Restart"))
        }
        XCTAssertThrowsError(try info(enabled: true, restart: false, url: "").compatibleURL()) {
            XCTAssertTrue($0.localizedDescription.contains("public address"))
        }
    }

    func testProblemDetailsBecomeTheMessage() {
        XCTAssertEqual(
            SiloAccountClient.problemMessage(in: Data("""
            {"title":"Validation failed","status":422,"detail":"The request did not pass validation; see errors.",
             "errors":[{"location":"header.x-profile-id","code":"required","detail":"The X-Profile-Id header is required."}]}
            """.utf8)),
            "The X-Profile-Id header is required."
        )
        XCTAssertEqual(
            SiloAccountClient.problemMessage(in: Data(#"{"title":"Unauthorized","status":401,"detail":"Incorrect username or password."}"#.utf8)),
            "Incorrect username or password."
        )
        XCTAssertNil(SiloAccountClient.problemMessage(in: Data("<html></html>".utf8)))
    }

    func testSiloLinkRoundTripsWithTheSession() throws {
        let link = SiloLink(
            nativeURL: URL(string: "https://silo.example")!,
            accessToken: "a",
            refreshToken: "r",
            profileID: "p1",
            profileName: "Ada",
            profileHasPin: true,
            profileToken: "pt"
        )
        let saved = SavedSession(
            serverURL: URL(string: "https://silo.example:8097")!,
            accessToken: "jf",
            userID: "u1",
            userName: "Ada",
            deviceID: "device",
            isSiloServer: true,
            siloLink: link
        )
        let decoded = try JSONDecoder().decode(SavedSession.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(decoded.siloLink, link)

        let plain = try JSONDecoder().decode(SavedSession.self, from: Data("""
        {"serverURL":"https://jellyfin.example","accessToken":"t","userID":"u","userName":"Bob","deviceID":"d","isSiloServer":false}
        """.utf8))
        XCTAssertNil(plain.siloLink)
    }
}
