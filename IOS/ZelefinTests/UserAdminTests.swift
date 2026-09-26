import JellyfinAPI
import XCTest
@testable import Zelefin

final class UserPolicyDraftTests: XCTestCase {
    func testApplyingWritesPermissionsBitrateParentalAndLibraries() {
        let source = UserPolicy(
            authenticationProviderID: "auth",
            enableAllFolders: true,
            enabledFolders: ["keep-me"],
            isAdministrator: false,
            isDisabled: false,
            maxParentalRating: 10,
            passwordResetProviderID: "reset",
            remoteClientBitrateLimit: 0
        )
        var draft = UserPolicyDraft(policy: source)
        draft.isAdministrator = true
        draft.isDisabled = true
        draft.enableSubtitleManagement = true
        draft.remoteClientBitrateLimit = RemoteBitrateLimit.mbps8.rawValue
        draft.maxParentalRating = 4
        draft.blockUnratedItems = [.movie, .series]
        draft.enableAllFolders = false
        draft.enabledFolders = ["lib-b", "lib-a"]

        let next = draft.applying(to: source)
        XCTAssertEqual(next.authenticationProviderID, "auth")
        XCTAssertEqual(next.passwordResetProviderID, "reset")
        XCTAssertEqual(next.isAdministrator, true)
        XCTAssertEqual(next.isDisabled, true)
        XCTAssertEqual(next.enableSubtitleManagement, true)
        XCTAssertEqual(next.remoteClientBitrateLimit, 8_000_000)
        XCTAssertEqual(next.maxParentalRating, 4)
        XCTAssertEqual(next.blockUnratedItems, [.movie, .series])
        XCTAssertEqual(next.enableAllFolders, false)
        XCTAssertEqual(next.enabledFolders, ["lib-a", "lib-b"])
    }

    func testDraftReadsEditSubtitlesFromPolicy() {
        let source = UserPolicy(
            authenticationProviderID: "auth",
            enableSubtitleManagement: true,
            passwordResetProviderID: "reset"
        )
        XCTAssertTrue(UserPolicyDraft(policy: source).enableSubtitleManagement)
    }

    func testAllLibrariesClearsFolderAllowList() {
        let source = UserPolicy(
            authenticationProviderID: "auth",
            enableAllFolders: false,
            enabledFolders: ["only-this"],
            passwordResetProviderID: "reset"
        )
        var draft = UserPolicyDraft(policy: source)
        draft.enableAllFolders = true
        let next = draft.applying(to: source)
        XCTAssertEqual(next.enableAllFolders, true)
        XCTAssertEqual(next.enabledFolders, [])
    }

    func testRemoteBitrateKeepsUnknownCustomValue() {
        XCTAssertEqual(RemoteBitrateLimit.resolved(3_500_000), 3_500_000)
        XCTAssertEqual(RemoteBitrateLimit.resolved(-20), 0)
        XCTAssertEqual(RemoteBitrateLimit.resolved(0), 0)
    }

    func testServerUserSubtitleNamesAdminAndDisabled() {
        var dto = UserDto(id: "1", name: "Ada", policy: UserPolicy(
            authenticationProviderID: "auth",
            isAdministrator: true,
            isDisabled: true,
            passwordResetProviderID: "reset"
        ))
        XCTAssertEqual(ServerUserAccount(dto: dto).statusSubtitle, "Administrator · Disabled")
        dto.policy = UserPolicy(
            authenticationProviderID: "auth",
            isAdministrator: false,
            isDisabled: false,
            passwordResetProviderID: "reset"
        )
        XCTAssertEqual(ServerUserAccount(dto: dto).statusSubtitle, "User")
    }

    func testOnlyAdminsCanChangeAnotherUsersPhoto() {
        XCTAssertTrue(
            UserImageAdminPolicy.canChangePhoto(
                actorIsAdmin: true,
                actorUserID: "admin",
                targetUserID: "kid"
            )
        )
        XCTAssertTrue(
            UserImageAdminPolicy.canChangePhoto(
                actorIsAdmin: false,
                actorUserID: "kid",
                targetUserID: "kid"
            )
        )
        XCTAssertFalse(
            UserImageAdminPolicy.canChangePhoto(
                actorIsAdmin: false,
                actorUserID: "kid",
                targetUserID: "admin"
            )
        )
        XCTAssertFalse(
            UserImageAdminPolicy.canChangePhoto(
                actorIsAdmin: true,
                actorUserID: "admin",
                targetUserID: ""
            )
        )
    }

    func testRemoteArtworkKindsMapToJellyfinImageTypes() {
        XCTAssertEqual(RemoteArtworkKind.poster.jellyfinTypeName, "Primary")
        XCTAssertEqual(RemoteArtworkKind.thumbnail.jellyfinTypeName, "Thumb")
        XCTAssertEqual(RemoteArtworkKind.logo.jellyfinTypeName, "Logo")
        XCTAssertEqual(RemoteArtworkKind.backdrop.jellyfinTypeName, "Backdrop")
    }
}
