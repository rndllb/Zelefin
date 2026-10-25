package app.zelefin.client.emby

import org.junit.Assert.assertEquals
import org.junit.Test

class EmbyApiTest {
    private val api = EmbyApi("http://emby.lan:8096/", accessToken = "tok", deviceId = "dev-1", deviceName = "Ana’s \"Pixel\" 📺", version = "0.1.0")

    @Test
    fun authorizationHeaderStaysPrintableAscii() {
        assertEquals("MediaBrowser Client=\"Zelefin\", Device=\"Ana's Pixel\", DeviceId=\"dev-1\", Version=\"0.1.0\"", api.authorization)
    }

    @Test
    fun mediaUrlsCarryTheTokenAndEncodeValues() {
        val url = api.url("/Videos/1093/index.bif", embyQuery { this["Width"] = 320 })
        assertEquals("http://emby.lan:8096/Videos/1093/index.bif?Width=320&api_key=tok", url)
        assertEquals("http://emby.lan:8096/Items?SearchTerm=a%20b%26c", api.url("/Items", listOf("SearchTerm" to "a b&c"), token = false))
    }

    @Test
    fun queriesDropEmptyValuesAndJoinLists() {
        val query = embyQuery {
            this["ParentId"] = null
            this["Filters"] = emptyList<String>()
            this["IncludeItemTypes"] = listOf("Movie", "Series")
            this["IsHD"] = true
            pipe("Genres", listOf("Horror", "Sci-Fi"))
            pipe("Tags", emptyList())
        }
        assertEquals(listOf("IncludeItemTypes" to "Movie,Series", "IsHD" to "true", "Genres" to "Horror|Sci-Fi"), query)
    }
}
