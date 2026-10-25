package app.zelefin.client.emby

import app.zelefin.client.jellyfin.ItemMetadataDraft
import app.zelefin.client.jellyfin.RemoteArtworkKind
import app.zelefin.client.jellyfin.RemoteIdentifyHit
import app.zelefin.client.jellyfin.UserPolicyDraft
import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put
import org.jellyfin.sdk.model.api.UnratedItem

/** One Emby call, built without a network so every write can be checked in tests. */
data class EmbyRequest(
    val method: String,
    val path: String,
    val query: List<Pair<String, String>> = emptyList(),
    val json: String? = null,
)

object EmbyRequests {
    const val DisplayPreferencesId = "zelefin"
    const val ClientName = "Zelefin"

    fun changeOwnPassword(userId: String, current: String, new: String) = EmbyRequest(
        "POST",
        "/Users/$userId/Password",
        json = buildJsonObject {
            put("Id", userId)
            put("CurrentPw", current)
            put("NewPw", new)
            put("ResetPassword", false)
        }.toString(),
    )

    fun setPassword(userId: String, new: String) = EmbyRequest(
        "POST",
        "/Users/$userId/Password",
        json = buildJsonObject {
            put("Id", userId)
            put("NewPw", new)
            put("ResetPassword", false)
        }.toString(),
    )

    fun resetPassword(userId: String) = EmbyRequest(
        "POST",
        "/Users/$userId/Password",
        json = buildJsonObject {
            put("Id", userId)
            put("ResetPassword", true)
        }.toString(),
    )

    fun deleteUserImage(userId: String) = EmbyRequest("DELETE", "/Users/$userId/Images/Primary")

    /** Emby replaces the whole user, so the rest of [current] goes back untouched. */
    fun renameUser(userId: String, current: JsonObject, name: String) =
        EmbyRequest("POST", "/Users/$userId", json = JsonObject(current + ("Name" to JsonPrimitive(name))).toString())

    fun updatePolicy(userId: String, current: JsonObject, draft: UserPolicyDraft) =
        EmbyRequest("POST", "/Users/$userId/Policy", json = EmbyJsonEdits.policy(current, draft).toString())

    fun displayPreferences(userId: String) = EmbyRequest(
        "GET",
        "/DisplayPreferences/$DisplayPreferencesId",
        embyQuery {
            this["UserId"] = userId
            this["Client"] = ClientName
        },
    )

    fun saveDisplayPreferences(userId: String, current: JsonObject, prefs: Map<String, String>) = EmbyRequest(
        "POST",
        "/DisplayPreferences/$DisplayPreferencesId",
        embyQuery { this["UserId"] = userId },
        EmbyJsonEdits.displayPreferences(current, prefs).toString(),
    )

    fun findPlaylist(userId: String, name: String) = EmbyRequest(
        "GET",
        "/Users/$userId/Items",
        embyQuery {
            this["Recursive"] = true
            this["IncludeItemTypes"] = "Playlist"
            this["SearchTerm"] = name
            this["Limit"] = 20
        },
    )

    fun createPlaylist(name: String, itemIds: List<String> = emptyList()) = EmbyRequest(
        "POST",
        "/Playlists",
        embyQuery {
            this["Name"] = name
            this["Ids"] = itemIds
            this["MediaType"] = "Video"
        },
    )

    fun playlistItems(playlistId: String, userId: String, fields: List<String> = emptyList()) = EmbyRequest(
        "GET",
        "/Playlists/$playlistId/Items",
        embyQuery {
            this["UserId"] = userId
            this["Fields"] = fields
            this["EnableUserData"] = true
        },
    )

    fun addToPlaylist(playlistId: String, userId: String, itemIds: List<String>) = EmbyRequest(
        "POST",
        "/Playlists/$playlistId/Items",
        embyQuery {
            this["Ids"] = itemIds
            this["UserId"] = userId
        },
    )

    /** Playlist entries are removed by their entry id (`PlaylistItemId`), not the item id. */
    fun removeFromPlaylist(playlistId: String, entryIds: List<String>) =
        EmbyRequest("DELETE", "/Playlists/$playlistId/Items", embyQuery { this["EntryIds"] = entryIds })

