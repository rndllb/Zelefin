package app.zelefin.client.emby

import app.zelefin.client.plugins.SkipSegment
import app.zelefin.core.EmbyChapter
import app.zelefin.core.EmbyJson
import app.zelefin.core.EmbyMediaSource
import app.zelefin.core.EmbyMediaStream
import app.zelefin.core.EmbyPlaybackInfo
import app.zelefin.core.PlaybackMethod
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EmbyPlaybackTest {
    private val base = "http://emby.example.test:8096"

    private fun info(json: String) = EmbyJson.parser.decodeFromString(EmbyPlaybackInfo.serializer(), json)

    private val streams = """
        [{"Codec":"h264","Type":"Video","Index":0,"IsDefault":true},
         {"Codec":"eac3","Language":"eng","Type":"Audio","Index":1,"IsDefault":true},
         {"Codec":"eac3","Language":"tur","Type":"Audio","Index":2},
         {"Codec":"subrip","Language":"tur","Type":"Subtitle","Index":3,"IsDefault":true,"DeliveryMethod":"Embed"},
         {"Codec":"subrip","Language":"eng","Type":"Subtitle","Index":4,"DeliveryMethod":"Embed"}]
    """.trimIndent()

    private val directPlay = info(
        """
        {"MediaSources":[
          {"Id":"mediasource_1093","Container":"mkv","Bitrate":10664843,"SupportsDirectPlay":true,"SupportsDirectStream":true,"SupportsTranscoding":true,
           "DirectStreamUrl":"/videos/1093/original.mkv?DeviceId=dev&MediaSourceId=mediasource_1093&PlaySessionId=ps1&api_key=tok",
           "DefaultAudioStreamIndex":1,"MediaStreams":$streams}],
         "PlaySessionId":"ps1"}
        """.trimIndent(),
    )

    private val transcode = info(
        """
        {"MediaSources":[
          {"Id":"mediasource_1093","Container":"mkv","SupportsDirectPlay":false,"SupportsDirectStream":false,"SupportsTranscoding":true,
           "TranscodingUrl":"/videos/1093/master.m3u8?DeviceId=dev&MediaSourceId=mediasource_1093&PlaySessionId=ps2&api_key=tok&StartTimeTicks=600000000&SegmentContainer=mp4",
           "DefaultAudioStreamIndex":1,"MediaStreams":[
             {"Codec":"h264","Type":"Video","Index":0},
             {"Codec":"eac3","Language":"eng","Type":"Audio","Index":1},
             {"Codec":"subrip","Language":"tur","Type":"Subtitle","Index":3,"DeliveryMethod":"External","DeliveryUrl":"/Videos/1093/mediasource_1093/Subtitles/3/0/Stream.subrip?api_key=tok"},
             {"Codec":"subrip","Language":"eng","Type":"Subtitle","Index":4,"DeliveryMethod":"External","DeliveryUrl":"/Videos/1093/mediasource_1093/Subtitles/4/0/Stream.subrip?api_key=tok"},
             {"Codec":"pgssub","Language":"eng","Type":"Subtitle","Index":5,"DeliveryMethod":"Encode"}]}],
         "PlaySessionId":"ps2"}
        """.trimIndent(),
    )

    @Test
    fun picksTheRequestedVersionByItsSourceId() {
        val two = info("""{"MediaSources":[{"Id":"mediasource_1"},{"Id":"mediasource_2"}]}""")
        assertEquals("mediasource_2", EmbyPlayback.source(two, "mediasource_2")?.id)
        assertEquals("mediasource_1", EmbyPlayback.source(two, "1093")?.id)
        assertEquals("mediasource_1", EmbyPlayback.source(two, null)?.id)
        assertNull(EmbyPlayback.source(info("""{"MediaSources":[]}"""), null))
    }

    @Test
    fun choosesTheMethodLikeJellyfin() {
        assertEquals(PlaybackMethod.DirectPlay, EmbyPlayback.method(directPlay.mediaSources[0]))
        assertEquals(PlaybackMethod.Transcode, EmbyPlayback.method(transcode.mediaSources[0]))
        val remux = EmbyMediaSource(supportsDirectStream = true, supportsTranscoding = true, transcodingUrl = "/videos/1/master.m3u8")
        assertEquals(PlaybackMethod.Remux, EmbyPlayback.method(remux))
        assertEquals(PlaybackMethod.DirectPlay, EmbyPlayback.method(EmbyMediaSource(supportsDirectStream = true)))
    }

    @Test
    fun directPlayUsesEmbysDirectStreamUrl() {
        val url = EmbyPlayback.streamUrl(base, "tok", "1093", directPlay.mediaSources[0], PlaybackMethod.DirectPlay, "dev", "ps1")
        assertEquals("$base/videos/1093/original.mkv?DeviceId=dev&MediaSourceId=mediasource_1093&PlaySessionId=ps1&api_key=tok", url)
    }

    @Test
    fun directPlayWithoutAUrlBuildsTheStaticStream() {
        val source = EmbyMediaSource(id = "mediasource_1093", container = "mkv,webm", supportsDirectPlay = true)
        val url = EmbyPlayback.streamUrl(base, "tok", "1093", source, PlaybackMethod.DirectPlay, "dev", "ps1")
        assertEquals("$base/Videos/1093/stream.mkv?Static=true&MediaSourceId=mediasource_1093&DeviceId=dev&PlaySessionId=ps1&api_key=tok", url)
    }

    @Test
    fun transcodeOpensHlsAtZero() {
        val url = EmbyPlayback.streamUrl(base, "tok", "1093", transcode.mediaSources[0], PlaybackMethod.Transcode, "dev", "ps2")!!
        assertTrue(url.startsWith("$base/videos/1093/master.m3u8?"))
        assertTrue("StartTimeTicks" !in url)
        assertEquals(1, Regex("api_key=").findAll(url).count())
    }

    @Test
    fun transcodeSideloadsTextSubtitles() {
        val subtitles = EmbyPlayback.externalSubtitles(base, "tok", "1093", transcode.mediaSources[0], PlaybackMethod.Transcode)
        assertEquals(listOf("jf-ext-3", "jf-ext-4"), subtitles.map { it.id })
        assertEquals("$base/Videos/1093/mediasource_1093/Subtitles/3/0/Stream.subrip?api_key=tok", subtitles[0].url)
        assertEquals(androidx.media3.common.MimeTypes.APPLICATION_SUBRIP, subtitles[0].mimeType)
        assertEquals("tur", subtitles[0].language)
        assertEquals(setOf(3, 4), EmbyPlayback.sideloadedIndexes(subtitles))
    }

    @Test
    fun directPlayOnlySideloadsFilesBesideTheVideo() {
        val source = EmbyMediaSource(
            id = "mediasource_1093",
            mediaStreams = listOf(
                EmbyMediaStream(index = 3, type = "Subtitle", codec = "subrip", deliveryMethod = "External", deliveryUrl = "/Videos/1093/mediasource_1093/Subtitles/3/0/Stream.srt"),
                EmbyMediaStream(index = 7, type = "Subtitle", codec = "srt", language = "eng", isExternal = true, deliveryMethod = "External"),
            ),
        )
        val subtitles = EmbyPlayback.externalSubtitles(base, "tok", "1093", source, PlaybackMethod.DirectPlay)
        assertEquals(listOf("jf-ext-7"), subtitles.map { it.id })
        assertEquals("$base/Videos/1093/mediasource_1093/Subtitles/7/Stream.srt?api_key=tok", subtitles.single().url)
    }

    @Test
    fun trackChoicesCountOnlyTracksInsideTheContainer() {
        val source = directPlay.mediaSources[0]
        val audio = EmbyPlayback.trackChoice(source.mediaStreams, subtitles = false, index = 2)!!
        assertEquals(1, audio.ordinal)
        assertEquals("tur", audio.language)
        val embedded = EmbyPlayback.trackChoice(source.mediaStreams, subtitles = true, index = 4)!!
        assertEquals(1, embedded.ordinal)
        assertNull(embedded.externalId)
        val sideloaded = EmbyPlayback.trackChoice(transcode.mediaSources[0].mediaStreams, subtitles = true, index = 4, sideloaded = setOf(3, 4))!!
        assertEquals("jf-ext-4", sideloaded.externalId)
        assertNull(EmbyPlayback.trackChoice(source.mediaStreams, subtitles = true, index = 9))
    }

    @Test
    fun languageTracksFollowTheUserScopedDefault() {
        val streams = directPlay.mediaSources[0].mediaStreams
        val scoped = EmbyPlayback.languageTracks(streams, subtitles = true, selectedIndex = null, scoped = true)
        assertTrue(scoped.none { it.isSelected })
        val unscoped = EmbyPlayback.languageTracks(streams, subtitles = true, selectedIndex = null, scoped = false)
        assertEquals(listOf(3), unscoped.filter { it.isSelected }.map { it.index })
        val audio = EmbyPlayback.languageTracks(streams, subtitles = false, selectedIndex = 2, scoped = true)
        assertEquals(listOf(2), audio.filter { it.isSelected }.map { it.index })
    }

    private val chapters = listOf(
        EmbyChapter(0, "Chapter 1", "Chapter"),
        EmbyChapter(600_000_000, "Intro", "IntroStart"),
        EmbyChapter(900_000_000, "Intro End", "IntroEnd"),
        EmbyChapter(1_200_000_000, "Chapter 2", "Chapter"),
        EmbyChapter(25_000_000_000, "Credits", "CreditsStart"),
    )

    @Test
    fun chapterMarkersBecomeSkipSegments() {
        val segments = EmbyPlayback.skipSegments(chapters, runtimeSeconds = 2600.0)
        assertEquals(
            listOf(SkipSegment(SkipSegment.Kind.Intro, 60.0, 90.0), SkipSegment(SkipSegment.Kind.Outro, 2500.0, 2600.0)),
            segments,
        )
        assertEquals(SkipSegment.Kind.Intro, SkipSegment.prompt(segments, 70.0)?.kind)
        assertEquals(90.0, SkipSegment.prompt(segments, 70.0)!!.seekTo, 0.0)
    }

    @Test
    fun missingOrTinyMarkersSkipNothing() {
        assertTrue(EmbyPlayback.skipSegments(chapters.filterNot { it.isMarker }, 2600.0).isEmpty())
        val tiny = listOf(EmbyChapter(600_000_000, null, "IntroStart"), EmbyChapter(610_000_000, null, "IntroEnd"))
        assertTrue(EmbyPlayback.skipSegments(tiny, 2600.0).isEmpty())
        val creditsOnly = listOf(EmbyChapter(25_000_000_000, null, "CreditsStart"))
        assertTrue(EmbyPlayback.skipSegments(creditsOnly, runtimeSeconds = null).isEmpty())
        val introEndOnly = listOf(EmbyChapter(450_000_000, null, "IntroEnd"))
        assertEquals(listOf(SkipSegment(SkipSegment.Kind.Intro, 0.0, 45.0)), EmbyPlayback.skipSegments(introEndOnly, 2600.0))
    }

    @Test
    fun timelineChaptersLeaveMarkersOut() {
        val timeline = EmbyPlayback.chapters(chapters)
        assertEquals(listOf("Chapter 1", "Chapter 2"), timeline.map { it.name })
        assertEquals(listOf(0.0, 120.0), timeline.map { it.startSeconds })
    }
}
