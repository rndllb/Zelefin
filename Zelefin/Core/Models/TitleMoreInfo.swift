import Foundation
import JellyfinAPI

struct TitleMoreRow: Equatable, Identifiable, Sendable {
    var id: String { label }
    var label: String
    var value: String
}

struct TitleMoreLink: Equatable, Identifiable, Sendable {
    var id: String { url.absoluteString }
    var name: String
    var url: URL
}

struct TitleMoreInfo: Equatable, Sendable {
    var information: [TitleMoreRow] = []
    var languages: [TitleMoreRow] = []
    var file: [TitleMoreRow] = []
    var links: [TitleMoreLink] = []
    var accessibilityNote: String?

    var hasDetails: Bool {
        !information.isEmpty || !languages.isEmpty || !file.isEmpty || !links.isEmpty
    }

    var needsEpisodeMedia: Bool {
        languages.isEmpty && file.isEmpty
    }

    func mergingMedia(from dto: BaseItemDto) -> TitleMoreInfo {
        let media = TitleMoreInfoMapper.media(from: dto)
        var copy = self
        if copy.languages.isEmpty {
            copy.languages = media.languages
        }
        if copy.file.isEmpty {
            copy.file = media.file
        }
        if copy.accessibilityNote == nil {
            copy.accessibilityNote = media.accessibilityNote
        }
        return copy
    }
}

enum TitleMoreInfoMapper {
    static func info(from dto: BaseItemDto, item: MediaItem) -> TitleMoreInfo {
        var info = TitleMoreInfo()
        info.information = information(from: dto, item: item)
        let media = media(from: dto)
        info.languages = media.languages
        info.file = media.file
        info.accessibilityNote = media.accessibilityNote
        info.links = links(from: dto)
        return info
    }

    static func information(from dto: BaseItemDto, item: MediaItem) -> [TitleMoreRow] {
        var rows: [TitleMoreRow] = []
        let studios = (dto.studios ?? [])
            .compactMap { $0.name?.trimmedNonEmpty }
        if !studios.isEmpty {
            rows.append(.init(label: "Studio", value: studios.joined(separator: ", ")))
        }
        if let original = dto.originalTitle?.trimmedNonEmpty, original != item.name {
            rows.append(.init(label: "Original Title", value: original))
        }
        if let released = releasedLabel(from: dto, year: item.year) {
            rows.append(.init(label: "Released", value: released))
        }
        if let runtime = runtimeLabel(from: dto, item: item) {
            rows.append(.init(label: "Run Time", value: runtime))
        }
        if let rated = ratedLabel(from: dto, item: item) {
            rows.append(.init(label: "Rated", value: rated))
        }
        let advisories = (dto.tags ?? []).compactMap(\.trimmedNonEmpty)
        if !advisories.isEmpty {
            rows.append(.init(label: "Content Advisories", value: advisories.joined(separator: ", ")))
        }
        let regions = (dto.productionLocations ?? []).compactMap(\.trimmedNonEmpty)
        if !regions.isEmpty {
            rows.append(.init(label: "Regions of Origin", value: regions.joined(separator: ", ")))
        }
        if let status = dto.status?.trimmedNonEmpty {
            rows.append(.init(label: "Status", value: status.capitalized))
        }
        if let airTime = dto.airTime?.trimmedNonEmpty {
            rows.append(.init(label: "Airs", value: airTime))
        }
        return rows
    }

    static func media(from dto: BaseItemDto) -> TitleMoreInfo {
        var info = TitleMoreInfo()
        let sources = dto.mediaSources ?? []
        let streams = dto.mediaStreams ?? sources.first?.mediaStreams ?? []
        let audioStreams = streams.filter { $0.type == .audio }
        let subtitleStreams = streams.filter { $0.type == .subtitle }

        let original = originalAudioLabel(from: audioStreams)
        if let original {
            info.languages.append(.init(label: "Original Audio", value: original))
        }
        if let audio = groupedAudioLabel(from: audioStreams) {
            info.languages.append(.init(label: "Audio", value: audio))
        }
        if let subtitles = subtitleLabel(from: subtitleStreams) {
            info.languages.append(.init(label: "Subtitles", value: subtitles))
        }

        info.file = fileRows(from: sources, streams: streams, fallbackContainer: dto.container)
        if subtitleStreams.contains(where: { $0.isHearingImpaired == true }) {
            info.accessibilityNote = "Closed captions include the spoken dialogue plus relevant non-dialogue information."
        }
        return info
    }

    static func audioFormatName(
        codec: String?,
        channelLayout: String?,
        spatial: AudioSpatialFormat?,
        isAudioDescription: Bool
    ) -> String {
        var parts: [String] = []
        let codecName = codecDisplayName(codec, spatial: spatial, layout: channelLayout)
        if let codecName {
            parts.append(codecName)
        }
        if isAudioDescription {
            parts.append("AD")
        }
        return parts.joined(separator: ", ")
    }

