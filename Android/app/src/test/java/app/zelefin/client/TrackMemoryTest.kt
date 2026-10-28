package app.zelefin.client

import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TrackMemoryTest {
    private val episodeOne = MediaItem(id = "e1", name = "One", kind = MediaKind.Episode, seriesId = "show")
    private val episodeTwo = MediaItem(id = "e2", name = "Two", kind = MediaKind.Episode, seriesId = "show")

    @Test
    fun episodesOfAShowShareOneEntry() {
        assertEquals("account.show", TrackMemory.key("account", episodeOne))
        assertEquals(TrackMemory.key("account", episodeOne), TrackMemory.key("account", episodeTwo))
        assertEquals("other.show", TrackMemory.key("other", episodeTwo))
    }

    @Test
    fun moviesKeepTheirOwnEntry() {
        val movie = MediaItem(id = "movie", name = "Movie", kind = MediaKind.Movie)
        assertEquals("account.movie", TrackMemory.key("account", movie))
    }

    @Test
    fun nothingIsKeptWithoutAnAccountOrShow() {
        assertNull(TrackMemory.key(null, episodeOne))
        assertNull(TrackMemory.key("account", episodeOne.copy(seriesId = null)))
    }

    @Test
    fun rememberedLanguagesBecomeTheStartingLanguages() {
        assertEquals(TrackMemory.Languages("jpn", "eng"), TrackMemory.languages("jpn", "eng", subtitlesOff = false))
        assertEquals(TrackMemory.Languages("jpn", PlaybackPreferences.OFF), TrackMemory.languages("jpn", "eng", subtitlesOff = true))
        assertEquals(
            TrackMemory.Languages(PlaybackPreferences.AUTOMATIC, PlaybackPreferences.AUTOMATIC),
            TrackMemory.languages(null, "und", subtitlesOff = false),
        )
    }
}
