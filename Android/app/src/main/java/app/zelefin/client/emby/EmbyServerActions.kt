package app.zelefin.client.emby

import app.zelefin.client.ServerLanguageCode
import app.zelefin.client.jellyfin.ActivityLogItem
import app.zelefin.client.jellyfin.AdminMediaFolder
import app.zelefin.client.jellyfin.CollectionEditor
import app.zelefin.client.jellyfin.ItemMetadataDraft
import app.zelefin.client.jellyfin.ParentalRatingChoice
import app.zelefin.client.jellyfin.RemoteArtworkKind
import app.zelefin.client.jellyfin.RemoteIdentifyHit
import app.zelefin.client.jellyfin.RemoteImageChoice
import app.zelefin.client.jellyfin.RemoteSession
import app.zelefin.client.jellyfin.ScheduledTask
import app.zelefin.client.jellyfin.ServerUserAccount
import app.zelefin.client.jellyfin.SessionControl
import app.zelefin.client.jellyfin.UserPolicyDraft
import app.zelefin.client.jellyfin.WatchlistPlaylistName
import app.zelefin.client.plugins.RemoteSubtitle
import app.zelefin.core.EmbyActivityResult
import app.zelefin.core.EmbyCreated
import app.zelefin.core.EmbyItemsResult
import app.zelefin.core.EmbyJson
import app.zelefin.core.EmbyLiveTvInfo
import app.zelefin.core.EmbyParentalRating
import app.zelefin.core.EmbyPlaylistEntries
import app.zelefin.core.EmbyRemoteImageResult
import app.zelefin.core.EmbySessionInfo
import app.zelefin.core.EmbyTaskInfo
import app.zelefin.core.MediaItem
import app.zelefin.core.TickClock
import app.zelefin.core.ZelefinException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

private suspend fun EmbyLibrary.call(request: EmbyRequest): EmbyApi.Reply = api.execute(request).also { expectOk(it) }

private suspend fun <T> EmbyLibrary.decode(request: EmbyRequest, serializer: KSerializer<T>): T {
    val reply = call(request)
    return runCatching { EmbyJson.parser.decodeFromString(serializer, reply.body) }
        .getOrElse { throw ZelefinException.server("Emby sent a reply Zelefin could not read.") }
}

private suspend fun EmbyLibrary.json(request: EmbyRequest): JsonElement {
    val reply = call(request)
    return runCatching { EmbyJson.parser.parseToJsonElement(reply.body) }
        .getOrElse { throw ZelefinException.server("Emby sent a reply Zelefin could not read.") }
}

private suspend fun EmbyLibrary.userObject(userId: String): JsonObject =
    json(EmbyRequest("GET", "/Users/$userId")) as? JsonObject ?: throw ZelefinException.missingUser()

private fun JsonObject.text(key: String): String? = (this[key] as? JsonPrimitive)?.contentOrNull?.trim()?.ifEmpty { null }

// Account

/** Administrator and subtitle rights of the signed-in user. */
suspend fun EmbyLibrary.accountRights(): Pair<Boolean, Boolean> = withContext(Dispatchers.IO) {
    val policy = userObject(user)["Policy"] as? JsonObject ?: return@withContext false to false
    val draft = EmbyJsonEdits.policyDraft(policy)
    val downloads = (policy["EnableSubtitleDownloading"] as? JsonPrimitive)?.contentOrNull == "true"
    draft.isAdministrator to (draft.isAdministrator || draft.enableSubtitleManagement || downloads)
}

/** The signed-in user's name and picture tag, as Emby has them now. */
suspend fun EmbyLibrary.currentAccount(): Pair<String?, String?> = withContext(Dispatchers.IO) {
    val user = userObject(user)
    user.text("Name") to user.text("PrimaryImageTag")
}

suspend fun EmbyLibrary.changeOwnPassword(current: String, new: String) = withContext(Dispatchers.IO) {
    val reply = api.execute(EmbyRequests.changeOwnPassword(user, current, new))
    if (reply.status == 401 || reply.status == 403) throw ZelefinException.server("The current password is not right.")
    if (!reply.ok) throw ZelefinException.server("Emby could not update the password (${reply.status}).")
}

suspend fun EmbyLibrary.setUserPassword(userId: String, newPassword: String) {
    if (newPassword.isEmpty()) throw ZelefinException.server("Enter a new password.")
    call(EmbyRequests.setPassword(userId, newPassword))
}

suspend fun EmbyLibrary.resetUserPassword(userId: String) {
    call(EmbyRequests.resetPassword(userId))
}

