# Zelefin

Native Jellyfin client for iPhone and iPad. The interface follows the Apple TV app: black ground, large titles, Continue Watching landscape cards, poster rows, and the system tab bar. iPad uses a sidebar.

Playback uses AVPlayer so HDR10, Dolby Vision, and Dolby Atmos stay on Apple’s decoder. MKV and other containers AVPlayer will not open are Direct Played on device (FFmpeg demux, VideoToolbox decode, sample-buffer presentation). The server transcodes only when the codec itself is outside that set.

## Features

### Sign in

- Branded sign-in with the Zelefin mark
- Jellyfin server URL, username, and password
- Try Review Demo on the sign-in screen: a sample library for App Review (Home, Movies, Shows, title pages, and Play) with no Jellyfin server. Hide the button with `ReviewDemo.isEnabled`, or delete `Zelefin/ReviewDemo` after approval.
- Quick Connect from another signed-in device
- Test connection before login
- Access Gateway tokens for Cloudflare Zero Trust or Pangolin, sent on every request including artwork and playback
- Multiple saved accounts on this device, with switch-user and Add User from Profile
- Profile photo (camera or photo library) and password change
- Access token on Profile, hidden until you reveal it, with copy

### Home

- Featured hero of latest movies and shows
- Continue Watching and Next Up, or one combined Continue Watching row (Interface settings)
- Recently added rows per library, collections, and genres
- Quality marks on posters when the file is 4K, HD, HDR / Dolby Vision, or Atmos (movies and episodes; series posters stay unmarked when there is no file)
- Pull to refresh, cache-first loads
- Long-press: play, download, mark watched or unwatched, go to the show or movie, add subtitles when this account can edit them
- Remove from Continue Watching or Next Up when Jellyfin Enhanced is installed, without clearing progress

### Browse

- Tabs for Home, Movies, Shows, Collections, Library, and Favorites (Collections and Favorites hidden by default)
- Reorder or hide tabs in Interface settings; iPad can also Edit the sidebar
- Favorites is movies and series marked favorite on the server; it is also listed under Library
- Movies and Shows load the full catalog, not the first page
- Sort by name, date added, date played, release date, runtime, play count, ratings, parental rating, or random
- Filter by played, unplayed, favorite, continue watching, genres, years, studios, tags, languages, ratings, subtitles, trailers, extras, and video kind (SD / HD / 4K, DVD, Blu-ray, ISO)
- Library lists every Jellyfin library on the server, plus Collections, Favorites, Downloaded, and Genres
- Indexing status sits under the header while the catalog is still catching up

### Title details

- Play / resume with progress
- Season episode carousel
- Related titles, cast, and collections
- About row: title and synopsis card, Tomatometer when Jellyfin has a critic score, and an age-guidance card from the official rating
- TMDB reviews, household write/edit reviews, and awards when Jellyfin Enhanced is installed (awards need Show Awards on the plugin; TMDB reviews need a TMDB key)
- MORE on the About card opens the full description; MORE on the hero opens the info sheet
- Information, Languages, and File lists on the title page (studio, runtime, audio, subtitles, container, bitrate)
- Download and share from the same pill
- Add Subtitles on movies and episodes when this account can edit subtitles (administrator or Edit Subtitles) and Open Subtitles is on the server
- Share a `zelefin://` link plus the Jellyfin web URL so another install or a browser can open the title

### Notifications

Zelefin watches the server from this device. It does not need a Jellyfin notification plugin.

- New movies, shows, and episodes added after this device has already seen the library: a banner on this iPhone or iPad, and tapping it opens that title
- Signing out and back in does not replay titles that were already on the server
- Administrators also get streams started, users coming online on another device, scheduled tasks starting, and new Seerr requests when Seerr is signed in under Plugins
- Settings → Notifications to turn each kind on or off
- Stream and online alerts follow Jellyfin session updates while the app is open; library adds also fire when Jellyfin reports a library change
- iOS may also refresh in the background. That is not instant push from Jellyfin; opening the app always checks right away

### Playback

