import XCTest
@testable import Zelefin

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
final class LiveActivityAttributesTests: XCTestCase {
    func testContentStateDefaultsAccentAndPaused() throws {
        let state = ZelefinActivityAttributes.ContentState(statusLine: "Starting…")
        XCTAssertEqual(state.accentHex, ZelefinActivityAttributes.ContentState.defaultAccentHex)
        XCTAssertFalse(state.isPaused)
        XCTAssertNil(state.badgeLabel)
        XCTAssertEqual(state.clampedFraction, 0)
    }

    func testContentStateDecodesMissingAccent() throws {
        let json = """
        {"statusLine":"Hi","isFinished":false,"isFailed":false}
        """.data(using: .utf8)!
        let state = try JSONDecoder().decode(ZelefinActivityAttributes.ContentState.self, from: json)
        XCTAssertEqual(state.accentHex, ZelefinActivityAttributes.ContentState.defaultAccentHex)
        XCTAssertFalse(state.isPaused)
    }

    func testKindsAreStableRawValues() {
        XCTAssertEqual(ZelefinActivityKind.download.rawValue, "download")
        XCTAssertEqual(ZelefinActivityKind.playback.rawValue, "playback")
        XCTAssertEqual(ZelefinActivityKind.syncPlay.rawValue, "syncPlay")
        XCTAssertEqual(ZelefinActivityKind.liveTV.rawValue, "liveTV")
        XCTAssertEqual(ZelefinActivityKind.request.rawValue, "request")
        XCTAssertEqual(ZelefinActivityKind.catalog.rawValue, "catalog")
        XCTAssertEqual(ZelefinActivityKind.remoteSession.rawValue, "remoteSession")
    }

    func testKindRoundTrip() throws {
        for kind in [
            ZelefinActivityKind.download,
            .playback,
            .syncPlay,
            .liveTV,
            .request,
            .catalog,
            .remoteSession
        ] {
            let data = try JSONEncoder().encode(kind)
            let decoded = try JSONDecoder().decode(ZelefinActivityKind.self, from: data)
            XCTAssertEqual(decoded, kind)
        }
    }

    func testCatalogMinimumVisibleSeconds() {
        XCTAssertGreaterThan(CatalogActivityPresenter.minimumVisibleSeconds, 1)
    }

    func testRemoteSessionsPreferenceDefaultsOff() {
        let key = RemoteSessionActivityPresenter.preferenceKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key))
    }
}
#endif
