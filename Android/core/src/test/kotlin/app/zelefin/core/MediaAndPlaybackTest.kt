package app.zelefin.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TickClockTest {
    @Test
    fun secondsRoundTrip() {
        val ticks = 90L * TickClock.TICKS_PER_SECOND
        assertEquals(90.0, TickClock.seconds(ticks), 0.001)
        assertEquals(ticks, TickClock.ticks(90.0))
    }
}

class MediaItemTest {
    @Test
    fun progressClamps() {
        val item = MediaItem(
            id = "1",
            name = "Dune",
            kind = MediaKind.Movie,
            year = 2024,
            runtime = 100.0,
            officialRating = "PG-13",
            genres = listOf("Action", "Adventure"),
            playbackPosition = 40.0,
        )
        assertEquals(0.4, item.progress, 0.001)
        assertEquals("2m", item.runtimeLabel)
    }

    @Test
    fun playActionDurationUsesRemainingWhenInProgress() {
        val item = MediaItem(
            id = "1",
            name = "Batman Begins",
            kind = MediaKind.Movie,
            runtime = 8400.0,
            officialRating = "PG-13",
            playbackPosition = 600.0,
        )
        assertEquals("2h 10m", item.playActionDurationLabel)
        assertEquals("Movie", item.kindLabel)
        assertEquals("2h 20m", item.runtimeLabel)
        assertEquals("13+", item.ageGateLabel)
    }

    @Test
    fun playActionDurationUsesRuntimeWhenUnwatched() {
        val item = MediaItem(
            id = "1",
            name = "Batman Begins",
            kind = MediaKind.Movie,
            runtime = 8400.0,
            playbackPosition = 0.0,
        )
        assertEquals("2h 20m", item.playActionDurationLabel)
    }

    @Test
    fun playActionDurationKeepsRemainingWhenUnderAMinute() {
        val item = MediaItem(id = "1", name = "Batman Begins", kind = MediaKind.Movie, runtime = 8400.0, playbackPosition = 8360.0)
        assertEquals("1m", item.playActionDurationLabel)
    }

    @Test
    fun playActionDurationFloorsRemainingMinutes() {
        val item = MediaItem(id = "1", name = "Batman Begins", kind = MediaKind.Movie, runtime = 8400.0, playbackPosition = 7764.0)
        assertEquals("10m", item.playActionDurationLabel)
    }

    @Test
    fun heroPlaybackItemUsesInProgressEpisode() {
        val show = MediaItem(id = "show", name = "Silo", kind = MediaKind.Series, runtime = 79_200.0, officialRating = "TV-MA")
        val watched = MediaItem(
            id = "e1",
            name = "Freedom Day",
            kind = MediaKind.Episode,
            runtime = 2400.0,
            seriesName = "Silo",
            seasonIndex = 1,
            episodeIndex = 1,
            playbackPosition = 2400.0,
            isPlayed = true,
            seriesId = "show",
        )
        val current = MediaItem(
            id = "e2",
            name = "Holston's Pick",
            kind = MediaKind.Episode,
            runtime = 2400.0,
            seriesName = "Silo",
            seasonIndex = 1,
            episodeIndex = 2,
            playbackPosition = 600.0,
            seriesId = "show",
        )
        val target = MediaItem.heroPlaybackItem(show, listOf(watched, current))
        assertEquals("e2", target.id)
        assertEquals("30m", target.playActionDurationLabel)
        assertEquals("22h", show.playActionDurationLabel)
    }

    @Test
    fun episodeLabel() {
        val episode = MediaItem(
            id = "e1",
            name = "The Gift",
            kind = MediaKind.Episode,
            seriesName = "The Bear",
            seasonIndex = 1,
            episodeIndex = 1,
            runtime = 1800.0,
            playbackPosition = 600.0,
        )
        assertEquals("S1, E1 · 20m", episode.episodeLabel)
    }

    @Test
    fun playedEpisodeIsWatched() {
        val episode = MediaItem(id = "e", name = "One", kind = MediaKind.Episode, runtime = 1000.0, isPlayed = true)
        assertTrue(episode.isWatched)
    }

    @Test
    fun episodePlayedToTheEndIsWatchedWithoutPlayedFlag() {
        val episode = MediaItem(
            id = "e",
            name = "One",
            kind = MediaKind.Episode,
            runtime = 1000.0,
            playbackPosition = 990.0,
        )
        assertTrue(episode.isWatched)
    }

    @Test
    fun episodeOpensSeriesDetail() {
        val episode = MediaItem(id = "e", name = "One", kind = MediaKind.Episode, seriesId = "show")
        assertEquals("show", episode.seriesDetailItemId)
        val movie = MediaItem(id = "m", name = "Movie", kind = MediaKind.Movie)
        assertNull(movie.seriesDetailItemId)
    }

