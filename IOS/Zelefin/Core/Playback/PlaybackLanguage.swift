import Foundation
import JellyfinAPI

/// The Jellyfin user settings that decide which audio and subtitle streams a title starts on.
/// Language codes are the two-letter picker codes; `ServerLanguageCode` converts to the
/// three-letter codes Jellyfin stores so Jellyfin Web shows the same selection.
struct JellyfinPlaybackPreferences: Equatable {
    static let anyLanguage = ""

    var audioLanguage = anyLanguage
    var playDefaultAudioTrack = false
    var subtitleLanguage = anyLanguage
    var subtitleMode: SubtitlePlaybackMode = .default

    init() {}

    init(configuration: UserConfiguration) {
        audioLanguage = ServerLanguageCode.fromServer(configuration.audioLanguagePreference)
        playDefaultAudioTrack = configuration.isPlayDefaultAudioTrack ?? false
        subtitleLanguage = ServerLanguageCode.fromServer(configuration.subtitleLanguagePreference)
        subtitleMode = configuration.subtitleMode ?? .default
    }

    func applying(to configuration: UserConfiguration) -> UserConfiguration {
        var config = configuration
        config.audioLanguagePreference = ServerLanguageCode.toServer(audioLanguage)
        config.isPlayDefaultAudioTrack = playDefaultAudioTrack
        config.subtitleLanguagePreference = ServerLanguageCode.toServer(subtitleLanguage)
        config.subtitleMode = subtitleMode
        return config
    }
}

enum ServerLanguageCode {
    /// Jellyfin keeps ISO 639-2 ("eng"); the pickers use 639-1 ("en").
    static func toServer(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }
        return Locale.LanguageCode(trimmed).identifier(.alpha3) ?? trimmed
    }

    static func fromServer(_ code: String?) -> String {
        let trimmed = (code ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }
        return Locale.LanguageCode(trimmed).identifier(.alpha2) ?? trimmed
    }
}

extension SubtitlePlaybackMode {
    static let choices: [SubtitlePlaybackMode] = [.default, .smart, .always, .onlyForced, .none]

    var title: String {
        switch self {
        case .default: return "Default"
        case .smart: return "Smart"
        case .always: return "Always"
        case .onlyForced: return "Only Forced"
        case .none: return "None"
        }
    }

    var summary: String {
        switch self {
        case .default: return "Subtitles follow the default and forced flags in the file."
        case .smart: return "Subtitles in the preferred language load when the audio is in another language."
        case .always: return "Subtitles in the preferred language load regardless of the audio language."
        case .onlyForced: return "Only subtitles flagged as forced load."
        case .none: return "No subtitles load unless you pick them during playback."
        }
    }
}

enum PlaybackLanguage {
    static let automaticCode = "automatic"
    static let offCode = "off"

    static var deviceCode: String {
        Locale.preferredLanguages.compactMap { identifier in
            Locale(identifier: identifier).language.languageCode?.identifier
        }.first ?? "en"
    }

    static func displayName(for code: String) -> String {
        switch code {
        case automaticCode: return "Automatic"
        case offCode: return "Off"
        case "": return "Any Language"
        default:
            let name = Locale.current.localizedString(forLanguageCode: code)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? code.uppercased() : name.localizedCapitalized
        }
    }

    static func normalize(_ raw: String?) -> String {
        guard let raw else { return "" }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }
        return trimmed.replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .first
            .map(String.init) ?? trimmed
    }

    static func matches(_ streamLanguage: String?, preference: String) -> Bool {
        let stream = normalize(streamLanguage)
        let want = normalize(preference)
        guard !stream.isEmpty, !want.isEmpty else { return false }
        return stream == want || stream.hasPrefix(want) || want.hasPrefix(stream)
    }

    static func audioIndex(in tracks: [MediaTrack], preference: String = PlaybackPreferences.audioLanguageCode) -> Int? {
        guard preference != automaticCode, !preference.isEmpty else {
            return tracks.first(where: \.isSelected)?.id ?? tracks.first?.id
        }
        return tracks.first { matches($0.language, preference: preference) }?.id
            ?? tracks.first(where: \.isSelected)?.id
            ?? tracks.first?.id
    }

    static func subtitleIndex(in tracks: [MediaTrack], preference: String = PlaybackPreferences.subtitleLanguageCode) -> Int? {
        if preference == offCode { return -1 }
        if preference == automaticCode || preference.isEmpty {
            return tracks.first(where: \.isSelected)?.id
        }
        return tracks.first { matches($0.language, preference: preference) }?.id
            ?? tracks.first(where: \.isSelected)?.id
    }

    static func selecting(_ tracks: [MediaTrack], selectedID: Int?) -> [MediaTrack] {
        tracks.map { track in
            MediaTrack(
                id: track.id,
                kind: track.kind,
                language: track.language,
                title: track.title,
                codec: track.codec,
                isSelected: track.id == selectedID,
                isDefault: track.isDefault
            )
        }
    }
}

enum FirstRunSetupStore {
    private static let prefix = "zelefin.setup.completed."

    static func hasCompleted(accountID: String) -> Bool {
        UserDefaults.standard.bool(forKey: prefix + accountID)
    }

    static func markCompleted(accountID: String) {
        UserDefaults.standard.set(true, forKey: prefix + accountID)
    }
}