suspend fun EmbyLibrary.deleteUserImage(userId: String) {
    call(EmbyRequests.deleteUserImage(userId))
}

suspend fun EmbyLibrary.displayPreferenceCustomPrefs(): Map<String, String> = withContext(Dispatchers.IO) {
    EmbyJsonEdits.customPrefs(json(EmbyRequests.displayPreferences(user)) as? JsonObject ?: JsonObject(emptyMap()))
}

suspend fun EmbyLibrary.updateDisplayPreferenceCustomPrefs(prefs: Map<String, String>) = withContext(Dispatchers.IO) {
    val current = json(EmbyRequests.displayPreferences(user)) as? JsonObject ?: JsonObject(emptyMap())
    call(EmbyRequests.saveDisplayPreferences(user, current, prefs))
}

// Administration

private fun serverUser(json: JsonObject): ServerUserAccount? {
    val id = json.text("Id") ?: return null
    return ServerUserAccount(
        id = id,
        name = json.text("Name") ?: "User",
        primaryImageTag = json.text("PrimaryImageTag"),
        policy = (json["Policy"] as? JsonObject)?.let(EmbyJsonEdits::policyDraft),
    )
}

suspend fun EmbyLibrary.adminUsers(): List<ServerUserAccount> = withContext(Dispatchers.IO) {
    (json(EmbyRequest("GET", "/Users")) as? JsonArray).orEmpty()
        .mapNotNull { (it as? JsonObject)?.let(::serverUser) }
        .sortedBy { it.name.lowercase() }
}

suspend fun EmbyLibrary.adminUser(id: String): ServerUserAccount = withContext(Dispatchers.IO) {
    serverUser(userObject(id)) ?: throw ZelefinException.missingUser()
}

/** Emby keeps library access by each folder's GUID, not its numeric id. */
suspend fun EmbyLibrary.adminMediaFolders(): List<AdminMediaFolder> = withContext(Dispatchers.IO) {
    val folders = json(EmbyRequest("GET", "/Library/MediaFolders")) as? JsonObject
    (folders?.get("Items") as? JsonArray).orEmpty().mapNotNull { element ->
        val folder = element as? JsonObject ?: return@mapNotNull null
        val id = folder.text("Guid") ?: folder.text("Id") ?: return@mapNotNull null
        AdminMediaFolder(id, folder.text("Name") ?: "Library")
    }
}

suspend fun EmbyLibrary.parentalRatings(): List<ParentalRatingChoice> = withContext(Dispatchers.IO) {
    val seen = mutableSetOf<String>()
    decode(EmbyRequest("GET", "/Localization/ParentalRatings"), ListSerializer(EmbyParentalRating.serializer())).mapNotNull { rating ->
        val name = rating.name?.trim().orEmpty()
        if (name.isEmpty()) return@mapNotNull null
        ParentalRatingChoice(name, rating.value).takeIf { seen.add(it.id) }
    }
}

suspend fun EmbyLibrary.updateUserPolicy(userId: String, draft: UserPolicyDraft) = withContext(Dispatchers.IO) {
    val current = userObject(userId)["Policy"] as? JsonObject ?: throw ZelefinException.server("This user has no policy on the server.")
    call(EmbyRequests.updatePolicy(userId, current, draft))
}

suspend fun EmbyLibrary.renameUser(account: ServerUserAccount, name: String) = withContext(Dispatchers.IO) {
    val trimmed = name.trim()
    if (trimmed.isEmpty()) throw ZelefinException.server("Enter a username.")
    call(EmbyRequests.renameUser(account.id, userObject(account.id), trimmed))
}

suspend fun EmbyLibrary.scheduledTasks(): List<ScheduledTask> = withContext(Dispatchers.IO) {
    EmbyServerMapping.scheduledTasks(decode(EmbyRequest("GET", "/ScheduledTasks"), ListSerializer(EmbyTaskInfo.serializer())))
}

suspend fun EmbyLibrary.startScheduledTask(id: String) {
    call(EmbyRequests.startTask(id))
}

suspend fun EmbyLibrary.stopScheduledTask(id: String) {
    call(EmbyRequests.stopTask(id))
}

suspend fun EmbyLibrary.activityLog(limit: Int = 80): List<ActivityLogItem> = withContext(Dispatchers.IO) {
    EmbyServerMapping.activity(decode(EmbyRequests.activityLog(limit), EmbyActivityResult.serializer()).items)
}

suspend fun EmbyLibrary.scanLibraries() {
    call(EmbyRequests.scanLibraries())
}

// Library actions

