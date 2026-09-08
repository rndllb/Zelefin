import UIKit
import XCTest
@testable import Zelefin

final class ServerURLTests: XCTestCase {
    func testNormalizeDefaultsToHTTPSAndKeepsSubpath() throws {
        let url = try ServerURL.normalize("jellyfin.example.com/jellyfin/")
        XCTAssertEqual(url.absoluteString, "https://jellyfin.example.com/jellyfin")
    }

    func testNormalizeKeepsHTTPForLAN() throws {
        let url = try ServerURL.normalize("http://192.168.1.12:8096/")
        XCTAssertEqual(url.absoluteString, "http://192.168.1.12:8096")
    }

    func testJoinKeepsReverseProxySubpath() {
        let base = URL(string: "https://media.example.com/jellyfin")!
        let url = ServerURL.resolve(base: base, path: "/Items/abc/Images/Primary")
        XCTAssertEqual(url?.absoluteString, "https://media.example.com/jellyfin/Items/abc/Images/Primary")
    }

    func testRewritesLocalhostTranscodeOntoPublicOrigin() {
        let base = URL(string: "https://jellyfin.example.com/jellyfin")!
        let leaked = "http://127.0.0.1:8096/Videos/abc/stream.m3u8?PlaySessionId=1"
        let url = ServerURL.resolve(base: base, path: leaked, token: "secret")
        XCTAssertEqual(
            url?.absoluteString,
            "https://jellyfin.example.com/jellyfin/Videos/abc/stream.m3u8?PlaySessionId=1&api_key=secret"
        )
    }

    func testRewritesPrivateLANHost() {
        let base = URL(string: "https://cf.example.com")!
        let url = ServerURL.rewriteIfNeeded(
            URL(string: "http://192.168.4.20:8096/Videos/x")!,
            publicBase: base
        )
        XCTAssertEqual(url.absoluteString, "https://cf.example.com/Videos/x")
    }

    func testDoesNotRewriteMatchingPublicHost() {
        let base = URL(string: "https://jellyfin.example.com")!
        let original = URL(string: "https://jellyfin.example.com/Videos/x")!
        XCTAssertEqual(ServerURL.rewriteIfNeeded(original, publicBase: base), original)
    }

    func testDockerHostnameIsInternal() {
        XCTAssertTrue(ServerURL.isInternalHost("jellyfin"))
        XCTAssertTrue(ServerURL.isInternalHost("localhost"))
        XCTAssertTrue(ServerURL.isInternalHost("10.8.0.2"))
        XCTAssertFalse(ServerURL.isInternalHost("jellyfin.example.com"))
    }

    func testAppendsAPIKeyWithoutDroppingQuery() {
        let base = URL(string: "https://example.com")!
        let url = ServerURL.resolve(base: base, path: "/Videos/1/stream.ts?static=true", token: "tok")
        XCTAssertEqual(url?.absoluteString, "https://example.com/Videos/1/stream.ts?static=true&api_key=tok")
    }

    func testAppendingQueryKeepsReverseProxyPath() {
        let base = URL(string: "https://media.example.com/jellyfin")!
        let path = ServerURL.resolve(base: base, path: "/Items")!
        let url = ServerURL.appending(
            [
                ("recursive", "true"),
                ("includeItemTypes", "Series"),
                ("parentId", "abc"),
            ],
            to: path
        )
        XCTAssertEqual(
            url.absoluteString,
            "https://media.example.com/jellyfin/Items?recursive=true&includeItemTypes=Series&parentId=abc"
        )
    }

    func testAppendingQueryKeepsExistingItems() {
        let url = URL(string: "https://example.com/Items?userId=1")!
        let result = ServerURL.appending([("recursive", "true")], to: url)
        XCTAssertEqual(result.absoluteString, "https://example.com/Items?userId=1&recursive=true")
    }

    func testAppendingEmptyQueryLeavesURLUnchanged() {
        let url = URL(string: "https://example.com/Items")!
        XCTAssertEqual(ServerURL.appending([], to: url), url)
    }
}

final class ServerReachabilityTests: XCTestCase {
    func testReachableMessageAndFlag() {
        let result = ServerReachability.reachable(serverName: "Home", version: "10.10")
        XCTAssertTrue(result.isReachable)
        XCTAssertEqual(result.message, "Reached Home (10.10)")
    }

