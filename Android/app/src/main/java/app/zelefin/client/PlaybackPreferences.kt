package app.zelefin.client

import android.content.Context
import android.content.SharedPreferences
import kotlin.math.abs

/** Player preferences stored in the shared "zelefin.playback" file so Settings can surface them. */
object PlaybackPreferences {
    const val NAME = "zelefin.playback"
    const val AUTOPLAY_NEXT = "autoplay-next"
    const val SKIP_BACKWARD = "skip-backward-seconds"
    const val SKIP_FORWARD = "skip-forward-seconds"
    const val DEFAULT_RATE = "default-rate"

    /** Bits per second of the selected [PlaybackQuality]; 0 is Auto. */
    const val MAX_BITRATE = "max-bitrate"
    const val ADAPTIVE_BITRATE = "adaptive-bitrate"

    /** ISO 639 code, or [AUTOMATIC] for the title default. */
    const val AUDIO_LANGUAGE = "audio-language"

    /** ISO 639 code, [AUTOMATIC] for the title default, or [OFF]. */
    const val SUBTITLE_LANGUAGE = "subtitle-language"

    const val PREFER_SDH = "prefer-sdh"
    const val PLAYER_ENGINE = "player-engine"
    const val DOWNLOAD_WIFI_ONLY = "download-wifi-only"
    const val THEME_SONGS = "theme-songs"
    const val THEME_VIDEOS = "theme-videos"
    const val THEME_VIDEO_SOUND = "theme-video-sound"
    const val ENGINE_EXOPLAYER = "exoplayer"
    const val ENGINE_MPV = "mpv"

    const val AUTOMATIC = "auto"
    const val OFF = "off"

    val skipIntervals = listOf(5, 10, 15, 30, 60)
    val speeds = listOf(0.5f, 1f, 1.25f, 1.5f, 2f)

    fun autoplayNext(context: Context): Boolean = prefs(context).getBoolean(AUTOPLAY_NEXT, true)

    fun setAutoplayNext(context: Context, value: Boolean) = prefs(context).edit().putBoolean(AUTOPLAY_NEXT, value).apply()

    fun skipBackward(context: Context): Int = resolvedInterval(prefs(context).getInt(SKIP_BACKWARD, 10))

    fun setSkipBackward(context: Context, seconds: Int) = prefs(context).edit().putInt(SKIP_BACKWARD, resolvedInterval(seconds)).apply()

    fun skipForward(context: Context): Int = resolvedInterval(prefs(context).getInt(SKIP_FORWARD, 10))

    fun setSkipForward(context: Context, seconds: Int) = prefs(context).edit().putInt(SKIP_FORWARD, resolvedInterval(seconds)).apply()

    fun defaultRate(context: Context): Float = resolvedRate(prefs(context).getFloat(DEFAULT_RATE, 1f))

    fun setDefaultRate(context: Context, rate: Float) = prefs(context).edit().putFloat(DEFAULT_RATE, resolvedRate(rate)).apply()

    fun selectedQuality(context: Context): PlaybackQuality = PlaybackQuality.resolved(prefs(context).getInt(MAX_BITRATE, 0))

    fun setSelectedQuality(context: Context, quality: PlaybackQuality) =
        prefs(context).edit().putInt(MAX_BITRATE, quality.bits).apply()

    fun adaptiveBitrate(context: Context): Boolean = prefs(context).getBoolean(ADAPTIVE_BITRATE, true)

    fun setAdaptiveBitrate(context: Context, value: Boolean) = prefs(context).edit().putBoolean(ADAPTIVE_BITRATE, value).apply()

    fun audioLanguage(context: Context): String = resolvedLanguage(prefs(context).getString(AUDIO_LANGUAGE, AUTOMATIC))

    fun setAudioLanguage(context: Context, code: String) = prefs(context).edit().putString(AUDIO_LANGUAGE, code).apply()

    fun subtitleLanguage(context: Context): String = resolvedLanguage(prefs(context).getString(SUBTITLE_LANGUAGE, AUTOMATIC))

    fun setSubtitleLanguage(context: Context, code: String) = prefs(context).edit().putString(SUBTITLE_LANGUAGE, code).apply()

    fun preferSdh(context: Context): Boolean = prefs(context).getBoolean(PREFER_SDH, false)

    fun setPreferSdh(context: Context, value: Boolean) = prefs(context).edit().putBoolean(PREFER_SDH, value).apply()

    fun playerEngine(context: Context): String {
        val raw = prefs(context).getString(PLAYER_ENGINE, ENGINE_MPV).orEmpty()
        return if (raw == ENGINE_EXOPLAYER) ENGINE_EXOPLAYER else ENGINE_MPV
    }

    fun setPlayerEngine(context: Context, engine: String) =
        prefs(context).edit().putString(PLAYER_ENGINE, if (engine == ENGINE_MPV) ENGINE_MPV else ENGINE_EXOPLAYER).apply()

    fun usesMpv(context: Context): Boolean = playerEngine(context) == ENGINE_MPV

    fun downloadWifiOnly(context: Context): Boolean = prefs(context).getBoolean(DOWNLOAD_WIFI_ONLY, false)

    fun setDownloadWifiOnly(context: Context, value: Boolean) = prefs(context).edit().putBoolean(DOWNLOAD_WIFI_ONLY, value).apply()

    /** Jellyfin theme songs behind title pages. Jellyfin keeps this per client; off until chosen. */
    fun themeSongs(context: Context): Boolean = prefs(context).getBoolean(THEME_SONGS, false)

    fun setThemeSongs(context: Context, value: Boolean) = prefs(context).edit().putBoolean(THEME_SONGS, value).apply()

    /** Jellyfin theme videos in place of the title page backdrop. Off until chosen. */
    fun themeVideos(context: Context): Boolean = prefs(context).getBoolean(THEME_VIDEOS, false)

    fun setThemeVideos(context: Context, value: Boolean) = prefs(context).edit().putBoolean(THEME_VIDEOS, value).apply()

    /** The theme video's own audio. Off keeps it muted. */
    fun themeVideoSound(context: Context): Boolean = prefs(context).getBoolean(THEME_VIDEO_SOUND, false)

    fun setThemeVideoSound(context: Context, value: Boolean) =
        prefs(context).edit().putBoolean(THEME_VIDEO_SOUND, value).apply()

    fun speedTitle(rate: Float): String {
        if (abs(rate - 1f) < 0.01f) return "1x"
        val whole = rate.toInt()
        return if (abs(rate - whole) < 0.001f) "${whole}x" else "${rate}x"
    }

    fun intervalTitle(seconds: Int): String = "$seconds seconds"

    private fun resolvedInterval(seconds: Int): Int = if (seconds in skipIntervals) seconds else 10

    private fun resolvedRate(rate: Float): Float = speeds.firstOrNull { abs(it - rate) < 0.01f } ?: 1f

    /** Older builds and iOS-style values ("automatic", "") all mean the title default. */
    private fun resolvedLanguage(raw: String?): String = when (val code = raw?.trim()?.lowercase().orEmpty()) {
        "", AUTOMATIC, "automatic" -> AUTOMATIC
        else -> code
    }

    private fun prefs(context: Context): SharedPreferences = context.getSharedPreferences(NAME, Context.MODE_PRIVATE)
}
