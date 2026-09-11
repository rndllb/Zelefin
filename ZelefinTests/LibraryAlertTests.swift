import XCTest
@testable import Zelefin

final class LibraryAlertTests: XCTestCase {
    func testFirstLibraryPollPrimesWithoutNotifying() {
        let movie = MediaItem.previewMovie(id: "dune", name: "Dune", year: 2021, added: Self.older)
        let result = LibraryAlertEngine.evaluate(
            previous: .empty,
            input: Self.input(items: [movie]),
            preferences: Self.userPrefs
        )
        XCTAssertTrue(result.alerts.isEmpty)
        XCTAssertTrue(result.next.primedLibrary)
        XCTAssertEqual(result.next.seenItemIDs, ["dune"])
        XCTAssertEqual(result.next.libraryWatermark, Self.older)
    }

    func testNewMovieNotifiesAndOpensThatItem() {
        let previous = LibraryAlertEngine.evaluate(
            previous: .empty,
            input: Self.input(items: [MediaItem.previewMovie(id: "dune", name: "Dune", year: 2021, added: Self.older)]),
            preferences: Self.userPrefs
        ).next
        let result = LibraryAlertEngine.evaluate(
            previous: previous,
            input: Self.input(items: [
                MediaItem.previewMovie(id: "dune", name: "Dune", year: 2021, added: Self.older),
                MediaItem.previewMovie(id: "andor", name: "Andor", year: 2022, added: Self.newer)
            ]),
            preferences: Self.userPrefs
        )
        XCTAssertEqual(result.alerts.count, 1)
        XCTAssertEqual(result.alerts[0].kind, .newTitle)
        XCTAssertEqual(result.alerts[0].itemID, "andor")
        XCTAssertEqual(result.alerts[0].body, "Andor (2022)")
    }

    func testSigningInDoesNotReplayTitlesAlreadyOnTheServer() {
        let latest = [
            MediaItem.previewMovie(id: "dune", name: "Dune", year: 2021, added: Self.older),
            MediaItem.previewMovie(id: "andor", name: "Andor", year: 2022, added: Self.older)
        ]
        let previous = LibraryAlertEngine.evaluate(
            previous: .empty,
            input: Self.input(items: latest),
            preferences: Self.userPrefs
        ).next
        let again = LibraryAlertEngine.evaluate(
            previous: previous,
            input: Self.input(items: latest),
            preferences: Self.userPrefs
        )
        XCTAssertTrue(again.alerts.isEmpty)
    }

    func testExistingLatestTitlesAreNotNewAfterAFreshBaseline() {
        let latest = [
            MediaItem.previewMovie(id: "dune", name: "Dune", year: 2021, added: Self.older),
            MediaItem.previewSeries(id: "andor", name: "Andor", year: 2022, added: Self.older)
        ]
        let result = LibraryAlertEngine.evaluate(
            previous: .empty,
            input: Self.input(items: latest),
            preferences: Self.userPrefs
        )
        XCTAssertTrue(result.alerts.isEmpty)

        let replay = LibraryAlertEngine.evaluate(
            previous: .empty,
            input: Self.input(items: latest),
            preferences: Self.userPrefs
        )
        XCTAssertTrue(replay.alerts.isEmpty)
    }

    func testLegacySnapshotWithoutWatermarkRebaselinesWithoutNotifying() {
        let previous = LibraryAlertSnapshot(
            seenItemIDs: [],
            playingKeys: [],
            onlineSessionIDs: [],
            seenRequestIDs: [],
            runningTaskIDs: [],
            primedLibrary: true,
            primedAdmin: false,
            primedSessions: false,
            libraryWatermark: nil
        )
        let latest = [
            MediaItem.previewMovie(id: "dune", name: "Dune", year: 2021, added: Self.older),
            MediaItem.previewMovie(id: "andor", name: "Andor", year: 2022, added: Self.older)
        ]
        let result = LibraryAlertEngine.evaluate(
            previous: previous,
            input: Self.input(items: latest),
            preferences: Self.userPrefs
        )
        XCTAssertTrue(result.alerts.isEmpty)
        XCTAssertEqual(result.next.libraryWatermark, Self.older)
        XCTAssertEqual(Set(result.next.seenItemIDs), ["dune", "andor"])
    }

