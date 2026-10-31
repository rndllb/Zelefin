package app.zelefin.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MediaVersionTest {
    @Test
    fun libraryVersionsKeepTheirNames() {
        val versions = MediaVersion.list(
            listOf(
                MediaVersion.Source("a", "2160p", "/movies/Dune - 2160p.mkv", "mkv"),
                MediaVersion.Source("b", "1080p", "/movies/Dune - 1080p.mkv", "mkv"),
                MediaVersion.Source("c", " ", "/movies/Dune - Directors Cut.mkv", "mkv"),
                MediaVersion.Source("d", null, null, "mkv"),
            ),
        )
        assertEquals(listOf("2160p", "1080p", "Dune - Directors Cut", "MKV"), versions.map { it.title })
    }

    @Test
    fun addonSourcesAreNamedByRelease() {
        val versions = MediaVersion.list(
            listOf(
                MediaVersion.Source(
                    id = "a",
                    name = "[RD+] Torrentio\n4k",
                    path = "/remux/x/VisionQuest.S01E01.2160p.DV",
                    container = "mkv",
                    sizeBytes = 5_300_000_000,
                    width = 3840,
                    height = 2160,
                    videoCodec = "hevc",
                    videoRange = "DOVI",
                    atmos = true,
                    channels = 6,
                    languages = listOf("eng", "fre", "und"),
                ),
                MediaVersion.Source("b", "[RD download] Torrentio\n4k", "/remux/6c1043dd-54c8-5ab3-b094-86f8dd58b6b0", "mkv"),
            ),
        )
        assertEquals(listOf("VisionQuest.S01E01.2160p.DV", "[RD download] Torrentio · 4k"), versions.map { it.title })
        assertTrue(versions[0].detail.orEmpty().startsWith("[RD+] Torrentio · 5.3 GB · 4K HEVC · Dolby Vision · Atmos · "))
        assertNull(versions[1].detail)
    }

    @Test
    fun aSingleFileHasNoPicker() {
        assertTrue(MediaVersion.pickable(MediaVersion.list(listOf(MediaVersion.Source("a", "1080p", null, null)))).isEmpty())
        val two = MediaVersion.pickable(
            MediaVersion.list(
                listOf(
                    MediaVersion.Source("a", "2160p", null, null),
                    MediaVersion.Source("", "x", null, null),
                    MediaVersion.Source("b", "1080p", null, null),
                ),
            ),
        )
        assertEquals(listOf("2160p", "1080p"), two.map { it.title })
    }
}
