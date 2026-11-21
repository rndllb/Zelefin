import Foundation

/// “Directed by …” / “Created by …” pulled from cast & crew for the title page.
/// Movies (and episodes) lean on directors; series lean on creators — Jellyfin stores
/// show runners as `Creator`, not `Director`.
enum TitleDirectors {
    struct Byline: Equatable {
        var label: String
        var people: [CreditPerson]

        var accessibilityLabel: String {
            lineText ?? label
        }

        var lineText: String? {
            let names = people.map(\.name)
            guard !names.isEmpty else { return nil }
            if names.count == 1 {
                return "\(label) \(names[0])"
            }
            if names.count == 2 {
                return "\(label) \(names[0]) and \(names[1])"
            }
            let head = names.dropLast().joined(separator: ", ")
            return "\(label) \(head), and \(names.last!)"
        }
    }

    static func people(from credits: [CreditPerson]) -> [CreditPerson] {
        byline(from: credits, itemKind: .movie)?.people ?? []
    }

    static func directors(from credits: [CreditPerson]) -> [CreditPerson] {
        matching(credits, where: isDirector)
    }

    static func creators(from credits: [CreditPerson]) -> [CreditPerson] {
        matching(credits, where: isCreator)
    }

    static func names(from credits: [CreditPerson]) -> [String] {
        people(from: credits).map(\.name)
    }

    static func line(from credits: [CreditPerson]) -> String? {
        byline(from: credits, itemKind: .movie)?.lineText
    }

    static func byline(from credits: [CreditPerson], itemKind: MediaKind) -> Byline? {
        let directors = matching(credits, where: isDirector)
        let creators = matching(credits, where: isCreator)
        switch itemKind {
        case .series, .season:
            if let creators = nonEmpty(creators) {
                return Byline(label: "Created by", people: creators)
            }
            if let directors = nonEmpty(directors) {
                return Byline(label: "Directed by", people: directors)
            }
        default:
            if let directors = nonEmpty(directors) {
                return Byline(label: "Directed by", people: directors)
            }
            if let creators = nonEmpty(creators) {
                return Byline(label: "Created by", people: creators)
            }
        }
        return nil
    }

    private static func nonEmpty(_ people: [CreditPerson]) -> [CreditPerson]? {
        people.isEmpty ? nil : people
    }

    private static func matching(
        _ credits: [CreditPerson],
        where matches: (CreditPerson) -> Bool
    ) -> [CreditPerson] {
        var seen = Set<String>()
        var out: [CreditPerson] = []
        for person in credits where matches(person) {
            let name = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            out.append(person)
        }
        return out
    }

    private static func isDirector(_ person: CreditPerson) -> Bool {
        if person.rank == 1 { return true }
        return roleMatches(person.roleLabel, stem: "director")
    }

    private static func isCreator(_ person: CreditPerson) -> Bool {
        if person.rank == 2 { return true }
        return roleMatches(person.roleLabel, stem: "creator")
    }

    private static func roleMatches(_ roleLabel: String, stem: String) -> Bool {
        let role = roleLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if role.isEmpty { return false }
        // "Director", "Director of …", "Film Director", and hyphenated "Co-Director".
        return role == stem
            || role.hasPrefix(stem)
            || role.hasSuffix(" \(stem)")
            || role.contains(" \(stem)")
            || role.hasSuffix("-\(stem)")
            || role.contains("-\(stem)")
    }
}
