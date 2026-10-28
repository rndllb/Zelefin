package app.zelefin.client

import android.content.Context
import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind

/** A track the viewer picked from the player menu. */
sealed interface TrackPick {
    data class Audio(val language: String?) : TrackPick
    data class Subtitle(val language: String?) : TrackPick
    data object SubtitlesOff : TrackPick
}

/**
 * The audio and subtitle languages last picked for a show (or a movie), kept per account and
 * handed to the server as the starting languages, so the next episode, auto-play and every
 * quality reload start on the viewer's choice instead of the title default.
 */
object TrackMemory {
    data class Languages(val audio: String, val subtitle: String)

    private val AUTOMATIC = Languages(PlaybackPreferences.AUTOMATIC, PlaybackPreferences.AUTOMATIC)

    fun languages(context: Context, accountId: String?, item: MediaItem): Languages {
        val key = key(accountId, item) ?: return AUTOMATIC
        val prefs = prefs(context)
        return languages(
            audio = prefs.getString("$key.audio", null),
            subtitle = prefs.getString("$key.subtitle", null),
            subtitlesOff = prefs.getBoolean("$key.subtitles-off", false),
        )
    }

    fun remember(context: Context, accountId: String?, item: MediaItem, pick: TrackPick) {
        val key = key(accountId, item) ?: return
        val editor = prefs(context).edit()
        when (pick) {
            is TrackPick.Audio -> editor.putString("$key.audio", usable(pick.language) ?: return)
            is TrackPick.Subtitle -> editor
                .putString("$key.subtitle", usable(pick.language) ?: return)
                .putBoolean("$key.subtitles-off", false)
            TrackPick.SubtitlesOff -> editor.putBoolean("$key.subtitles-off", true)
        }
        editor.apply()
    }

    internal fun languages(audio: String?, subtitle: String?, subtitlesOff: Boolean) = Languages(
        audio = usable(audio) ?: PlaybackPreferences.AUTOMATIC,
        subtitle = if (subtitlesOff) PlaybackPreferences.OFF else usable(subtitle) ?: PlaybackPreferences.AUTOMATIC,
    )

    /** Episodes share their show's entry; anything else keeps its own so reloads stay on the pick. */
    internal fun key(accountId: String?, item: MediaItem): String? {
        val account = accountId?.takeIf { it.isNotBlank() } ?: return null
        val title = if (item.kind == MediaKind.Episode) item.seriesId?.takeIf { it.isNotBlank() } ?: return null else item.id
        return "$account.$title"
    }

    /** Untagged tracks can't be found again by language, so they aren't remembered. */
    internal fun usable(language: String?): String? = language?.trim()?.takeIf {
        it.isNotEmpty() && !it.equals("und", ignoreCase = true) && !it.equals("unknown", ignoreCase = true)
    }

    private fun prefs(context: Context) = context.getSharedPreferences("zelefin.series-tracks", Context.MODE_PRIVATE)
}
