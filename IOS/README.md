# Zelefin

Native Jellyfin client for iPhone and iPad, compatible with Silo. The interface follows the Apple TV app: black ground, large titles, Continue Watching landscape cards, poster rows, and the system tab bar. iPad uses a sidebar.

Playback uses AVPlayer so HDR10, Dolby Vision, and Dolby Atmos stay on Apple’s decoder. MKV and other containers AVPlayer will not open are Direct Played on device (FFmpeg demux, VideoToolbox decode, sample-buffer presentation). The server transcodes only when the codec itself is outside that set.

## Features

### Sign in

- Branded sign-in with the Zelefin mark; pick Jellyfin or Silo before you enter the server
- Login disclaimer and splashscreen from this Jellyfin server’s branding, when they are set
- Jellyfin or Silo server URL, username (or email on Silo), and password
- Test Connection reports whether the URL is Jellyfin or Silo
- Household profiles and PIN on Silo after login (Who’s watching)
- Try Review Demo on the sign-in screen: a sample library for App Review (Home, Movies, Shows, title pages, and Play) with no server. Hide the button with `ReviewDemo.isEnabled`, or delete `IOS/Zelefin/ReviewDemo` after approval.
- After a new Jellyfin or Silo sign-in, a one-time setup: preferred audio and subtitle languages, optional Seerr sign-in, and Install Plugin for Jellyfin administrators. Silo skips Seerr and the plugin. Review Demo and restoring a saved account skip this screen
- Quick Connect from another signed-in Jellyfin device
- Access Gateway tokens for Cloudflare Zero Trust or Pangolin, sent on every request including artwork and playback
- Multiple saved accounts on this device, with switch-user and Add User / Add Account from Profile
- Profile photo (camera or photo library) and password change. On Silo, avatars are presets or a photo when the server stores them
- Access token on Profile, hidden until you reveal it, with copy

### Home

- Featured hero from Interface settings: recently added, random, continue watching, next up, recommendations, recently watched, or favorites
- Continue Watching and Next Up, or one combined Continue Watching row (Interface settings)
- Reorder or hide Home rows in Interface settings, including Featured, recommendations, recently added, collections, and genres
- Because You Watched and Because You Liked rows when Jellyfin returns them
- Upcoming Episodes
- Recently added rows per library, collections, and genres
- Quality marks on posters when the file is 4K, HD, HDR / Dolby Vision, or Atmos (movies and episodes; series posters stay unmarked when there is no file)
- Pull to refresh, cache-first loads
- Long-press: play, download, mark watched or unwatched, go to the show or movie, add subtitles when this account can edit them
- Remove from Continue Watching or Next Up when Jellyfin Enhanced is installed, without clearing progress

### Browse

- Tabs for Home, Movies, Shows, Live TV, Collections, Library, and Favorites (Live TV, Collections, and Favorites hidden by default)
- Reorder or hide tabs in Interface settings; iPad can also Edit the sidebar
- Favorites is movies and series marked favorite on the server; it is also listed under Library
- Movies and Shows load the full catalog, not the first page
- Sort by name, date added, date played, release date, runtime, play count, ratings, parental rating, or random
- Filter by played, unplayed, favorite, continue watching, genres, years, studios, tags, languages, ratings, subtitles, trailers, extras, and video kind (SD / HD / 4K, DVD, Blu-ray, ISO)
- Library lists movies, shows, and Live TV on the server, plus Collections, Favorites, Downloaded, and Genres. Music, playlists, books, photos, home videos, and other Jellyfin libraries stay off this list
- Each library room shows a short preview of recent titles. Hold a room and drag to reorder it. The eye hides it from Library
- Live TV opens On Now, Guide, Channels, and Recordings
- Indexing status sits under the header while the catalog is still catching up

### Title details

- Play / resume with progress
- Season episode carousel
- Local trailers first, then remote trailers Jellyfin lists for the title
- Extras and theme videos
- Related titles, cast, and collections
- Cast and crew open a person page of their titles
- About row: title and synopsis card, Tomatometer when Jellyfin has a critic score, community rating, and an age-guidance card from the official rating
- TMDB reviews, household write/edit reviews, and awards when Jellyfin Enhanced is installed (awards need Show Awards on the plugin; TMDB reviews need a TMDB key)
- MORE on the About card opens the full description; MORE on the hero opens the info sheet
- Information, Languages, and File lists on the title page (studio, runtime, audio, subtitles, container, bitrate)
- Download and share from the same pill
- More: favorite, like or dislike, add to a collection, play on another device, and Play in SyncPlay
- Select Audio and Select Subtitles from the file’s tracks (Jellyfin streams, or Silo watch/catalog `audio_tracks` / `subtitle_tracks`)
- Version picker when a title has more than one file
- Administrators can refresh metadata, edit Poster / Thumbnail / Logo / Backdrop from remote images, and delete the title from the library. Delete asks with a centered alert before Jellyfin removes the files. Delete and remote images stay Jellyfin-only. Applying new art refreshes posters and heroes in the app without leaving the title
- Add Subtitles on movies and episodes when this account can edit subtitles (administrator or Edit Subtitles) and Open Subtitles is on the Jellyfin server. Silo does not offer Add Subtitles from this app
- Share a `zelefin://` link plus the Jellyfin web URL so another install or a browser can open the title
- On iPhone, title and Live TV program pages use the same 45 pt glass Back and More pills as iPad. The rest of the iPhone UI stays portrait; the video player can rotate to landscape

