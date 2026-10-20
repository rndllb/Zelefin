package app.zelefin.client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LibraryLayoutTest {
    private val rooms = listOf(
        LibraryRoom("m", "Movies", LibraryKind.Movies),
        LibraryRoom("s", "Shows", LibraryKind.Shows),
        LibraryRoom("cols", "Collections", LibraryKind.Collections),
        LibraryRoom("home", "Cameras", LibraryKind.HomeVideos),
        LibraryRoom("tv", "Live TV", LibraryKind.LiveTV),
        LibraryRoom("mix", "Trailers", LibraryKind.Other),
        LibraryRoom("rec", "Recordings", LibraryKind.Other),
    )

    @Test
    fun defaultOrderPutsCollectionsMoviesShowsFirst() {
        val arranged = LibraryLayout().arranged(rooms)
        assertEquals(listOf("cols", "m", "s", "mix", "home", "tv", "rec"), arranged.map { it.id })
    }

    @Test
    fun defaultHiddenDropsLiveTvAndRecordings() {
        val displayed = LibraryLayout().displayed(rooms)
        assertEquals(listOf("cols", "m", "s", "mix"), displayed.map { it.id })
        assertEquals(setOf("home", "tv", "rec"), LibraryLayout().resolvedHidden(rooms))
    }

    @Test
    fun shownAllKeepsLiveTvAndRecordings() {
        val layout = LibraryLayout(hidden = emptySet(), usesDefaultHidden = false)
        assertEquals(listOf("cols", "m", "s", "mix", "home", "tv", "rec"), layout.displayed(rooms).map { it.id })
        assertEquals("none", layout.encodedHidden())
    }

    @Test
    fun customOrderKeepsLeftoversInDefaultRank() {
        val layout = LibraryLayout(order = listOf("mix", "m", "s"), hidden = setOf("tv"), usesDefaultHidden = false)
        assertEquals(listOf("mix", "m", "s", "cols", "home", "rec"), layout.displayed(rooms).map { it.id })
    }

    @Test
    fun parseHiddenEmptyUsesDefaults() {
        assertEquals(emptySet<String>() to true, LibraryLayout.parseHidden(""))
        assertEquals(emptySet<String>() to false, LibraryLayout.parseHidden("none"))
        assertEquals(setOf("tv") to false, LibraryLayout.parseHidden("tv"))
    }

    @Test
    fun recordingNameRanksLast() {
        val recordings = LibraryRoom("rec", "DVR Recordings", LibraryKind.Other)
        assertTrue(recordings.isHiddenOnLibraryByDefault)
        assertEquals(4, recordings.libraryCardRank)
    }
}
