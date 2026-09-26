# App Review demo

Sample library used on the sign-in screen so App Review can open Zelefin without a Jellyfin server.

To remove it later:

1. Delete this `ReviewDemo` folder.
2. Remove the `ReviewDemo` calls from `ConnectView.swift` and `SessionStore.swift`.
3. Restore `final class JellyfinLibraryClient: Sendable` in `JellyfinLibraryClient.swift`.
4. Delete `ZelefinTests/ReviewDemoTests.swift`.

Or hide the sign-in button only: set `ReviewDemo.isEnabled` to `false`.
