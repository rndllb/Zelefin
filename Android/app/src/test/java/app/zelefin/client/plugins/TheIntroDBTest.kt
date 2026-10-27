package app.zelefin.client.plugins

import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TheIntroDBTest {
    @Test
    fun responseBecomesSegments() {
        val body = """
            {"tvdb_id":81189,"type":"tv","season":1,"episode":1,
             "recap":[{"start_ms":null,"end_ms":45000}],
             "intro":[{"start_ms":228566,"end_ms":246538}],
             "credits":[{"start_ms":3431000,"end_ms":null}],
             "preview":[{"start_ms":3440000,"end_ms":3441000}]}
        """.trimIndent()
        val segments = TheIntroDB.parse(body, runtime = 3480.0)
        assertEquals(listOf(SkipSegment.Kind.Recap, SkipSegment.Kind.Intro, SkipSegment.Kind.Outro), segments.map { it.kind })
        assertEquals(0.0, segments[0].start, 0.0)
        assertEquals(228.566, segments[1].start, 0.001)
        assertEquals(3480.0, segments[2].end, 0.0)
    }

    @Test
    fun openEndedCreditsNeedARuntime() {
        assertTrue(TheIntroDB.parse("""{"credits":[{"start_ms":3431000,"end_ms":null}]}""", runtime = null).isEmpty())
        assertTrue(TheIntroDB.parse("""{"error":"no submissions"}""", runtime = 100.0).isEmpty())
    }

    @Test
    fun lookupUrl() {
        val url = TheIntroDB.url(TheIntroDB.Lookup(81189, 1396, "tt0903747", 1, 2, 2_901_920))!!.toHttpUrl()
        assertEquals("api.theintrodb.org", url.host)
        assertEquals("81189", url.queryParameter("tvdb_id"))
        assertEquals("1", url.queryParameter("season"))
        assertEquals("2901920", url.queryParameter("duration_ms"))
        assertNull(TheIntroDB.url(TheIntroDB.Lookup()))
        assertEquals(listOf("tmdb_id"), TheIntroDB.url(TheIntroDB.Lookup(tmdbId = 603))!!.toHttpUrl().queryParameterNames.toList())
    }

    @Test
    fun recapAndPreviewGetTheirOwnButtons() {
        val segments = listOf(
            SkipSegment(SkipSegment.Kind.Intro, 75.0, 110.0),
            SkipSegment(SkipSegment.Kind.Recap, 0.0, 75.0),
            SkipSegment(SkipSegment.Kind.Preview, 2580.0, 2640.0),
        )
        assertEquals("Skip Recap", SkipSegment.prompt(segments, 5.0)?.title)
        assertEquals("Skip Intro", SkipSegment.prompt(segments, 80.0)?.title)
        assertEquals("Skip Preview", SkipSegment.prompt(segments, 2600.0)?.title)
    }

    @Test
    fun detectsThePluginByName() {
        assertTrue(TheIntroDBPlugin.isInstalled(listOf("TheIntroDB")))
        assertTrue(!TheIntroDBPlugin.isInstalled(listOf("Intro Skipper")))
        assertTrue(!IntroSkipperPlugin.isInstalled(listOf("TheIntroDB")))
    }

    @Test
    fun pluginPresenceAndGreyedRows() {
        val entries = listOf(
            PluginEntry("Intro Skipper", enabled = false),
            PluginEntry("TheIntroDB", enabled = true),
            PluginEntry("TheIntroDB", enabled = false),
        )
        assertEquals(PluginPresence.Disabled, PluginPresence.of(entries) { IntroSkipperPlugin.isInstalled(listOf(it)) })
        assertEquals(PluginPresence.Enabled, PluginPresence.of(entries) { TheIntroDBPlugin.isInstalled(listOf(it)) })
        assertEquals(PluginPresence.NotInstalled, PluginPresence.of(entries) { it == "Open Subtitles" })
        assertTrue(SkipPluginChoice.isGreyedOut(PluginPresence.Disabled, PluginPresence.Enabled))
        assertTrue(!SkipPluginChoice.isGreyedOut(PluginPresence.Enabled, PluginPresence.Enabled))
        assertTrue(!SkipPluginChoice.isGreyedOut(PluginPresence.Disabled, PluginPresence.NotInstalled))
    }
}
