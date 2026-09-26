import XCTest
@testable import Zelefin

final class JellyfinServerCapabilitiesTests: XCTestCase {
    func testParsesJellyfin12AndReleaseCandidates() {
        for version in ["12.0.0", "12.0.0-rc7", "12.1.2"] {
            let caps = JellyfinServerCapabilities(version: version)
            XCTAssertEqual(caps.generation, .jellyfin12Plus, version)
            XCTAssertEqual(caps.itemCollectionsAvailability, true, version)
            XCTAssertTrue(caps.prefersPlaybackInfoBody, version)
        }
    }

    func testParsesJellyfin10Family() {
        for version in ["10.11.11", "10.10.7", "10.9.11"] {
            let caps = JellyfinServerCapabilities(version: version)
            XCTAssertEqual(caps.generation, .jellyfin10, version)
            XCTAssertEqual(caps.itemCollectionsAvailability, false, version)
            XCTAssertFalse(caps.prefersPlaybackInfoBody, version)
        }
    }

    func testUnknownWhenVersionMissing() {
        for version in [nil, "", "dev", "x.y"] as [String?] {
            let caps = JellyfinServerCapabilities(version: version)
            XCTAssertEqual(caps.generation, .unknown)
            XCTAssertNil(caps.itemCollectionsAvailability)
            XCTAssertFalse(caps.prefersPlaybackInfoBody)
        }
    }

    func testSavedSessionDecodesWithoutServerVersion() throws {
        let json = """
        {
          "serverURL": "https://jellyfin.example",
          "accessToken": "token",
          "userID": "user",
          "userName": "Ada",
          "deviceID": "device"
        }
        """.data(using: .utf8)!
        let saved = try JSONDecoder().decode(SavedSession.self, from: json)
        XCTAssertNil(saved.serverVersion)
    }

    func testAccountBoxMigratesALegacySingleSession() throws {
        let json = """
        {
          "serverURL": "https://jellyfin.example",
          "accessToken": "token",
          "userID": "user",
          "userName": "Ada",
          "deviceID": "device"
        }
        """.data(using: .utf8)!
        let box = try SavedAccountBox.decode(from: json)
        XCTAssertEqual(box.accounts.count, 1)
        XCTAssertEqual(box.current?.userName, "Ada")
        XCTAssertEqual(box.currentID, box.current?.accountID)
    }

    func testAccountBoxUpsertsAndRemovesUsers() {
        var box = SavedAccountBox(accounts: [], currentID: "")
        let ada = SavedSession(
            serverURL: URL(string: "https://jellyfin.example")!,
            accessToken: "a",
            userID: "1",
            userName: "Ada",
            deviceID: "device"
        )
        let bob = SavedSession(
            serverURL: URL(string: "https://jellyfin.example")!,
            accessToken: "b",
            userID: "2",
            userName: "Bob",
            deviceID: "device"
        )
        box.upsert(ada)
        box.upsert(bob)
        XCTAssertEqual(box.current?.userName, "Bob")
        XCTAssertEqual(box.accounts.map(\.userName), ["Ada", "Bob"])
        box.upsert(
            SavedSession(
                serverURL: ada.serverURL,
                accessToken: "a2",
                userID: ada.userID,
                userName: ada.userName,
                deviceID: ada.deviceID
            ),
            select: false
        )
        XCTAssertEqual(box.current?.userName, "Bob")
        XCTAssertEqual(box.accounts.first { $0.userID == "1" }?.accessToken, "a2")
        XCTAssertEqual(box.remove(id: bob.accountID)?.userName, "Ada")
        XCTAssertEqual(box.accounts.map(\.userName), ["Ada"])
    }
}
