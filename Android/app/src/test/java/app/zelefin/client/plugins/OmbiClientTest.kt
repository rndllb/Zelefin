package app.zelefin.client.plugins

import org.junit.Assert.assertEquals
import org.junit.Test

class OmbiClientTest {
    @Test
    fun searchTitlesLoseTheirYear() {
        assertEquals("Dune" to 2021, OmbiClient.splitYear("Dune (2021)"))
        assertEquals("Dune: Prophecy" to null, OmbiClient.splitYear("Dune: Prophecy"))
        assertEquals("Blade Runner 2049" to 2017, OmbiClient.splitYear("Blade Runner 2049 (2017)"))
        assertEquals("Movie (Director's Cut)" to null, OmbiClient.splitYear("Movie (Director's Cut)"))
    }

    @Test
    fun requestUrlsKeepOneSlashAndTheProxyPath() {
        assertEquals("http://zimaos.local:3579/api/v1/Token", OmbiClient.url("http://zimaos.local:3579", "api/v1/Token").toString())
        assertEquals("https://example.com/ombi/api/v1/Token", OmbiClient.url("https://example.com/ombi", "/api/v1/Token").toString())
    }
}
