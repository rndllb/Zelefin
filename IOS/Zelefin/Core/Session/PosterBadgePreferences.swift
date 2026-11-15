import Foundation

/// Which marks appear on posters. Defaults keep today's look; Interface settings can quiet them down.
enum PosterBadgePreferences {
    static let ratingKey = "zelefin.poster-badge.rating"
    static let qualityKey = "zelefin.poster-badge.quality"
    static let watchedKey = "zelefin.poster-badge.watched"

    static var showsRating: Bool {
        if UserDefaults.standard.object(forKey: ratingKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: ratingKey)
    }

    static var showsQuality: Bool {
        if UserDefaults.standard.object(forKey: qualityKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: qualityKey)
    }

    static var showsWatched: Bool {
        if UserDefaults.standard.object(forKey: watchedKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: watchedKey)
    }
}