    func testTitlesOlderThanTheBaselineAreNotNew() {
        let previous = LibraryAlertEngine.evaluate(
            previous: .empty,
            input: Self.input(items: []),
            preferences: Self.userPrefs
        ).next
        XCTAssertNotNil(previous.libraryWatermark)
        let result = LibraryAlertEngine.evaluate(
            previous: previous,
            input: Self.input(items: [
                MediaItem.previewMovie(id: "dune", name: "Dune", year: 2021, added: Self.older)
            ]),
            preferences: Self.userPrefs
        )
        XCTAssertTrue(result.alerts.isEmpty)
    }

    func testEpisodesCollapseToTheShow() {
        let previous = LibraryAlertEngine.evaluate(
            previous: .empty,
            input: Self.input(items: [MediaItem.previewMovie(id: "dune", name: "Dune", year: 2021, added: Self.older)]),
            preferences: Self.userPrefs
        ).next
        let result = LibraryAlertEngine.evaluate(
            previous: previous,
            input: Self.input(items: [
                MediaItem.previewMovie(id: "dune", name: "Dune", year: 2021, added: Self.older),
                MediaItem.previewEpisode(id: "ep-1", seriesID: "show-1", seriesName: "Andor", added: Self.newer),
                MediaItem.previewEpisode(id: "ep-2", seriesID: "show-1", seriesName: "Andor", added: Self.newer),
                MediaItem.previewSeries(id: "show-1", name: "Andor", year: 2022, added: Self.newer)
            ]),
            preferences: Self.userPrefs
        )
        XCTAssertEqual(result.alerts.count, 1)
        XCTAssertEqual(result.alerts[0].itemID, "show-1")
        XCTAssertEqual(result.alerts[0].body, "Andor")
    }

    func testOverflowSummarizesExtraTitles() {
        let previous = LibraryAlertEngine.evaluate(
            previous: .empty,
            input: Self.input(items: [MediaItem.previewMovie(id: "old", name: "Old", year: 2020, added: Self.older)]),
            preferences: Self.userPrefs
        ).next
        let items = (1...5).map { MediaItem.previewMovie(id: "m\($0)", name: "Movie \($0)", year: 2024, added: Self.newer) }
        let result = LibraryAlertEngine.evaluate(
            previous: previous,
            input: Self.input(items: [MediaItem.previewMovie(id: "old", name: "Old", year: 2020, added: Self.older)] + items),
            preferences: Self.userPrefs
        )
        XCTAssertEqual(result.alerts.count, 4)
        XCTAssertEqual(result.alerts.prefix(3).compactMap(\.itemID), ["m1", "m2", "m3"])
        XCTAssertEqual(result.alerts[3].body, "2 more new titles.")
        XCTAssertNil(result.alerts[3].itemID)
    }

    func testThisDeviceStreamIsIgnored() {
        let primed = LibraryAlertEngine.evaluate(
            previous: .empty,
            input: Self.input(sessions: [
                Self.playing(id: "local", deviceID: "iphone-1", user: "Ada")
            ]),
            preferences: Self.adminPrefs
        ).next
        let result = LibraryAlertEngine.evaluate(
            previous: primed,
            input: Self.input(sessions: [
                Self.playing(id: "local", deviceID: "iphone-1", user: "Ada")
            ]),
            preferences: Self.adminPrefs
        )
        XCTAssertTrue(result.alerts.isEmpty)
    }

    func testAdminIsNotifiedWhenSomeoneStartsAStream() {
        let primed = LibraryAlertEngine.evaluate(
            previous: .empty,
            input: Self.input(sessions: []),
            preferences: Self.adminPrefs
        ).next
        let result = LibraryAlertEngine.evaluate(
            previous: primed,
            input: Self.input(sessions: [
                Self.playing(id: "tv", deviceID: "tv-1", user: "Sam", userID: "u-sam")
            ]),
            preferences: Self.adminPrefs
        )
        let stream = result.alerts.first { $0.kind == .streamStarted }
        XCTAssertEqual(stream?.body, "Sam started Dune (2021).")
        XCTAssertEqual(stream?.itemID, "m1")
    }

    func testAdminIsNotifiedWhenAUserComesOnline() {
        let primed = LibraryAlertEngine.evaluate(
            previous: .empty,
            input: Self.input(sessions: []),
            preferences: Self.adminPrefs
        ).next
        let result = LibraryAlertEngine.evaluate(
            previous: primed,
            input: Self.input(sessions: [
                Self.idle(id: "tv", deviceID: "tv-1", user: "Sam", userID: "u-sam")
            ]),
            preferences: Self.adminPrefs
        )
        let online = result.alerts.first { $0.kind == .userOnline }
        XCTAssertEqual(online?.body, "Sam is on Infuse · Living Room.")
        XCTAssertNil(online?.itemID)
    }

