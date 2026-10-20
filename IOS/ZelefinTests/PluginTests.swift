import XCTest
import JellyfinAPI
@testable import Zelefin

final class SkipSegmentTests: XCTestCase {
    func testPromptShowsIntroThenOutro() {
        let intro = SkipSegment(kind: .intro, start: 10, end: 40)
        let outro = SkipSegment(kind: .outro, start: 1200, end: 1260)
        XCTAssertNil(SkipSegment.prompt(in: [intro, outro], at: 4))
        XCTAssertEqual(SkipSegment.prompt(in: [intro, outro], at: 12)?.kind, .intro)
        XCTAssertEqual(SkipSegment.prompt(in: [intro, outro], at: 12)?.title, "Skip Intro")
        XCTAssertEqual(SkipSegment.prompt(in: [intro, outro], at: 38)?.kind, .intro)
        XCTAssertNil(SkipSegment.prompt(in: [intro, outro], at: 40))
        XCTAssertEqual(SkipSegment.prompt(in: [intro, outro], at: 1210)?.kind, .outro)
        XCTAssertEqual(SkipSegment.prompt(in: [intro, outro], at: 1210)?.title, "Skip Outro")
    }

    func testShortSegmentsAreIgnored() {
        let blip = SkipSegment(kind: .intro, start: 10, end: 11.5)
        XCTAssertNil(SkipSegment.prompt(in: [blip], at: 10.2))
    }

    func testPluginTimestampsMapCreditsToOutro() {
        let payload = IntroSkipperTimestampsResponse(
            introduction: IntroTimestampPayload(introStart: 8, introEnd: 42, valid: true),
            credits: IntroTimestampPayload(introStart: 1300, introEnd: 1360, valid: true)
        )
        let segments = payload.segments
        XCTAssertEqual(segments.map(\.kind), [.intro, .outro])
        XCTAssertEqual(segments[0].start, 8)
        XCTAssertEqual(segments[1].end, 1360)
    }

    func testInvalidPluginTimestampsAreDropped() {
        let payload = IntroTimestampPayload(introStart: 0, introEnd: 0, valid: true)
        XCTAssertNil(payload.segment(kind: .intro))
    }

    func testDetectsIntroSkipperPluginNames() {
        XCTAssertTrue(IntroSkipperPlugin.isInstalled(names: ["Intro Skipper"]))
        XCTAssertTrue(IntroSkipperPlugin.isInstalled(names: ["introskipper"]))
        XCTAssertFalse(IntroSkipperPlugin.isInstalled(names: ["Playback Reporting", "Open Subtitles"]))
    }
}

final class OpenSubtitlesPluginTests: XCTestCase {
    func testDetectsOpenSubtitlesPluginNames() {
        XCTAssertTrue(OpenSubtitlesPlugin.isInstalled(names: ["Open Subtitles"]))
        XCTAssertTrue(OpenSubtitlesPlugin.isInstalled(names: ["OpenSubtitles"]))
        XCTAssertTrue(OpenSubtitlesPlugin.isInstalled(names: ["jellyfin-plugin-opensubtitles"]))
        XCTAssertFalse(OpenSubtitlesPlugin.isInstalled(names: ["Intro Skipper", "Playback Reporting"]))
    }

    func testMatchDropsMissingIDs() {
        XCTAssertNil(RemoteSubtitleMatch(RemoteSubtitleInfo(id: nil, name: "Release")))
        XCTAssertNil(RemoteSubtitleMatch(RemoteSubtitleInfo(id: "  ", name: "Release")))
    }