    fun createCollection(name: String, itemIds: List<String>) = EmbyRequest(
        "POST",
        "/Collections",
        embyQuery {
            this["Name"] = name
            this["Ids"] = itemIds
            this["IsLocked"] = false
        },
    )

    fun addToCollection(collectionId: String, itemIds: List<String>) =
        EmbyRequest("POST", "/Collections/$collectionId/Items", embyQuery { this["Ids"] = itemIds })

    fun removeFromCollection(collectionId: String, itemIds: List<String>) =
        EmbyRequest("DELETE", "/Collections/$collectionId/Items", embyQuery { this["Ids"] = itemIds })

    fun deleteItem(itemId: String) = EmbyRequest("DELETE", "/Items/$itemId")

    /** Full metadata refresh with images left alone, like the Jellyfin path. */
    fun refreshItem(itemId: String) = EmbyRequest(
        "POST",
        "/Items/$itemId/Refresh",
        embyQuery {
            this["Recursive"] = true
            this["MetadataRefreshMode"] = "FullRefresh"
            this["ImageRefreshMode"] = "Default"
            this["ReplaceAllMetadata"] = false
            this["ReplaceAllImages"] = false
        },
    )

    fun updateItem(itemId: String, current: JsonObject, draft: ItemMetadataDraft) =
        EmbyRequest("POST", "/Items/$itemId", json = EmbyJsonEdits.metadata(current, draft).toString())

    /** Null for kinds Emby has no remote search for in this app (only movies and shows). */
    fun remoteSearch(item: MediaItem): EmbyRequest? {
        val kind = when (item.kind) {
            MediaKind.Movie -> "Movie"
            MediaKind.Series -> "Series"
            else -> return null
        }
        return EmbyRequest(
            "POST",
            "/Items/RemoteSearch/$kind",
            json = buildJsonObject {
                put(
                    "SearchInfo",
                    buildJsonObject {
                        put("Name", item.name)
                        item.year?.let { put("Year", it) }
                        item.tmdbId?.let { put("ProviderIds", buildJsonObject { put("Tmdb", it.toString()) }) }
                        put("IsAutomated", false)
                    },
                )
                item.id.toLongOrNull()?.let { put("ItemId", it) }
                put("IncludeDisabledProviders", false)
            }.toString(),
        )
    }

    fun applyRemoteSearch(itemId: String, hit: RemoteIdentifyHit) = EmbyRequest(
        "POST",
        "/Items/RemoteSearch/Apply/$itemId",
        embyQuery { this["ReplaceAllImages"] = true },
        (hit.raw as? JsonObject)?.toString() ?: throw app.zelefin.core.ZelefinException.server("That match came from another server."),
    )

    fun remoteImages(itemId: String, kind: RemoteArtworkKind) = EmbyRequest(
        "GET",
        "/Items/$itemId/RemoteImages",
        embyQuery {
            this["Type"] = kind.type.serialName
            this["StartIndex"] = 0
            this["Limit"] = 40
            this["IncludeAllLanguages"] = true
        },
    )

    fun downloadRemoteImage(itemId: String, kind: RemoteArtworkKind, imageUrl: String) = EmbyRequest(
        "POST",
        "/Items/$itemId/RemoteImages/Download",
        embyQuery {
            this["Type"] = kind.type.serialName
            this["ImageUrl"] = imageUrl
        },
    )

    /** Emby needs the media source, and wants the three-letter language code its providers use. */
    fun subtitleSearch(itemId: String, mediaSourceId: String, language: String, perfectMatch: Boolean) = EmbyRequest(
        "GET",
        "/Items/$itemId/RemoteSearch/Subtitles/$language",
        embyQuery {
            this["MediaSourceId"] = mediaSourceId
            if (perfectMatch) this["IsPerfectMatch"] = true
        },
    )

    fun subtitleDownload(itemId: String, mediaSourceId: String, subtitleId: String) = EmbyRequest(
        "POST",
        "/Items/$itemId/RemoteSearch/Subtitles/$subtitleId",
        embyQuery { this["MediaSourceId"] = mediaSourceId },
    )

    fun activityLog(limit: Int) = EmbyRequest(
        "GET",
        "/System/ActivityLog/Entries",
        embyQuery {
            this["StartIndex"] = 0
            this["Limit"] = limit
        },
    )

    fun startTask(taskId: String) = EmbyRequest("POST", "/ScheduledTasks/Running/$taskId")

