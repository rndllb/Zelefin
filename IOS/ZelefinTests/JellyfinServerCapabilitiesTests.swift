import JellyfinAPI
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

    func testAccountBoxDropsRetiredSiloNativeSignIns() throws {
        let json = """
        {
          "currentID": "silo.example|7",
          "accounts": [
            {
              "serverURL": "https://silo.example",
              "accessToken": "silo-token",
              "userID": "7",
              "userName": "Ada",
              "deviceID": "device",
              "backend": "silo",
              "profileID": "p1",
              "isPrimaryProfile": true
            },
            {
              "serverURL": "https://jellyfin.example",
              "accessToken": "token",
              "userID": "user",
              "userName": "Bob",
              "deviceID": "device",
              "backend": "jellyfin"
            }
          ]
        }
        """.data(using: .utf8)!
        let box = try SavedAccountBox.decode(from: json)
        XCTAssertEqual(box.retiredSiloAccounts, 1)
        XCTAssertEqual(box.accounts.map(\.userName), ["Bob"])
        XCTAssertEqual(box.current?.userName, "Bob")
        XCTAssertEqual(box.current?.isSiloServer, false)
    }

    func testSiloServerFlagRoundTrips() throws {
        let saved = SavedSession(
            serverURL: URL(string: "https://silo.example:8097")!,
            accessToken: "token",
            userID: "user",
            userName: "Kids",
            deviceID: "device",
            isSiloServer: true
        )
        let decoded = try JSONDecoder().decode(SavedSession.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(decoded, saved)
        XCTAssertTrue(decoded.isSiloServer)
    }

    func testSiloUsersShowOnlyTheProfileName() throws {
        XCTAssertEqual(SavedSession.displayName("ada#Kids", isSiloServer: true), "Kids")
        XCTAssertEqual(SavedSession.displayName("ada", isSiloServer: true), "ada")
        XCTAssertEqual(SavedSession.displayName("ada#", isSiloServer: true), "ada#")
        XCTAssertEqual(SavedSession.displayName("ada#Kids", isSiloServer: false), "ada#Kids")
        let saved = try JSONDecoder().decode(SavedSession.self, from: Data("""
        {"serverURL":"https://silo.example:8097","accessToken":"t","userID":"u","userName":"ada#Kids","deviceID":"d","isSiloServer":true}
        """.utf8))
        XCTAssertEqual(saved.userName, "Kids")
    }

    func testSiloIsRecognizedByItsLoginDisclaimer() {
        XCTAssertTrue(ServerProbe.isSiloDisclaimer(
            "Silo provides Jellyfin-compatible app support. Silo is not affiliated with or endorsed by the Jellyfin project."
        ))
        XCTAssertFalse(ServerProbe.isSiloDisclaimer(""))
        XCTAssertFalse(ServerProbe.isSiloDisclaimer("Welcome to the family media server."))
    }
}