    func testMatchFormatsTitleAndFlags() {
        let match = RemoteSubtitleMatch(
            RemoteSubtitleInfo(
                downloadCount: 1240,
                format: "srt",
                id: "abc_srt-en-9",
                isForced: true,
                isHashMatch: true,
                isHearingImpaired: true,
                name: "Movie.2024.1080p",
                providerName: "Open Subtitles"
            )
        )
        XCTAssertEqual(match?.id, "abc_srt-en-9")
        XCTAssertEqual(match?.title, "Movie.2024.1080p")
        XCTAssertTrue(match?.isHashMatch == true)
        XCTAssertTrue(match?.detail.contains("Open Subtitles") == true)
        XCTAssertTrue(match?.detail.contains("SRT") == true)
        XCTAssertTrue(match?.detail.contains("Hash match") == true)
        XCTAssertTrue(match?.detail.contains("SDH") == true)
        XCTAssertTrue(match?.detail.contains("Forced") == true)
        XCTAssertTrue(match?.detail.contains("downloads") == true)
    }

    func testLanguageListIncludesEnglish() {
        XCTAssertTrue(SubtitleSearchLanguage.choices.contains(where: { $0.code == "en" }))
        XCTAssertEqual(SubtitleSearchLanguage.preferred.code.isEmpty, false)
    }

    func testRemoteSubtitlesOnlyOnMoviesAndEpisodes() {
        XCTAssertTrue(item(kind: .movie).supportsRemoteSubtitles)
        XCTAssertTrue(item(kind: .episode).supportsRemoteSubtitles)
        XCTAssertFalse(item(kind: .series).supportsRemoteSubtitles)
        XCTAssertFalse(item(kind: .season).supportsRemoteSubtitles)
    }

    func testAddSubtitlesWhenPluginExists() {
        XCTAssertTrue(
            RemoteSubtitleOffer.shouldShowAddSubtitles(
                canManageSubtitles: true,
                pluginAvailable: true,
                supportsRemote: true
            )
        )
        XCTAssertFalse(
            RemoteSubtitleOffer.shouldShowAddSubtitles(
                canManageSubtitles: false,
                pluginAvailable: true,
                supportsRemote: true
            )
        )
        XCTAssertFalse(
            RemoteSubtitleOffer.shouldShowAddSubtitles(
                canManageSubtitles: true,
                pluginAvailable: false,
                supportsRemote: true
            )
        )
        XCTAssertFalse(
            RemoteSubtitleOffer.shouldShowAddSubtitles(
                canManageSubtitles: true,
                pluginAvailable: true,
                supportsRemote: false
            )
        )
    }

    func testEditSubtitlesPermissionMatchesJellyfinPolicy() {
        XCTAssertTrue(RemoteSubtitleOffer.canManageSubtitles(isAdministrator: true, enableSubtitleManagement: false))
        XCTAssertTrue(RemoteSubtitleOffer.canManageSubtitles(isAdministrator: false, enableSubtitleManagement: true))
        XCTAssertFalse(RemoteSubtitleOffer.canManageSubtitles(isAdministrator: false, enableSubtitleManagement: false))
    }

    func testOpenSubtitlesVisibleWhenPluginCatalogIsHidden() {
        XCTAssertTrue(
            RemoteSubtitleOffer.pluginAvailable(
                listed: true,
                catalogNames: ["Open Subtitles"],
                canManageSubtitles: true,
                canListPlugins: true
            )
        )
        XCTAssertFalse(
            RemoteSubtitleOffer.pluginAvailable(
                listed: false,
                catalogNames: ["Intro Skipper"],
                canManageSubtitles: true,
                canListPlugins: true
            )
        )
        XCTAssertFalse(
            RemoteSubtitleOffer.pluginAvailable(
                listed: false,
                catalogNames: [],
                canManageSubtitles: true,
                canListPlugins: true
            )
        )
        XCTAssertTrue(
            RemoteSubtitleOffer.pluginAvailable(
                listed: false,
                catalogNames: [],
                canManageSubtitles: true,
                canListPlugins: false
            )
        )
        XCTAssertFalse(
            RemoteSubtitleOffer.pluginAvailable(
                listed: false,
                catalogNames: [],
                canManageSubtitles: false,
                canListPlugins: false
            )
        )
    }