    fun stopTask(taskId: String) = EmbyRequest("DELETE", "/ScheduledTasks/Running/$taskId")

    fun scanLibraries() = EmbyRequest("POST", "/Library/Refresh")

    fun sessions(controllableBy: String? = null, deviceId: String? = null) = EmbyRequest(
        "GET",
        "/Sessions",
        embyQuery {
            this["ControllableByUserId"] = controllableBy
            this["DeviceId"] = deviceId
        },
    )

    fun playOnSession(sessionId: String, itemId: String, startTicks: Long?) = EmbyRequest(
        "POST",
        "/Sessions/$sessionId/Playing",
        embyQuery {
            this["ItemIds"] = itemId
            this["PlayCommand"] = "PlayNow"
            this["StartPositionTicks"] = startTicks
        },
    )

    fun playstate(sessionId: String, command: String, seekTicks: Long? = null, controllingUserId: String? = null) = EmbyRequest(
        "POST",
        "/Sessions/$sessionId/Playing/$command",
        json = buildJsonObject {
            put("Command", command)
            seekTicks?.let { put("SeekPositionTicks", it) }
            controllingUserId?.let { put("ControllingUserId", it) }
        }.toString(),
    )

    fun generalCommand(sessionId: String, name: String) = EmbyRequest("POST", "/Sessions/$sessionId/Command/$name")

    fun message(sessionId: String, header: String, text: String, timeoutMs: Int) = EmbyRequest(
        "POST",
        "/Sessions/$sessionId/Message",
        embyQuery {
            this["Text"] = text
            this["Header"] = header
            this["TimeoutMs"] = timeoutMs
        },
    )

    /** Only what the socket handler acts on; volume stays with the phone. */
    val SupportedCommands = listOf("DisplayMessage", "Play", "Playstate")

    fun capabilities(sessionId: String) = EmbyRequest(
        "POST",
        "/Sessions/Capabilities/Full",
        embyQuery { this["Id"] = sessionId },
        buildJsonObject {
            put("PlayableMediaTypes", buildJsonArray { add(JsonPrimitive("Video")) })
            put("SupportedCommands", JsonArray(SupportedCommands.map(::JsonPrimitive)))
            put("SupportsMediaControl", true)
            put("SupportsSync", false)
        }.toString(),
    )

    fun liveTvInfo() = EmbyRequest("GET", "/LiveTv/Info")

    fun liveChannels(userId: String, start: Int, limit: Int, fields: List<String>) = EmbyRequest(
        "GET",
        "/LiveTv/Channels",
        embyQuery {
            this["UserId"] = userId
            this["StartIndex"] = start
            this["Limit"] = limit
            this["AddCurrentProgram"] = true
            this["EnableUserData"] = true
            this["Fields"] = fields
            this["EnableImageTypes"] = "Primary,Thumb,Backdrop,Logo"
        },
    )

    fun closeLiveStream(liveStreamId: String) =
        EmbyRequest("POST", "/LiveStreams/Close", embyQuery { this["LiveStreamId"] = liveStreamId })
}

/** Edits to whole Emby objects that must be sent back with every other field kept. */
object EmbyJsonEdits {
    fun policyDraft(policy: JsonObject): UserPolicyDraft = UserPolicyDraft(
        isAdministrator = policy.flag("IsAdministrator"),
        isDisabled = policy.flag("IsDisabled"),
        enableSubtitleManagement = policy.flag("EnableSubtitleManagement"),
        remoteClientBitrateLimit = (policy["RemoteClientBitrateLimit"] as? JsonPrimitive)?.intOrNull?.coerceAtLeast(0) ?: 0,
        maxParentalRating = (policy["MaxParentalRating"] as? JsonPrimitive)?.intOrNull,
        blockUnratedItems = policy.strings("BlockUnratedItems")
            .mapNotNull { raw -> UnratedItem.entries.firstOrNull { it.serialName.equals(raw, ignoreCase = true) } }
            .toSet(),
        enableAllFolders = policy.flag("EnableAllFolders"),
        enabledFolders = policy.strings("EnabledFolders").toSet(),
    )