/** The Watchlist is a private playlist named like the Jellyfin one, made on first use. */
suspend fun EmbyLibrary.watchlistPlaylistId(create: Boolean): String? = withContext(Dispatchers.IO) {
    decode(EmbyRequests.findPlaylist(user, WatchlistPlaylistName), EmbyItemsResult.serializer()).items
        .firstOrNull { it.name.equals(WatchlistPlaylistName, ignoreCase = true) }?.id
        ?: if (create) {
            decode(EmbyRequests.createPlaylist(WatchlistPlaylistName), EmbyCreated.serializer()).id
                ?: throw ZelefinException.server("Emby did not create a Watchlist playlist.")
        } else {
            null
        }
}

suspend fun EmbyLibrary.watchlistItems(): List<MediaItem> = withContext(Dispatchers.IO) {
    val playlist = runCatching { watchlistPlaylistId(create = false) }.getOrNull() ?: return@withContext emptyList()
    with(EmbyLibrary) {
        decode(EmbyRequests.playlistItems(playlist, user, EmbyLibrary.ListFields), EmbyItemsResult.serializer()).items.media()
            .map { it.copy(isWatchlisted = true) }
    }
}

suspend fun EmbyLibrary.setWatchlisted(itemId: String, watchlisted: Boolean) = withContext(Dispatchers.IO) {
    val playlist = watchlistPlaylistId(create = watchlisted) ?: return@withContext
    if (watchlisted) {
        call(EmbyRequests.addToPlaylist(playlist, user, listOf(itemId)))
    } else {
        val entries = decode(EmbyRequests.playlistItems(playlist, user), EmbyPlaylistEntries.serializer()).items
            .filter { it.id == itemId }.mapNotNull { it.playlistItemId }
        if (entries.isNotEmpty()) call(EmbyRequests.removeFromPlaylist(playlist, entries))
    }
}

suspend fun EmbyLibrary.collectionEditor(itemId: String): CollectionEditor = withContext(Dispatchers.IO) {
    val collections = boxSets(80)
    val members = page("/Users/$user/Items") {
        this["Recursive"] = true
        this["IncludeItemTypes"] = "BoxSet"
        this["ListItemIds"] = itemId
    }.items.mapNotNull { it.id }.toSet()
    CollectionEditor(collections, members)
}

suspend fun EmbyLibrary.addToCollection(collectionId: String, itemId: String) {
    call(EmbyRequests.addToCollection(collectionId, listOf(itemId)))
}

suspend fun EmbyLibrary.removeFromCollection(collectionId: String, itemId: String) {
    call(EmbyRequests.removeFromCollection(collectionId, listOf(itemId)))
}

suspend fun EmbyLibrary.createCollection(name: String, itemId: String) {
    call(EmbyRequests.createCollection(name, listOf(itemId)))
}

suspend fun EmbyLibrary.refreshItemMetadata(itemId: String) {
    call(EmbyRequests.refreshItem(itemId))
}

suspend fun EmbyLibrary.updateItemMetadata(itemId: String, draft: ItemMetadataDraft) = withContext(Dispatchers.IO) {
    val current = json(EmbyRequest("GET", "/Users/$user/Items/$itemId")) as? JsonObject
        ?: throw ZelefinException.server("This title could not be read.")
    call(EmbyRequests.updateItem(itemId, current, draft))
}

suspend fun EmbyLibrary.searchIdentify(item: MediaItem): List<RemoteIdentifyHit> = withContext(Dispatchers.IO) {
    val request = EmbyRequests.remoteSearch(item) ?: return@withContext emptyList()
    EmbyJsonEdits.identifyHits(json(request))
}

suspend fun EmbyLibrary.applyIdentify(itemId: String, hit: RemoteIdentifyHit) {
    call(EmbyRequests.applyRemoteSearch(itemId, hit))
}

suspend fun EmbyLibrary.remoteArtwork(itemId: String, kind: RemoteArtworkKind): List<RemoteImageChoice> = withContext(Dispatchers.IO) {
    EmbyServerMapping.remoteImages(decode(EmbyRequests.remoteImages(itemId, kind), EmbyRemoteImageResult.serializer()).images)
}

suspend fun EmbyLibrary.downloadRemoteArtwork(itemId: String, kind: RemoteArtworkKind, imageUrl: String) {
    call(EmbyRequests.downloadRemoteImage(itemId, kind, imageUrl))
}

suspend fun EmbyLibrary.deleteLibraryItem(itemId: String) {
    call(EmbyRequests.deleteItem(itemId))
}

