package app.zelefin.client

import org.jellyfin.sdk.model.api.SubtitlePlaybackMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PlaybackLanguageTest {
    private val tracks = listOf(
        LanguageTrack(2, "eng", false, "English"),
        LanguageTrack(3, "spa", false, "Spanish"),
    )

    @Test
    fun alwaysTurnsSubtitlesOnWithoutPreferredLanguage() {
        assertEquals(
            2,
            PlaybackLanguage.startingSubtitleIndex(
                tracks = tracks,
                serverIndex = null,
                mode = SubtitlePlaybackMode.ALWAYS,
                preferredLanguage = "",
                audioLanguage = "eng",
                preferSdh = false,
                deviceLanguage = "en",
            ),
        )
        assertNull(
            PlaybackLanguage.startingSubtitleIndex(
                tracks = tracks,
                serverIndex = null,
                mode = SubtitlePlaybackMode.DEFAULT,
                preferredLanguage = "",
                audioLanguage = "eng",
                preferSdh = false,
                deviceLanguage = "en",
            ),
        )
        assertNull(
            PlaybackLanguage.startingSubtitleIndex(
                tracks = tracks,
                serverIndex = null,
                mode = SubtitlePlaybackMode.ALWAYS,
                preferredLanguage = "",
                audioLanguage = "eng",
                preferSdh = false,
                deviceLanguage = "en",
                forcedByUser = true,
            ),
        )
    }

    @Test
    fun matchesLabelAcceptsDisplayNames() {
        assertEquals(true, PlaybackLanguage.matchesLabel("English · SRT", "eng", "en"))
        assertEquals(true, PlaybackLanguage.matchesLabel("Español", "spa", "es"))
        assertEquals(false, PlaybackLanguage.matchesLabel("Japanese", "jpn", "en"))
    }

    @Test
    fun alwaysPrefersTheChosenLanguage() {
        assertEquals(
            3,
            PlaybackLanguage.startingSubtitleIndex(
                tracks = tracks,
                serverIndex = null,
                mode = SubtitlePlaybackMode.ALWAYS,
                preferredLanguage = "es",
                audioLanguage = "eng",
                preferSdh = false,
                deviceLanguage = "en",
            ),
        )
    }
}
