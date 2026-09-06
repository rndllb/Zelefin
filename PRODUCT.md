# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Stack

delegated: Swift / SwiftUI multiplatform (iOS, iPadOS, tvOS) with a shared target. Confirmed by the request and the linked Swift practices guide. Networking via the official `jellyfin-sdk-swift`. Playback via AVFoundation / AVKit first; Zelefin Direct Play demuxes containers AVPlayer will not open (FFmpeg → VideoToolbox → sample-buffer layer). VLCKit is not in this build.

## Users

People who already run a Jellyfin server and watch on Apple hardware: Apple TV 4K in the living room, iPhone in bed or commuting, iPad on the couch. The job is to open the library and play a title with the picture and sound the file actually contains.

## Product Purpose

Zelefin is a native Jellyfin client for Apple TV, iPhone, and iPad. It exists so HDR, Dolby Vision, and Dolby Atmos survive the path from the server to the display and speakers. Success is a 4K Dolby Vision / Atmos title lighting the TV correctly, with audio and subtitle choices and watch progress reported back to Jellyfin.

## Positioning

AVPlayer-first playback. Direct play or remux whenever Apple can decode the stream; transcode only when the device cannot. Zelefin Direct Play is the MKV path, not a second picture pipeline. That is the claim a generic web wrapper or a VLC-default client cannot make.

## Operating Context

Self-hosted Jellyfin over LAN or remote URL. Sign-in with username/password or Quick Connect. Evening living-room sessions on tvOS with the Siri Remote, plus touch sessions on iPhone and iPad. Server transcoding is available but treated as a last resort because it often strips Vision and Atmos.

## Capabilities and Constraints

Confirmed for the first build:

- Connect to a Jellyfin server, authenticate, persist the session
- Home, movie and TV libraries, item detail
- AVPlayer playback with HDR10, Dolby Vision, and Dolby Atmos when the file and device allow it
- MKV Direct Play via Zelefin’s engine (FFmpeg demux → VideoToolbox → sample-buffer layer)
- Audio and subtitle track selection
- Playback progress reporting to the server

Destination, not first build: music, live TV/DVR, downloads, SyncPlay, photos, books, and remaining server features.

Constraints:

- Follow Swift API Design Guidelines, protocol-oriented design, small focused types, no force unwraps or force casts, throwing errors, ARC-safe closures, SwiftUI, and unit tests
- Honor Apple HIG per device class: tab/navigation on iOS and iPadOS, focus engine on tvOS
- AVPlayer does not Direct Play most MKV containers; Zelefin Direct Play demuxes those on the device
- Dolby Vision Profile 5 and Atmos need the native player, not VLC
- FFmpeg is LGPL, stays dynamically linked, and license texts ship in Settings

Undecided: App Store identity and whether the first TestFlight is iOS-only or includes tvOS.

## Brand Commitments

The product name is Zelefin. Voice is direct and technical when playback quality is at stake (codec, range, audio format) and otherwise plain.

The UI matches the Apple TV app on iPhone, iPad, and Apple TV: true-black ground, SF Pro, large titles, landscape Continue Watching cards with progress, portrait poster rows, section headers with chevrons, rounded posters, a profile button in the trailing toolbar, and the system floating tab bar. Do not invent a separate visual world.

## Evidence on Hand

No real library, screenshots, or server credentials are in this repository. First-build UI may use clearly labeled synthetic library data for layout. Do not invent Jellyfin capabilities, codec support, or playback results the Apple stack cannot actually deliver.

## Product Principles

1. Picture and sound of the file beat a universal-but-tonemapped player.
2. Native Apple controls and navigation beat a custom media-app chrome.
3. Direct play, then remux, then transcode.
4. One shared Swift model; each OS keeps its own interaction grammar.
5. Ship a working living-room path before spreading across every Jellyfin feature.

## Accessibility & Inclusion

Dynamic Type, Reduce Motion, VoiceOver, and tvOS focus order are required. Contrast follows system semantic colors. Playback UI must remain operable with the Siri Remote and with VoiceOver on iPhone.
