package app.zelefin.client.jellyfin

import app.zelefin.core.ItemMapper
import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.jellyfin.sdk.api.client.extensions.itemRefreshApi
import org.jellyfin.sdk.api.client.extensions.libraryApi
import org.jellyfin.sdk.api.client.extensions.remoteImageApi
import org.jellyfin.sdk.api.client.extensions.sessionApi
import org.jellyfin.sdk.api.client.extensions.syncPlayApi
import org.jellyfin.sdk.model.api.GeneralCommandType
import org.jellyfin.sdk.model.api.ImageType
import org.jellyfin.sdk.model.api.JoinGroupRequestDto
import org.jellyfin.sdk.model.api.MessageCommand
import org.jellyfin.sdk.model.api.MetadataRefreshMode
import org.jellyfin.sdk.model.api.NewGroupRequestDto
import org.jellyfin.sdk.model.api.PlayCommand
import org.jellyfin.sdk.model.api.PlayMethod
import org.jellyfin.sdk.model.api.PlayRequestDto
import org.jellyfin.sdk.model.api.PlaystateCommand
import org.jellyfin.sdk.model.api.SessionInfoDto
import org.jellyfin.sdk.model.api.TranscodingInfo

private const val TicksPerSecond = 10_000_000L

private fun Double.toTicks(): Long = (this * TicksPerSecond).toLong()

/** A Jellyfin client session: who is signed in, what they are watching, and how it streams. Mirrors iOS `PlaybackSession`. */
data class RemoteSession(
    val id: String,
    val userId: String?,
    val userName: String,
    val userImageTag: String?,
    val client: String,
    val deviceName: String,
    val deviceType: String?,
    val deviceId: String?,
    val applicationVersion: String?,
    val remoteEndPoint: String?,
    val supportsRemoteControl: Boolean,
    val supportsMediaControl: Boolean,
    val nowPlaying: MediaItem?,
    val nowPlayingName: String?,
    val nowViewingName: String?,
    val position: Double,
    val runtime: Double?,
    val isPaused: Boolean,
    val isMuted: Boolean,
    val canSeek: Boolean,
    val volumeLevel: Int?,
    val playMethod: String,
    val transcoding: List<Pair<String, String>>,
    val supportedCommands: Set<String>,
) {
    val isPlaying: Boolean get() = nowPlaying != null || nowPlayingName != null
    val canControl: Boolean get() = supportsRemoteControl || supportsMediaControl
    val userLabel: String get() = userName.ifBlank { "Unknown user" }
    val deviceLabel: String get() = listOf(client, deviceName).filter { it.isNotBlank() }.joinToString(" · ")
    val supportsMessages: Boolean get() = GeneralCommandType.DISPLAY_MESSAGE.serialName in supportedCommands
    val supportsVolume: Boolean
        get() = GeneralCommandType.VOLUME_UP.serialName in supportedCommands ||
            GeneralCommandType.MUTE.serialName in supportedCommands ||
            GeneralCommandType.TOGGLE_MUTE.serialName in supportedCommands

    val title: String
        get() = nowPlaying?.let(::sessionTitle) ?: nowPlayingName ?: nowViewingName ?: "Idle"

    val progressFraction: Float
        get() {
            val length = runtime ?: return 0f
            if (length <= 0) return 0f
            return (position / length).toFloat().coerceIn(0f, 1f)
        }

    val positionLabel: String
        get() {
            val elapsed = clockLabel(position)
            val length = runtime?.takeIf { it > 0 } ?: return elapsed
            return "$elapsed / ${clockLabel(length)}"
        }

    fun isThisDevice(localDeviceId: String?): Boolean = deviceId != null && localDeviceId != null && deviceId == localDeviceId
}

data class SyncPlayGroup(val id: String, val name: String, val participants: List<String>, val state: String) {
    val subtitle: String
        get() = "$state · ${if (participants.isEmpty()) "No one else yet" else participants.joinToString(", ")}"
}