    func testDetailRefreshesMovieOrMatchingEpisode() {
        XCTAssertTrue(
            SubtitleCatalogRefresh.shouldRefreshDetail(
                detailItemID: "movie-1",
                episodeIDs: [],
                savedItemID: "movie-1"
            )
        )
        XCTAssertTrue(
            SubtitleCatalogRefresh.shouldRefreshDetail(
                detailItemID: "show-1",
                episodeIDs: ["ep-1", "ep-2"],
                savedItemID: "ep-2"
            )
        )
        XCTAssertFalse(
            SubtitleCatalogRefresh.shouldRefreshDetail(
                detailItemID: "movie-1",
                episodeIDs: [],
                savedItemID: "movie-2"
            )
        )
    }

    private func item(kind: MediaKind) -> MediaItem {
        MediaItem(
            id: "1",
            name: "Title",
            kind: kind,
            overview: nil,
            year: 2024,
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
            queueKind: .nextUp,
            videoRange: .sdr,
            audioFormat: .unknown
        )
    }
}

final class SeerrTitleTests: XCTestCase {
    func testAvailabilityMapsSeerrStatus() {
        XCTAssertEqual(SeerrTitle.Availability(status: 5), .available)
        XCTAssertEqual(SeerrTitle.Availability(status: 2), .pending)
        XCTAssertEqual(SeerrTitle.Availability(status: 3), .processing)
        XCTAssertEqual(SeerrTitle.Availability(status: nil), .missing)
        XCTAssertTrue(SeerrTitle.Availability(status: 5).isOnServer)
        XCTAssertTrue(SeerrTitle.Availability(status: 4).isOnServer)
        XCTAssertTrue(SeerrTitle.Availability(status: 2).isRequested)
        XCTAssertTrue(SeerrTitle.Availability(status: nil).buttonTitle == "Request")
    }

    func testSearchResultIgnoresPeople() {
        let person = SeerrSearchResult(
            id: 1,
            mediaType: "person",
            title: nil,
            name: "Actor",
            releaseDate: nil,
            firstAirDate: nil,
            overview: nil,
            posterPath: nil,
            mediaInfo: nil
        )
        XCTAssertNil(SeerrClient.title(from: person))
    }

    func testSearchResultMapsMovie() {
        let movie = SeerrSearchResult(
            id: 27205,
            mediaType: "movie",
            title: "Inception",
            name: nil,
            releaseDate: "2010-07-16",
            firstAirDate: nil,
            overview: "A thief.",
            posterPath: "/poster.jpg",
            mediaInfo: SeerrMediaInfo(status: nil)
        )
        let title = SeerrClient.title(from: movie)
        XCTAssertEqual(title?.name, "Inception")
        XCTAssertEqual(title?.year, 2010)
        XCTAssertEqual(title?.kind, .movie)
        XCTAssertTrue(title?.canRequest == true)
        XCTAssertEqual(title?.posterURL?.absoluteString, "https://image.tmdb.org/t/p/w342/poster.jpg")
    }

    func testJellyfinCatalogMatchesTmdbIDs() {
        let catalog = JellyfinTmdbCatalog(movieIDs: [27205], seriesIDs: [1396])
        let movie = SeerrTitle(
            tmdbID: 27205,
            kind: .movie,
            name: "Inception",
            year: 2010,
            overview: nil,
            posterURL: nil,
            availability: .missing
        )
        let other = SeerrTitle(
            tmdbID: 1,
            kind: .movie,
            name: "Unknown",
            year: nil,
            overview: nil,
            posterURL: nil,
            availability: .missing
        )
        XCTAssertTrue(movie.isInJellyfin(catalog: catalog))
        XCTAssertFalse(other.isInJellyfin(catalog: catalog))
        XCTAssertTrue(
            SeerrTitle(
                tmdbID: 10,
                kind: .movie,
                name: "On Server",
                year: nil,
                overview: nil,
                posterURL: nil,
                availability: .available
            ).isInJellyfin(catalog: JellyfinTmdbCatalog())
        )
    }