    @Test
    fun mapsJellyfinEpisodeTicksAndSeasonIndex() {
        val item = ItemMapper.mediaItem(
            JellyfinItemSnapshot(
                id = "ep",
                name = "Pilot",
                type = "Episode",
                seriesName = "Show",
                seriesId = "series",
                indexNumber = 3,
                parentIndexNumber = 1,
                runTimeTicks = 30L * TickClock.TICKS_PER_SECOND,
                playbackPositionTicks = 10L * TickClock.TICKS_PER_SECOND,
                played = false,
                primaryImageTag = "tag",
                imageTags = mapOf("Primary" to "tag", "Logo" to "logo"),
                backdropImageTags = listOf("bd"),
                providerIds = mapOf("Tmdb" to "42"),
            ),
        )!!
        assertEquals(MediaKind.Episode, item.kind)
        assertEquals(1, item.seasonIndex)
        assertEquals(3, item.episodeIndex)
        assertEquals(10.0, item.playbackPosition, 0.001)
        assertEquals(30.0, item.runtime)
        assertEquals("tag", item.primaryImageTag)
        assertEquals("logo", item.logoImageTag)
        assertEquals(42, ItemMapper.tmdbId(mapOf("Tmdb" to "42")))
    }

    @Test
    fun skipsLibraryFolders() {
        assertNull(ItemMapper.mediaItem(JellyfinItemSnapshot(id = "lib", name = "Movies", type = "CollectionFolder")))
    }
}

class PlaybackResumeTest {
    @Test
    fun directPlayOpensAtSavedPlayhead() {
        assertEquals(600.0, PlaybackResumePolicy.clientStartPosition(PlaybackMethod.DirectPlay, 600.0))
        assertNull(PlaybackResumePolicy.clientStartPosition(PlaybackMethod.DirectPlay, 4.0))
        assertNull(PlaybackResumePolicy.clientStartPosition(PlaybackMethod.Remux, 600.0))
        assertNull(PlaybackResumePolicy.clientStartPosition(PlaybackMethod.Transcode, 600.0))
        assertEquals(
            600.0,
            PlaybackResumePolicy.clientStartPosition(PlaybackMethod.Remux, 600.0, clientOwnsPlayhead = true),
        )
        assertNull(
            PlaybackResumePolicy.clientStartPosition(PlaybackMethod.Remux, 4.0, clientOwnsPlayhead = true),
        )
    }

    @Test
    fun deferredSeekOnlyWhenDirectPlayStuckAtHead() {
        assertTrue(PlaybackResumePolicy.needsDeferredSeek(PlaybackMethod.DirectPlay, 0.0, 600.0))
        assertFalse(PlaybackResumePolicy.needsDeferredSeek(PlaybackMethod.DirectPlay, 600.0, 600.0))
        assertFalse(PlaybackResumePolicy.needsDeferredSeek(PlaybackMethod.Remux, 0.0, 600.0))
        assertTrue(
            PlaybackResumePolicy.needsDeferredSeek(PlaybackMethod.Remux, 0.0, 600.0, clientOwnsPlayhead = true),
        )
        assertFalse(
            PlaybackResumePolicy.needsDeferredSeek(PlaybackMethod.Remux, 600.0, 600.0, clientOwnsPlayhead = true),
        )
    }

    @Test
    fun remuxUrlGetsStartTimeTicksWhenJellyfinOmitsThem() {
        val url = "https://jellyfin.local/Videos/1/master.m3u8?MediaSourceId=a"
        val patched = StreamResumeUrl.ensuringStartTimeTicks(url, PlaybackMethod.Transcode, 600.0)
        assertTrue(patched.contains("StartTimeTicks=6000000000"))
        val already = "https://jellyfin.local/Videos/1/master.m3u8?StartTimeTicks=1"
        assertEquals(already, StreamResumeUrl.ensuringStartTimeTicks(already, PlaybackMethod.Transcode, 600.0))
        assertEquals(url, StreamResumeUrl.ensuringStartTimeTicks(url, PlaybackMethod.DirectPlay, 600.0))
    }

    @Test
    fun playbackStartReportKeepsSavedPlayhead() {
        assertEquals(600.0, PlaybackResumePolicy.reportStartPosition(0.0, 600.0), 0.001)
        assertEquals(612.0, PlaybackResumePolicy.reportStartPosition(612.0, 600.0), 0.001)
        assertEquals(0.0, PlaybackResumePolicy.reportStartPosition(0.0, 2.0), 0.001)
    }
}

class ArtworkUrlTest {
    @Test
    fun episodeThumbUsesSeriesArt() {
        val item = MediaItem(
            id = "episode",
            name = "Space Pilot 3000",
            kind = MediaKind.Episode,
            seriesId = "futurama",
            seriesThumbImageTag = "series-thumb",
        )
        val url = ArtworkUrls.thumb("https://media.example.com", item, "token", 640)
        assertTrue(url!!.contains("/Items/futurama/Images/Thumb"))
        assertTrue(url.contains("tag=series-thumb"))
        assertFalse(url.contains("/Items/episode/"))
    }

    @Test
    fun missingThumbDoesNotInventARequest() {
        val item = MediaItem(id = "episode", name = "Space Pilot 3000", kind = MediaKind.Episode)
        assertNull(ArtworkUrls.thumb("https://media.example.com", item, "token", 640))
    }
}
