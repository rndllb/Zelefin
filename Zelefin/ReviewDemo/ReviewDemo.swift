import Foundation

/// App Review sample library. Isolated so it can be deleted after approval.
enum ReviewDemo {
    /// Hide the sign-in button without deleting this folder.
    static let isEnabled = false

    static let userID = "zelefin.review.demo"
    static let userName = "Reviewer"
    static let serverName = "Zelefin Review"
    static let accessToken = "review-demo-token"
    static let playSessionID = "review-demo-play"

    static let serverURL = URL(string: "https://review.zelefin.app")!

    static let session = SavedSession(
        serverURL: serverURL,
        accessToken: accessToken,
        userID: userID,
        userName: userName,
        deviceID: DeviceIdentity.deviceID(),
        userImageTag: nil,
        serverVersion: "10.10.0",
        serverName: serverName
    )

    static func isSession(_ session: SavedSession?) -> Bool {
        session?.userID == userID
    }

    static func libraryClient(deviceID: String) -> JellyfinLibraryClient {
        let client = JellyfinNetworking.client(
            url: serverURL,
            accessToken: accessToken,
            deviceID: deviceID
        )
        return ReviewDemoLibraryClient(client: client, userID: userID, serverVersion: session.serverVersion)
    }
}