    func testReadsTmdbProviderIDCaseInsensitively() {
        XCTAssertEqual(JellyfinTmdbCatalog.tmdbID(from: ["Tmdb": "27205"]), 27205)
        XCTAssertEqual(JellyfinTmdbCatalog.tmdbID(from: ["tmdb": "1396"]), 1396)
        XCTAssertEqual(JellyfinTmdbCatalog.tmdbID(from: ["TheMovieDb": "550"]), 550)
        XCTAssertNil(JellyfinTmdbCatalog.tmdbID(from: ["Imdb": "tt1375666"]))
    }

    func testReadsImdbProviderID() {
        XCTAssertEqual(JellyfinTmdbCatalog.imdbID(from: ["Imdb": "tt1375666"]), "tt1375666")
        XCTAssertEqual(JellyfinTmdbCatalog.imdbID(from: ["imdb": "1375666"]), "tt1375666")
        XCTAssertNil(JellyfinTmdbCatalog.imdbID(from: ["Tmdb": "27205"]))
    }

    func testDecodesSeerrRelatedVideos() throws {
        let json = Data("""
        {
          "id": 1396,
          "relatedVideos": [
            {
              "url": "https://youtube.com/watch?v=YoHD9XEInc0",
              "site": "YouTube",
              "key": "YoHD9XEInc0",
              "name": "Official Trailer",
              "size": 1080,
              "type": "Trailer"
            }
          ]
        }
        """.utf8)
        let details = try JSONDecoder().decode(SeerrTvDetails.self, from: json)
        XCTAssertEqual(details.relatedVideos?.count, 1)
        XCTAssertEqual(details.relatedVideos?.first?.key, "YoHD9XEInc0")
    }

    func testCookieParsesConnectSid() {
        let cookie = SeerrCookie.parse(
            setCookie: "connect.sid=s%3Aabc.signature; Path=/; HttpOnly; SameSite=Lax"
        )
        XCTAssertEqual(cookie?.name, "connect.sid")
        XCTAssertEqual(cookie?.value, "s:abc.signature")
    }

    func testCookieHeaderUsesSession() {
        let session = SeerrSession(cookieName: "connect.sid", cookieValue: "s:abc.signature", displayName: "Randall")
        let header = SeerrCookie.header(session: session, url: URL(string: "https://seerr.example.com")!)
        XCTAssertTrue(header.contains("connect.sid="))
        XCTAssertTrue(header.contains("abc.signature"))
    }

    func testJellyfinBodyIsUsernameAndPasswordOnly() {
        let body = SeerrClient.jellyfinBody(username: "Randall", password: "secret")
        XCTAssertEqual(body["username"] as? String, "Randall")
        XCTAssertEqual(body["password"] as? String, "secret")
        XCTAssertNil(body["hostname"])
        XCTAssertNil(body["accessToken"])
    }

    func testUserDisplayPrefersUsername() {
        let user = SeerrUser(
            id: 1,
            email: "hey@itsme.com",
            username: "Randall",
            displayName: nil,
            jellyfinUsername: "jelly",
            plexUsername: nil
        )
        XCTAssertEqual(user.displayLabel, "Randall")
    }

    func testPreferredCookiePicksConnectSid() {
        let other = HTTPCookie(properties: [
            .domain: "seerr.example.com",
            .path: "/",
            .name: "other",
            .value: "nope"
        ])!
        let sid = HTTPCookie(properties: [
            .domain: "seerr.example.com",
            .path: "/",
            .name: "connect.sid",
            .value: "s:abc.signature"
        ])!
        let cookie = SeerrCookie.preferred(from: [other, sid])
        XCTAssertEqual(cookie?.name, "connect.sid")
        XCTAssertEqual(cookie?.value, "s:abc.signature")
    }
}