    func testAuthenticationRequiredIsStillReachable() {
        let result = ServerReachability.reachableRequiringAuthentication
        XCTAssertTrue(result.isReachable)
        XCTAssertEqual(
            result.message,
            "Reached the server, but it requires auth at the public-info endpoint."
        )
    }

    func testAccessGatewayErrorIsNotReachable() {
        let result = ServerReachability(error: ZelefinError.accessGateway)
        XCTAssertEqual(result, .blockedByAccessGateway)
        XCTAssertFalse(result.isReachable)
        XCTAssertEqual(result.message, ZelefinError.accessGateway.errorDescription)
    }

    func testExplainsTimedOutURLError() {
        let result = ServerReachability(error: URLError(.timedOut))
        XCTAssertEqual(result, .failed(description: "The request timed out."))
        XCTAssertFalse(result.isReachable)
    }

    func testExplainsUnknownHost() {
        XCTAssertEqual(
            ServerReachability.explanation(for: URLError(.cannotFindHost)),
            "Couldn’t find that host. Check the URL."
        )
    }
}

final class AccessGatewayTests: XCTestCase {
    func testHeadersCoverCloudflareAndPangolin() {
        let headers = AccessGateway.headers(clientID: "abc.access", clientSecret: "super-secret")
        XCTAssertEqual(headers["CF-Access-Client-Id"], "abc.access")
        XCTAssertEqual(headers["CF-Access-Client-Secret"], "super-secret")
        XCTAssertEqual(headers["P-Access-Token-Id"], "abc.access")
        XCTAssertEqual(headers["P-Access-Token"], "super-secret")
    }

    func testEmptyCredentialsSendNoHeaders() {
        XCTAssertTrue(AccessGateway.headers(clientID: "  ", clientSecret: "").isEmpty)
    }

    func testDetectsCloudflareAccessRedirect() {
        let response = HTTPURLResponse(
            url: URL(string: "https://jellyfin.example.com/System/Info/Public")!,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Location": "https://jellyfin.example.com.cloudflareaccess.com/cdn-cgi/access/login",
                "Content-Type": "text/html"
            ]
        )!
        XCTAssertTrue(AccessGateway.isChallenge(response: response, data: Data("<html></html>".utf8)))
    }

    func testJSONSuccessIsNotAChallenge() {
        let response = HTTPURLResponse(
            url: URL(string: "https://jellyfin.example.com/System/Info/Public")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        XCTAssertFalse(AccessGateway.isChallenge(response: response, data: Data("{\"ServerName\":\"JF\"}".utf8)))
    }
}

final class ProfileImageTests: XCTestCase {
    func testJellyfinUploadBodyIsBase64NotRawJPEG() {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        let body = JellyfinImagePayload.requestBody(imageJPEG: jpeg)
        XCTAssertNotEqual(body, jpeg)
        XCTAssertEqual(Data(base64Encoded: body), jpeg)
    }

    func testEncoderProducesJPEGBytes() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let jpeg = ProfileImageEncoder.jpegData(from: image)
        XCTAssertNotNil(jpeg)
        XCTAssertEqual(jpeg?.prefix(2), Data([0xFF, 0xD8]))
        XCTAssertEqual(Data(base64Encoded: JellyfinImagePayload.requestBody(imageJPEG: jpeg!)), jpeg)
    }

    func testSessionSocketUsesWebSocketSchemeAndAuthQuery() {
        let https = URL(string: "https://media.example.com/jellyfin/")!
        let socket = ServerURL.sessionSocket(base: https, token: "tok", deviceID: "dev-1")
        XCTAssertEqual(socket?.scheme, "wss")
        XCTAssertEqual(socket?.path, "/jellyfin/socket")
        XCTAssertEqual(socket?.value(for: "api_key"), "tok")
        XCTAssertEqual(socket?.value(for: "deviceId"), "dev-1")

        let lan = URL(string: "http://192.168.1.12:8096")!
        XCTAssertEqual(
            ServerURL.sessionSocket(base: lan, token: "tok", deviceID: "dev-1")?.scheme,
            "ws"
        )
    }

    func testLanAddressDefaultsToHTTP() throws {
        XCTAssertEqual(
            try ServerURL.normalizeLanAddress("192.168.1.100:8096").absoluteString,
            "http://192.168.1.100:8096"
        )
        XCTAssertEqual(
            try ServerURL.normalizeLanAddress("jellyfin.example.com").absoluteString,
            "https://jellyfin.example.com"
        )
    }
}

private extension URL {
    func value(for name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }
}
