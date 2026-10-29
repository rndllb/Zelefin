package app.zelefin.client.ui

import app.zelefin.client.LibraryKind
import app.zelefin.client.LibraryRoom
import app.zelefin.client.R
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LibraryIconsTest {
    private val anime = LibraryRoom("a1", "ANime Shows")
    private val youTube = LibraryRoom("y1", "YouTube", LibraryKind.YouTube)
    private val home = LibraryRoom("h1", "Home Videos", LibraryKind.HomeVideos)

    @Test
    fun onlyLibrariesNamedAnimeCanPickAnIcon() {
        assertTrue(LibraryIcons.canChoose(anime))
        assertTrue(LibraryIcons.canChoose(LibraryRoom("a2", "My anime movies")))
        assertFalse(LibraryIcons.canChoose(youTube))
    }

    @Test
    fun choicesRoundTripLikeIOS() {
        val raw = "b=AnimeBoyWithTie,a=AnimeCharacter"
        val parsed = LibraryIcons.parse(raw)
        assertEquals(mapOf("a" to "AnimeCharacter", "b" to "AnimeBoyWithTie"), parsed)
        assertEquals("a=AnimeCharacter,b=AnimeBoyWithTie", LibraryIcons.raw(parsed))
        assertEquals(emptyMap<String, String>(), LibraryIcons.parse(""))
    }

    @Test
    fun defaultsFollowTheLibrary() {
        assertEquals(R.drawable.anime_library, LibraryIcons.icon(anime, selected = false, picks = emptyMap()))
        assertEquals(R.drawable.iconsax_youtube_filled, LibraryIcons.icon(youTube, selected = true, picks = emptyMap()))
        assertEquals(R.drawable.iconsax_library, LibraryIcons.icon(home, selected = false, picks = emptyMap()))
        val recordings = LibraryRoom("r1", "TV Recordings", LibraryKind.HomeVideos)
        assertEquals(R.drawable.iconsax_recording, LibraryIcons.icon(recordings, selected = false, picks = emptyMap()))
        assertEquals(R.drawable.iconsax_recording_filled, LibraryIcons.icon(recordings, selected = true, picks = emptyMap()))
    }

    @Test
    fun aPickedIconOnlyAppliesToAnimeLibraries() {
        val picks = mapOf(anime.id to "AnimeBoyWithTie", youTube.id to "AnimeBoyWithTie")
        assertEquals(R.drawable.anime_boy_with_tie, LibraryIcons.icon(anime, selected = true, picks = picks))
        assertNull(LibraryIcons.chosen(youTube, picks))
        assertNull(LibraryIcons.chosen(anime, mapOf(anime.id to "NotAnIcon")))
    }
}