    static func languageName(from code: String?) -> String {
        let trimmed = code?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, trimmed.lowercased() != "und" else { return "Unknown" }
        if let name = Locale.current.localizedString(forLanguageCode: trimmed) {
            return name
        }
        if let mapped = iso6391[trimmed.lowercased()],
           let name = Locale.current.localizedString(forLanguageCode: mapped)
        {
            return name
        }
        if trimmed.count == 3, let name = Locale.current.localizedString(forLanguageCode: String(trimmed.prefix(2))) {
            return name
        }
        return trimmed
    }

    static func subtitleMark(isHearingImpaired: Bool, isForced: Bool) -> String? {
        if isHearingImpaired { return "CC" }
        if isForced { return "Forced" }
        return nil
    }

    private static func links(from dto: BaseItemDto) -> [TitleMoreLink] {
        (dto.externalURLs ?? []).compactMap { entry in
            guard let name = entry.name?.trimmedNonEmpty,
                  let raw = entry.url?.trimmedNonEmpty,
                  let url = URL(string: raw)
            else { return nil }
            return TitleMoreLink(name: name, url: url)
        }
    }

    private static func releasedLabel(from dto: BaseItemDto, year: Int?) -> String? {
        if let date = dto.premiereDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
        if let year {
            return "\(year)"
        }
        return dto.productionYear.map { "\($0)" }
    }

    private static func runtimeLabel(from dto: BaseItemDto, item: MediaItem) -> String? {
        if let ticks = dto.cumulativeRunTimeTicks ?? dto.runTimeTicks {
            let seconds = TickClock.seconds(from: ticks)
            if seconds > 0 {
                return MediaItem.moreInfoRuntimeLabel(seconds)
            }
        }
        return item.runtime.flatMap(MediaItem.moreInfoRuntimeLabel)
    }

    private static func ratedLabel(from dto: BaseItemDto, item: MediaItem) -> String? {
        let rating = dto.officialRating?.trimmedNonEmpty ?? item.officialRating?.trimmedNonEmpty
        let custom = dto.customRating?.trimmedNonEmpty
        if let rating, let custom, custom.caseInsensitiveCompare(rating) != .orderedSame {
            if custom.lowercased().hasPrefix(rating.lowercased()) {
                return custom
            }
            return "\(rating) \(custom)"
        }
        return custom ?? rating
    }

    private static func originalAudioLabel(from streams: [MediaStream]) -> String? {
        let names = streams
            .map { languageName(from: $0.language) }
            .reduce(into: [String]()) { result, name in
                if !result.contains(name) { result.append(name) }
            }
        guard !names.isEmpty else { return nil }
        return names.joined(separator: ", ")
    }

    private static func groupedAudioLabel(from streams: [MediaStream]) -> String? {
        var grouped: [(language: String, formats: [String])] = []
        var index: [String: Int] = [:]
        for stream in streams {
            let language = languageName(from: stream.language)
            let described = ItemMapper.hasAudioDescription(from: [stream])
            let format = audioFormatName(
                codec: stream.codec,
                channelLayout: stream.channelLayout,
                spatial: stream.audioSpatialFormat,
                isAudioDescription: false
            )
            func add(_ value: String) {
                if let existing = index[language] {
                    if !grouped[existing].formats.contains(value) {
                        grouped[existing].formats.append(value)
                    }
                } else {
                    index[language] = grouped.count
                    grouped.append((language, [value]))
                }
            }
            if !format.isEmpty {
                add(format)
            }
            if described {
                add("AD")
            }
        }
        guard !grouped.isEmpty else { return nil }
        return grouped.map { language, formats in
            "\(language) (\(formats.joined(separator: ", ")))"
        }.joined(separator: ", ")
    }

