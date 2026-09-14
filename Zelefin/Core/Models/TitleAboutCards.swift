import Foundation

enum TitleAboutCard: Equatable, Identifiable, Sendable {
    case synopsis(title: String, genres: String?, overview: String?)
    case tomatometer(score: Int, isFresh: Bool, meaning: String)
    case audience(score: String, meaning: String)
    case commonSense(age: String, meaning: String)

    var id: String {
        switch self {
        case .synopsis: "synopsis"
        case .tomatometer: "tomatometer"
        case .audience: "audience"
        case .commonSense: "commonSense"
        }
    }
}

enum TitleAboutCards {
    static func cards(for item: MediaItem) -> [TitleAboutCard] {
        let synopsis = synopsisCard(for: item)
        let tomatometer = tomatometerCard(for: item)
        let audience = audienceCard(for: item)
        let commonSense = commonSenseCard(for: item)
        guard synopsis != nil || tomatometer != nil || audience != nil || commonSense != nil else { return [] }

        var cards: [TitleAboutCard] = []
        cards.append(synopsis ?? .synopsis(title: item.name, genres: genreLine(from: item.genres), overview: nil))
        if let tomatometer { cards.append(tomatometer) }
        if let audience { cards.append(audience) }
        if let commonSense { cards.append(commonSense) }
        return cards
    }

    static func genreLine(from genres: [String]) -> String? {
        let names = genres.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        return names.map { $0.uppercased() }.joined(separator: ", ")
    }

    static func tomatometerMeaning(score: Double) -> String {
        let percent = Int(score.rounded())
        if score >= 60 {
            return "\(percent)% of professional critic reviews are positive. Titles at 60% or higher are Fresh."
        }
        return "\(percent)% of professional critic reviews are positive. Titles below 60% are Rotten."
    }

    static func commonSenseMeaning(officialRating: String?, ageGate: String) -> String {
        let compact = (officialRating ?? ageGate).uppercased().filter { !$0.isWhitespace }
        if compact.contains("NC-17") || compact == "X" || ageGate == "18+" {
            return "Adults only. No one 17 and under admitted."
        }
        if compact == "R" || compact.contains("TV-MA") || ageGate == "17+" {
            return "Restricted. Under 17 requires accompanying parent or adult guardian. May contain intense violence, strong language, or sexual content."
        }
        if compact.contains("PG-13") {
            return "Parents strongly cautioned. Some material may be inappropriate for children under 13."
        }
        if compact.contains("TV-14") {
            return "Parents strongly cautioned. May be unsuitable for children under 14."
        }
        if compact == "PG" || compact.contains("TV-PG") {
            return "Parental guidance suggested. Some material may not be suitable for children."
        }
        if compact.contains("TV-Y7") {
            return "Directed to older children. May include mild fantasy or comedic violence."
        }
        if compact == "G" || compact.contains("TV-G") || compact.hasPrefix("TV-Y") || ageGate == "All" {
            return "Suitable for all ages."
        }
        if ageGate == "13+" {
            return "Parents strongly cautioned. Some material may be inappropriate for children under 13."
        }
        if ageGate == "7+" {
            return "Parental guidance suggested. Some material may not be suitable for children."
        }
        return "Age guidance based on the title’s official rating."
    }

    private static func synopsisCard(for item: MediaItem) -> TitleAboutCard? {
        let overview = item.overview?.trimmingCharacters(in: .whitespacesAndNewlines)
        let genres = genreLine(from: item.genres)
        let hasOverview = overview.map { !$0.isEmpty } ?? false
        guard hasOverview || genres != nil else { return nil }
        return .synopsis(
            title: item.name,
            genres: genres,
            overview: hasOverview ? overview : nil
        )
    }

    private static func tomatometerCard(for item: MediaItem) -> TitleAboutCard? {
        guard let score = item.criticRating, score > 0 else { return nil }
        return .tomatometer(
            score: Int(score.rounded()),
            isFresh: score >= 60,
            meaning: tomatometerMeaning(score: score)
        )
    }

    static func audienceMeaning(score: Double) -> String {
        if score <= 10 {
            return "Community score stored on this Jellyfin item, usually from TMDB user votes."
        }
        return "Community score stored on this Jellyfin item."
    }

    private static func audienceCard(for item: MediaItem) -> TitleAboutCard? {
        guard let score = item.communityRating, score > 0 else { return nil }
        let label: String
        if score <= 10 {
            label = String(format: score.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", score)
        } else {
            label = "\(Int(score.rounded()))%"
        }
        return .audience(score: label, meaning: audienceMeaning(score: score))
    }

    private static func commonSenseCard(for item: MediaItem) -> TitleAboutCard? {
        guard let age = item.ageGateLabel else { return nil }
        return .commonSense(
            age: age,
            meaning: commonSenseMeaning(officialRating: item.officialRating, ageGate: age)
        )
    }
}
