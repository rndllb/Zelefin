import XCTest
import JellyfinAPI
@testable import Zelefin

final class RemoteControlTests: XCTestCase {
    func testPlaystateCommandsMapOntoPlayerActions() {
        XCTAssertEqual(RemotePlaybackAction.playstate(.pause, seekTicks: nil), .pause)
        XCTAssertEqual(RemotePlaybackAction.playstate(.unpause, seekTicks: nil), .play)
        XCTAssertEqual(RemotePlaybackAction.playstate(.playPause, seekTicks: nil), .playPause)
        XCTAssertEqual(RemotePlaybackAction.playstate(.stop, seekTicks: nil), .stop)
        XCTAssertEqual(RemotePlaybackAction.playstate(.nextTrack, seekTicks: nil), .next)
        XCTAssertEqual(RemotePlaybackAction.playstate(.rewind, seekTicks: nil), .skip(-10))
        XCTAssertEqual(RemotePlaybackAction.playstate(.seek, seekTicks: nil), nil)
        XCTAssertEqual(
            RemotePlaybackAction.playstate(.seek, seekTicks: 10_000_000),
            .seek(1)
        )
    }

    func testGeneralCommandsMapVolumeAndMute() {
        XCTAssertEqual(RemotePlaybackAction.general(.mute), .mute)
        XCTAssertEqual(RemotePlaybackAction.general(.unmute), .unmute)
        XCTAssertEqual(RemotePlaybackAction.general(.volumeUp), .volumeUp)
        XCTAssertEqual(RemotePlaybackAction.general(.playState), .playPause)
        XCTAssertNil(RemotePlaybackAction.general(.goHome))
    }

    func testInternetDatesWithAndWithoutFractionalSeconds() {
        XCTAssertNotNil(JellyfinJSONDate.date(from: "2026-09-11T03:12:00Z"))
        XCTAssertNotNil(JellyfinJSONDate.date(from: "2026-09-11T03:12:00.123Z"))
        XCTAssertNotNil(JellyfinJSONDate.date(from: "2026-09-11T03:12:00.1234567Z"))
        XCTAssertNotNil(JellyfinJSONDate.date(from: "2026-09-11T03:12:00.123456Z"))
        XCTAssertNotNil(JellyfinJSONDate.date(from: "2026-09-11T03:12:00+00:00"))
        XCTAssertNil(JellyfinJSONDate.date(from: "not-a-date"))
    }

    func testSessionListDecodesJellyfinFractionalDates() throws {
        let json = Data(
            #"""
            [{"Id":"tv","UserName":"Sam","DeviceId":"tv-1","Client":"Infuse","DeviceName":"Living Room","LastActivityDate":"2026-09-11T03:12:00.1234567Z","LastPlaybackCheckIn":"2026-09-11T03:12:00.1234567Z","NowPlayingItem":{"Name":"Dune","Id":"m1","Type":"Movie","ProductionYear":2021,"DateCreated":"2026-09-10T01:00:00.7654321Z"}}]
            """#.utf8
        )
        let dtos = try JellyfinJSONDate.decoder.decode([SessionInfoDto].self, from: json)
        XCTAssertEqual(dtos.count, 1)
        XCTAssertEqual(dtos[0].id, "tv")
        XCTAssertNotNil(dtos[0].lastActivityDate)
        XCTAssertEqual(PlaybackSession(dto: dtos[0])?.userName, "Sam")
        XCTAssertEqual(PlaybackSession(dto: dtos[0])?.nowPlaying?.name, "Dune")
    }

    func testSessionsWebsocketMessageWithFractionalDates() throws {
        let json = Data(
            #"""
            {"MessageType":"Sessions","MessageId":"1","Data":[{"Id":"tv","UserName":"Sam","LastActivityDate":"2026-09-11T03:12:00.1234567Z"}]}
            """#.utf8
        )
        let message = try JellyfinJSONDate.decoder.decode(OutboundWebSocketMessage.self, from: json)
        guard case let .sessionsMessage(payload) = message else {
            return XCTFail("expected Sessions")
        }
        XCTAssertEqual(payload.data?.first?.id, "tv")
        XCTAssertNotNil(payload.data?.first?.lastActivityDate)
    }

    func testCapabilitiesAdvertiseMediaControl() {
        XCTAssertEqual(RemoteControlProfile.capabilities.isSupportsMediaControl, true)
        XCTAssertEqual(RemoteControlProfile.capabilities.playableMediaTypes, [.video])
        XCTAssertTrue(RemoteControlProfile.capabilities.supportedCommands?.contains(.mute) == true)
        XCTAssertTrue(RemoteControlProfile.capabilities.supportedCommands?.contains(.displayMessage) == true)
    }

    func testDisplayMessageParsesGeneralCommandPayload() throws {
        let json = Data(
            #"""
            {"MessageType":"GeneralCommand","Data":{"Name":"DisplayMessage","Arguments":{"Header":"Zelefin","Text":"Server restart in 5 minutes","TimeoutMs":"8000"}}}
            """#.utf8
        )
        let message = SessionDisplayMessage.parse(json: json)
        XCTAssertEqual(message?.header, "Zelefin")
        XCTAssertEqual(message?.text, "Server restart in 5 minutes")
        XCTAssertEqual(message?.timeoutMs, 8000)
    }

    func testDisplayMessageParsesNumericTimeoutAndAlternateKeys() throws {
        let json = Data(
            #"""
            {"MessageType":"DisplayMessage","Data":{"header":"Admin","text":"Hello","timeoutMs":5000}}
            """#.utf8
        )
        let message = SessionDisplayMessage.parse(json: json)
        XCTAssertEqual(message?.header, "Admin")
        XCTAssertEqual(message?.text, "Hello")
        XCTAssertEqual(message?.timeoutMs, 5000)
    }

    func testDisplayMessageParsesPluginPush() {
        let userInfo: [AnyHashable: Any] = [
            "type": "sessionMessage",
            "kind": "sessionMessage",
            "title": "Admin",
            "body": "Hello from the dashboard"
        ]
        XCTAssertTrue(SessionDisplayMessage.isPush(userInfo))
        let message = SessionDisplayMessage.fromPush(userInfo)
        XCTAssertEqual(message?.header, "Admin")
        XCTAssertEqual(message?.text, "Hello from the dashboard")
        XCTAssertNil(LibraryAlertDestination.parse(userInfo))
    }
}