    private static func subtitleLabel(from streams: [MediaStream]) -> String? {
        var parts: [String] = []
        var seen = Set<String>()
        for stream in streams {
            var label = languageName(from: stream.language)
            if let mark = subtitleMark(
                isHearingImpaired: stream.isHearingImpaired == true,
                isForced: stream.isForced == true
            ) {
                label += " (\(mark))"
            }
            if seen.insert(label).inserted {
                parts.append(label)
            }
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ")
    }

    private static func fileRows(from sources: [MediaSourceInfo], streams: [MediaStream], fallbackContainer: String?) -> [TitleMoreRow] {
        var rows: [TitleMoreRow] = []
        if sources.count > 1 {
            let versions = sources.compactMap(versionLabel(from:)).joined(separator: "\n")
            if !versions.isEmpty {
                rows.append(.init(label: "Versions", value: versions))
            }
        } else if let source = sources.first, let version = versionLabel(from: source) {
            rows.append(.init(label: "File", value: version))
        } else if let container = containerLabel(fallbackContainer) {
            rows.append(.init(label: "Format", value: container))
        }

        let video = streams.first(where: { $0.type == .video })
        if let videoLine = videoLine(from: video) {
            rows.append(.init(label: "Video", value: videoLine))
        }
        if let bitrate = sources.first?.bitrate ?? video?.bitRate, bitrate > 0 {
            rows.append(.init(label: "Bitrate", value: bitrateLabel(bitrate)))
        }
        return rows
    }

    private static func versionLabel(from source: MediaSourceInfo) -> String? {
        var parts: [String] = []
        let streams = source.mediaStreams ?? []
        if let resolution = ItemMapper.videoResolution(from: streams).displayName {
            parts.append(resolution)
        }
        if let container = containerLabel(source.container) {
            parts.append(container)
        }
        if let size = source.size, size > 0 {
            parts.append(CacheInventory.formatBytes(Int64(size)))
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private static func videoLine(from stream: MediaStream?) -> String? {
        guard let stream else { return nil }
        var parts: [String] = []
        if let width = stream.width, let height = stream.height, width > 0, height > 0 {
            parts.append("\(width)×\(height)")
        }
        if let codec = videoCodecName(stream.codec) {
            parts.append(codec)
        }
        let range = ItemMapper.videoRange(from: [stream])
        if range != .sdr {
            parts.append(range.displayName)
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    static func codecDisplayName(_ codec: String?, spatial: AudioSpatialFormat?, layout: String?) -> String? {
        if spatial == .dolbyAtmos {
            return "Dolby Atmos"
        }
        let raw = codec?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let channels = layout?.lowercased() ?? ""
        switch raw {
        case "eac3" where channels.contains("atmos") || raw.contains("joc"):
            return "Dolby Atmos"
        case "truehd" where channels.contains("atmos"):
            return "Dolby Atmos"
        case "eac3":
            return layoutLabel("Dolby Digital Plus", layout)
        case "ac3":
            return layoutLabel("Dolby Digital", layout)
        case "truehd", "mlp":
            return "Dolby TrueHD"
        case "dca", "dts":
            return layoutLabel("DTS", layout)
        case "dtshd", "dts-hd", "dtsma", "dts-hd ma":
            return "DTS-HD MA"
        case "aac", "aac_latm":
            return "AAC"
        case "opus":
            return "Opus"
        case "flac":
            return "FLAC"
        case "mp3":
            return "MP3"
        case let value where value.hasPrefix("pcm"):
            return "PCM"
        case "":
            return layoutLabel(nil, layout)
        default:
            return layoutLabel(raw.uppercased(), layout)
        }
    }

    static func bitrateLabel(_ bitsPerSecond: Int) -> String {
        let mbps = Double(bitsPerSecond) / 1_000_000
        if mbps >= 10 {
            return "\(Int(mbps.rounded())) Mbps"
        }
        if mbps >= 1 {
            return String(format: "%.1f Mbps", mbps)
        }
        let kbps = Double(bitsPerSecond) / 1_000
        return "\(Int(kbps.rounded())) kbps"
    }

    static func containerLabel(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        let first = trimmed.split(separator: ",").first.map(String.init) ?? trimmed
        return first.uppercased()
    }

    private static func layoutLabel(_ codec: String?, _ layout: String?) -> String? {
        let cleaned = layout?
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let codec, let cleaned, !cleaned.isEmpty, !codec.localizedCaseInsensitiveContains(cleaned) {
            return "\(codec) \(cleaned)"
        }
        return codec ?? cleaned?.uppercased()
    }

    private static func videoCodecName(_ codec: String?) -> String? {
        switch codec?.lowercased() {
        case "hevc", "h265": return "HEVC"
        case "h264", "avc": return "H.264"
        case "av1": return "AV1"
        case "vp9": return "VP9"
        case "mpeg2video": return "MPEG-2"
        case "mpeg4": return "MPEG-4"
        case let value?:
            return value.uppercased()
        default:
            return nil
        }
    }

    private static let iso6391: [String: String] = [
        "eng": "en", "jpn": "ja", "kor": "ko", "fra": "fr", "fre": "fr",
        "spa": "es", "deu": "de", "ger": "de", "ita": "it", "por": "pt",
        "rus": "ru", "zho": "zh", "chi": "zh", "nld": "nl", "dut": "nl",
        "swe": "sv", "nor": "no", "dan": "da", "fin": "fi", "pol": "pl",
        "hun": "hu", "ces": "cs", "cze": "cs", "ara": "ar", "hin": "hi",
        "tha": "th", "vie": "vi", "tur": "tr", "ell": "el", "gre": "el"
    ]
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension MediaItem {
    static func moreInfoRuntimeLabel(_ interval: TimeInterval) -> String? {
        guard interval > 0 else { return nil }
        return minutesLabel(interval)
    }
}
