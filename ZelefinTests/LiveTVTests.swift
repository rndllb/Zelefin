import XCTest
import JellyfinAPI
@testable import Zelefin

final class LiveTVTests: XCTestCase {
    func testRemainingLabelFormatsHoursAndMinutes() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(
            LiveTVTime.remainingLabel(until: now.addingTimeInterval(73 * 60), from: now),
            "1h 13m left"
        )
        XCTAssertEqual(
            LiveTVTime.remainingLabel(until: now.addingTimeInterval(8 * 60), from: now),
            "8m left"
        )
        XCTAssertEqual(
            LiveTVTime.remainingLabel(until: now.addingTimeInterval(-1), from: now),
            "Ending"
        )
    }

    func testDaysLabelCollapsesWeekPatterns() {
        XCTAssertEqual(
            LiveTVTime.daysLabel(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]),
            "Weekdays"
        )
        XCTAssertEqual(LiveTVTime.daysLabel(["Saturday", "Sunday"]), "Weekends")
        XCTAssertEqual(
            LiveTVTime.daysLabel(["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]),
            "Every day"
        )
        XCTAssertEqual(LiveTVTime.daysLabel(["Tuesday", "Thursday"]), "Tue, Thu")
    }

    func testProgramFilterAndProgress() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let channel = MediaItem.liveChannelStub(id: "ch", name: "Harbor")
        let program = LiveProgram(
            item: MediaItem.liveChannelStub(id: "p", name: "Night Watch"),
            channel: channel,
            channelNumber: "4",
            startDate: now.addingTimeInterval(-30 * 60),
            endDate: now.addingTimeInterval(30 * 60),
            episodeTitle: nil,
            isMovie: false,
            isSeries: true,
            isNews: false,
            isKids: false,
            isSports: false,
            timerID: nil,
            seriesTimerID: nil
        )
        XCTAssertTrue(program.isOnNow(at: now))
        XCTAssertEqual(program.airProgress(at: now), 0.5, accuracy: 0.001)
        XCTAssertTrue(program.matches(.series))
        XCTAssertFalse(program.matches(.sports))
        XCTAssertTrue(program.matches([]))
        XCTAssertTrue(program.matches([.series, .sports]))
        XCTAssertFalse(program.matches([.sports, .news]))
        XCTAssertEqual(program.remainingLabel(at: now), "30m left")
    }

    func testSectionTitlesCoverJellyfinSurfaces() {
        XCTAssertEqual(LiveTVSection.allCases.map(\.title), [
            "On Now", "Guide", "Channels", "Recordings"
        ])
        XCTAssertEqual(LiveTVProgramFilter.allCases.map(\.title), [
            "Movies", "Sports", "News", "Kids", "Series"
        ])
    }

    func testAiringProgramsReplaceChannelStubs() {
        let channelItem = MediaItem.liveChannelStub(id: "ch", name: "Harbor")
        let channels = [LiveChannel(item: channelItem, number: "4", currentProgram: nil)]
        let now = Date()
        let airing = LiveProgram(
            item: MediaItem.liveChannelStub(id: "p", name: "Night Watch", primaryImageTag: "still"),
            channel: MediaItem.liveChannelStub(id: "ch", name: "Harbor"),
            channelNumber: "4",
            startDate: now,
            endDate: now.addingTimeInterval(60),
            episodeTitle: "After Hours",
            isMovie: false,
            isSeries: true,
            isNews: false,
            isKids: false,
            isSports: false,
            timerID: nil,
            seriesTimerID: nil
        )
        let merged = channels.overlaying(airing: [airing])
        XCTAssertEqual(merged.first?.currentProgram?.name, "Night Watch")
        XCTAssertEqual(merged.first?.currentProgram?.item.primaryImageTag, "still")
        XCTAssertEqual(merged.first?.currentProgram?.channel.id, "ch")
        XCTAssertEqual(merged.first?.currentProgram?.episodeTitle, "After Hours")
    }

    func testChannelsSectionSortsByChannelNumber() {
        let harbor = LiveChannel(
            item: MediaItem.liveChannelStub(id: "ch-harbor", name: "Harbor"),
            number: "12",
            currentProgram: nil
        )
        let news = LiveChannel(
            item: MediaItem.liveChannelStub(id: "ch-news", name: "News"),
            number: "4.1",
            currentProgram: nil
        )
        let sports = LiveChannel(
            item: MediaItem.liveChannelStub(id: "ch-sports", name: "Sports"),
            number: "4",
            currentProgram: nil
        )
        XCTAssertEqual([harbor, news, sports].sortedByLineup().map(\.id), [
            "ch-sports", "ch-news", "ch-harbor"
        ])
        XCTAssertEqual(sports.lineupTitle, "4 Sports")
        XCTAssertEqual(news.lineupTitle, "4.1 News")
    }

    func testChannelFiltersKeepMatchingCurrentPrograms() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sportsProgram = LiveProgram(
            item: MediaItem.liveChannelStub(id: "p-sports", name: "Night Game"),
            channel: MediaItem.liveChannelStub(id: "ch-sports", name: "Sports"),
            channelNumber: "4",
            startDate: now,
            endDate: now.addingTimeInterval(60),
            episodeTitle: nil,
            isMovie: false,
            isSeries: false,
            isNews: false,
            isKids: false,
            isSports: true,
            timerID: nil,
            seriesTimerID: nil
        )
        let seriesProgram = LiveProgram(
            item: MediaItem.liveChannelStub(id: "p-series", name: "Night Watch"),
            channel: MediaItem.liveChannelStub(id: "ch-series", name: "Harbor"),
            channelNumber: "12",
            startDate: now,
            endDate: now.addingTimeInterval(60),
            episodeTitle: nil,
            isMovie: false,
            isSeries: true,
            isNews: false,
            isKids: false,
            isSports: false,
            timerID: nil,
            seriesTimerID: nil
        )
        let sports = LiveChannel(
            item: MediaItem.liveChannelStub(id: "ch-sports", name: "Sports"),
            number: "4",
            currentProgram: sportsProgram
        )
        let harbor = LiveChannel(
            item: MediaItem.liveChannelStub(id: "ch-series", name: "Harbor"),
            number: "12",
            currentProgram: seriesProgram
        )
        let idle = LiveChannel(
            item: MediaItem.liveChannelStub(id: "ch-idle", name: "Idle"),
            number: "8",
            currentProgram: nil
        )
        let rows = [sports, harbor, idle]
        XCTAssertEqual(rows.matching(programFilters: []).map(\.id), ["ch-sports", "ch-series", "ch-idle"])
        XCTAssertEqual(rows.matching(programFilters: [.sports]).map(\.id), ["ch-sports"])
        XCTAssertEqual(rows.matching(programFilters: [.series, .news]).map(\.id), ["ch-series"])
        XCTAssertTrue(rows.matching(programFilters: [.movies]).isEmpty)
    }

    func testGuideTimelineSizesBlocksByRuntime() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(
            LiveTVGuideTimeline.widthPoints(from: start, to: start.addingTimeInterval(30 * 60)),
            120,
            accuracy: 0.01
        )
        XCTAssertEqual(
            LiveTVGuideTimeline.widthPoints(from: start, to: start.addingTimeInterval(60 * 60)),
            240,
            accuracy: 0.01
        )
        XCTAssertEqual(
            LiveTVGuideTimeline.widthPoints(from: start, to: start.addingTimeInterval(120 * 60)),
            480,
            accuracy: 0.01
        )
        XCTAssertEqual(
            LiveTVGuideTimeline.xPoints(start: start.addingTimeInterval(30 * 60), rangeStart: start),
            120,
            accuracy: 0.01
        )
    }

    func testGuideTimelineClampsAndProgress() {
        let rangeStart = Date(timeIntervalSince1970: 1_700_000_000)
        let rangeEnd = rangeStart.addingTimeInterval(2 * 3600)
        let visible = LiveTVGuideTimeline.clampedInterval(
            start: rangeStart.addingTimeInterval(-30 * 60),
            end: rangeStart.addingTimeInterval(30 * 60),
            rangeStart: rangeStart,
            rangeEnd: rangeEnd
        )
        XCTAssertEqual(visible?.start, rangeStart)
        XCTAssertEqual(visible?.end, rangeStart.addingTimeInterval(30 * 60))
        XCTAssertEqual(
            LiveTVGuideTimeline.progressWidthPoints(
                visibleStart: visible!.start,
                visibleEnd: visible!.end,
                now: rangeStart.addingTimeInterval(15 * 60)
            ),
            60,
            accuracy: 0.01
        )
    }

    func testGuideSlotStartRoundsDownToHalfHour() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 17, minute: 47))!
        let slot = LiveTVGuideTimeline.slotStart(containing: date, calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: slot), 17)
        XCTAssertEqual(calendar.component(.minute, from: slot), 30)
        XCTAssertEqual(
            LiveTVGuideTimeline.slots(from: slot, to: slot.addingTimeInterval(90 * 60)).count,
            3
        )
    }

    func testProgramLabelsShowAirWindowAndChannel() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let locale = Locale(identifier: "en_US")
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 19, minute: 51))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 20, minute: 44))!
        XCTAssertEqual(
            LiveTVTime.airWindowLabel(from: start, to: end, calendar: calendar, locale: locale),
            "Mon, Sep 14 7:51 PM - 8:44 PM"
        )
        XCTAssertEqual(
            LiveTVTime.airTimesLabel(from: start, to: end, calendar: calendar, locale: locale),
            "7:51 PM - 8:44 PM"
        )
        XCTAssertEqual(LiveTVTime.channelLabel("2352"), "CH 2352")
        XCTAssertEqual(LiveTVTime.channelLabel("CH 8"), "CH 8")
        XCTAssertNil(LiveTVTime.channelLabel("  "))

        let program = LiveProgram(
            item: MediaItem.liveChannelStub(id: "p", name: "ONE Fight Night."),
            channel: MediaItem.liveChannelStub(id: "ch", name: "One Championship TV"),
            channelNumber: "2352",
            startDate: start,
            endDate: end,
            episodeTitle: "OFN 6: Superbon v Allazov",
            isMovie: false,
            isSeries: true,
            isNews: false,
            isKids: false,
            isSports: true,
            timerID: nil,
            seriesTimerID: nil
        )
        XCTAssertEqual(program.episodeLine, "OFN 6: Superbon v Allazov")
        XCTAssertEqual(program.channelLine, "CH 2352  One Championship TV")
    }

    func testRecordingsKeepInProgressItemsAndSkipFolders() {
        let active = BaseItemDto(
            id: "rec-1",
            isFolder: false,
            name: "Night Watch",
            status: "InProgress",
            timerID: "timer-1",
            type: .recording
        )
        let folder = BaseItemDto(
            id: "folder-1",
            isFolder: true,
            name: "Night Watch",
            type: .recording
        )
        let unnamed = BaseItemDto(
            id: "rec-2",
            isFolder: false,
            seriesName: "Harbor",
            status: "Completed",
            type: .video
        )
        let mappedActive = ItemMapper.recordingItem(from: active)
        XCTAssertEqual(mappedActive?.item.name, "Night Watch")
        XCTAssertEqual(mappedActive?.isInProgress, true)
        XCTAssertEqual(mappedActive?.timerID, "timer-1")
        XCTAssertNil(ItemMapper.recordingItem(from: folder))
        XCTAssertEqual(ItemMapper.recordingItem(from: unnamed)?.item.name, "Harbor")
        XCTAssertEqual(ItemMapper.recordingItem(from: unnamed)?.isInProgress, false)

        let completed = LiveTVRecording(
            item: MediaItem.liveChannelStub(id: "rec-1", name: "Night Watch"),
            isInProgress: false,
            timerID: nil
        )
        let live = LiveTVRecording(
            item: MediaItem.liveChannelStub(id: "rec-1", name: "Night Watch"),
            isInProgress: true,
            timerID: "timer-1"
        )
        let other = LiveTVRecording(
            item: MediaItem.liveChannelStub(id: "rec-3", name: "Kickoff"),
            isInProgress: false,
            timerID: nil
        )
        let merged = LiveTVRecording.merging(inProgress: [live], completed: [completed, other])
        XCTAssertEqual(merged.map(\.id), ["rec-1", "rec-3"])
        XCTAssertEqual(merged.first?.isInProgress, true)
    }
}
