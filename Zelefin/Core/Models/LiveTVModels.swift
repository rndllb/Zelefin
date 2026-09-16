import Foundation

enum LiveTVSection: String, CaseIterable, Identifiable, Sendable {
    case onNow
    case guide
    case channels
    case recordings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onNow: "On Now"
        case .guide: "Guide"
        case .channels: "Channels"
        case .recordings: "Recordings"
        }
    }
}

enum LiveTVProgramFilter: String, CaseIterable, Identifiable, Sendable {
    case movies
    case sports
    case news
    case kids
    case series

    var id: String { rawValue }

    var title: String {
        switch self {
        case .movies: "Movies"
        case .sports: "Sports"
        case .news: "News"
        case .kids: "Kids"
        case .series: "Series"
        }
    }
}

struct LiveChannel: Identifiable, Hashable, Sendable {
    let item: MediaItem
    let number: String?
    let currentProgram: LiveProgram?

    var id: String { item.id }
    var name: String { item.name }
    var playItem: MediaItem { item }

    var lineupTitle: String {
        let number = number?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if number.isEmpty { return name }
        if name.isEmpty { return number }
        return "\(number) \(name)"
    }
}

extension [LiveChannel] {
    func overlaying(airing programs: [LiveProgram]) -> [LiveChannel] {
        var byChannel: [String: LiveProgram] = [:]
        for program in programs where byChannel[program.channel.id] == nil {
            byChannel[program.channel.id] = program
        }
        return map { channel in
            guard let airing = byChannel[channel.id] else { return channel }
            return LiveChannel(
                item: channel.item,
                number: channel.number,
                currentProgram: airing.withChannel(channel.item, number: channel.number)
            )
        }
    }

    func sortedByLineup() -> [LiveChannel] {
        sorted { lhs, rhs in
            let left = lhs.number?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let right = rhs.number?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !left.isEmpty || !right.isEmpty {
                let order = left.localizedStandardCompare(right)
                if order != .orderedSame { return order == .orderedAscending }
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func matching(programFilters: Set<LiveTVProgramFilter>) -> [LiveChannel] {
        guard !programFilters.isEmpty else { return self }
        return filter { channel in
            guard let program = channel.currentProgram else { return false }
            return program.matches(programFilters)
        }
    }
}

struct LiveProgram: Identifiable, Hashable, Sendable {
    let item: MediaItem
    let channel: MediaItem
    let channelNumber: String?
    let startDate: Date?
    let endDate: Date?
    let episodeTitle: String?
    let isMovie: Bool
    let isSeries: Bool
    let isNews: Bool
    let isKids: Bool
    let isSports: Bool
    let timerID: String?
    let seriesTimerID: String?

    var id: String { item.id }
    var name: String { item.name }
    var overview: String? { item.overview }
    var playItem: MediaItem { channel }

    func matches(_ filter: LiveTVProgramFilter) -> Bool {
        switch filter {
        case .movies: isMovie
        case .sports: isSports
        case .news: isNews
        case .kids: isKids
        case .series: isSeries
        }
    }

    func matches(_ filters: Set<LiveTVProgramFilter>) -> Bool {
        filters.isEmpty || filters.contains { matches($0) }
    }

    func withChannel(_ channel: MediaItem, number: String?) -> LiveProgram {
        LiveProgram(
            item: item,
            channel: channel,
            channelNumber: number ?? channelNumber,
            startDate: startDate,
            endDate: endDate,
            episodeTitle: episodeTitle,
            isMovie: isMovie,
            isSeries: isSeries,
            isNews: isNews,
            isKids: isKids,
            isSports: isSports,
            timerID: timerID,
            seriesTimerID: seriesTimerID
        )
    }

    func isOnNow(at date: Date = .now) -> Bool {
        guard let startDate, let endDate else { return false }
        return startDate <= date && date < endDate
    }

    func airProgress(at date: Date = .now) -> Double {
        guard let startDate, let endDate else { return 0 }
        let span = endDate.timeIntervalSince(startDate)
        guard span > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(startDate) / span))
    }

    func remainingLabel(at date: Date = .now) -> String? {
        LiveTVTime.remainingLabel(until: endDate, from: date)
    }

    func startTimeLabel(at date: Date = .now) -> String {
        guard let startDate else { return "Scheduled" }
        if isOnNow(at: date) {
            return remainingLabel(at: date) ?? "On Now"
        }
        return LiveTVTime.airTimeLabel(startDate, relativeTo: date)
    }

    var episodeLine: String? {
        let title = episodeTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? nil : title
    }

    var airWindowLabel: String? {
        LiveTVTime.airWindowLabel(from: startDate, to: endDate)
    }

    var airTimesLabel: String? {
        LiveTVTime.airTimesLabel(from: startDate, to: endDate)
    }

    var channelLine: String {
        let name = channel.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return [LiveTVTime.channelLabel(channelNumber), name.isEmpty ? nil : name]
            .compactMap { $0 }
            .joined(separator: "  ")
    }

    var metadataParts: [String] {
        var parts: [String] = []
        if let genre = item.genres.first, !genre.isEmpty {
            parts.append(genre)
        }
        if let remaining = remainingLabel() {
            parts.append(remaining)
        } else if let startDate {
            parts.append(LiveTVTime.airTimeLabel(startDate))
        }
        if let rating = item.officialRating, !rating.isEmpty {
            parts.append(rating)
        }
        if item.hasClosedCaptions {
            parts.append("CC")
        }
        return parts
    }
}

struct LiveGuideChannel: Identifiable, Hashable, Sendable {
    let channel: LiveChannel
    let programs: [LiveProgram]

