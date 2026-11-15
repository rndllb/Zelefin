package app.zelefin.client

/**
 * Per-title picks from the detail More menu (iOS `PlaybackLaunchOptions`).
 * Cleared audio/subtitle indexes when the version changes — stream numbers belong to one file.
 */
data class PlaybackLaunchOptions(
    val quality: PlaybackQuality? = null,
    val audioIndex: Int? = null,
    val subtitleIndex: Int? = null,
    val subtitlesDisabled: Boolean = false,
    val mediaSourceId: String? = null,
    val skipCinemaIntros: Boolean = false,
) {
    val resolvedQuality: PlaybackQuality
        get() = quality ?: PlaybackQuality.Auto

    val subtitleStreamIndex: Int?
        get() = if (subtitlesDisabled) -1 else subtitleIndex

    fun chooseVersion(id: String): PlaybackLaunchOptions {
        if (mediaSourceId == id) return this
        return copy(mediaSourceId = id, audioIndex = null, subtitleIndex = null, subtitlesDisabled = false)
    }
}
