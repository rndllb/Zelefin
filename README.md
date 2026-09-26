# Zelefin

Native Jellyfin client for phones and tablets, also compatible with Silo. Sign in, browse, and Play stay free.

The iPhone and iPad app is in [`IOS/`](IOS/). The Android phone and tablet app is in [`Android/`](Android/).

## iOS

iPhone and iPad, iOS 18. The interface follows the Apple TV app: black ground, large titles, and a system tab bar. iPad uses a sidebar. Playback uses AVPlayer, with on-device Direct Play for containers AVPlayer will not open. The server transcodes only when the codec itself is outside that set.

Feature list, plugins, and Zelefin Plus: [IOS/README.md](IOS/README.md).

```bash
cd IOS
xcodegen generate
open Zelefin.xcodeproj
```

Select an iPhone or iPad and run. Sign in with a Jellyfin or Silo server URL, username, and password, or tap Try Review Demo. Local HTTP servers are allowed.

## Android

Phones and tablets, Android 8 (API 26) and later. Jetpack Compose and Media3. Same servers as iOS: Jellyfin and Silo, including Quick Connect, Silo household PIN, and Access Gateway headers.

This build covers sign-in, Home, Movies, Shows, Library, the title page, and play / resume. It does not yet include the rest of the iOS app (Live TV, downloads, SyncPlay, plugins, and the rest of Settings).

Open the `Android/` folder in Android Studio and run the `app` configuration. `minSdk` is 26, `compileSdk` and `targetSdk` are 35, and the Gradle wrapper expects Gradle 8.11.1. Local HTTP servers are allowed.

## Links

- App: [github.com/rndllb/Zelefin](https://github.com/rndllb/Zelefin)
- Plugin: [github.com/rndllb/Zelefin-Plugin](https://github.com/rndllb/Zelefin-Plugin)
- Site: [zelefin.app](https://zelefin.app)