final class SeerrRequestTests: XCTestCase {
    func testPreferredServerUsesMatchingDefault() {
        let hd = SeerrServiceServer(id: 1, name: "HD", is4k: false, isDefault: true, activeDirectory: "/tv")
        let uhd = SeerrServiceServer(id: 2, name: "UHD", is4k: true, isDefault: true, activeDirectory: "/tv-4k")
        let extraHD = SeerrServiceServer(id: 3, name: "Backup", is4k: false, isDefault: false)
        XCTAssertEqual(SeerrRequestDefaults.preferredServer(from: [hd, uhd, extraHD], is4k: false)?.id, 1)
        XCTAssertEqual(SeerrRequestDefaults.preferredServer(from: [hd, uhd, extraHD], is4k: true)?.id, 2)
    }

    func testPreferredServerFallsBackToFirstMatchingQuality() {
        let hd = SeerrServiceServer(id: 1, name: "HD", is4k: false, isDefault: false)
        let uhd = SeerrServiceServer(id: 2, name: "UHD", is4k: true, isDefault: false)
        XCTAssertEqual(SeerrRequestDefaults.preferredServer(from: [uhd, hd], is4k: false)?.id, 1)
        XCTAssertEqual(SeerrRequestDefaults.preferredServer(from: [hd], is4k: true)?.id, 1)
    }

    func testMovieDraftOmitsSeasonsAndUsesDefaults() {
        let draft = SeerrRequestDraft(
            kind: .movie,
            tmdbID: 27205,
            is4k: false,
            serverID: 1,
            profileID: 6,
            rootFolder: "/movies"
        )
        let body = draft.jsonObject
        XCTAssertEqual(body["mediaType"] as? String, "movie")
        XCTAssertEqual(body["mediaId"] as? Int, 27205)
        XCTAssertEqual(body["is4k"] as? Bool, false)
        XCTAssertEqual(body["serverId"] as? Int, 1)
        XCTAssertEqual(body["profileId"] as? Int, 6)
        XCTAssertEqual(body["rootFolder"] as? String, "/movies")
        XCTAssertNil(body["seasons"])
        XCTAssertNil(body["languageProfileId"])
    }

    func testTVDraftSendsSelectedSeasons() {
        let draft = SeerrRequestDraft(
            kind: .tv,
            tmdbID: 1396,
            seasons: .numbers([1, 2, 5]),
            is4k: true,
            serverID: 2,
            profileID: 8,
            rootFolder: "/tv-4k",
            languageProfileID: 1
        )
        let body = draft.jsonObject
        XCTAssertEqual(body["mediaType"] as? String, "tv")
        XCTAssertEqual(body["seasons"] as? [Int], [1, 2, 5])
        XCTAssertEqual(body["is4k"] as? Bool, true)
        XCTAssertEqual(body["languageProfileId"] as? Int, 1)
    }

    func testTVDraftCanRequestAllSeasons() {
        let draft = SeerrRequestDraft(kind: .tv, tmdbID: 1396, seasons: .all)
        XCTAssertEqual(draft.jsonObject["seasons"] as? String, "all")
    }

    func testOccupiedSeasonUses4KStatus() {
        let season = SeerrMediaSeason(seasonNumber: 2, status: 5, status4k: 1)
        XCTAssertTrue(season.isOccupied(is4k: false))
        XCTAssertFalse(season.isOccupied(is4k: true))
    }

    func testPartialTitlesCanBeRequested() {
        XCTAssertTrue(SeerrTitle.Availability(status: 4).canRequest)
        XCTAssertEqual(SeerrTitle.Availability(status: 4).buttonTitle, "Request More")
        XCTAssertFalse(SeerrTitle.Availability(status: 5).canRequest)
    }

