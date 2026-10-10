# Zelefin (Android)

The Android app. iPhone and iPad live in `../IOS/`. Product overview, full feature list, and server notes are in the [repository README](../README.md).

Native Jellyfin and Silo client. Emby and Plex are coming. There is no Zelefin Plus, no subscription, and no in-app purchase.

Open the `Android/` folder in Android Studio. Sign in with your own server.

## Android-only in this tree

- Material 3 chrome: edge-to-edge navigation bar, accent-tinted surfaces, settings hub
- Chromecast
- Media3 / ExoPlayer and optional mpv
- Dock tab names on by default

Live TV, Picture-in-Picture, and AirPlay are iOS-only in this build.

Everything else in the root README (home, library, search, Discover, downloads, SyncPlay, sessions, messages, notifications, Jellyfin admin) is on Android as well.

## Requirements

- Android 8 (API 26) or later
- A Jellyfin or Silo server you can reach from the device

## Open in Android Studio

1. Open the `Android/` folder.
2. Pick an emulator or a device with USB debugging.
3. Run the `app` configuration.

## License

See [LICENSE](../LICENSE).
