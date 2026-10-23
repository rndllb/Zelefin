package app.zelefin.client.downloads

import org.junit.Assert.assertEquals
import org.junit.Test

class DownloadFailureMessageTest {
    @Test
    fun refusedDownloadsShowTheServersReason() {
        assertEquals(
            "You are not allowed to download this item",
            downloadFailureMessage(403, """{"Error":"Forbidden","Message":"You are not allowed to download this item"}"""),
        )
        assertEquals("This server doesn't allow downloads for this account.", downloadFailureMessage(403, null))
        assertEquals("Downloads aren't available on this server.", downloadFailureMessage(503, "<html></html>"))
        assertEquals("Media file not found", downloadFailureMessage(404, """{"title":"Not Found","detail":"Media file not found"}"""))
        assertEquals(ZelefinDownloads.FailureMessage, downloadFailureMessage(500, null))
    }
}