final class UserViewsDecodingTests: XCTestCase {
    func testUnknownCollectionTypeKeepsTheOtherLibraries() throws {
        let json = """
        {
          "Items": [
            {"Id": "a1", "Name": "Movies", "Type": "CollectionFolder", "CollectionType": "movies"},
            {"Id": "b2", "Name": "Shows", "Type": "CollectionFolder", "CollectionType": "tvshows"},
            {"Id": "c3", "Name": "Everything", "Type": "CollectionFolder", "CollectionType": "mixed"}
          ],
          "TotalRecordCount": 3,
          "StartIndex": 0
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(BaseItemDtoQueryResult.self, from: json))
        let result = try ItemMapper.decodeViews(json)
        XCTAssertEqual(result.items?.map(\.name), ["Movies", "Shows", "Everything"])
        XCTAssertEqual(result.items?.map(\.collectionType), [.movies, .tvshows, nil])
        let kinds = (result.items ?? []).compactMap(ItemMapper.library(from:)).map(\.libraryKind)
        XCTAssertEqual(kinds, [.movies, .shows, .other])
    }
}

final class SiloAccountTests: XCTestCase {
    func testDecodesSiloSignInReplies() throws {
        let pair = try JSONDecoder().decode(SiloTokenPair.self, from: Data("""
        {"access_token":"a","refresh_token":"r","expires_in":900,
         "user":{"id":"7","username":"ada","email":"","role":"user","permissions":[],"download_allowed":true,"password_change_required":false}}
        """.utf8))
        XCTAssertEqual(pair.accessToken, "a")
        XCTAssertEqual(pair.refreshToken, "r")

        let profiles = try JSONDecoder().decode(SiloProfileCollection.self, from: Data("""
        {"avatar_upload_enabled":true,"max_advisory_age_supported":true,"require_advisory_age_supported":true,
         "items":[{"id":"p1","name":"Ada","avatar":"","avatar_source":"upload","avatar_url":"/api/v2/profiles/p1/avatar?v=2",
                   "has_pin":true,"is_child":false,"is_primary":true},
                  {"id":"p2","name":"Kids","avatar":"fox","avatar_source":"preset","has_pin":false,"is_child":true,"is_primary":false}]}
        """.utf8))
        XCTAssertTrue(profiles.avatarUploadEnabled)
        let ada = profiles.items[0].resolved(against: URL(string: "https://silo.example")!)
        XCTAssertEqual(ada.avatarURL?.absoluteString, "https://silo.example/api/v2/profiles/p1/avatar?v=2")
        XCTAssertTrue(ada.hasPin)
        XCTAssertTrue(ada.hasUploadedAvatar)
        XCTAssertTrue(profiles.items[1].isChild)
        XCTAssertNil(profiles.items[1].avatarURL)

        let preset = SiloProfile(
            id: "p3", name: "Fox", avatar: "preset:dicebear:fun-emoji:mango-otter",
            avatarURL: URL(string: "https://api.dicebear.com/9.x/fun-emoji/svg?seed=mango-otter&size=128"),
            hasPin: false, isChild: false, isPrimary: false, avatarSource: "preset"
        ).resolved(against: URL(string: "https://silo.example")!)
        XCTAssertEqual(preset.avatarURL?.path, "/9.x/fun-emoji/png")
        XCTAssertTrue(preset.hasAvatar)
        XCTAssertEqual(SiloProfileAvatars.presetRef("dicebear:fun-emoji:mango-otter"), "preset:dicebear:fun-emoji:mango-otter")

        let verified = try JSONDecoder().decode(SiloProfileVerification.self, from: Data("""
        {"valid":true,"profile_token":"pt","expires_at":"2026-10-23T05:00:00Z"}
        """.utf8))
        XCTAssertEqual(verified.profileToken, "pt")
    }

    func testConnectInfoGatesTheJellyfinCompatibleAddress() throws {
        func info(enabled: Bool, restart: Bool, url: String) throws -> SiloConnectInfo {
            try JSONDecoder().decode(SiloConnectInfo.self, from: Data("""
            {"jellyfin":{"enabled":\(enabled),"pending_restart":\(restart),"public_url":"\(url)","server_name":"Home"},
             "account":{"password_login_available":true}}
            """.utf8))
        }
        XCTAssertEqual(try info(enabled: true, restart: false, url: "https://silo.example:8097").compatibleURL().absoluteString,
                       "https://silo.example:8097")
        XCTAssertThrowsError(try info(enabled: false, restart: false, url: "https://silo.example:8097").compatibleURL()) {
            XCTAssertTrue($0.localizedDescription.contains("Turn on"))
        }
        XCTAssertThrowsError(try info(enabled: true, restart: true, url: "https://silo.example:8097").compatibleURL()) {
            XCTAssertTrue($0.localizedDescription.contains("Restart"))
        }
        XCTAssertThrowsError(try info(enabled: true, restart: false, url: "").compatibleURL()) {
            XCTAssertTrue($0.localizedDescription.contains("public address"))
        }
    }

    func testProblemDetailsBecomeTheMessage() {
        XCTAssertEqual(
            SiloAccountClient.problemMessage(in: Data("""
            {"title":"Validation failed","status":422,"detail":"The request did not pass validation; see errors.",
             "errors":[{"location":"header.x-profile-id","code":"required","detail":"The X-Profile-Id header is required."}]}
            """.utf8)),
            "The X-Profile-Id header is required."
        )
        XCTAssertEqual(
            SiloAccountClient.problemMessage(in: Data(#"{"title":"Unauthorized","status":401,"detail":"Incorrect username or password."}"#.utf8)),
            "Incorrect username or password."
        )
        XCTAssertNil(SiloAccountClient.problemMessage(in: Data("<html></html>".utf8)))
    }

    func testSiloLinkRoundTripsWithTheSession() throws {
        let link = SiloLink(
            nativeURL: URL(string: "https://silo.example")!,
            accessToken: "a",
            refreshToken: "r",
            profileID: "p1",
            profileName: "Ada",
            profileHasPin: true,
            profileToken: "pt"
        )
        let saved = SavedSession(
            serverURL: URL(string: "https://silo.example:8097")!,
            accessToken: "jf",
            userID: "u1",
            userName: "Ada",
            deviceID: "device",
            isSiloServer: true,
            siloLink: link
        )
        let decoded = try JSONDecoder().decode(SavedSession.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(decoded.siloLink, link)

        let plain = try JSONDecoder().decode(SavedSession.self, from: Data("""
        {"serverURL":"https://jellyfin.example","accessToken":"t","userID":"u","userName":"Bob","deviceID":"d","isSiloServer":false}
        """.utf8))
        XCTAssertNil(plain.siloLink)
    }
}
