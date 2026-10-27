import Foundation

struct SkipSegment: Hashable, Sendable {
    /// The four kinds TheIntroDB and Jellyfin's media segments share. `outro` is the credits.
    enum Kind: String, Hashable, Sendable, CaseIterable {
        case recap
        case intro
        case outro
        case preview
    }

    let kind: Kind
    let start: TimeInterval
    let end: TimeInterval

    var title: String {
        switch kind {
        case .recap: "Skip Recap"
        case .intro: "Skip Intro"
        case .outro: "Skip Credits"
        case .preview: "Skip Preview"
        }
    }

    var seekTime: TimeInterval { max(end, start) }

    func isActive(at time: TimeInterval) -> Bool {
        guard end - start >= 3 else { return false }
        return time >= (start - 0.35) && time < (end - 0.8)
    }

    /// The earliest-starting segment playing now; overlapping sources settle on one button.
    static func prompt(in segments: [SkipSegment], at time: TimeInterval) -> SkipSegment? {
        segments
            .filter { $0.isActive(at: time) }
            .min { $0.start < $1.start }
    }

    static func fromPluginTimestamps(intro: IntroTimestampPayload?, credits: IntroTimestampPayload?) -> [SkipSegment] {
        [intro.flatMap { $0.segment(kind: .intro) }, credits.flatMap { $0.segment(kind: .outro) }]
            .compactMap { $0 }
    }
}

struct IntroTimestampPayload: Hashable, Sendable, Codable {
    var introStart: Double?
    var introEnd: Double?
    var valid: Bool?

    enum CodingKeys: String, CodingKey {
        case introStart = "IntroStart"
        case introEnd = "IntroEnd"
        case valid = "Valid"
        case introStartCamel = "introStart"
        case introEndCamel = "introEnd"
        case validCamel = "valid"
    }

    init(introStart: Double?, introEnd: Double?, valid: Bool? = true) {
        self.introStart = introStart
        self.introEnd = introEnd
        self.valid = valid
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        introStart = try container.decodeIfPresent(Double.self, forKey: .introStart)
            ?? container.decodeIfPresent(Double.self, forKey: .introStartCamel)
        introEnd = try container.decodeIfPresent(Double.self, forKey: .introEnd)
            ?? container.decodeIfPresent(Double.self, forKey: .introEndCamel)
        valid = try container.decodeIfPresent(Bool.self, forKey: .valid)
            ?? container.decodeIfPresent(Bool.self, forKey: .validCamel)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(introStart, forKey: .introStart)
        try container.encodeIfPresent(introEnd, forKey: .introEnd)
        try container.encodeIfPresent(valid, forKey: .valid)
    }

    func segment(kind: SkipSegment.Kind) -> SkipSegment? {
        guard valid != false else { return nil }
        guard let start = introStart, let end = introEnd, end - start >= 3 else { return nil }
        return SkipSegment(kind: kind, start: start, end: end)
    }
}

struct IntroSkipperTimestampsResponse: Hashable, Sendable, Codable {
    var introduction: IntroTimestampPayload?
    var credits: IntroTimestampPayload?

    enum CodingKeys: String, CodingKey {
        case introduction = "Introduction"
        case credits = "Credits"
        case introductionCamel = "introduction"
        case creditsCamel = "credits"
    }

    init(introduction: IntroTimestampPayload? = nil, credits: IntroTimestampPayload? = nil) {
        self.introduction = introduction
        self.credits = credits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        introduction = try container.decodeIfPresent(IntroTimestampPayload.self, forKey: .introduction)
            ?? container.decodeIfPresent(IntroTimestampPayload.self, forKey: .introductionCamel)
        credits = try container.decodeIfPresent(IntroTimestampPayload.self, forKey: .credits)
            ?? container.decodeIfPresent(IntroTimestampPayload.self, forKey: .creditsCamel)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(introduction, forKey: .introduction)
        try container.encodeIfPresent(credits, forKey: .credits)
    }

    var segments: [SkipSegment] {
        SkipSegment.fromPluginTimestamps(intro: introduction, credits: credits)
    }
}

enum IntroSkipperPlugin {
    static func isInstalled(names: [String]) -> Bool {
        names.contains { name in
            let lower = name.lowercased()
            return lower.contains("intro skip") || lower.contains("introskipper")
        }
    }
}

/// Zelefin's settings treat Intro Skipper and TheIntroDB as alternatives: with one enabled, the other is
/// shown greyed out. Jellyfin itself would run both.
enum SkipPluginChoice {
    static func isGreyedOut(_ plugin: PluginPresence, other: PluginPresence) -> Bool {
        other == .enabled && plugin != .enabled
    }
}

/// TheIntroDB's Jellyfin plugin, which fills media segments from TheIntroDB's community timestamps.
enum TheIntroDBPlugin {
    static func isInstalled(names: [String]) -> Bool {
        names.contains { $0.lowercased().filter(\.isLetter).contains("theintrodb") }
    }
}
