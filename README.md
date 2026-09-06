# Zelefin

Native Jellyfin client for iPhone, iPad, and Apple TV. The interface follows the Apple TV app: black ground, large titles, Continue Watching landscape cards, poster rows, and the system tab bar. Playback uses AVPlayer so HDR10, Dolby Vision, and Dolby Atmos stay on Apple’s decoder. MKV and other containers AVPlayer will not open are Direct Played by Zelefin (FFmpeg demux, VideoToolbox decode, sample-buffer presentation).

## Open in Xcode

```bash
cd Zelefin
xcodegen generate
open Zelefin.xcodeproj
```

Select an iPhone, iPad, or Apple TV destination and run. Sign in with your Jellyfin server URL, username, and password. Local HTTP servers are allowed.

## Playback

AVPlayer presents MP4, MOV, and server HLS. MKV and similar containers Direct Play through Zelefin’s engine: FFmpeg demux, VideoToolbox decode, sample-buffer presentation. The server transcodes only when the codec itself is outside that set. Progress is reported back to Jellyfin.

## First build

Home, movie and TV libraries, item detail, search, audio/subtitle metadata, and native playback. Music, live TV, downloads, and SyncPlay are not in this pass.
