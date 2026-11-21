import XCTest
@testable import Zelefin

final class TitleDirectorsTests: XCTestCase {
    func testDirectedByLine() {
        XCTAssertNil(TitleDirectors.line(from: []))
        XCTAssertEqual(
            TitleDirectors.people(from: [person("Nolan", "Director", rank: 1)]).map(\.id),
            ["Nolan"]
        )
        XCTAssertEqual(
            TitleDirectors.line(from: [person("Nolan", "Director", rank: 1)]),
            "Directed by Nolan"
        )
        XCTAssertEqual(
            TitleDirectors.line(from: [
                person("A", "Director", rank: 1),
                person("B", "Director", rank: 1),
            ]),
            "Directed by A and B"
        )
        XCTAssertEqual(
            TitleDirectors.line(from: [
                person("A", "Director", rank: 1),
                person("B", "Director", rank: 1),
                person("C", "Director", rank: 1),
            ]),
            "Directed by A, B, and C"
        )
        XCTAssertEqual(
            TitleDirectors.line(from: [
                person("Actor", "Cast", rank: 0),
                person("Villeneuve", "Director", rank: 1),
            ]),
            "Directed by Villeneuve"
        )
    }

    func testActorDirectorKeepsDirectorCredit() {
        let same = "person-1"
        let credits = [
            CreditPerson(id: same, name: "Eastwood", roleLabel: "Walt Kowalski", imageTag: nil, rank: 0),
            CreditPerson(id: same, name: "Eastwood", roleLabel: "Director", imageTag: nil, rank: 1),
        ]
        XCTAssertEqual(TitleDirectors.names(from: credits), ["Eastwood"])
    }

    func testCoDirectorRoleIsDetected() {
        XCTAssertEqual(
            TitleDirectors.names(from: [person("Lee", "Co-Director", rank: 5)]),
            ["Lee"]
        )
        XCTAssertEqual(
            TitleDirectors.names(from: [person("Nolan", "Film Director", rank: 5)]),
            ["Nolan"]
        )
    }

    func testSeriesUsesCreatedBy() {
        let credits = [
            person("Actor", "Cast", rank: 0),
            person("Gilligan", "Creator", rank: 2),
        ]
        let byline = TitleDirectors.byline(from: credits, itemKind: .series)
        XCTAssertEqual(byline?.label, "Created by")
        XCTAssertEqual(byline?.people.map(\.name), ["Gilligan"])
        XCTAssertEqual(byline?.lineText, "Created by Gilligan")
    }

    func testSeriesFallsBackToDirectedBy() {
        let byline = TitleDirectors.byline(
            from: [person("Director", "Director", rank: 1)],
            itemKind: .series
        )
        XCTAssertEqual(byline?.label, "Directed by")
        XCTAssertEqual(byline?.people.map(\.name), ["Director"])
    }

    func testHeroSizeCompactIsShorterThanTall() {
        let size = CGSize(width: 390, height: 844)
        XCTAssertLessThan(
            HeroSizePreferences.compact.height(for: size),
            HeroSizePreferences.tall.height(for: size)
        )
    }

    private func person(_ name: String, _ role: String, rank: Int) -> CreditPerson {
        CreditPerson(id: name, name: name, roleLabel: role, imageTag: nil, rank: rank)
    }
}
