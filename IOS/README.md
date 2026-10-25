<div align="center">

# Zelefin · iOS

iPhone and iPad. Full product list lives in the [repository README](../README.md).

<img src="https://img.shields.io/badge/iOS-18+-111111?style=for-the-badge&logo=apple&logoColor=white" alt="iOS 18+" />
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

## Run

1. Open `Zelefin.xcodeproj`
2. Pick an iPhone or iPad simulator, or a signed-in device
3. Run

`project.yml` is the XcodeGen spec if you need to regenerate the project.

```bash
xcodebuild test -scheme Zelefin -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

[License](../LICENSE)