    func testSameUserOnANewDeviceCountsAsOnline() {
        let primed = LibraryAlertEngine.evaluate(
            previous: .empty,
            input: Self.input(sessions: [
                Self.idle(id: "tv", deviceID: "tv-1", user: "Sam", userID: "u-sam")
            ]),
            preferences: Self.adminPrefs
        ).next
        let result = LibraryAlertEngine.evaluate(
            previous: primed,
            input: Self.input(sessions: [
                Self.idle(id: "tv", deviceID: "tv-1", user: "Sam", userID: "u-sam"),
                Self.idle(id: "phone", deviceID: "phone-2", user: "Sam", userID: "u-sam")
            ]),
            preferences: Self.adminPrefs
        )
        XCTAssertEqual(result.alerts.map(\.kind), [.userOnline])
        XCTAssertEqual(result.alerts[0].body, "Sam is on Infuse · Living Room.")
    }

    func testIdleSessionStartingPlaybackNotifiesStream() {
        let primed = LibraryAlertEngine.evaluate(
            previous: .empty,
            input: Self.input(sessions: [
                Self.idle(id: "tv", deviceID: "tv-1", user: "Sam", userID: "u-sam")
            ]),
            preferences: Self.adminPrefs
        ).next
        let result = LibraryAlertEngine.evaluate(
            previous: primed,
            input: Self.input(sessions: [
                Self.playing(id: "tv", deviceID: "tv-1", user: "Sam", userID: "u-sam")
            ]),
            preferences: Self.adminPrefs
        )
        XCTAssertEqual(result.alerts.map(\.kind), [.streamStarted])
        XCTAssertEqual(result.alerts[0].body, "Sam started Dune (2021).")
    }

    func testSessionAlertsFireAfterAdminWasPrimedWithoutSessions() {
        let primed = LibraryAlertEngine.evaluate(
            previous: .empty,
            input: Self.input(
                items: nil,
                sessions: nil,
                requests: nil,
                tasks: [LibraryAlertTask(id: "scan", name: "Scan media library")]
            ),
            preferences: Self.adminPrefs
        ).next
        XCTAssertTrue(primed.primedAdmin)
        XCTAssertFalse(primed.primedSessions)

        let primedSessions = LibraryAlertEngine.evaluate(
            previous: primed,
            input: Self.input(
                items: nil,
                sessions: [Self.idle(id: "tv", deviceID: "tv-1", user: "Sam", userID: "u-sam")],
                requests: nil,
                tasks: nil
            ),
            preferences: Self.adminPrefs
        )
        XCTAssertTrue(primedSessions.alerts.isEmpty)
        XCTAssertTrue(primedSessions.next.primedSessions)
        XCTAssertEqual(primedSessions.next.runningTaskIDs, ["scan"])

        let result = LibraryAlertEngine.evaluate(
            previous: primedSessions.next,
            input: Self.input(
                items: nil,
                sessions: [Self.playing(id: "tv", deviceID: "tv-1", user: "Sam", userID: "u-sam")],
                requests: nil,
                tasks: nil
            ),
            preferences: Self.adminPrefs
        )
        XCTAssertEqual(result.alerts.map(\.kind), [.streamStarted])
        XCTAssertEqual(result.alerts[0].body, "Sam started Dune (2021).")
    }

    func testMissingSessionListDoesNotDropOnlineState() {
        let primed = LibraryAlertEngine.evaluate(
            previous: .empty,
            input: Self.input(sessions: [
                Self.playing(id: "tv", deviceID: "tv-1", user: "Sam", userID: "u-sam")
            ]),
            preferences: Self.adminPrefs
        ).next
        let skipped = LibraryAlertEngine.evaluate(
            previous: primed,
            input: Self.input(sessions: nil),
            preferences: Self.adminPrefs
        )
        XCTAssertTrue(skipped.alerts.isEmpty)
        XCTAssertEqual(skipped.next.playingKeys, primed.playingKeys)
        XCTAssertTrue(skipped.next.primedSessions)

        let result = LibraryAlertEngine.evaluate(
            previous: skipped.next,
            input: Self.input(sessions: [
                Self.playing(id: "tv", deviceID: "tv-1", user: "Sam", userID: "u-sam")
            ]),
            preferences: Self.adminPrefs
        )
        XCTAssertTrue(result.alerts.filter { $0.kind == .streamStarted }.isEmpty)
    }

