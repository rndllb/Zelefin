package app.zelefin.client

import app.zelefin.client.ui.LogLine
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ZelefinLogTest {
    @Test
    fun secretsNeverReachTheLog() {
        val line = ZelefinLog.redact(
            """GET host/Videos/1/stream?api_key=abc123&Static=true X-Emby-Token=tok9 Authorization: Bearer eyJhbGciOi.x.y MediaBrowser Client="Zelefin", Token="sekret" {"Username":"Avery","Pw":"pw-4471","password":"hunter2"}""",
        )
        for (secret in listOf("abc123", "tok9", "eyJhbGciOi", "sekret", "pw-4471", "hunter2")) {
            assertFalse("$secret leaked: $line", line.contains(secret))
        }
        assertTrue(line.contains("Static=true"))
        assertTrue(line.contains("Avery"))
    }

    @Test
    fun linesParseIntoTheirParts() {
        val line = LogLine.of("2026-11-01 08:41:03.120 WARN [Network] GET host/Items → 404")
        assertEquals(ZelefinLog.Level.Warning, line.level)
        assertEquals("Network", line.category)
        assertEquals("GET host/Items → 404", line.message)
        assertEquals("11-01 08:41:03", line.time)
        assertEquals(listOf("b", "a"), LogLine.parse("2026-11-01 08:41:03.120 INFO [X] a\n2026-11-01 08:41:04.120 INFO [X] b\n").map { it.message })
    }

    @Test
    fun expectedAnswersStayOutOfTheLog() {
        val host = "jellyfin.example.com"
        assertTrue(ZelefinLog.isExpectedStatus("/socket", host, 101))
        assertTrue(ZelefinLog.isExpectedStatus("/api/v2/system/setup", host, 404))
        assertTrue(ZelefinLog.isExpectedStatus("/Episode/abc/IntroSkipperSegments", host, 404))
        assertTrue(ZelefinLog.isExpectedStatus("/Episode/abc/IntroTimestamps", host, 404))
        assertTrue(ZelefinLog.isExpectedStatus("/Items/abc/Images/Logo", host, 404))
        assertFalse(ZelefinLog.isExpectedStatus("/Items/abc", host, 404))
        assertFalse(ZelefinLog.isExpectedStatus("/Episode/abc/IntroSkipperSegments", host, 500))
        assertFalse(ZelefinLog.isExpectedStatus("/JellyfinEnhanced/awards/movie/584", host, 503))
    }
}
