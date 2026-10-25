package app.zelefin.client.emby

import app.zelefin.client.jellyfin.ActivityLogItem
import app.zelefin.client.jellyfin.RemoteImageChoice
import app.zelefin.client.jellyfin.RemoteSession
import app.zelefin.client.jellyfin.ScheduledTask
import app.zelefin.core.EmbyActivityEntry
import app.zelefin.core.EmbyRemoteImage
import app.zelefin.core.EmbySessionInfo
import app.zelefin.core.EmbyTaskInfo
import app.zelefin.core.EmbyTranscodingInfo
import app.zelefin.core.ItemMapper
import app.zelefin.core.TickClock
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import org.jellyfin.sdk.model.api.TaskCompletionStatus
import org.jellyfin.sdk.model.api.TaskState

/** Emby's session, task, and activity answers in the shapes the Jellyfin screens already show. */
object EmbyServerMapping {
    fun remoteSession(dto: EmbySessionInfo): RemoteSession? {
        val id = dto.id?.takeIf { it.isNotBlank() } ?: return null
        val playing = dto.nowPlayingItem
        val item = playing?.let { ItemMapper.mediaItem(it.toSnapshot()) }
        val state = dto.playState
        val method = when (state?.playMethod) {
            "DirectPlay" -> "Direct Play"
            "DirectStream" -> "Direct Stream"
            "Transcode" -> "Transcode"
            else -> if (dto.transcodingInfo != null) "Transcode" else "Unknown"
        }
        return RemoteSession(
            id = id,
            userId = dto.userId,
            userName = dto.userName.orEmpty(),
            userImageTag = dto.userPrimaryImageTag,
            client = dto.client.orEmpty(),
            deviceName = dto.deviceName.orEmpty(),
            deviceType = dto.deviceType,
            deviceId = dto.deviceId,
            applicationVersion = dto.applicationVersion,
            remoteEndPoint = dto.remoteEndPoint,
            supportsRemoteControl = dto.supportsRemoteControl,
            supportsMediaControl = dto.supportsRemoteControl,
            nowPlaying = item,
            nowPlayingName = if (item == null && playing != null) playing.name ?: "Playing" else null,
            nowViewingName = null,
            position = TickClock.seconds(state?.positionTicks ?: 0L),
            runtime = item?.runtime ?: playing?.runTimeTicks?.let(TickClock::seconds),
            isPaused = state?.isPaused == true,
            isMuted = state?.isMuted == true,
            canSeek = state?.canSeek == true,
            volumeLevel = state?.volumeLevel,
            playMethod = method,
            transcoding = dto.transcodingInfo?.let(::transcodingRows).orEmpty(),
            supportedCommands = dto.supportedCommands.toSet(),
        )
    }

    /** Playing sessions first, then by most recent activity, like the Jellyfin list. */
    fun sessions(dtos: List<EmbySessionInfo>): List<RemoteSession> =
        dtos.sortedWith(compareByDescending<EmbySessionInfo> { it.nowPlayingItem != null }.thenByDescending { it.lastActivityDate.orEmpty() })
            .mapNotNull(::remoteSession)

    private fun transcodingRows(info: EmbyTranscodingInfo): List<Pair<String, String>> = buildList {
        val stream = buildList {
            info.container?.takeIf { it.isNotBlank() }?.let { add(it.uppercase()) }
            info.videoCodec?.takeIf { it.isNotBlank() }?.let { add(if (info.isVideoDirect) "${it.uppercase()} direct" else it.uppercase()) }
            info.audioCodec?.takeIf { it.isNotBlank() }?.let { codec ->
                var audio = codec.uppercase()
                info.audioChannels?.let { audio += " ${it}ch" }
                if (info.isAudioDirect) audio += " direct"
                add(audio)
            }
        }
        if (stream.isNotEmpty()) add("Stream" to stream.joinToString(" · "))
        if (info.width != null && info.height != null) add("Resolution" to "${info.width}×${info.height}")
        info.bitrate?.takeIf { it > 0 }?.let { bitrate ->
            add("Bitrate" to if (bitrate >= 1_000_000) String.format("%.1f Mbps", bitrate / 1_000_000.0) else "${bitrate / 1_000} kbps")
        }
        if (info.transcodeReasons.isNotEmpty()) add("Reason" to info.transcodeReasons.joinToString(", ") { it.spacedWords() })
        info.completionPercentage?.let { add("Complete" to "${it.toInt()}%") }
    }

    fun scheduledTask(dto: EmbyTaskInfo): ScheduledTask? {
        val id = dto.id?.takeIf { it.isNotBlank() } ?: return null
        val last = dto.lastExecutionResult
        return ScheduledTask(
            id = id,
            name = dto.name?.trim()?.ifEmpty { null } ?: "Scheduled task",
            category = dto.category?.trim()?.ifEmpty { null } ?: "Other",
            summary = dto.description?.trim().orEmpty(),
            state = TaskState.entries.firstOrNull { it.serialName.equals(dto.state, ignoreCase = true) } ?: TaskState.IDLE,
            progressPercentage = dto.currentProgressPercentage,
            isHidden = dto.isHidden,
            lastStatus = TaskCompletionStatus.entries.firstOrNull { it.serialName.equals(last?.status, ignoreCase = true) },
            lastStarted = localTime(last?.startTimeUtc),
            lastEnded = localTime(last?.endTimeUtc),
            lastError = last?.errorMessage?.trim()?.ifEmpty { null },
        )
    }

    fun scheduledTasks(dtos: List<EmbyTaskInfo>): List<ScheduledTask> = dtos.mapNotNull(::scheduledTask)
        .sortedWith(
            compareByDescending<ScheduledTask> { it.isActive }
                .thenBy(String.CASE_INSENSITIVE_ORDER) { it.category }
                .thenBy(String.CASE_INSENSITIVE_ORDER) { it.name },
        )

    fun activity(entries: List<EmbyActivityEntry>): List<ActivityLogItem> = entries.mapNotNull { entry ->
        val title = entry.name?.trim().orEmpty()
        if (title.isEmpty()) return@mapNotNull null
        ActivityLogItem(
            id = entry.id.orEmpty(),
            title = title,
            detail = entry.shortOverview ?: entry.overview,
            date = localTime(entry.date),
            type = entry.type,
        )
    }

    fun remoteImages(images: List<EmbyRemoteImage>): List<RemoteImageChoice> = images.mapNotNull { info ->
        val url = info.url?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
        RemoteImageChoice(url, info.thumbnailUrl?.takeIf { it.isNotBlank() }, info.providerName ?: "Provider", info.width, info.height)
    }.distinctBy { it.url }

    /** Emby dates are UTC with seven fractional digits; the admin screens show local time. */
    fun localTime(raw: String?): LocalDateTime? = raw?.trim()?.takeIf { it.isNotEmpty() }?.let { text ->
        runCatching { OffsetDateTime.parse(text).atZoneSameInstant(ZoneId.systemDefault()).toLocalDateTime() }.getOrNull()
    }

    private fun String.spacedWords(): String = buildString {
        this@spacedWords.forEachIndexed { index, char ->
            if (char.isUpperCase() && index > 0) append(' ')
            append(char)
        }
    }.lowercase()
}
