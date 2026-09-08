# Zelefin

Native Jellyfin client for iPhone and iPad. The interface follows the Apple TV app: black ground, large titles, Continue Watching landscape cards, poster rows, and the system tab bar. iPad uses a sidebar.

Playback uses AVPlayer so HDR10, Dolby Vision, and Dolby Atmos stay on Apple’s decoder. MKV and other containers AVPlayer will not open are Direct Played on device (FFmpeg demux, VideoToolbox decode, sample-buffer presentation). The server transcodes only when the codec itself is outside that set.

## Features

### Sign in

- Jellyfin server URL, username, and password
- Quick Connect from another signed-in device
- Test connection before login
- Access Gateway tokens for Cloudflare Zero Trust or Pangolin, sent on every request including artwork and playback
- Multiple saved accounts on this device, with switch-user and Add User from Profile
- Profile photo (camera or photo library) and password change

### Home

- Featured hero of latest movies and shows
- Continue Watching and Next Up, or one combined Continue Watching row (Interface settings)
- Recently added rows per library, collections, and genres
- Pull to refresh, cache-first loads
- Long-press: play, download, mark watched or unwatched, go to the show or movie, add subtitles when Open Subtitles is installed

### Browse

- Tabs for Home, Movies, Shows, Collections, and Library (Collections hidden by default)
- Reorder or hide tabs in Interface settings; iPad can also Edit the sidebar
- Movies and Shows load the full catalog, not the first page
- Sort by name, date added, date played, release date, runtime, play count, ratings, parental rating, or random
- Filter by played, unplayed, favorite, continue watching, genres, years, studios, tags, languages, ratings, subtitles, trailers, extras, and video kind (SD / HD / 4K, DVD, Blu-ray, ISO)
- Library lists every Jellyfin library on the server, plus Collections, Downloaded, and Genres
- Indexing status sits under the header while the catalog is still catching up

### Title details

- Play / resume with progress
- Season episode carousel
- Related titles
- Download and share from the same pill
- Add Subtitles on movies and episodes when the Open Subtitles plugin is on the server
- Share a `zelefin://` link plus the Jellyfin web URL so another install or a browser can open the title

### Playback

- AVPlayer for Apple-compatible Direct Play and remuxed HLS
- Zelefin Direct Play for MKV and similar containers
- Optional native video player (AVPlayer only; MKV remuxes on the server)
- Prefer fMP4 or MPEG-TS when using the native player
- Audio and subtitle track selection, including sidecar files and on-device cues for Direct Play
- Skip intro and credits when Intro Skipper is installed (manual buttons, optional auto-skip)
- Auto play next episode
- Skip intervals, default playback speed, and max bitrate / quality
- Picture in Picture and AirPlay
- Playback stats overlay
- Progress reported back to Jellyfin
- Background audio

### Plugins

Settings → Plugins shows what this Jellyfin server actually has installed. Zelefin does not install plugins; it uses the ones already on the server.

- **Intro Skipper** — Skip Intro and Skip Credits during playback. Optional auto-skip for intros and credits.
- **Open Subtitles** — Search and download a subtitle onto the server from More on a movie or episode, Search, or the player. Sidecar files (`.srt` and similar) show in the subtitle list on Direct Play. The title page refreshes after a download so you do not have to leave and come back.
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

### Users

- Administrators can manage server users from Settings: photo, rename, password set/reset, administrator flag, disable account, remote bitrate cap, parental max rating, block unrated types, and per-library access

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

- Combine Continue Watching and Next Up
- Drag to reorder tabs, hide any tab except Home, reset to defaults

## Open in Xcode

```bash
cd Zelefin
xcodegen generate
open Zelefin.xcodeproj
```

Select an iPhone or iPad destination and run. Sign in with your Jellyfin server URL, username, and password. Local HTTP servers are allowed.

Requires iOS 18. This build is iPhone and iPad only.

## Not in this build

Music, live TV / DVR, SyncPlay, photos, and books are not first-class experiences. A music or live TV library may still appear in Library if the server has one.
