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
