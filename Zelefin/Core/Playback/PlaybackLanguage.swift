import Foundation

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
        case "": return "Automatic"
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