    func testServiceDetailsDecodeProfilesAndDrive() throws {
        let json = """
        {
          "server": {
            "id": 0,
            "name": "Radarr",
            "is4k": false,
            "isDefault": true,
            "activeProfileId": 6,
            "activeDirectory": "/mnt/movies"
          },
          "profiles": [{ "id": 6, "name": "HD-1080p" }, { "id": 8, "name": "Ultra-HD" }],
          "rootFolders": [{ "id": 1, "path": "/mnt/movies", "freeSpace": 500000000000 }]
        }
        """.data(using: .utf8)!
        let details = try JSONDecoder().decode(SeerrServiceDetails.self, from: json)
        XCTAssertEqual(details.server.activeProfileId, 6)
        XCTAssertEqual(details.server.activeDirectory, "/mnt/movies")
        XCTAssertEqual(details.profiles.map(\.name), ["HD-1080p", "Ultra-HD"])
        XCTAssertEqual(details.rootFolders.first?.path, "/mnt/movies")
        XCTAssertTrue(details.rootFolders.first?.pickerTitle.contains("free") == true)
        XCTAssertEqual(
            SeerrRequestDefaults.preferredServer(from: [details.server], is4k: false)?.activeDirectory,
            "/mnt/movies"
        )
    }
}

final class SeerrDiscoverTests: XCTestCase {
    func testDiscoverPathsMatchSeerr() {
        XCTAssertEqual(SeerrDiscoverQuery.trending.path, "api/v1/discover/trending")
        XCTAssertEqual(SeerrDiscoverQuery.popularMovies.path, "api/v1/discover/movies")
        XCTAssertEqual(SeerrDiscoverQuery.upcomingMovies.path, "api/v1/discover/movies/upcoming")
        XCTAssertEqual(SeerrDiscoverQuery.popularTV.path, "api/v1/discover/tv")
        XCTAssertEqual(SeerrDiscoverQuery.upcomingTV.path, "api/v1/discover/tv/upcoming")
        XCTAssertEqual(SeerrDiscoverQuery.movieGenre(id: 28, name: "Action").path, "api/v1/discover/movies/genre/28")
        XCTAssertEqual(SeerrDiscoverQuery.tvGenre(id: 18, name: "Drama").path, "api/v1/discover/tv/genre/18")
        XCTAssertEqual(SeerrDiscoverQuery.studio(id: 2, name: "Disney").path, "api/v1/discover/movies/studio/2")
        XCTAssertEqual(SeerrDiscoverQuery.network(id: 213, name: "Netflix").path, "api/v1/discover/tv/network/213")
        XCTAssertEqual(SeerrDiscoverQuery.requests.path, "api/v1/request")
    }

    func testMovieDetailsWithoutMediaTypeStillMap() {
        let payload = SeerrSearchResult(
            id: 550,
            mediaType: nil,
            title: "Fight Club",
            name: nil,
            releaseDate: "1999-10-15",
            firstAirDate: nil,
            overview: nil,
            posterPath: "/poster.jpg",
            mediaInfo: nil
        )
        let title = SeerrClient.title(from: payload, defaultKind: .movie)
        XCTAssertEqual(title?.kind, .movie)
        XCTAssertEqual(title?.name, "Fight Club")
        XCTAssertEqual(title?.year, 1999)
    }

    func testGenreSliderUsesFirstBackdrop() throws {
        let json = """
        [{ "id": 28, "name": "Action", "backdrops": ["/a.jpg", "/b.jpg"] }]
        """.data(using: .utf8)!
        let genres = try JSONDecoder().decode([SeerrGenreSliderItem].self, from: json)
        XCTAssertEqual(genres.first?.name, "Action")
        XCTAssertEqual(genres.first?.imageURL?.absoluteString, "https://image.tmdb.org/t/p/w780/a.jpg")
    }

    func testRequestListReadsTMDBAndType() throws {
        let json = """
        {
          "pageInfo": { "page": 1, "pages": 3, "results": 40 },
          "results": [{
            "id": 9,
            "media": { "tmdbId": 1396, "mediaType": "tv", "status": 2 }
          }]
        }
        """.data(using: .utf8)!
        let page = try JSONDecoder().decode(SeerrRequestListResponse.self, from: json)
        XCTAssertEqual(page.pageInfo?.pages, 3)
        XCTAssertEqual(page.results.first?.media.tmdbId, 1396)
        XCTAssertEqual(page.results.first?.media.mediaType, "tv")
    }