private suspend fun EmbyLibrary.mediaSourceId(itemId: String): String =
    item(itemId).mediaSources.firstOrNull()?.id ?: throw ZelefinException.server("Emby has no file for this title.")

/** [language] is a picker code ("en"); Emby's subtitle providers search by the three-letter code. */
suspend fun EmbyLibrary.searchSubtitles(itemId: String, language: String, perfectMatch: Boolean?): List<RemoteSubtitle> =
    withContext(Dispatchers.IO) {
        val request = EmbyRequests.subtitleSearch(itemId, mediaSourceId(itemId), ServerLanguageCode.toServer(language), perfectMatch == true)
        (json(request) as? JsonArray).orEmpty().mapNotNull { (it as? JsonObject)?.let(RemoteSubtitle::parse) }
    }

/** Downloads onto the server, then waits up to 8s for the new subtitle stream to show on the title. */
suspend fun EmbyLibrary.downloadSubtitle(itemId: String, subtitleId: String) = withContext(Dispatchers.IO) {
    val before = subtitleCount(itemId)
    call(EmbyRequests.subtitleDownload(itemId, mediaSourceId(itemId), subtitleId))
    repeat(20) {
        delay(400)
        if (subtitleCount(itemId) != before) return@withContext
    }
}

private suspend fun EmbyLibrary.subtitleCount(itemId: String): Int =
    runCatching { item(itemId).streams.count { it.isSubtitle } }.getOrDefault(-1)

// Sessions and remote control

suspend fun EmbyLibrary.playbackSessions(controllableOnly: Boolean = false): List<RemoteSession> = withContext(Dispatchers.IO) {
    val request = EmbyRequests.sessions(controllableBy = user.takeIf { controllableOnly })
    EmbyServerMapping.sessions(decode(request, ListSerializer(EmbySessionInfo.serializer())))
}

suspend fun EmbyLibrary.playOnSession(sessionId: String, item: MediaItem) {
    val start = item.playbackPosition.takeIf { it > 5 }?.let(TickClock::ticks)
    call(EmbyRequests.playOnSession(sessionId, item.id, start))
}

suspend fun EmbyLibrary.sendSessionControl(session: RemoteSession, control: SessionControl) {
    val request = when (control) {
        SessionControl.Previous -> EmbyRequests.playstate(session.id, "PreviousTrack", controllingUserId = user)
        SessionControl.Next -> EmbyRequests.playstate(session.id, "NextTrack", controllingUserId = user)
        SessionControl.PlayPause -> EmbyRequests.playstate(session.id, if (session.isPaused) "Unpause" else "Pause", controllingUserId = user)
        SessionControl.Stop -> EmbyRequests.playstate(session.id, "Stop", controllingUserId = user)
        SessionControl.Back10 -> EmbyRequests.playstate(session.id, "Seek", TickClock.ticks((session.position - 10).coerceAtLeast(0.0)), user)
        SessionControl.Forward10 -> {
            val end = session.runtime ?: (session.position + 10)
            EmbyRequests.playstate(session.id, "Seek", TickClock.ticks((session.position + 10).coerceAtMost(end)), user)
        }
        SessionControl.VolumeDown -> EmbyRequests.generalCommand(session.id, "VolumeDown")
        SessionControl.VolumeUp -> EmbyRequests.generalCommand(session.id, "VolumeUp")
        SessionControl.Mute -> EmbyRequests.generalCommand(session.id, if (session.isMuted) "Unmute" else "Mute")
    }
    call(request)
}

suspend fun EmbyLibrary.sendSessionMessage(sessionId: String, text: String) {
    val trimmed = text.trim()
    if (trimmed.isEmpty()) return
    call(EmbyRequests.message(sessionId, "Zelefin", trimmed, 8000))
}

/** Emby wants the session id with the capabilities, so this device's session is looked up first. */
suspend fun EmbyLibrary.advertiseSessionCapabilities() = withContext(Dispatchers.IO) {
    val own = decode(EmbyRequests.sessions(deviceId = api.deviceId), ListSerializer(EmbySessionInfo.serializer())).firstOrNull()?.id
        ?: return@withContext
    call(EmbyRequests.capabilities(own))
}

// Live TV

suspend fun EmbyLibrary.liveTvEnabled(): Boolean = withContext(Dispatchers.IO) {
    runCatching { decode(EmbyRequests.liveTvInfo(), EmbyLiveTvInfo.serializer()).isEnabled }.getOrDefault(false)
}

suspend fun EmbyLibrary.closeLiveStream(liveStreamId: String) {
    call(EmbyRequests.closeLiveStream(liveStreamId))
}
