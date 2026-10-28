<div align="center">

# Zelefin · iOS

iPhone, iPad, and Mac. Full product list lives in the [repository README](../README.md).

<img src="https://img.shields.io/badge/iOS-18+-111111?style=for-the-badge&logo=apple&logoColor=white" alt="iOS 18+" />
<img src="https://img.shields.io/badge/macOS-15+%20·%20Intel%20%26%20Apple%20silicon-111111?style=for-the-badge&logo=apple&logoColor=white" alt="macOS 15+, Intel and Apple silicon" />
<img src="https://img.shields.io/badge/Jellyfin-ready-00A4DC?style=for-the-badge" alt="Jellyfin" />
<img src="https://img.shields.io/badge/Silo-ready-2ad4fc?style=for-the-badge&labelColor=111111" alt="Silo" />
<img src="https://img.shields.io/badge/Emby-ready-52B54B?style=for-the-badge&labelColor=111111" alt="Emby" />

Open `Zelefin.xcodeproj`. Sign in with your own server. No Plus, no subscription.

</div>

---

## Only on this tree

<table>
<tr>
<td width="50%" valign="top">

📺 **Live TV guide**  
On Now, channels, listings, recordings already on the server.

</td>
<td width="50%" valign="top">

🖼️ **PiP & AirPlay**  
AVPlayer / VideoToolbox. HDR stays on Apple’s decoder.

▶️ **MPV, AetherEngine, or Native**  
MPV by default: every audio and subtitle track, styled subtitles, hardware decoding.

</td>
</tr>
<tr>
<td width="50%" valign="top">

🧪 **Review Demo**  
Bundled catalog. Never calls a server.

</td>
<td width="50%" valign="top">

🔤 **Catalog extras**  
A–Z rail. Subtitle size, color, and position.

</td>
</tr>
</table>

Jellyfin, Silo, and Emby, with home, library, search, Discover, downloads, SyncPlay, sessions, lock-screen alerts, and admin tools, match Android.

---

## Mac

The same app built for the Mac with Mac Catalyst, native on Intel and Apple silicon (M-series) Macs, macOS 15+. It runs as a Mac app ("Optimize Interface for Mac") with a fixed sidebar like the TV app, posters six across, and rows sized to the window.

- **MPV** comes from upstream [MPVKit](https://github.com/mpvkit/MPVKit) on the Mac (the iPhone build's AVFoundation video output has no Mac Catalyst build) and draws through Vulkan on MoltenVK. `scripts/build-mpv.sh` links it into the Mac slice of `ZelefinMPV`.
- **AetherEngine** isn’t on the Mac yet: its FFmpeg and LibDovi ship no Mac Catalyst builds ([AetherEngine#253](https://github.com/superuser404notfound/AetherEngine/issues/253)). The Mac plays with MPV or Apple’s player.
- **ZelefinMacBridge** is a small AppKit bundle in the app’s PlugIns folder. It keeps the sidebar from collapsing or resizing and hides its sidebar button, which Catalyst’s split view can’t do.

---

## Run

1. Open `Zelefin.xcodeproj`
2. Pick an iPhone or iPad simulator, a signed-in device, or **My Mac (Mac Catalyst)**
3. Run

MPV is a framework too large for git (`Packages/ZelefinMPV`). Build it once before the first run:

```bash
scripts/build-mpv.sh
```

`project.yml` is the XcodeGen spec if you need to regenerate the project.

```bash
xcodebuild test -scheme Zelefin -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

[License](../LICENSE)