    var id: String { channel.id }
}

struct LiveTVRecording: Identifiable, Hashable, Sendable {
    let item: MediaItem
    let isInProgress: Bool
    let timerID: String?

    var id: String { item.id }

    func withItem(_ item: MediaItem) -> LiveTVRecording {
        LiveTVRecording(item: item, isInProgress: isInProgress, timerID: timerID)
    }

    static func merging(inProgress: [LiveTVRecording], completed: [LiveTVRecording]) -> [LiveTVRecording] {
        var seen = Set<String>()
        return (inProgress + completed).filter { seen.insert($0.id).inserted }
    }
}

enum LiveTVGuideTimeline {
    static let pointsPerMinute: Double = 4
    static let slotMinutes: Int = 30
    static let channelColumnWidth: Double = 108
    static let rowHeight: Double = 74
    static let headerHeight: Double = 36
    static let rowSpacing: Double = 6

    static func slotStart(containing date: Date, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minute = components.minute ?? 0
        components.minute = minute - (minute % slotMinutes)
        components.second = 0
        components.nanosecond = 0
        return calendar.date(from: components) ?? date
    }

    static func slots(from start: Date, to end: Date) -> [Date] {
        let step = TimeInterval(slotMinutes * 60)
        var result: [Date] = []
        var cursor = start
        while cursor < end {
            result.append(cursor)
            cursor = cursor.addingTimeInterval(step)
        }
        return result
    }

    static func clampedInterval(
        start: Date?,
        end: Date?,
        rangeStart: Date,
        rangeEnd: Date
    ) -> (start: Date, end: Date)? {
        guard let start, let end else { return nil }
        let visibleStart = max(start, rangeStart)
        let visibleEnd = min(end, rangeEnd)
        guard visibleEnd > visibleStart else { return nil }
        return (visibleStart, visibleEnd)
    }

    static func widthPoints(from start: Date, to end: Date) -> Double {
        max(0, end.timeIntervalSince(start) / 60 * pointsPerMinute)
    }

    static func xPoints(start: Date, rangeStart: Date) -> Double {
        start.timeIntervalSince(rangeStart) / 60 * pointsPerMinute
    }

    static func progressWidthPoints(visibleStart: Date, visibleEnd: Date, now: Date) -> Double {
        let playhead = min(max(now, visibleStart), visibleEnd)
        return widthPoints(from: visibleStart, to: playhead)
    }
}

enum LiveTVTime {
    static func remainingLabel(until end: Date?, from date: Date = .now) -> String? {
        guard let end else { return nil }
        let seconds = end.timeIntervalSince(date)
        if seconds <= 0 { return "Ending" }
        let hours = Int(seconds) / 3600
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m left" : "\(hours)h left"
        }
        return "\(max(1, minutes))m left"
    }

    static func airTimeLabel(_ date: Date, relativeTo now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDate(date, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: now) ?? date) {
            return "Tomorrow \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func airWindowLabel(
        from start: Date?,
        to end: Date?,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String? {
        guard let start, let end else { return nil }
        let day = Self.dayLabel(start, calendar: calendar, locale: locale)
        let startTime = Self.timeLabel(start, calendar: calendar, locale: locale)
        let endTime = Self.timeLabel(end, calendar: calendar, locale: locale)
        if calendar.isDate(start, inSameDayAs: end) {
            return "\(day) \(startTime) - \(endTime)"
        }
        let endDay = Self.dayLabel(end, calendar: calendar, locale: locale)
        return "\(day) \(startTime) - \(endDay) \(endTime)"
    }

    static func airTimesLabel(
        from start: Date?,
        to end: Date?,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String? {
        guard let start, let end else { return nil }
        let startTime = Self.timeLabel(start, calendar: calendar, locale: locale)
        let endTime = Self.timeLabel(end, calendar: calendar, locale: locale)
        return "\(startTime) - \(endTime)"
    }

    static func channelLabel(_ number: String?) -> String? {
        let trimmed = number?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        if trimmed.uppercased().hasPrefix("CH") { return trimmed }
        return "CH \(trimmed)"
    }

    private static func dayLabel(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        date.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .weekday(.abbreviated)
                .month(.abbreviated)
                .day()
        )
    }

    private static func timeLabel(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        date.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .hour()
                .minute()
        )
    }

    static func daysLabel(_ days: [String]) -> String {
        let order = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let set = Set(days)
        if set.count == 7 { return "Every day" }
        if set == Set(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]) { return "Weekdays" }
        if set == Set(["Saturday", "Sunday"]) { return "Weekends" }
        let short: [String: String] = [
            "Sunday": "Sun",
            "Monday": "Mon",
            "Tuesday": "Tue",
            "Wednesday": "Wed",
            "Thursday": "Thu",
            "Friday": "Fri",
            "Saturday": "Sat"
        ]
        return order.compactMap { day in
            set.contains(day) ? short[day] : nil
        }.joined(separator: ", ")
    }
}
