package app.zelefin.client

import org.jellyfin.sdk.model.api.SubtitlePlaybackMode
import org.jellyfin.sdk.model.api.UserConfiguration
import java.util.Locale

/**
 * The Jellyfin user settings that decide which audio and subtitle streams a title starts on.
 * Mirrors iOS `JellyfinPlaybackPreferences`. Language codes are the two-letter picker codes;
 * [ServerLanguageCode] converts to the three-letter codes Jellyfin stores so Jellyfin Web shows
 * the same selection.
 */
data class JellyfinPlaybackPreferences(
    val audioLanguage: String = ANY_LANGUAGE,
    val playDefaultAudioTrack: Boolean = false,
    val subtitleLanguage: String = ANY_LANGUAGE,
    val subtitleMode: SubtitlePlaybackMode = SubtitlePlaybackMode.DEFAULT,
) {
    fun applyTo(configuration: UserConfiguration): UserConfiguration = configuration.copy(
        audioLanguagePreference = ServerLanguageCode.toServer(audioLanguage),
        playDefaultAudioTrack = playDefaultAudioTrack,
        subtitleLanguagePreference = ServerLanguageCode.toServer(subtitleLanguage),
        subtitleMode = subtitleMode,
    )

    companion object {
        const val ANY_LANGUAGE = ""

        fun from(configuration: UserConfiguration) = JellyfinPlaybackPreferences(
            audioLanguage = ServerLanguageCode.fromServer(configuration.audioLanguagePreference),
            playDefaultAudioTrack = configuration.playDefaultAudioTrack,
            subtitleLanguage = ServerLanguageCode.fromServer(configuration.subtitleLanguagePreference),
            subtitleMode = configuration.subtitleMode,
        )
    }
}

object ServerLanguageCode {
    /** Jellyfin keeps ISO 639-2 ("eng"); the pickers use 639-1 ("en"). */
    fun toServer(code: String): String {
        val trimmed = code.trim().lowercase()
        if (trimmed.isEmpty()) return ""
        return runCatching { Locale(trimmed).isO3Language }.getOrNull()?.ifEmpty { null } ?: trimmed
    }

    fun fromServer(code: String?): String {
        val trimmed = code?.trim()?.lowercase().orEmpty()
        if (trimmed.isEmpty()) return ""
        return PlaybackLanguage.alias(trimmed) ?: trimmed
    }
}

val SubtitlePlaybackMode.title: String
    get() = when (this) {
        SubtitlePlaybackMode.DEFAULT -> "Default"
        SubtitlePlaybackMode.SMART -> "Smart"
        SubtitlePlaybackMode.ALWAYS -> "Always"
        SubtitlePlaybackMode.ONLY_FORCED -> "Only Forced"
        SubtitlePlaybackMode.NONE -> "None"
    }

val SubtitlePlaybackMode.summary: String
    get() = when (this) {
        SubtitlePlaybackMode.DEFAULT -> "Subtitles follow the default and forced flags in the file."
        SubtitlePlaybackMode.SMART -> "Subtitles in the preferred language load when the audio is in another language."
        SubtitlePlaybackMode.ALWAYS -> "Subtitles in the preferred language load regardless of the audio language."
        SubtitlePlaybackMode.ONLY_FORCED -> "Only subtitles flagged as forced load."
        SubtitlePlaybackMode.NONE -> "No subtitles load unless you pick them during playback."
    }

val SubtitlePlaybackModeChoices = listOf(
    SubtitlePlaybackMode.DEFAULT,
    SubtitlePlaybackMode.SMART,
    SubtitlePlaybackMode.ALWAYS,
    SubtitlePlaybackMode.ONLY_FORCED,
    SubtitlePlaybackMode.NONE,
)
