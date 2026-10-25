package app.zelefin.client.emby

import app.zelefin.client.jellyfin.RemoteArtworkKind
import app.zelefin.client.jellyfin.RemoteIdentifyHit
import app.zelefin.core.EmbyJson
import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class EmbyRequestsTest {
    private fun body(request: EmbyRequest): JsonObject = EmbyJson.parser.parseToJsonElement(request.json!!).jsonObject

    private fun assertRequest(request: EmbyRequest, method: String, path: String, vararg query: Pair<String, String>) {
        assertEquals(method, request.method)
        assertEquals(path, request.path)
        assertEquals(query.toList(), request.query)
    }

    @Test
    fun passwords() {
        val own = EmbyRequests.changeOwnPassword("u1", "old", "new")
        assertRequest(own, "POST", "/Users/u1/Password")
        assertEquals(buildJsonObject { put("Id", "u1"); put("CurrentPw", "old"); put("NewPw", "new"); put("ResetPassword", false) }, body(own))
        assertEquals(buildJsonObject { put("Id", "u2"); put("NewPw", "pw"); put("ResetPassword", false) }, body(EmbyRequests.setPassword("u2", "pw")))
        assertEquals(buildJsonObject { put("Id", "u2"); put("ResetPassword", true) }, body(EmbyRequests.resetPassword("u2")))
    }

    @Test
    fun userImageAndRename() {
        assertRequest(EmbyRequests.deleteUserImage("u1"), "DELETE", "/Users/u1/Images/Primary")
        val current = buildJsonObject { put("Id", "u1"); put("Name", "ana"); put("HasPassword", true) }
        val rename = EmbyRequests.renameUser("u1", current, "Ana")
        assertRequest(rename, "POST", "/Users/u1")
        assertEquals(buildJsonObject { put("Id", "u1"); put("Name", "Ana"); put("HasPassword", true) }, body(rename))
    }

    @Test
    fun displayPreferencesReadAndWrite() {
        assertRequest(EmbyRequests.displayPreferences("u1"), "GET", "/DisplayPreferences/zelefin", "UserId" to "u1", "Client" to "Zelefin")
        val current = EmbyJson.parser.parseToJsonElement("""{"Id":"zelefin","CustomPrefs":[],"SortOrder":"Ascending","Client":"Zelefin"}""").jsonObject
        val save = EmbyRequests.saveDisplayPreferences("u1", current, mapOf("tabOrder" to "home,movies"))
        assertRequest(save, "POST", "/DisplayPreferences/zelefin", "UserId" to "u1")
        assertEquals("""{"Id":"zelefin","CustomPrefs":{"tabOrder":"home,movies"},"SortOrder":"Ascending","Client":"Zelefin"}""", save.json)
    }

    @Test
    fun playlists() {
        assertRequest(
            EmbyRequests.findPlaylist("u1", "Watchlist"),
            "GET", "/Users/u1/Items",
            "Recursive" to "true", "IncludeItemTypes" to "Playlist", "SearchTerm" to "Watchlist", "Limit" to "20",
        )
        assertRequest(EmbyRequests.createPlaylist("Watchlist"), "POST", "/Playlists", "Name" to "Watchlist", "MediaType" to "Video")
        assertRequest(EmbyRequests.createPlaylist("Zelefin Test", listOf("1093")), "POST", "/Playlists", "Name" to "Zelefin Test", "Ids" to "1093", "MediaType" to "Video")
        assertRequest(EmbyRequests.addToPlaylist("p1", "u1", listOf("1093", "1213")), "POST", "/Playlists/p1/Items", "Ids" to "1093,1213", "UserId" to "u1")
        assertRequest(EmbyRequests.removeFromPlaylist("p1", listOf("e7")), "DELETE", "/Playlists/p1/Items", "EntryIds" to "e7")
        assertRequest(EmbyRequests.playlistItems("p1", "u1"), "GET", "/Playlists/p1/Items", "UserId" to "u1", "EnableUserData" to "true")
    }

    @Test
    fun collections() {
        assertRequest(EmbyRequests.createCollection("Zelefin Test", listOf("1093")), "POST", "/Collections", "Name" to "Zelefin Test", "Ids" to "1093", "IsLocked" to "false")
        assertRequest(EmbyRequests.addToCollection("c1", listOf("1093")), "POST", "/Collections/c1/Items", "Ids" to "1093")
        assertRequest(EmbyRequests.removeFromCollection("c1", listOf("1093")), "DELETE", "/Collections/c1/Items", "Ids" to "1093")
    }

    @Test
    fun metadataActions() {
        assertRequest(EmbyRequests.deleteItem("1093"), "DELETE", "/Items/1093")
        assertRequest(
            EmbyRequests.refreshItem("1093"),
            "POST", "/Items/1093/Refresh",
            "Recursive" to "true", "MetadataRefreshMode" to "FullRefresh", "ImageRefreshMode" to "Default",
            "ReplaceAllMetadata" to "false", "ReplaceAllImages" to "false",
        )
        assertRequest(
            EmbyRequests.remoteImages("1093", RemoteArtworkKind.Backdrop),
            "GET", "/Items/1093/RemoteImages",
            "Type" to "Backdrop", "StartIndex" to "0", "Limit" to "40", "IncludeAllLanguages" to "true",
        )
        assertRequest(
            EmbyRequests.downloadRemoteImage("1093", RemoteArtworkKind.Poster, "https://img.example/p.jpg"),
            "POST", "/Items/1093/RemoteImages/Download",
            "Type" to "Primary", "ImageUrl" to "https://img.example/p.jpg",
        )
    }

    @Test
    fun identifySearchAndApply() {
        val movie = MediaItem(id = "1093", name = "Halloween Kills", kind = MediaKind.Movie, year = 2021, tmdbId = 610253)
        val search = EmbyRequests.remoteSearch(movie)!!
        assertRequest(search, "POST", "/Items/RemoteSearch/Movie")
        assertEquals(
            """{"SearchInfo":{"Name":"Halloween Kills","Year":2021,"ProviderIds":{"Tmdb":"610253"},"IsAutomated":false},"ItemId":1093,"IncludeDisabledProviders":false}""",
            search.json,
        )
        assertEquals("/Items/RemoteSearch/Series", EmbyRequests.remoteSearch(movie.copy(kind = MediaKind.Series))?.path)
        assertNull(EmbyRequests.remoteSearch(movie.copy(kind = MediaKind.Episode)))
        val raw = buildJsonObject { put("Name", "Halloween Kills"); put("SearchProviderName", "TheMovieDb") }
        val apply = EmbyRequests.applyRemoteSearch("1093", RemoteIdentifyHit("Halloween Kills", 2021, null, emptyMap(), null, raw))
        assertRequest(apply, "POST", "/Items/RemoteSearch/Apply/1093", "ReplaceAllImages" to "true")
        assertEquals(raw, body(apply))
    }

    @Test
    fun remoteSubtitles() {
        assertRequest(
            EmbyRequests.subtitleSearch("1093", "mediasource_1093", "eng", perfectMatch = true),
            "GET", "/Items/1093/RemoteSearch/Subtitles/eng",
            "MediaSourceId" to "mediasource_1093", "IsPerfectMatch" to "true",
        )
        assertEquals(listOf("MediaSourceId" to "mediasource_1093"), EmbyRequests.subtitleSearch("1093", "mediasource_1093", "eng", false).query)
        assertRequest(
            EmbyRequests.subtitleDownload("1093", "mediasource_1093", "os-42"),
            "POST", "/Items/1093/RemoteSearch/Subtitles/os-42",
            "MediaSourceId" to "mediasource_1093",
        )
    }

    @Test
    fun administration() {
        assertRequest(EmbyRequests.activityLog(80), "GET", "/System/ActivityLog/Entries", "StartIndex" to "0", "Limit" to "80")
        assertRequest(EmbyRequests.startTask("t1"), "POST", "/ScheduledTasks/Running/t1")
        assertRequest(EmbyRequests.stopTask("t1"), "DELETE", "/ScheduledTasks/Running/t1")
        assertRequest(EmbyRequests.scanLibraries(), "POST", "/Library/Refresh")
    }

    @Test
    fun remoteControl() {
        assertRequest(EmbyRequests.sessions(controllableBy = "u1"), "GET", "/Sessions", "ControllableByUserId" to "u1")
        assertRequest(EmbyRequests.sessions(deviceId = "dev"), "GET", "/Sessions", "DeviceId" to "dev")
        assertRequest(
            EmbyRequests.playOnSession("s1", "1093", 600_000_000),
            "POST", "/Sessions/s1/Playing",
            "ItemIds" to "1093", "PlayCommand" to "PlayNow", "StartPositionTicks" to "600000000",
        )
        assertRequest(EmbyRequests.playOnSession("s1", "1093", null), "POST", "/Sessions/s1/Playing", "ItemIds" to "1093", "PlayCommand" to "PlayNow")
        val seek = EmbyRequests.playstate("s1", "Seek", 100_000_000, "u1")
        assertRequest(seek, "POST", "/Sessions/s1/Playing/Seek")
        assertEquals(buildJsonObject { put("Command", "Seek"); put("SeekPositionTicks", 100_000_000); put("ControllingUserId", "u1") }, body(seek))
        assertEquals(buildJsonObject { put("Command", "Pause") }, body(EmbyRequests.playstate("s1", "Pause")))
        assertRequest(EmbyRequests.generalCommand("s1", "VolumeUp"), "POST", "/Sessions/s1/Command/VolumeUp")
        assertRequest(
            EmbyRequests.message("s1", "Zelefin", "Dinner is ready", 8000),
            "POST", "/Sessions/s1/Message",
            "Text" to "Dinner is ready", "Header" to "Zelefin", "TimeoutMs" to "8000",
        )
        val capabilities = EmbyRequests.capabilities("s9")
        assertRequest(capabilities, "POST", "/Sessions/Capabilities/Full", "Id" to "s9")
        assertEquals(
            """{"PlayableMediaTypes":["Video"],"SupportedCommands":["DisplayMessage","Play","Playstate"],"SupportsMediaControl":true,"SupportsSync":false}""",
            capabilities.json,
        )
    }

    @Test
    fun liveTv() {
        assertRequest(EmbyRequests.liveTvInfo(), "GET", "/LiveTv/Info")
        assertRequest(
            EmbyRequests.liveChannels("u1", 200, 100, listOf("Overview")),
            "GET", "/LiveTv/Channels",
            "UserId" to "u1", "StartIndex" to "200", "Limit" to "100", "AddCurrentProgram" to "true",
            "EnableUserData" to "true", "Fields" to "Overview", "EnableImageTypes" to "Primary,Thumb,Backdrop,Logo",
        )
        assertRequest(EmbyRequests.closeLiveStream("live-1"), "POST", "/LiveStreams/Close", "LiveStreamId" to "live-1")
    }

    @Test
    fun applyingAnotherServersMatchFails() {
        val foreign = RemoteIdentifyHit("x", null, null, emptyMap(), null, JsonPrimitive("not an object"))
        val failure = runCatching { EmbyRequests.applyRemoteSearch("1", foreign) }.exceptionOrNull()
        assertEquals("That match came from another server.", failure?.message)
    }
}