/** Same four artwork kinds as iOS `RemoteArtworkKind`. */
enum class RemoteArtworkKind(val title: String, val type: ImageType, val aspect: Float) {
    Poster("Poster", ImageType.PRIMARY, 2f / 3f),
    Thumbnail("Thumbnail", ImageType.THUMB, 16f / 9f),
    Logo("Logo", ImageType.LOGO, 8f / 3f),
    Backdrop("Backdrop", ImageType.BACKDROP, 16f / 9f),
}

data class RemoteImageChoice(
    val url: String,
    val thumbnailUrl: String?,
    val provider: String,
    val width: Int?,
    val height: Int?,
) {
    val previewUrl: String get() = thumbnailUrl ?: url
    val sizeLabel: String? get() = if (width != null && height != null) "$width×$height" else null
}

enum class SessionControl { Previous, PlayPause, Next, Stop, Back10, Forward10, VolumeDown, VolumeUp, Mute }

/** The device id this app reports to Jellyfin, used to leave this phone out of remote targets. */
val JellyfinLibrary.reportedDeviceId: String get() = sdk.deviceInfo.id

suspend fun JellyfinLibrary.playbackSessions(controllableBy: UUID? = null): List<RemoteSession> = withContext(Dispatchers.IO) {
    val dtos = sdk.sessionApi.getSessions(controllableBy, null, 960).content
    val sorted = dtos.sortedWith(
        compareByDescending<SessionInfoDto> { it.nowPlayingItem != null }
            .thenByDescending { if (it.nowPlayingItem != null) it.lastPlaybackCheckIn else it.lastActivityDate },
    )
    sorted.mapNotNull(::remoteSession)
}

suspend fun JellyfinLibrary.playOnSession(sessionId: String, item: MediaItem) = withContext(Dispatchers.IO) {
    val start = item.playbackPosition.takeIf { it > 5 }?.toTicks()
    sdk.sessionApi.play(sessionId, PlayCommand.PLAY_NOW, listOf(UUID.fromString(item.id)), start, null, null, null, null)
}

suspend fun JellyfinLibrary.sendSessionControl(session: RemoteSession, control: SessionControl, userId: String?) =
    withContext(Dispatchers.IO) {
        val api = sdk.sessionApi
        suspend fun playstate(command: PlaystateCommand, seek: Double? = null) {
            api.sendPlaystateCommand(session.id, command, seek?.toTicks(), userId)
        }
        when (control) {
            SessionControl.Previous -> playstate(PlaystateCommand.PREVIOUS_TRACK)
            SessionControl.Next -> playstate(PlaystateCommand.NEXT_TRACK)
            SessionControl.PlayPause -> playstate(if (session.isPaused) PlaystateCommand.UNPAUSE else PlaystateCommand.PAUSE)
            SessionControl.Stop -> playstate(PlaystateCommand.STOP)
            SessionControl.Back10 -> playstate(PlaystateCommand.SEEK, (session.position - 10).coerceAtLeast(0.0))
            SessionControl.Forward10 -> {
                val end = session.runtime ?: (session.position + 10)
                playstate(PlaystateCommand.SEEK, (session.position + 10).coerceAtMost(end))
            }
            SessionControl.VolumeDown -> { api.sendGeneralCommand(session.id, GeneralCommandType.VOLUME_DOWN) }
            SessionControl.VolumeUp -> { api.sendGeneralCommand(session.id, GeneralCommandType.VOLUME_UP) }
            SessionControl.Mute -> {
                api.sendGeneralCommand(session.id, if (session.isMuted) GeneralCommandType.UNMUTE else GeneralCommandType.MUTE)
            }
        }
        Unit
    }

suspend fun JellyfinLibrary.sendSessionMessage(sessionId: String, text: String) = withContext(Dispatchers.IO) {
    val trimmed = text.trim()
    if (trimmed.isEmpty()) return@withContext
    sdk.sessionApi.sendMessageCommand(sessionId, MessageCommand(header = "Zelefin", text = trimmed, timeoutMs = 8000))
    Unit
}

