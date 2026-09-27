package app.zelefin.client.ui

import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import app.zelefin.core.PlaybackMethod
import app.zelefin.core.PlaybackPlan
import java.util.Locale

internal sealed interface SleepTimer {
    data object Off : SleepTimer
    data class Minutes(val minutes: Int) : SleepTimer
    data object EndOfEpisode : SleepTimer

    companion object {
        val durations = listOf(15, 30, 45, 60)
    }
}

internal fun sleepTitle(timer: SleepTimer): String = when (timer) {
    SleepTimer.Off -> "Off"
    is SleepTimer.Minutes -> "${timer.minutes} minutes"
    SleepTimer.EndOfEpisode -> "End of Episode"
}

private class StatLine(val label: String, val value: String)
private class StatSection(val title: String, val lines: List<StatLine>)

/** Mirrors iOS `PlaybackStatsOverlay`: a dark card at the top leading corner. */
@OptIn(UnstableApi::class)
@Composable
internal fun PlaybackStatsPanel(
    player: ExoPlayer,
    plan: PlaybackPlan,
    position: Double,
    duration: Double,
    speed: Float,
    fillsScreen: Boolean,
    modifier: Modifier = Modifier,
) {
    val video = player.videoFormat
    val audio = player.audioFormat
    val size = player.videoSize
    val host = runCatching { java.net.URI(plan.streamUrl).host }.getOrNull()
    val local = plan.streamUrl.startsWith("file:")
    val buffered = (player.totalBufferedDuration / 1000.0).coerceAtLeast(0.0)
    val dropped = player.videoDecoderCounters?.droppedBufferCount
    val sections = listOf(
        StatSection(
            "Session",
            listOfNotNull(
                StatLine("Title", plan.item.name),
                StatLine("Playhead", "${clockText(position)} / ${clockText(duration)}"),
                StatLine("Rate", String.format(Locale.US, "%.2fx", speed)),
                StatLine(
                    "Stream",
                    when {
                        local -> "Downloaded file"
                        plan.method == PlaybackMethod.DirectPlay -> "Direct Play"
                        plan.method == PlaybackMethod.Remux -> "Direct Stream"
                        else -> "Transcode"
                    },
                ),
                StatLine("Player", "ExoPlayer"),
                StatLine("Zoom", if (fillsScreen) "Fill" else "Fit"),
            ),
        ),
        StatSection(
            "Video",
            listOfNotNull(
                StatLine("Codec", videoCodecName(video) ?: plan.videoCodec?.uppercase() ?: "—"),
                video?.let { StatLine("Size", "${it.width}×${it.height}") },
                size.takeIf { it.width > 0 }?.let { StatLine("Display", "${(it.width * it.pixelWidthHeightRatio).toInt()}×${it.height}") },
                video?.frameRate?.takeIf { it > 0 }?.let { StatLine("Frame rate", String.format(Locale.US, "%.3f fps", it)) },
                bitrateText(video?.bitrate)?.let { StatLine("Bitrate", it) },
                StatLine("Range", videoRange(video)),
                StatLine("Container", plan.container?.uppercase() ?: "—"),
                dropped?.let { StatLine("Dropped", "$it frames") },
            ),
        ),
        StatSection(
            "Audio",
            listOfNotNull(
                audio?.let { StatLine("Track", it.label ?: it.language ?: "Default") },
                StatLine("Codec", audioCodecName(audio) ?: "—"),
                audio?.channelCount?.takeIf { it > 0 }?.let { StatLine("Layout", layoutName(it)) },
                audio?.sampleRate?.takeIf { it > 0 }?.let { StatLine("Sample rate", "${it / 1000.0} kHz") },
                bitrateText(audio?.bitrate)?.let { StatLine("Bitrate", it) },
            ),
        ),
        StatSection(
            "Network",
            listOfNotNull(
                StatLine("Host", if (local) "This device" else host ?: "—"),
                StatLine("Buffer", String.format(Locale.US, "%.1f s", buffered)),
                StatLine("Loading", if (player.isLoading) "Yes" else "No"),
            ),
        ),
    )
    val shape = RoundedCornerShape(14.dp)
    Column(
        modifier
            .widthIn(max = 360.dp)
            .heightIn(max = 420.dp)
            .clip(shape)
            .background(Color.Black.copy(alpha = 0.62f))
            .border(1.dp, Color.White.copy(alpha = 0.12f), shape)
            .verticalScroll(rememberScrollState())
            .padding(14.dp),
    ) {
        sections.forEachIndexed { index, section ->
            if (index > 0) Spacer(Modifier.height(10.dp))
            Text(
                section.title.uppercase(),
                color = Color.White.copy(alpha = 0.55f),
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.SemiBold,
                fontSize = 11.sp,
                letterSpacing = 0.6.sp,
            )
            Spacer(Modifier.height(4.dp))
            section.lines.forEach { line ->
                Row {
                    Text(
                        line.label,
                        color = Color.White.copy(alpha = 0.62f),
                        fontFamily = ZelefinFont,
                        fontSize = 12.sp,
                        modifier = Modifier.width(92.dp),
                    )
                    Text(
                        line.value,
                        color = Color.White,
                        fontSize = 12.sp,
                        style = TextStyle(fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace),
                        maxLines = 2,
                    )
                }
            }
        }
    }
}

