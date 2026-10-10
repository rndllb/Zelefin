# Zelefin (iOS)

The iPhone and iPad app. Android lives in `../Android/`. Product overview, full feature list, and server notes are in the [repository README](../README.md).

Native Jellyfin and Silo client. Emby and Plex are coming. There is no Zelefin Plus, no subscription, and no in-app purchase.

Open `Zelefin.xcodeproj` in Xcode. Sign in with your own server.

## iOS-only in this tree

- Live TV guide
- Picture-in-picture and AirPlay
- Review Demo, a local bundled catalog that never calls a server
- AVFoundation / AVPlayerKit playback
- Catalog A–Z rail and subtitle appearance (size, color, position)

Everything else in the root README (home, library, search, Discover, downloads, SyncPlay, sessions, messages, notifications, Jellyfin admin) is on iPhone and iPad as well.

## Requirements

- iOS 26, iPhone or iPad
- A Jellyfin or Silo server you can reach from the device

## Open in Xcode

1. Open `Zelefin.xcodeproj`.
2. Pick an iPhone or iPad simulator, or a signed-in device.
3. Run.

`project.yml` is the XcodeGen spec if you need to regenerate the project.

## Tests

```bash
xcodebuild test -scheme Zelefin -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## License

See [LICENSE](../LICENSE).
