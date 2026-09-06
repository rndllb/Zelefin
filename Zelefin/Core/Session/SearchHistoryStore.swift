import Foundation

enum SearchHistoryStore: Sendable {
    static let key = "zelefin.search.recent"
    static let limit = 20

    static func load(defaults: UserDefaults = .standard) -> [MediaItem] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([MediaItem].self, from: data)) ?? []
    }

    static func save(_ items: [MediaItem], defaults: UserDefaults = .standard) {
        let trimmed = Array(items.prefix(limit))
        defaults.set(try? JSONEncoder().encode(trimmed), forKey: key)
    }

    static func inserting(_ item: MediaItem, into items: [MediaItem], limit: Int = limit) -> [MediaItem] {
        var next = items.filter { $0.id != item.id }
        next.insert(item, at: 0)
        return Array(next.prefix(limit))
    }

    static func record(_ item: MediaItem, defaults: UserDefaults = .standard) {
        save(inserting(item, into: load(defaults: defaults)), defaults: defaults)
    }

    static func remove(id: String, defaults: UserDefaults = .standard) {
        save(load(defaults: defaults).filter { $0.id != id }, defaults: defaults)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