    func testRequestListReadsRequester() throws {
        let json = """
        {
          "pageInfo": { "page": 1, "pages": 1, "results": 1 },
          "results": [{
            "id": 9,
            "media": { "tmdbId": 27205, "mediaType": "movie", "status": 2 },
            "requestedBy": {
              "id": 1,
              "email": "randall@example.com",
              "username": "Randall",
              "jellyfinUsername": "Randall"
            }
          }]
        }
        """.data(using: .utf8)!
        let page = try JSONDecoder().decode(SeerrRequestListResponse.self, from: json)
        XCTAssertEqual(page.results.first?.requestedBy?.requestLabel, "Randall")
        XCTAssertEqual(page.results.first?.id, 9)
    }

    func testRequestLabelPrefersUsernameOverEmail() {
        let user = SeerrUser(
            id: 1,
            email: "hide@example.com",
            username: "Alex",
            displayName: nil,
            jellyfinUsername: nil,
            plexUsername: nil
        )
        XCTAssertEqual(user.requestLabel, "Alex")
        XCTAssertNil(SeerrUser().requestLabel)
    }

    func testStudiosAndNetworksMatchSeerr() {
        XCTAssertEqual(SeerrCompany.studios.first?.name, "Disney")
        XCTAssertEqual(SeerrCompany.studios.first?.id, 2)
        XCTAssertEqual(SeerrCompany.networks.first?.name, "Netflix")
        XCTAssertEqual(SeerrCompany.networks.first?.id, 213)
        XCTAssertEqual(SeerrCompany.studios.first?.query.path, "api/v1/discover/movies/studio/2")
        XCTAssertEqual(SeerrCompany.networks.first?.query.path, "api/v1/discover/tv/network/213")
    }

    func testHomeHidesUntilRowsLoad() {
        XCTAssertTrue(SeerrDiscoverHome().isEmpty)
        var home = SeerrDiscoverHome()
        home.trending = [
            SeerrTitle(tmdbID: 1, kind: .movie, name: "Dune", year: 2021, overview: nil, posterURL: nil, availability: .missing)
        ]
        XCTAssertFalse(home.isEmpty)
        home.markRequested(home.trending[0])
        XCTAssertEqual(home.trending[0].availability, .pending)
    }
}

final class SeerrSessionPersistenceTests: XCTestCase {
    func testRelaunchDoesNotClearSeerr() {
        XCTAssertFalse(PluginSettings.shouldClearSession(switchingFrom: nil, to: "ada", ownerAccountID: nil))
        XCTAssertFalse(PluginSettings.shouldClearSession(switchingFrom: "ada", to: "ada", ownerAccountID: "ada"))
    }

    func testUpdateKeepsSeerrForTheSameUser() {
        XCTAssertFalse(PluginSettings.shouldClearSession(switchingFrom: nil, to: "ada", ownerAccountID: "ada"))
    }

    func testSwitchingJellyfinUserClearsSeerr() {
        XCTAssertTrue(PluginSettings.shouldClearSession(switchingFrom: "ada", to: "bob", ownerAccountID: "ada"))
    }

    func testSigningInAsADifferentUserAfterSignOutClearsSeerr() {
        XCTAssertTrue(PluginSettings.shouldClearSession(switchingFrom: nil, to: "bob", ownerAccountID: "ada"))
    }

    func testUnauthorizedIsDistinctFromAServerError() {
        XCTAssertTrue(ZelefinError.seerrUnauthorized.isSeerrUnauthorized)
        XCTAssertFalse(ZelefinError.server("Seerr is unreachable.").isSeerrUnauthorized)
    }
}

