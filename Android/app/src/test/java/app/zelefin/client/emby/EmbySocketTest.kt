package app.zelefin.client.emby

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class EmbySocketTest {
    @Test
    fun socketUrlUsesEmbysPathAndTheMatchingScheme() {
        assertEquals(
            "ws://emby.example.test:8096/embywebsocket?api_key=tok&deviceId=dev-1",
            EmbySocketMessages.url("http://emby.example.test:8096", "tok", "dev-1"),
        )
        assertEquals(
            "wss://media.example.com/emby/embywebsocket?api_key=tok&deviceId=a%2Bb",
            EmbySocketMessages.url("https://media.example.com/emby/", "tok", "a+b"),
        )
        assertNull(EmbySocketMessages.url("ftp://x", "tok", "dev"))
    }

    @Test
    fun keepAlive() {
        assertEquals(EmbySocketEvent.KeepAlive(60), EmbySocketMessages.parse("""{"MessageType":"ForceKeepAlive","Data":60}"""))
        assertEquals(EmbySocketEvent.KeepAlive(60), EmbySocketMessages.parse("""{"MessageType":"ForceKeepAlive"}"""))
        assertNull(EmbySocketMessages.parse("""{"MessageType":"KeepAlive"}"""))
    }

    @Test
    fun play() {
        val event = EmbySocketMessages.parse(
            """{"MessageType":"Play","Data":{"ItemIds":["1093","1213"],"StartIndex":1,"StartPositionTicks":600000000,"PlayCommand":"PlayNow","ControllingUserId":"u1"}}""",
        ) as EmbySocketEvent.Play
        assertEquals("1213", event.itemId)
        assertEquals(60.0, event.startSeconds, 0.0)
        assertEquals("PlayNow", event.command)
        val minimal = EmbySocketMessages.parse("""{"MessageType":"Play","Data":{"ItemIds":[1093]}}""") as EmbySocketEvent.Play
        assertEquals("1093", minimal.itemId)
        assertEquals(0.0, minimal.startSeconds, 0.0)
        assertNull(EmbySocketMessages.parse("""{"MessageType":"Play","Data":{"ItemIds":[]}}"""))
    }

    @Test
    fun playstate() {
        assertEquals(EmbySocketEvent.Playstate("Pause", null), EmbySocketMessages.parse("""{"MessageType":"Playstate","Data":{"Command":"Pause"}}"""))
        assertEquals(
            EmbySocketEvent.Playstate("Seek", 125.5),
            EmbySocketMessages.parse("""{"MessageType":"Playstate","Data":{"Command":"Seek","SeekPositionTicks":1255000000}}"""),
        )
        assertNull(EmbySocketMessages.parse("""{"MessageType":"Playstate","Data":{}}"""))
    }

    @Test
    fun messages() {
        assertEquals(
            EmbySocketEvent.Message("Dinner", "Pause the movie", 5000),
            EmbySocketMessages.parse(
                """{"MessageType":"GeneralCommand","Data":{"Name":"DisplayMessage","Arguments":{"Header":"Dinner","Text":"Pause the movie","TimeoutMs":"5000"}}}""",
            ),
        )
        assertEquals(
            EmbySocketEvent.Message("Hello", "Hello", null),
            EmbySocketMessages.parse("""{"MessageType":"DisplayMessage","Data":{"Header":"Hello"}}"""),
        )
        assertEquals(
            EmbySocketEvent.Command("SetVolume", mapOf("Volume" to "40")),
            EmbySocketMessages.parse("""{"MessageType":"GeneralCommand","Data":{"Name":"SetVolume","Arguments":{"Volume":"40"}}}"""),
        )
    }

    @Test
    fun userDataAndJunk() {
        assertEquals(
            EmbySocketEvent.UserDataChanged(listOf("1093")),
            EmbySocketMessages.parse("""{"MessageType":"UserDataChanged","Data":{"UserId":"u1","UserDataList":[{"ItemId":"1093","Played":true}]}}"""),
        )
        assertNull(EmbySocketMessages.parse("""{"MessageType":"LibraryChanged","Data":{}}"""))
        assertNull(EmbySocketMessages.parse("not json"))
        assertEquals("""{"MessageType":"KeepAlive"}""", EmbySocketMessages.KeepAlive)
    }
}