suspend fun JellyfinLibrary.syncPlayGroups(): List<SyncPlayGroup> = withContext(Dispatchers.IO) {
    sdk.syncPlayApi.syncPlayGetGroups().content.map { dto ->
        SyncPlayGroup(
            id = dto.groupId.toString(),
            name = dto.groupName.trim().ifEmpty { "SyncPlay" },
            participants = dto.participants,
            state = dto.state.serialName,
        )
    }
}

suspend fun JellyfinLibrary.syncPlayCreateGroup(name: String): SyncPlayGroup = withContext(Dispatchers.IO) {
    val dto = sdk.syncPlayApi.syncPlayCreateGroup(NewGroupRequestDto(groupName = name)).content
    SyncPlayGroup(dto.groupId.toString(), dto.groupName.trim().ifEmpty { name }, dto.participants, dto.state.serialName)
}

suspend fun JellyfinLibrary.syncPlayJoinGroup(id: String) = withContext(Dispatchers.IO) {
    sdk.syncPlayApi.syncPlayJoinGroup(JoinGroupRequestDto(groupId = UUID.fromString(id)))
    Unit
}

suspend fun JellyfinLibrary.syncPlayLeaveGroup() = withContext(Dispatchers.IO) {
    sdk.syncPlayApi.syncPlayLeaveGroup()
    Unit
}

suspend fun JellyfinLibrary.syncPlaySetQueue(item: MediaItem) = withContext(Dispatchers.IO) {
    val start = item.playbackPosition.takeIf { it > 5 } ?: 0.0
    sdk.syncPlayApi.syncPlaySetNewQueue(
        PlayRequestDto(playingQueue = listOf(UUID.fromString(item.id)), playingItemPosition = 0, startPositionTicks = start.toTicks()),
    )
    Unit
}

/** iOS `refreshItemMetadata`: full metadata refresh, images left alone. */
suspend fun JellyfinLibrary.refreshItemMetadata(itemId: String) = withContext(Dispatchers.IO) {
    sdk.itemRefreshApi.refreshItem(
        UUID.fromString(itemId),
        MetadataRefreshMode.FULL_REFRESH,
        MetadataRefreshMode.DEFAULT,
        false,
        false,
        false,
    )
    Unit
}

/** Asks Jellyfin to scan every library for new files and refresh metadata, like iOS `scanLibraries()`. */
suspend fun JellyfinLibrary.scanLibraries() = withContext(Dispatchers.IO) {
    sdk.libraryApi.refreshLibrary()
    Unit
}

suspend fun JellyfinLibrary.deleteLibraryItem(itemId: String) = withContext(Dispatchers.IO) {
    sdk.libraryApi.deleteItem(UUID.fromString(itemId))
    Unit
}

suspend fun JellyfinLibrary.remoteArtwork(itemId: String, kind: RemoteArtworkKind): List<RemoteImageChoice> = withContext(Dispatchers.IO) {
    sdk.remoteImageApi.getRemoteImages(UUID.fromString(itemId), kind.type, 0, 40, null, true).content.images.orEmpty()
        .mapNotNull { info ->
            val url = info.url?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            RemoteImageChoice(url, info.thumbnailUrl?.takeIf { it.isNotBlank() }, info.providerName ?: "Provider", info.width, info.height)
        }
        .distinctBy { it.url }
}

suspend fun JellyfinLibrary.downloadRemoteArtwork(itemId: String, kind: RemoteArtworkKind, imageUrl: String) = withContext(Dispatchers.IO) {
    sdk.remoteImageApi.downloadRemoteImage(UUID.fromString(itemId), kind.type, imageUrl)
    Unit
}

