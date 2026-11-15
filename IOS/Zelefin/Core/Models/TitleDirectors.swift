import Foundation

/// Directors pulled out of cast & crew for the title page, the way Plex surfaces them.
enum TitleDirectors {
    static func people(from credits: [CreditPerson]) -> [CreditPerson] {
        var seen = Set<String>()
        var directors: [CreditPerson] = []
        for person in credits where isDirector(person) {
            let name = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            directors.append(person)
        }
        return directors
    }

    static func names(from credits: [CreditPerson]) -> [String] {
        people(from: credits).map(\.name)
    }

    static func line(from credits: [CreditPerson]) -> String? {
        let names = names(from: credits)
        guard !names.isEmpty else { return nil }
        if names.count == 1 {
            return "Directed by \(names[0])"
        }
        if names.count == 2 {
            return "Directed by \(names[0]) and \(names[1])"
        }
        let head = names.dropLast().joined(separator: ", ")
        return "Directed by \(head), and \(names.last!)"
    }

    private static func isDirector(_ person: CreditPerson) -> Bool {
        if person.rank == 1 { return true }
        let role = person.roleLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return role == "director" || role.hasPrefix("director")
    }
}