- AVPlayer for Apple-compatible Direct Play and remuxed HLS
- Zelefin Direct Play for MKV and similar containers
- Optional native video player (AVPlayer only; MKV remuxes on the server)
- Prefer fMP4 or MPEG-TS when using the native player
- Audio and subtitle track selection, including sidecar files and on-device cues for Direct Play
- Skip intro and credits when Intro Skipper is installed (manual buttons, optional auto-skip)
- Auto play next episode
- Skip intervals and default playback speed
- Adaptive bitrate on by default: measures Wi-Fi or cellular to the Jellyfin server, Direct Plays when the file fits, transcodes when it does not
- During playback, steps down after a stall and back up when the buffer stays healthy (one quality step at a time; a short hitch while the stream restarts)
- Settings → Playback: Maximum Quality ceiling, and Test with Demo File to measure this connection
- Manual quality in the player still wins for that title
- Movies and episodes resume from the saved playhead (including transcoded streams)
- Picture in Picture and AirPlay
- Playback stats overlay
- Progress reported back to Jellyfin
- Background audio

### Plugins

Settings → Plugins shows what this Jellyfin server actually has installed. Zelefin does not install plugins; it uses the ones already on the server.

- **Intro Skipper** — Skip Intro and Skip Credits during playback. Optional auto-skip for intros and credits.
- **Open Subtitles** — Search and download a subtitle onto the server from More on a movie or episode, Search, or the player. Requires an administrator or a user with Edit Subtitles. Sidecar files (`.srt` and similar) show in the subtitle list on Direct Play. The title page refreshes after a download so you do not have to leave and come back.
- **Jellyfin Enhanced** — Remove from Continue Watching or Next Up without changing watched state. TMDB reviews, household reviews, and awards on the title page. Detection uses the plugin list, or `/JellyfinEnhanced/version` when `/Plugins` is admin-only.
- **Seerr / Jellyseerr** — Sign in here with your Jellyfin username and password, then discover and request titles from Search. Not a Jellyfin plugin; a separate request app that talks to Radarr and Sonarr.

### Search and requests

- Search the Jellyfin library
- Discover and request through Seerr or Jellyseerr (sign in under Plugins)
- Trending, popular, upcoming, genres, studios, and networks
- Request movies and shows with Radarr / Sonarr server, quality, folder, and season picks

### Downloads

- Download titles for offline play
- Progress on posters, detail, and Library → Downloaded
- Local playback with watch progress

### Sessions

- Who is connected and what they are playing
- Transcode details (codec, resolution, bitrate, reason)
- Remote control of other clients that accept it (play, pause, skip, volume)
- This device also accepts remote control from Jellyfin while the socket stays up
- This device reports its marketing model name to Jellyfin, such as iPhone 17 Pro

### Scheduled tasks

- Administrators can open Scheduled Tasks from Settings or the profile menu
- Start or cancel a task, and watch progress while it runs
- Tapping a “scheduled task started” notification opens this list

### Users

- Administrators can manage server users from Settings: photo, rename, password set/reset, administrator flag, Edit Subtitles, disable account, remote bitrate cap, parental max rating, block unrated types, and per-library access
- Edit Subtitles (`EnableSubtitleManagement`) lets a non-admin search and download subtitles the same way an administrator can

### Network

- Remote URL and optional local URL
- Auto-switch to the local address on configured home Wi-Fi
- Access Gateway for servers behind Cloudflare or Pangolin

### Cache

- Artwork broken down as posters, backdrops, logos, and other
- Metadata for Home, catalogs, and title details
- Clear per kind or all
- Auto-refresh missing images and metadata

### Interface

- Accent color for buttons, highlights, and icons. Cyan (the login button) is the default; presets and a custom hex are in Interface settings
- Combine Continue Watching and Next Up
- Drag to reorder tabs, hide any tab except Home, reset to defaults

## Open in Xcode

```bash
cd Zelefin
xcodegen generate
open Zelefin.xcodeproj
```

Select an iPhone or iPad destination and run. Sign in with your Jellyfin server URL, username, and password, or tap Try Review Demo to browse a sample library. Local HTTP servers are allowed.

Requires iOS 18. This build is iPhone and iPad only.

## Not in this build

Music, live TV / DVR, SyncPlay, photos, and books are not first-class experiences. A music or live TV library may still appear in Library if the server has one.