    fun policy(current: JsonObject, draft: UserPolicyDraft): JsonObject = JsonObject(
        current + mapOf(
            "IsAdministrator" to JsonPrimitive(draft.isAdministrator),
            "IsDisabled" to JsonPrimitive(draft.isDisabled),
            "EnableSubtitleManagement" to JsonPrimitive(draft.enableSubtitleManagement),
            "RemoteClientBitrateLimit" to JsonPrimitive(draft.remoteClientBitrateLimit),
            "MaxParentalRating" to (draft.maxParentalRating?.let(::JsonPrimitive) ?: JsonNull),
            "BlockUnratedItems" to JsonArray(draft.blockUnratedItems.map { JsonPrimitive(it.serialName) }.sortedBy { it.content }),
            "EnableAllFolders" to JsonPrimitive(draft.enableAllFolders),
            "EnabledFolders" to JsonArray(if (draft.enableAllFolders) emptyList() else draft.enabledFolders.sorted().map(::JsonPrimitive)),
        ),
    )

    /** Emby sends `CustomPrefs` as an empty array until something is stored. */
    fun customPrefs(preferences: JsonObject): Map<String, String> =
        (preferences["CustomPrefs"] as? JsonObject).orEmpty().mapNotNull { (key, value) -> (value as? JsonPrimitive)?.contentOrNull?.let { key to it } }.toMap()

    fun displayPreferences(current: JsonObject, prefs: Map<String, String>): JsonObject {
        val merged = customPrefs(current) + prefs
        return JsonObject(
            current + mapOf(
                "Id" to JsonPrimitive(EmbyRequests.DisplayPreferencesId),
                "Client" to JsonPrimitive(EmbyRequests.ClientName),
                "CustomPrefs" to JsonObject(merged.mapValues { JsonPrimitive(it.value) }),
            ),
        )
    }

    /** The same fields the Jellyfin editor saves; Emby reads genres and tags from the `*Items` lists. */
    fun metadata(current: JsonObject, draft: ItemMetadataDraft): JsonObject {
        val genres = draft.genres.split(',').map { it.trim() }.filter { it.isNotEmpty() }
        val tags = draft.tags.split(',').map { it.trim() }.filter { it.isNotEmpty() }
        fun named(values: List<String>) = JsonArray(values.map { name -> buildJsonObject { put("Name", name) } })
        val name = draft.name.trim().ifEmpty { (current["Name"] as? JsonPrimitive)?.contentOrNull.orEmpty() }
        return JsonObject(
            current + mapOf(
                "Name" to JsonPrimitive(name),
                "Overview" to (draft.overview.trim().ifEmpty { null }?.let(::JsonPrimitive) ?: JsonNull),
                "ProductionYear" to (draft.year.trim().toIntOrNull()?.let(::JsonPrimitive) ?: JsonNull),
                "OfficialRating" to (draft.officialRating.trim().ifEmpty { null }?.let(::JsonPrimitive) ?: JsonNull),
                "Genres" to JsonArray(genres.map(::JsonPrimitive)),
                "GenreItems" to named(genres),
                "Tags" to JsonArray(tags.map(::JsonPrimitive)),
                "TagItems" to named(tags),
            ),
        )
    }

    fun identifyHits(results: JsonElement): List<RemoteIdentifyHit> = (results as? JsonArray).orEmpty().mapNotNull { element ->
        val hit = element as? JsonObject ?: return@mapNotNull null
        RemoteIdentifyHit(
            name = hit.text("Name") ?: "Untitled",
            year = (hit["ProductionYear"] as? JsonPrimitive)?.intOrNull,
            overview = hit.text("Overview"),
            providerIds = (hit["ProviderIds"] as? JsonObject).orEmpty()
                .mapNotNull { (key, value) -> (value as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotBlank() }?.let { key to it } }
                .toMap(),
            imageUrl = hit.text("ImageUrl"),
            raw = hit,
        )
    }

    private fun JsonObject.flag(key: String): Boolean = (this[key] as? JsonPrimitive)?.contentOrNull == "true"

    private fun JsonObject.text(key: String): String? = (this[key] as? JsonPrimitive)?.contentOrNull?.trim()?.ifEmpty { null }

    private fun JsonObject.strings(key: String): List<String> =
        (this[key] as? JsonArray).orEmpty().mapNotNull { (it as? JsonPrimitive)?.contentOrNull?.takeIf { value -> value.isNotBlank() } }
}
