# Zelefin

Native Jellyfin and Silo client for iPhone, iPad, and Android. Emby and Plex are next.

Open `IOS/Zelefin.xcodeproj` in Xcode, or `Android/` in Android Studio. Sign in with your own server. There is no Zelefin Plus, no subscription, and no in-app purchase.

## Servers

- **Jellyfin** and **Silo** work today. Sign in with a URL and an API key. Extra accounts sit in the profile sheet.
- **Emby** and **Plex** are coming. They are not in this build.
- The optional [Zelefin plugin](https://github.com/rndllb/Zelefin-Plugin) is Jellyfin-only. It sends lock-screen alerts and dashboard messages when the app is closed.

Silo hides Jellyfin-only tools (users, libraries, plugins, dashboard, activity, backups, branding, scheduled tasks, parental controls, hardware encoding).

## Features

- Home with continue watching, next up, recently added, and latest from each library
- Library rooms for movies, shows, collections, favorites, and playlists, with type, genre, year, rating, sort, randomize, and an A–Z jump
- Search the signed-in server, or Discover and request titles when Seerr is signed in
- Title detail: backdrop, overview, seasons, similar, people, chapters, special features, extras
- Cast and crew photos from the server, with a people browser
- Downloads for movies and episodes, with a Downloads tab and storage totals
- Playback: play, pause, skip, speed, audio, subtitles, chapters; resume from the server
- Direct play when the device can decode the file; transcode only when it cannot
- HDR, Dolby Vision, and Dolby Atmos shown when the file has them
- Cinema mode bumpers and intro / credits skip when the server provides them
- Playback and subtitle language preferences, plus subtitle size, color, and position
- Picture-in-picture and AirPlay on Apple; Chromecast, Media3 / ExoPlayer, and mpv on Android
- SyncPlay on Jellyfin, including with the official web client: the group waits, then plays together
- Live TV guide on iPhone and iPad (not on Android yet)
- Sessions: see other devices, send play and playstate, and send a Display Message
- In-app popup when a session message arrives while Zelefin is open; lock-screen notification when it is closed (Jellyfin plugin)
- Notifications for library new items, sessions starting, and user messages, with per-kind toggles
- Remote and dashboard on Jellyfin: other sessions, play queues, and send-to-device
- Server admin on Jellyfin (administrator accounts): users, libraries, plugins, scheduled tasks, activity log, backups, branding, scan libraries, dashboard
- Settings: appearance, home rows, playback, downloads, notifications, and which tabs sit in the dock
- Interface density, poster text, and theme; Android uses Material 3, with dock tab names on by default
- Review Demo on iPhone and iPad, a local bundled catalog that never calls a server

## Requirements

- iOS 26, iPhone or iPad
- Android 8 (API 26) or later
- A Jellyfin or Silo server you can reach from the device

## Open in Xcode

1. Open `IOS/Zelefin.xcodeproj`.
2. Pick an iPhone or iPad simulator, or a signed-in device.
3. Run.

`IOS/project.yml` is the XcodeGen spec if you need to regenerate the project.

## Open in Android Studio

1. Open the `Android/` folder.
2. Pick an emulator or a device with USB debugging.
3. Run the `app` configuration.

## Tests

```bash
cd IOS
xcodebuild test -scheme Zelefin -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Not in this build

Music, offline playback of already-transcoded copies beyond the Downloads tab, and a public App Store / Play Store listing. Emby and Plex sign-in ships later.

## License

See [LICENSE](LICENSE).
