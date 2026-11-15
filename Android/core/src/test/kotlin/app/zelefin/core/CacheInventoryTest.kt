package app.zelefin.core

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CacheInventoryTest {
    @Test
    fun classifiesFileNamesLikeIos() {
        assertEquals(ArtworkImageKind.Poster, ArtworkImageKind.classify("poster-abc"))
        assertEquals(ArtworkImageKind.Backdrop, ArtworkImageKind.classify("backdrop-abc.missing"))
        assertEquals(ArtworkImageKind.Logo, ArtworkImageKind.classify("logo-abc"))
        assertEquals(ArtworkImageKind.Other, ArtworkImageKind.classify("other-abc"))
        assertEquals(ArtworkImageKind.Other, ArtworkImageKind.classify("journal"))
    }

    @Test
    fun splitsCoilEntriesByKindPrefix() {
        val root = File.createTempFile("zelefin-cache", "").apply {
            delete()
            mkdirs()
        }
        val artwork = File(root, "Artwork").apply { mkdirs() }
        val posterKey = "poster-abc"
        val logoKey = "logo-def"
        File(artwork, CacheInventory.coilFileHash(posterKey) + ".1").writeBytes(ByteArray(1500))
        File(artwork, CacheInventory.coilFileHash(logoKey) + ".1").writeBytes(ByteArray(2500))
        File(artwork, CacheInventory.coilFileHash("deadbeef") + ".1").writeBytes(ByteArray(800))
        val index = File(root, "kinds.txt")
        index.writeText("$posterKey\n$logoKey\n")

        val usage = CacheInventory.artworkUsage(artwork, index)
        assertEquals(1500, usage.posters.bytes)
        assertEquals(2500, usage.logos.bytes)
        assertEquals(800, usage.other.bytes)
        assertEquals(0, usage.backdrops.bytes)
        assertEquals(4800, usage.total.bytes)
        assertTrue(usage.posters.fileCount == 1)
        root.deleteRecursively()
    }

    @Test
    fun countsMetadataFoldersSeparately() {
        val root = File.createTempFile("zelefin-meta", "").apply {
            delete()
            mkdirs()
        }
        File(root, "HomeSnapshots").apply { mkdirs() }.resolve("a.json").writeText("home")
        File(root, "CatalogSnapshots").apply { mkdirs() }.resolve("b.json").writeText("catalogs")
        File(root, "ItemDetailSnapshots").apply { mkdirs() }.resolve("c.json").writeText("title")
        val usage = CacheInventory.metadataUsage(root)
        assertEquals("home".length.toLong(), usage.home.bytes)
        assertEquals("catalogs".length.toLong(), usage.catalog.bytes)
        assertEquals("title".length.toLong(), usage.itemDetail.bytes)
        assertEquals(usage.home.bytes + usage.catalog.bytes + usage.itemDetail.bytes, usage.total.bytes)
        assertEquals("Home", MetadataCacheFolder.Home.title)
        assertEquals("Title details", MetadataCacheFolder.ItemDetail.title)
        root.deleteRecursively()
    }

    @Test
    fun formatsZeroAsKilobytes() {
        assertEquals("0 KB", CacheInventory.formatBytes(0))
        assertEquals("0 KB", CacheInventory.formatBytes(-4))
    }
}
