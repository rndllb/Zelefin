import XCTest
@testable import Zelefin

final class HomeNetworkTests: XCTestCase {
    func testStaysOnRemoteUntilHomeWiFiMatches() {
        XCTAssertEqual(
            HomeNetworkResolver.route(
                autoSwitch: true,
                hasLocalURL: true,
                homeSSIDs: ["Randll"],
                currentSSID: nil,
                ssidReadable: true
            ),
            .remote
        )
        XCTAssertEqual(
            HomeNetworkResolver.route(
                autoSwitch: true,
                hasLocalURL: true,
                homeSSIDs: ["Randll"],
                currentSSID: "CoffeeShop",
                ssidReadable: true
            ),
            .remote
        )
        XCTAssertEqual(
            HomeNetworkResolver.route(
                autoSwitch: true,
                hasLocalURL: true,
                homeSSIDs: ["Randll"],
                currentSSID: "randll",
                ssidReadable: true
            ),
            .local
        )
    }

    func testAutoSwitchOffAlwaysUsesRemote() {
        XCTAssertEqual(
            HomeNetworkResolver.route(
                autoSwitch: false,
                hasLocalURL: true,
                homeSSIDs: ["Randll"],
                currentSSID: "Randll",
                ssidReadable: true
            ),
            .remote
        )
    }

    func testMissingLocalURLStaysRemote() {
        XCTAssertEqual(
            HomeNetworkResolver.route(
                autoSwitch: true,
                hasLocalURL: false,
                homeSSIDs: ["Randll"],
                currentSSID: "Randll",
                ssidReadable: true
            ),
            .remote
        )
    }

    func testPlatformsWithoutSSIDUseLocalWhenConfigured() {
        XCTAssertEqual(
            HomeNetworkResolver.route(
                autoSwitch: true,
                hasLocalURL: true,
                homeSSIDs: [],
                currentSSID: nil,
                ssidReadable: false
            ),
            .local
        )
    }

    func testActiveURLFollowsRoute() {
        let remote = URL(string: "https://jellyfin.example.com")!
        let local = URL(string: "http://192.168.1.100:8096")!
        XCTAssertEqual(HomeNetworkResolver.activeURL(remote: remote, local: local, route: .remote), remote)
        XCTAssertEqual(HomeNetworkResolver.activeURL(remote: remote, local: local, route: .local), local)
        XCTAssertEqual(HomeNetworkResolver.activeURL(remote: remote, local: nil, route: .local), remote)
    }

    func testAddingSSIDIsCaseInsensitiveAndSorted() {
        XCTAssertEqual(HomeNetworkResolver.adding("Randll", to: ["Office"]), ["Office", "Randll"])
        XCTAssertEqual(HomeNetworkResolver.adding("randll", to: ["Randll"]), ["Randll"])
        XCTAssertEqual(HomeNetworkResolver.adding("  ", to: ["Office"]), ["Office"])
    }

    func testSameEndpointIgnoresTrailingSlash() {
        let a = URL(string: "https://jellyfin.example.com/jellyfin")!
        let b = URL(string: "https://jellyfin.example.com/jellyfin/")!
        XCTAssertTrue(HomeNetworkResolver.isSameEndpoint(a, b))
    }
}