internal fun clockText(seconds: Double): String {
    val total = seconds.coerceAtLeast(0.0).toLong()
    val hours = total / 3600
    val minutes = (total % 3600) / 60
    val secs = total % 60
    return if (hours > 0) String.format(Locale.US, "%d:%02d:%02d", hours, minutes, secs) else String.format(Locale.US, "%d:%02d", minutes, secs)
}

private fun bitrateText(bits: Int?): String? {
    if (bits == null || bits <= 0 || bits == Format.NO_VALUE) return null
    return if (bits >= 1_000_000) String.format(Locale.US, "%.1f Mbps", bits / 1_000_000.0) else "${bits / 1000} kbps"
}

private fun videoCodecName(format: Format?): String? = when (format?.sampleMimeType) {
    MimeTypes.VIDEO_H264 -> "H.264"
    MimeTypes.VIDEO_H265 -> "HEVC"
    MimeTypes.VIDEO_AV1 -> "AV1"
    MimeTypes.VIDEO_VP9 -> "VP9"
    MimeTypes.VIDEO_VP8 -> "VP8"
    MimeTypes.VIDEO_DOLBY_VISION -> "Dolby Vision"
    MimeTypes.VIDEO_MPEG2 -> "MPEG-2"
    MimeTypes.VIDEO_MP4V -> "MPEG-4"
    null -> null
    else -> format.sampleMimeType?.substringAfter('/')?.uppercase()
}

private fun audioCodecName(format: Format?): String? = when (format?.sampleMimeType) {
    MimeTypes.AUDIO_AC3 -> "Dolby Digital"
    MimeTypes.AUDIO_E_AC3 -> "Dolby Digital+"
    MimeTypes.AUDIO_E_AC3_JOC -> "Dolby Atmos (DD+)"
    MimeTypes.AUDIO_TRUEHD -> "TrueHD"
    MimeTypes.AUDIO_DTS, MimeTypes.AUDIO_DTS_HD, MimeTypes.AUDIO_DTS_EXPRESS -> "DTS"
    MimeTypes.AUDIO_AAC -> "AAC"
    MimeTypes.AUDIO_OPUS -> "Opus"
    MimeTypes.AUDIO_FLAC -> "FLAC"
    MimeTypes.AUDIO_MPEG -> "MP3"
    MimeTypes.AUDIO_VORBIS -> "Vorbis"
    null -> null
    else -> format.sampleMimeType?.substringAfter('/')?.uppercase()
}

private fun layoutName(channels: Int): String = when (channels) {
    1 -> "Mono"
    2 -> "Stereo"
    6 -> "5.1"
    8 -> "7.1"
    else -> "$channels channels"
}

private fun videoRange(format: Format?): String {
    val info = format?.colorInfo ?: return "SDR"
    if (format.sampleMimeType == MimeTypes.VIDEO_DOLBY_VISION) return "Dolby Vision"
    return when (info.colorTransfer) {
        C.COLOR_TRANSFER_ST2084 -> "HDR10"
        C.COLOR_TRANSFER_HLG -> "HLG"
        else -> "SDR"
    }
}
