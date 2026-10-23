package app.zelefin.client

/** A title's Jellyfin theme song and theme video, as playable stream URLs, and whether the video is heard. */
data class ThemeMedia(val songUrl: String? = null, val videoUrl: String? = null, val videoSound: Boolean = false) {
    val isEmpty: Boolean get() = songUrl == null && videoUrl == null
}
