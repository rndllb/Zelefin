package app.zelefin.client.emby

import app.zelefin.core.EmbyActivityResult
import app.zelefin.core.EmbyJson
import app.zelefin.core.EmbyRemoteImageResult
import app.zelefin.core.EmbySessionInfo
import app.zelefin.core.EmbyTaskInfo
import app.zelefin.core.MediaKind
import kotlinx.serialization.builtins.ListSerializer
import org.jellyfin.sdk.model.api.TaskCompletionStatus
import org.jellyfin.sdk.model.api.TaskState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EmbyServerMappingTest {
    private val sessions = """
        [{"Id":"idle1","UserId":"u1","UserName":"ana","Client":"Emby Web","DeviceName":"Firefox","DeviceId":"web-1",
          "LastActivityDate":"2026-10-24T00:10:00.0000000Z","SupportsRemoteControl":true,"InternalDeviceId":7,
          "SupportedCommands":["MoveUp","DisplayMessage","VolumeUp"],"PlayState":{"CanSeek":false,"IsPaused":false,"IsMuted":false,"RepeatMode":"RepeatNone"}},
         {"Id":"play1","UserId":"u1","UserName":"ana","Client":"Emby for Android","DeviceName":"Pixel","DeviceId":"tv-1",
          "LastActivityDate":"2026-10-23T20:00:00.0000000Z","SupportsRemoteControl":true,
          "NowPlayingItem":{"Name":"Pilot","Id":"40968","Type":"Episode","SeriesName":"Pretty Little Liars","IndexNumber":1,"ParentIndexNumber":1,"RunTimeTicks":26763410000},
          "PlayState":{"PositionTicks":6000000000,"CanSeek":true,"IsPaused":true,"IsMuted":false,"VolumeLevel":80,"PlayMethod":"Transcode"},
          "TranscodingInfo":{"Container":"ts","VideoCodec":"h264","AudioCodec":"aac","AudioChannels":2,"IsAudioDirect":false,"Width":1280,"Height":720,
            "Bitrate":4200000,"CompletionPercentage":12.5,"TranscodeReasons":["ContainerBitrateExceedsLimit"]}},
         {"UserName":"no id"}]
    """.trimIndent()

    @Test
    fun sessionsMapLikeJellyfinOnesWithPlayingFirst() {
        val mapped = EmbyServerMapping.sessions(EmbyJson.parser.decodeFromString(ListSerializer(EmbySessionInfo.serializer()), sessions))
        assertEquals(listOf("play1", "idle1"), mapped.map { it.id })
        val playing = mapped[0]
        assertTrue(playing.isPlaying)
        assertEquals(MediaKind.Episode, playing.nowPlaying?.kind)
        assertEquals("Pretty Little Liars · S1:E1 · Pilot", playing.title)
        assertEquals(600.0, playing.position, 0.0)
        assertEquals(2676.341, playing.runtime!!, 0.001)
        assertTrue(playing.isPaused)
        assertTrue(playing.canSeek)
        assertEquals(80, playing.volumeLevel)
        assertEquals("Transcode", playing.playMethod)
        assertTrue(playing.canControl)
        assertEquals("Emby for Android · Pixel", playing.deviceLabel)
        assertEquals(
            listOf(
                "Stream" to "TS · H264 · AAC 2ch",
                "Resolution" to "1280×720",
                "Bitrate" to "4.2 Mbps",
                "Reason" to "container bitrate exceeds limit",
                "Complete" to "12%",
            ),
            playing.transcoding,
        )
        val idle = mapped[1]
        assertFalse(idle.isPlaying)
        assertTrue(idle.supportsMessages)
        assertTrue(idle.supportsVolume)
        assertTrue(idle.isThisDevice("web-1"))
    }

    @Test
    fun scheduledTasksKeepStateAndLastRun() {
        val tasks = EmbyJson.parser.decodeFromString(
            ListSerializer(EmbyTaskInfo.serializer()),
            """[{"Name":"Scan media library","State":"Idle","Id":"t1","Category":"Library","Description":"Scans folders.","IsHidden":false,
                 "LastExecutionResult":{"StartTimeUtc":"2026-10-23T03:30:00.0000000Z","EndTimeUtc":"2026-10-23T03:38:14.2534114Z","Status":"Completed"},"Triggers":[]},
                {"Name":"Refresh people","State":"Running","CurrentProgressPercentage":42.5,"Id":"t2","Category":"Library"},
                {"Name":"Broken","State":"Idle","Id":"t3","Category":"Maintenance","LastExecutionResult":{"Status":"Failed","ErrorMessage":" disk full "}},
                {"Name":"No id"}]""",
        )
        val mapped = EmbyServerMapping.scheduledTasks(tasks)
        assertEquals(listOf("t2", "t1", "t3"), mapped.map { it.id })
        assertEquals(TaskState.RUNNING, mapped[0].state)
        assertEquals("Running · 42%", mapped[0].stateSubtitle)
        assertEquals(TaskCompletionStatus.COMPLETED, mapped[1].lastStatus)
        assertEquals("8:14", mapped[1].lastDurationLabel)
        assertEquals("disk full", mapped[2].lastError)
        assertTrue(mapped[1].canStart)
        assertTrue(mapped[0].canCancel)
    }

    @Test
    fun activityAndRemoteImages() {
        val activity = EmbyJson.parser.decodeFromString(
            EmbyActivityResult.serializer(),
            """{"Items":[{"Id":4012,"Name":"ana signed in","ShortOverview":"From 192.168.1.20","Type":"SessionStarted","Date":"2026-10-24T00:47:06.0530000Z","Severity":"Info"},
                         {"Id":4011,"Name":" "}],"TotalRecordCount":2}""",
        )
        val log = EmbyServerMapping.activity(activity.items)
        assertEquals(1, log.size)
        assertEquals("4012", log[0].id)
        assertEquals("SessionStarted · From 192.168.1.20", log[0].subtitle)
        assertTrue(log[0].date != null)
        val images = EmbyJson.parser.decodeFromString(
            EmbyRemoteImageResult.serializer(),
            """{"Images":[{"ProviderName":"TheTVDB","Url":"https://a/1.jpg","Width":680,"Height":1000},{"ProviderName":"TheTVDB","Url":"https://a/1.jpg"},{"Url":""}],"TotalRecordCount":3}""",
        )
        val choices = EmbyServerMapping.remoteImages(images.images)
        assertEquals(1, choices.size)
        assertEquals("680×1000", choices[0].sizeLabel)
        assertEquals("https://a/1.jpg", choices[0].previewUrl)
    }

    @Test
    fun datesBecomeLocalTimeAndJunkIsDropped() {
        val utc = EmbyServerMapping.localTime("2026-10-23T03:38:14.2534114Z")!!
        val expected = java.time.OffsetDateTime.parse("2026-10-23T03:38:14.2534114Z").atZoneSameInstant(java.time.ZoneId.systemDefault()).toLocalDateTime()
        assertEquals(expected, utc)
        assertNull(EmbyServerMapping.localTime("yesterday"))
        assertNull(EmbyServerMapping.localTime(null))
    }
}