final class PlaybackLanguageTests: XCTestCase {
    func testMatchesEnglishVariants() {
        XCTAssertTrue(PlaybackLanguage.matches("eng", preference: "en"))
        XCTAssertTrue(PlaybackLanguage.matches("en-US", preference: "en"))
        XCTAssertTrue(PlaybackLanguage.matches("en", preference: "eng"))
        XCTAssertFalse(PlaybackLanguage.matches("ja", preference: "en"))
    }

    func testSubtitleOffUsesDisabledIndex() {
        let tracks = [
            MediaTrack(id: 2, kind: .subtitle, language: "en", title: "English", codec: "srt", isSelected: true, isDefault: true)
        ]
        XCTAssertEqual(PlaybackLanguage.subtitleIndex(in: tracks, preference: PlaybackLanguage.offCode), -1)
        XCTAssertEqual(PlaybackLanguage.subtitleIndex(in: tracks, preference: "en"), 2)
    }

    func testAlwaysTurnsSubtitlesOnWithoutPreferredLanguage() {
        let tracks = [
            MediaTrack(id: 2, kind: .subtitle, language: "eng", title: "English", codec: "srt", isSelected: false, isDefault: false),
            MediaTrack(id: 3, kind: .subtitle, language: "spa", title: "Spanish", codec: "srt", isSelected: false, isDefault: false)
        ]
        XCTAssertEqual(
            PlaybackLanguage.startingSubtitleIndex(
                in: tracks,
                serverIndex: nil,
                mode: .always,
                preferredLanguage: "",
                audioLanguage: "eng",
                preferSDH: false,
                deviceLanguage: "en"
            ),
            2
        )
        XCTAssertNil(
            PlaybackLanguage.startingSubtitleIndex(
                in: tracks,
                serverIndex: nil,
                mode: .default,
                preferredLanguage: "",
                audioLanguage: "eng",
                preferSDH: false,
                deviceLanguage: "en"
            )
        )
        XCTAssertNil(
            PlaybackLanguage.startingSubtitleIndex(
                in: tracks,
                serverIndex: nil,
                mode: .always,
                preferredLanguage: "",
                audioLanguage: "eng",
                preferSDH: false,
                deviceLanguage: "en",
                forcedByUser: true
            )
        )
    }

    func testAudioPrefersMatchingLanguage() {
        let tracks = [
            MediaTrack(id: 1, kind: .audio, language: "ja", title: "Japanese", codec: "aac", isSelected: true, isDefault: true),
            MediaTrack(id: 2, kind: .audio, language: "en", title: "English", codec: "aac", isSelected: false, isDefault: false)
        ]
        XCTAssertEqual(PlaybackLanguage.audioIndex(in: tracks, preference: "en"), 2)
        XCTAssertEqual(PlaybackLanguage.audioIndex(in: tracks, preference: PlaybackLanguage.automaticCode), 1)
    }
}

final class ZelefinPluginCatalogTests: XCTestCase {
    func testInsertsRepositoryOnce() {
        let first = ZelefinPluginCatalog.insertingCatalog(into: [])
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.url, ZelefinPluginCatalog.repositoryURL)
        XCTAssertEqual(ZelefinPluginCatalog.insertingCatalog(into: first).count, 1)
    }

    func testRepositoryURLMatchIgnoresTrailingSlash() {
        XCTAssertTrue(ZelefinPluginCatalog.urlsMatch(
            ZelefinPluginCatalog.repositoryURL + "/",
            ZelefinPluginCatalog.repositoryURL
        ))
    }
}

final class FirstRunSetupStoreTests: XCTestCase {
    func testMarksAccountComplete() {
        let id = "test.example|\(UUID().uuidString)"
        XCTAssertFalse(FirstRunSetupStore.hasCompleted(accountID: id))
        FirstRunSetupStore.markCompleted(accountID: id)
        XCTAssertTrue(FirstRunSetupStore.hasCompleted(accountID: id))
        UserDefaults.standard.removeObject(forKey: "zelefin.setup.completed." + id)
    }
}