### Notifications

Lock-screen alerts need the [Zelefin plugin](https://github.com/rndllb/Zelefin-Plugin) on this Jellyfin server. Without it, this app does not watch the server or post banners.

- Settings → Notifications explains what the plugin does and lets a Jellyfin administrator install it now
- New movies, shows, and episodes: a banner on this iPhone or iPad, and tapping it opens that title
- Administrators also get streams started, users coming online on another device, scheduled tasks starting, and new Seerr requests when Seerr is signed in under Plugins
- Settings → Notifications to turn banners on or off after the plugin is installed
- You do not paste an Apple key on the server. Restart Jellyfin after you install or remove the plugin
- Silo has no Zelefin plugin, so notifications are not available on that server
- Privacy, terms, and support: [zelefin.app/privacy](https://zelefin.app/privacy), [zelefin.app/terms](https://zelefin.app/terms), [zelefin.app/support](https://zelefin.app/support)

### Playback

- AVPlayer for Apple-compatible Direct Play and remuxed HLS
- Zelefin Direct Play for MKV and similar containers
- Optional native video player (AVPlayer only; MKV remuxes on the server)
- Prefer fMP4 or MPEG-TS when using the native player
- Preferred audio and subtitle languages in Settings → Playback (also set on first sign-in). Automatic uses the title default; Off turns subtitles off. A chosen language is used when that track exists
- Audio and subtitle track selection, including sidecar files and on-device cues for Direct Play
- On Silo, playback uses protocol v3. Auto Direct Plays the original file on this device (same as Jellyfin), including HDR — Zelefin maps it on device instead of asking Silo to tone-map. Native Video Player still uses AVPlayer for MP4 and HLS; MKV stays on the built-in engine so Silo does not remux HDR into a transcode. Prefer fMP4 in HLS applies when a remux is required, and MPEG-TS is used when fMP4 is off
- Adaptive bitrate still measures this connection. On Silo it does not cap Direct Play; a lower Maximum Quality is the only start cap. If Silo still has to re-encode HDR (incompatible codec, subtitle burn-in, or a quality cap), enable **Software HDR Tone Mapping** in Silo → Settings → Playback. Hardware HDR Tone Mapping only permits a GPU recipe after Silo smoke-tests it (VA-API `tonemap_vaapi` or similar). With software off and no validated GPU executor, playback stops with “no validated HDR-preserving or tone-map recipe is installed.” The chapter-thumbnail HDR rows on that page do not apply to playback. Transcoded HDR becomes SDR. Restart Silo if those toggles still show a restart badge.
- Chapters and trickplay thumbnails when Jellyfin has them
- Cinema intros before the title when the server queues them
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
- Progress reported back to Jellyfin or Silo
- Background audio
- iPhone stays portrait outside playback. Opening the player unlocks landscape; closing it returns to portrait. iPad keeps every orientation

### Plugins

Settings → Plugins shows what this Jellyfin server actually has installed. The first-sign-in setup can add the Zelefin catalog and install the companion plugin for administrators, the same way Neptune does.

- **Zelefin** — Required companion plugin for lock-screen alerts. Also stores Seerr URL and API key and Intro Skipper defaults. Settings → Notifications and first-time setup offer Install Plugin to admins. You can also add `https://raw.githubusercontent.com/rndllb/Zelefin-Plugin/main/manifest.json` in Jellyfin → Dashboard → Plugins → Catalog. Admins do not need an Apple Developer account.
- **Intro Skipper** — Skip Intro and Skip Credits during playback. Optional auto-skip for intros and credits.
- **Open Subtitles** — Search and download a subtitle onto the server from More on a movie or episode, Search, or the player. Requires an administrator or a user with Edit Subtitles. Sidecar files (`.srt` and similar) show in the subtitle list on Direct Play. The title page refreshes after a download so you do not have to leave and come back.
- **Jellyfin Enhanced** — Remove from Continue Watching or Next Up without changing watched state. TMDB reviews, household reviews, and awards on the title page. Detection uses the plugin list, or `/JellyfinEnhanced/version` when `/Plugins` is admin-only.
- **Seerr / Jellyseerr** — Sign in here with your Jellyfin username and password, then discover and request titles from Search. Not a Jellyfin plugin; a separate request app that talks to Radarr and Sonarr.
- **Silo requests** — Built into Silo, not installed as a Jellyfin plugin. Plugins settings pick this server’s Seerr plugin or its Sonarr & Radarr requests plugin. You do not sign in to Seerr separately. Open Subtitles search/download from this app needs public object storage on the Silo host and is not offered here.

### Search and requests

- Search this server’s library (movies, shows, people, collections, and Live TV on Jellyfin)
- Genre cards with a mark per genre. Music and Music Video stay hidden. Combined Action & Adventure is hidden. Game Show hyphen and space spellings collapse to one card
- Discover and request through Seerr or Jellyseerr on Jellyfin (sign in under Plugins), or through Silo’s request plugins from Search
- Trending, popular, upcoming, genres, studios, and networks. Television genres such as News, Soap, and Talk request TV, not movies
- Request movies and shows with Radarr / Sonarr server, quality, folder, and season picks
- A pending request can be approved, declined, or edited first. Titles already on the server show a checkmark and do not open a request

### Downloads

- Download titles for offline play
- Progress on posters, detail, and Library → Downloaded
- Local playback with watch progress

### Sessions

- Who is connected and what they are playing
- Transcode details (codec, resolution, bitrate, reason)
- Remote control of other clients that accept it (play, pause, skip, volume), under the progress bar on that session
- Message a connected session. The other client shows it as a display message from Zelefin
- This device also accepts remote control from Jellyfin while the socket stays up
- This device reports its marketing model name to Jellyfin, such as iPhone 17 Pro

### SyncPlay

- Settings → SyncPlay: create a group, join one that is running, or leave
- Play in SyncPlay from More on a movie or episode
- Pause, seek, and play on this device stay in step with the group while you are joined

### Live TV

- Library → Live TV opens a guide, not a poster grid
- On Now: channel logos, the program that is airing, its still, time left, and a progress bar. Filter by movies, sports, news, kids, and series the same way Movies and Shows filter
- Channels: a grid of channel logos with the number, name, what’s on, and air times. Tap a card to watch live. Filter the same way On Now does
- Program page: Watch Live and Watch List. Restart when a recording of that title is already in progress on the server
- Up Next on that channel lists the programs that follow, without opening another page
- Guide: listings sized by how long each program runs, with a live progress fill on what is airing. Filter by movies, sports, news, kids, and series the same way On Now does
- Recordings already saved on the server, including titles that are still recording. Play from the card; More matches Home. This app does not schedule new recordings

### Scheduled tasks

- Administrators can open Scheduled Tasks from Settings or the profile menu
- Start or cancel a task, and watch progress while it runs
- Tapping a “scheduled task started” notification opens this list

### Users and Silo accounts

- On Jellyfin, administrators can manage server users from Settings: photo, rename, password set/reset, administrator flag, Edit Subtitles, disable account, remote bitrate cap, parental max rating, block unrated types, and per-library access
- Edit Subtitles (`EnableSubtitleManagement`) lets a non-admin search and download subtitles the same way an administrator can
- On Silo, Profile lists household profiles under Household and saved logins under Accounts. Switch profile from the avatar menu the same way you switch a Jellyfin user; a locked profile asks for a PIN, not a full-screen picker
- Silo administrators can create accounts (a default household profile is created), invite by email, stop a session, run tasks, scan libraries, and read audit and operational logs

### Admin tools

Administrators also get these from Settings. Jellyfin:

- Activity Log: who signed in, what scanned, what failed
- Backups: create an archive, restore one (Jellyfin restarts)
- Branding: login disclaimer, custom CSS, splashscreen upload or delete
- Scan Libraries: look for new files and refresh metadata (with confirmation)

Silo (when this login can administer the server):

- Accounts: create, rename, password, admin flag, disable, delete
- Invitations: email invite, copy claim link, resend, revoke
- Sessions: who is playing, stop playback
- Scheduled Tasks: start, cancel, watch progress
- Devices, Libraries (scan), stream/transcode nodes
- Audit log and operational log

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
- Featured hero source: recently added, random, continue watching, next up, recommendations, recently watched, or favorites
- Combine Continue Watching and Next Up
- Drag to reorder Home rows and turn any row off, including Featured
- Drag to reorder tabs, hide any tab except Home, reset to defaults
- Tab order, Home row layout, and the combined Continue Watching row sync to this Jellyfin user as display preferences, so another Zelefin install on the same account can pick them up
- About shows Version and Build, plus Privacy Policy and Terms of Use on [zelefin.app](https://zelefin.app)

## Open in Xcode

```bash
xcodegen generate
open Zelefin.xcodeproj
```

Select an iPhone or iPad destination and run. Sign in with your Jellyfin or Silo server URL, username, and password, or tap Try Review Demo to browse a sample library. Local HTTP servers are allowed.

Requires iOS 18. This build is iPhone and iPad only.

## Links

- App: [github.com/rndllb/Zelefin](https://github.com/rndllb/Zelefin)
- Plugin: [github.com/rndllb/Zelefin-Plugin](https://github.com/rndllb/Zelefin-Plugin)
- Site: [zelefin.app](https://zelefin.app)

## Not in this build

This app is movies and shows. On Jellyfin it also includes Live TV. Music, playlists, books, photos, home videos, and other library types do not appear in Library, Home, or Search. Silo sessions hide Live TV, SyncPlay, Jellyfin remote control, Jellyfin backups/branding, and Jellyfin plugins. Emby and Plex are not in this build.