    func testAdminIsNotifiedAboutNewSeerrRequests() {
        let primed = LibraryAlertEngine.evaluate(
            previous: .empty,
            input: Self.input(requests: [
                LibraryAlertRequest(id: "1", title: "Dune", requester: "Ada")
            ]),
            preferences: Self.adminPrefs
        ).next
        let result = LibraryAlertEngine.evaluate(
            previous: primed,
            input: Self.input(requests: [
                LibraryAlertRequest(id: "1", title: "Dune", requester: "Ada"),
                LibraryAlertRequest(id: "2", title: "Andor", requester: "Sam")
            ]),
            preferences: Self.adminPrefs
        )
        XCTAssertEqual(result.alerts.map(\.kind), [.seerrRequest])
        XCTAssertEqual(result.alerts[0].body, "Sam requested Andor.")
    }

    func testNonAdminDoesNotGetSessionAlerts() {
        let primed = LibraryAlertEngine.evaluate(
            previous: .empty,
            input: Self.input(sessions: []),
            preferences: Self.userPrefs
        ).next
        let result = LibraryAlertEngine.evaluate(
            previous: primed,
            input: Self.input(sessions: [
                Self.playing(id: "tv", deviceID: "tv-1", user: "Sam", userID: "u-sam")
            ]),
            preferences: Self.userPrefs
        )
        XCTAssertTrue(result.alerts.isEmpty)
        XCTAssertFalse(result.next.primedAdmin)
    }

    func testAdminIsNotifiedWhenAScheduledTaskStarts() {
        let primed = LibraryAlertEngine.evaluate(
            previous: .empty,
            input: Self.input(tasks: [
                LibraryAlertTask(id: "scan", name: "Scan media library")
            ]),
            preferences: Self.adminPrefs
        ).next
        XCTAssertTrue(primed.primedAdmin)
        XCTAssertEqual(primed.runningTaskIDs, ["scan"])

        let result = LibraryAlertEngine.evaluate(
            previous: primed,
            input: Self.input(tasks: [
                LibraryAlertTask(id: "scan", name: "Scan media library"),
                LibraryAlertTask(id: "chapters", name: "Chapter image extraction")
            ]),
            preferences: Self.adminPrefs
        )
        XCTAssertEqual(result.alerts.map(\.kind), [.scheduledTask])
        XCTAssertEqual(result.alerts[0].body, "Chapter image extraction is running.")
        XCTAssertTrue(result.alerts[0].opensScheduledTasks)
        XCTAssertNil(result.alerts[0].itemID)
    }

    func testNonAdminDoesNotGetScheduledTaskAlerts() {
        let primed = LibraryAlertEngine.evaluate(
            previous: .empty,
            input: Self.input(tasks: []),
            preferences: Self.userPrefs
        ).next
        let result = LibraryAlertEngine.evaluate(
            previous: primed,
            input: Self.input(tasks: [
                LibraryAlertTask(id: "scan", name: "Scan media library")
            ]),
            preferences: Self.userPrefs
        )
        XCTAssertTrue(result.alerts.isEmpty)
    }

    func testDisabledLeavesSnapshotUnchanged() {
        let previous = LibraryAlertSnapshot(
            seenItemIDs: ["dune"],
            playingKeys: [],
            onlineSessionIDs: [],
            seenRequestIDs: [],
            runningTaskIDs: [],
            primedLibrary: true,
            primedAdmin: true,
            primedSessions: true
        )
        let result = LibraryAlertEngine.evaluate(
            previous: previous,
            input: Self.input(items: [MediaItem.previewMovie(id: "new", name: "New", year: 2026)]),
            preferences: .allOff
        )
        XCTAssertTrue(result.alerts.isEmpty)
        XCTAssertEqual(result.next, previous)
    }

    func testSnapshotReadsLegacyOnlineUserIDs() throws {
        let json = Data(#"{"onlineUserIDs":["tv-session"],"primedSessions":true}"#.utf8)
        let snapshot = try JSONDecoder().decode(LibraryAlertSnapshot.self, from: json)
        XCTAssertEqual(snapshot.onlineSessionIDs, ["tv-session"])
        XCTAssertTrue(snapshot.primedSessions)
    }
}

private extension LibraryAlertTests {
    static let older = Date(timeIntervalSince1970: 1_700_000_000)
    static let newer = Date(timeIntervalSince1970: 1_800_000_000)

