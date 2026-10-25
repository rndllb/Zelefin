package app.zelefin.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EmbyModelsTest {
    @Test
    fun detectsEmbyFromItsPublicInfo() {
        assertTrue(
            EmbyDetection.isEmby(
                """{"LocalAddress":"http://emby.example.test:8096","ServerName":"emby","Version":"4.10.2.0","Id":"0f1e2d3c4b5a69788796a5b4c3d2e1f0"}""",
            ),
        )
        assertFalse(EmbyDetection.isEmby("""{"ServerName":"jf","Version":"10.10.7","ProductName":"Jellyfin Server","Id":"x"}"""))
        assertFalse(EmbyDetection.isEmby("""{"ServerName":"odd","Version":"10.9.0"}"""))
        assertFalse(EmbyDetection.isEmby("""{"ServerName":"none"}"""))
        assertFalse(EmbyDetection.isEmby("<html>not json</html>"))
    }

    private val movie = """
        {"Name":"Halloween Kills","Id":"1093","Type":"Movie","Container":"mkv","PremiereDate":"2021-10-14T00:00:00.0000000Z",
         "CriticRating":38,"OfficialRating":"R","Overview":"Michael manages to free himself. ","Genres":["Horror"],
         "CommunityRating":6.4,"RunTimeTicks":63889920000,"ProductionYear":2021,
         "ProviderIds":{"Imdb":"tt10665338","Tmdb":"610253"},
         "Studios":[{"Name":"Blumhouse Productions","Id":3603}],"GenreItems":[{"Name":"Horror","Id":2070}],
         "UserData":{"PlaybackPositionTicks":12000000000,"PlayCount":0,"IsFavorite":true,"Played":false},
         "ImageTags":{"Primary":"p1","Logo":"l1","Thumb":"t1"},"BackdropImageTags":["b1","b2"],
         "People":[
           {"Name":"David Gordon Green","Id":"3778","Type":"Director"},
           {"Name":"Danny McBride","Id":"3779","Type":"Writer","PrimaryImageTag":"c3"},
           {"Name":"Jamie Lee Curtis","Id":"12","Role":"Laurie Strode","Type":"Actor"},
           {"Name":"David Gordon Green","Id":"3778","Type":"Writer"}
         ],
         "MediaSources":[{"Id":"mediasource_1093","Container":"mkv","Bitrate":10664843,"SupportsDirectPlay":true,
           "MediaStreams":[],"Chapters":[{"StartPositionTicks":0,"Name":"Chapter 1","MarkerType":"Chapter","ChapterIndex":0}]}],
         "MediaStreams":[
           {"Codec":"h264","VideoRange":"SDR","ExtendedVideoType":"None","DisplayTitle":"1080p H264","Height":800,"Width":1920,"Type":"Video","Index":0,"IsDefault":true},
           {"Codec":"eac3","Language":"eng","DisplayTitle":"English EAC3 5.1 (Default)","ChannelLayout":"5.1","Channels":6,"Type":"Audio","Index":1,"IsDefault":true},
           {"Codec":"subrip","Language":"tur","DisplayTitle":"Turkish (Default SUBRIP)","Type":"Subtitle","Index":3,"IsDefault":true}
         ],
         "Width":1920,"Height":800}
    """.trimIndent()

    @Test
    fun movieMapsLikeAJellyfinItem() {
        val dto = EmbyJson.parser.decodeFromString(EmbyItem.serializer(), movie)
        assertEquals("3603", dto.studios.single().id)
        val item = ItemMapper.mediaItem(dto.toSnapshot())!!
        assertEquals("1093", item.id)
        assertEquals(MediaKind.Movie, item.kind)
        assertEquals("Michael manages to free himself.", item.overview)
        assertEquals(2021, item.year)
        assertEquals(6388.992, item.runtime!!, 0.001)
        assertEquals("R", item.officialRating)
        assertEquals(listOf("Horror"), item.genres)
        assertEquals(610253, item.tmdbId)
        assertEquals(38.0, item.criticRating!!, 0.0)
        assertEquals(6.4, item.communityRating!!, 0.0)
        assertEquals(1200.0, item.playbackPosition, 0.0)
        assertTrue(item.isFavorite)
        assertFalse(item.isPlayed)
        assertEquals("p1", item.primaryImageTag)
        assertEquals("t1", item.thumbImageTag)
        assertEquals("l1", item.logoImageTag)
        assertEquals(listOf("b1", "b2"), item.backdropImageTags)
        assertEquals(VideoResolution.Hd, item.videoResolution)
        assertEquals(VideoRange.Sdr, item.videoRange)
        assertEquals(AudioFormat.Surround, item.audioFormat)
        assertTrue(item.hasClosedCaptions)
        assertEquals("mediasource_1093", item.mediaSourceId)
        assertEquals("2021-10-14T00:00:00.0000000Z", item.premiereDate)
        assertEquals(listOf("12", "3778", "3779"), item.people.map { it.id })
        assertEquals("Laurie Strode", item.people[0].roleLabel)
        assertEquals("Director", item.people[1].roleLabel)
        assertEquals("c3", item.people[2].imageTag)
    }

    @Test
    fun episodeKeepsItsShowAndPlace() {
        val episode = """
            {"Name":"Pilot","Id":"40968","Type":"Episode","IndexNumber":1,"ParentIndexNumber":1,"SeriesName":"Pretty Little Liars",
             "SeriesId":"40944","SeriesPrimaryImageTag":"sp","ParentBackdropItemId":"40944","ParentLogoItemId":"40944","ParentLogoImageTag":"lg",
             "UserData":{"PlaybackPositionTicks":0,"Played":true},"ImageTags":{},"BackdropImageTags":[],
             "MediaSources":[{"Id":"mediasource_40968","MediaStreams":[
               {"Codec":"hevc","ExtendedVideoType":"DolbyVision","VideoRange":"HDR","Width":3840,"Height":2160,"Type":"Video","Index":0},
               {"Codec":"truehd","Title":"TrueHD Atmos 7.1","Channels":8,"Type":"Audio","Index":1}]}]}
        """.trimIndent()
        val item = ItemMapper.mediaItem(EmbyJson.parser.decodeFromString(EmbyItem.serializer(), episode).toSnapshot(), PlaybackQueueKind.NextUp)!!
        assertEquals(MediaKind.Episode, item.kind)
        assertEquals(1, item.seasonIndex)
        assertEquals(1, item.episodeIndex)
        assertEquals("40944", item.seriesId)
        assertEquals("40944", item.seriesDetailItemId)
        assertEquals("40944", item.parentBackdropItemId)
        assertEquals("lg", item.parentLogoImageTag)
        assertTrue(item.isPlayed)
        assertEquals(PlaybackQueueKind.NextUp, item.queueKind)
        assertEquals(VideoRange.DolbyVision, item.videoRange)
        assertEquals(VideoResolution.FourK, item.videoResolution)
        assertEquals(AudioFormat.Atmos, item.audioFormat)
        assertEquals("mediasource_40968", item.mediaSourceId)
    }

    @Test
    fun hdrFlavorsComeFromTheExtendedVideoType() {
        fun range(extended: String, plain: String = "HDR"): VideoRange {
            val json = """{"Id":"1","Name":"x","Type":"Movie","MediaStreams":[{"Type":"Video","ExtendedVideoType":"$extended","VideoRange":"$plain"}]}"""
            return ItemMapper.mediaItem(EmbyJson.parser.decodeFromString(EmbyItem.serializer(), json).toSnapshot())!!.videoRange
        }
        assertEquals(VideoRange.Hlg, range("HyperLogGamma"))
        assertEquals(VideoRange.Hdr10Plus, range("Hdr10Plus"))
        assertEquals(VideoRange.Hdr10, range("Hdr10"))
        assertEquals(VideoRange.Sdr, range("None", "SDR"))
    }

    @Test
    fun foldersAndViewsAreNotTitles() {
        val view = """{"Name":"Anime","Id":"35349","Type":"CollectionFolder","ImageTags":{"Primary":"x"}}"""
        assertNull(ItemMapper.mediaItem(EmbyJson.parser.decodeFromString(EmbyItem.serializer(), view).toSnapshot()))
        val boxSet = """{"Name":"Halloween Collection","Id":"4865","Type":"BoxSet","ChildCount":11}"""
        assertEquals(MediaKind.Collection, ItemMapper.mediaItem(EmbyJson.parser.decodeFromString(EmbyItem.serializer(), boxSet).toSnapshot())?.kind)
    }

    @Test
    fun liveStreamIdIsKeptOnTheSource() {
        val source = EmbyJson.parser.decodeFromString(EmbyMediaSource.serializer(), """{"Id":"src","LiveStreamId":"live-7","SupportsDirectPlay":false}""")
        assertEquals("live-7", source.liveStreamId)
    }

    @Test
    fun chapterMarkersAreNotChapters() {
        assertFalse(EmbyChapter(0, "Chapter 1", "Chapter").isMarker)
        assertFalse(EmbyChapter(0, "Chapter 1", null).isMarker)
        assertTrue(EmbyChapter(0, "Intro", "IntroStart").isMarker)
        assertTrue(EmbyChapter(0, "Credits", "CreditsStart").isMarker)
    }
}
