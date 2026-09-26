package app.zelefin.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ArtworkDiskKeyTest {
    @Test
    fun stripsApiKeyAndCacheBusterAndSortsQuery() {
        val withToken = ArtworkDiskKey.key(
            "https://jellyfin.local/Items/abc/Images/Primary?maxHeight=420&quality=90&tag=t1&api_key=SECRET",
        )
        val reordered = ArtworkDiskKey.key(
            "https://jellyfin.local/Items/abc/Images/Primary?quality=90&tag=t1&maxHeight=420&v=9",
        )
        assertEquals(withToken, reordered)
        assertTrue(withToken.startsWith("poster-"))
        assertEquals("poster-".length + 64, withToken.length)
    }

    @Test
    fun classifiesJellyfinImagePaths() {
        assertTrue(ArtworkDiskKey.key("https://h/Items/a/Images/Backdrop?tag=1").startsWith("backdrop-"))
        assertTrue(ArtworkDiskKey.key("https://h/Items/a/Images/Logo?tag=1").startsWith("logo-"))
        assertTrue(ArtworkDiskKey.key("https://h/Items/a/Images/Thumb").startsWith("poster-"))
        assertTrue(ArtworkDiskKey.key("https://h/Items/a/Images/Banner?tag=1").startsWith("poster-"))
        assertTrue(ArtworkDiskKey.key("https://silo.local/posters/1.jpg").startsWith("other-"))
    }
}