    static let userPrefs = LibraryAlertPreferences(
        isEnabled: true,
        libraryAdds: true,
        streams: true,
        online: true,
        requests: true,
        scheduledTasks: false,
        isAdministrator: false
    )

    static let adminPrefs = LibraryAlertPreferences(
        isEnabled: true,
        libraryAdds: false,
        streams: true,
        online: true,
        requests: true,
        scheduledTasks: true,
        isAdministrator: true
    )

    static func input(
        items: [MediaItem]? = [],
        sessions: [PlaybackSession]? = [],
        requests: [LibraryAlertRequest]? = [],
        tasks: [LibraryAlertTask]? = []
    ) -> LibraryAlertInput {
        LibraryAlertInput(
            latestItems: items,
            sessions: sessions,
            requests: requests,
            tasks: tasks,
            localDeviceID: "iphone-1"
        )
    }

    static func playing(
        id: String,
        deviceID: String,
        user: String,
        userID: String = "u1"
    ) -> PlaybackSession {
        PlaybackSession(
            id: id,
            userID: userID,
            userName: user,
            userImageTag: nil,
            client: "Infuse",
            deviceName: "Living Room",
            deviceType: "Apple TV",
            deviceID: deviceID,
            applicationVersion: "8.0",
            remoteEndPoint: "10.0.0.12",
            isActive: true,
            supportsRemoteControl: true,
            supportsMediaControl: true,
            nowPlaying: MediaItem.previewMovie(id: "m1", name: "Dune", year: 2021),
            nowPlayingName: nil,
            nowViewingName: nil,
            position: 120,
            runtime: 7_200,
            isPaused: false,
            isMuted: false,
            canSeek: true,
            volumeLevel: 80,
            playMethod: .directPlay,
            transcoding: nil,
            lastActivity: Date(),
            lastPlaybackCheckIn: Date(),
            supportedCommands: []
        )
    }

    static func idle(
        id: String,
        deviceID: String,
        user: String,
        userID: String
    ) -> PlaybackSession {
        PlaybackSession(
            id: id,
            userID: userID,
            userName: user,
            userImageTag: nil,
            client: "Infuse",
            deviceName: "Living Room",
            deviceType: "Apple TV",
            deviceID: deviceID,
            applicationVersion: "8.0",
            remoteEndPoint: nil,
            isActive: true,
            supportsRemoteControl: false,
            supportsMediaControl: false,
            nowPlaying: nil,
            nowPlayingName: nil,
            nowViewingName: nil,
            position: 0,
            runtime: nil,
            isPaused: false,
            isMuted: false,
            canSeek: false,
            volumeLevel: nil,
            playMethod: .unknown,
            transcoding: nil,
            lastActivity: Date(),
            lastPlaybackCheckIn: nil,
            supportedCommands: []
        )
    }
}

private extension MediaItem {
    static func previewMovie(id: String, name: String, year: Int, added: Date? = nil) -> MediaItem {
        preview(id: id, name: name, kind: .movie, year: year, dateCreated: added)
    }

    static func previewSeries(id: String, name: String, year: Int, added: Date? = nil) -> MediaItem {
        preview(id: id, name: name, kind: .series, year: year, dateCreated: added)
    }

    static func previewEpisode(id: String, seriesID: String, seriesName: String, added: Date? = nil) -> MediaItem {
        preview(
            id: id,
            name: "One Way Out",
            kind: .episode,
            year: 2022,
            seriesName: seriesName,
            seriesID: seriesID,
            dateCreated: added
        )
    }

    static func preview(
        id: String,
        name: String,
        kind: MediaKind,
        year: Int?,
        seriesName: String? = nil,
        seriesID: String? = nil,
        dateCreated: Date? = nil
    ) -> MediaItem {
        MediaItem(
            id: id,
            name: name,
            kind: kind,
            overview: nil,
            year: year,
            runtime: 7_200,
            officialRating: nil,
            genres: [],
            seriesName: seriesName,
            seasonIndex: kind == .episode ? 1 : nil,
            episodeIndex: kind == .episode ? 10 : nil,
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
            seriesID: seriesID,
            imageItemID: nil,
            queueKind: .resume,
            videoRange: .sdr,
            audioFormat: .unknown,
            dateCreated: dateCreated
        )
    }
}
