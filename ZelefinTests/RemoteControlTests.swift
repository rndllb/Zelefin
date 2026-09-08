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

    func testCapabilitiesAdvertiseMediaControl() {
        XCTAssertEqual(RemoteControlProfile.capabilities.isSupportsMediaControl, true)
        XCTAssertEqual(RemoteControlProfile.capabilities.playableMediaTypes, [.video])
        XCTAssertTrue(RemoteControlProfile.capabilities.supportedCommands?.contains(.mute) == true)
    }
}