private fun remoteSession(dto: SessionInfoDto): RemoteSession? {
    val id = dto.id?.takeIf { it.isNotBlank() } ?: return null
    val playing = dto.nowPlayingItem
    val item = playing?.let { ItemMapper.mediaItem(it.toSnapshot()) }
    val runtime = item?.runtime ?: playing?.runTimeTicks?.let { it.toDouble() / TicksPerSecond }
    val method = when (dto.playState?.playMethod) {
        PlayMethod.DIRECT_PLAY -> "Direct Play"
        PlayMethod.DIRECT_STREAM -> "Direct Stream"
        PlayMethod.TRANSCODE -> "Transcode"
        null -> if (dto.transcodingInfo != null) "Transcode" else "Unknown"
    }
    return RemoteSession(
        id = id,
        userId = dto.userId.toString(),
        userName = dto.userName.orEmpty(),
        userImageTag = dto.userPrimaryImageTag,
        client = dto.client.orEmpty(),
        deviceName = dto.deviceName.orEmpty(),
        deviceType = dto.deviceType,
        deviceId = dto.deviceId,
        applicationVersion = dto.applicationVersion,
        remoteEndPoint = dto.remoteEndPoint,
        supportsRemoteControl = dto.supportsRemoteControl,
        supportsMediaControl = dto.supportsMediaControl,
        nowPlaying = item,
        nowPlayingName = if (item == null && playing != null) playing.name ?: "Playing" else null,
        nowViewingName = dto.nowViewingItem?.name,
        position = (dto.playState?.positionTicks ?: 0L).toDouble() / TicksPerSecond,
        runtime = runtime,
        isPaused = dto.playState?.isPaused ?: false,
        isMuted = dto.playState?.isMuted ?: false,
        canSeek = dto.playState?.canSeek ?: false,
        volumeLevel = dto.playState?.volumeLevel,
        playMethod = method,
        transcoding = dto.transcodingInfo?.let(::transcodingRows).orEmpty(),
        supportedCommands = dto.supportedCommands.map { it.serialName }.toSet(),
    )
}

private fun transcodingRows(info: TranscodingInfo): List<Pair<String, String>> = buildList {
    val stream = buildList {
        info.container?.takeIf { it.isNotBlank() }?.let { add(it.uppercase()) }
        info.videoCodec?.takeIf { it.isNotBlank() }?.let { add(if (info.isVideoDirect) "${it.uppercase()} direct" else it.uppercase()) }
        info.audioCodec?.takeIf { it.isNotBlank() }?.let { codec ->
            var audio = codec.uppercase()
            info.audioChannels?.let { audio += " ${it}ch" }
            if (info.isAudioDirect) audio += " direct"
            add(audio)
        }
        info.hardwareAccelerationType?.serialName?.takeIf { it != "none" }?.let { add(it.uppercase()) }
    }
    if (stream.isNotEmpty()) add("Stream" to stream.joinToString(" · "))
    if (info.width != null && info.height != null) add("Resolution" to "${info.width}×${info.height}")
    info.bitrate?.takeIf { it > 0 }?.let { bitrate ->
        add(
            "Bitrate" to when {
                bitrate >= 1_000_000 -> String.format("%.1f Mbps", bitrate / 1_000_000.0)
                bitrate >= 1_000 -> "${bitrate / 1_000} kbps"
                else -> "$bitrate bps"
            },
        )
    }
    if (info.transcodeReasons.isNotEmpty()) {
        add("Reason" to info.transcodeReasons.joinToString(", ") { reason -> reason.serialName.spacedWords() })
    }
    info.completionPercentage?.let { add("Complete" to "${it.toInt()}%") }
}

private fun String.spacedWords(): String = buildString {
    this@spacedWords.forEachIndexed { index, char ->
        if (char.isUpperCase() && index > 0) append(' ')
        append(char)
    }
}.lowercase()

private fun sessionTitle(item: MediaItem): String {
    if (item.kind == MediaKind.Episode) {
        val parts = mutableListOf<String>()
        item.seriesName?.takeIf { it.isNotBlank() }?.let(parts::add)
        if (item.seasonIndex != null && item.episodeIndex != null) parts += "S${item.seasonIndex}:E${item.episodeIndex}"
        if (parts.isEmpty() || parts.first() != item.name) parts += item.name
        return parts.joinToString(" · ")
    }
    return item.year?.let { "${item.name} ($it)" } ?: item.name
}

fun clockLabel(seconds: Double): String {
    val total = seconds.toLong().coerceAtLeast(0)
    val hours = total / 3600
    val minutes = (total % 3600) / 60
    val secs = total % 60
    return if (hours > 0) "%d:%02d:%02d".format(hours, minutes, secs) else "%d:%02d".format(minutes, secs)
}
