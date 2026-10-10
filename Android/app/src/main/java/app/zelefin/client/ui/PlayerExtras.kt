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
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.Dp
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
    PlaybackStatsCard(
        sections = listOf(
            StatSection(
                "Session",
                listOfNotNull(
                    StatLine("Title", plan.item.name),
                    StatLine("Playhead", "${clockText(position)} / ${clockText(duration)}"),
                    StatLine("Rate", String.format(Locale.US, "%.2fx", speed)),
                    StatLine("Stream", streamMethodLabel(plan, local)),
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
        ),
        modifier = modifier,
    )
}

@Composable
internal fun MpvPlaybackStatsPanel(
    controller: MpvController,
    plan: PlaybackPlan,
    position: Double,
    duration: Double,
    speed: Float,
    fillsScreen: Boolean,
    modifier: Modifier = Modifier,
) {
    val local = plan.streamUrl.startsWith("file:")
    val host = runCatching { java.net.URI(plan.streamUrl).host }.getOrNull()
    val videoW = controller.int("video-params/w")
    val videoH = controller.int("video-params/h")
    val displayW = controller.int("dwidth")
    val displayH = controller.int("dheight")
    val fps = controller.double("estimated-vf-fps")?.takeIf { it > 0 }
        ?: controller.double("container-fps")?.takeIf { it > 0 }
    val cache = controller.double("demuxer-cache-duration")?.takeIf { it >= 0 }
    val cacheSpeed = controller.double("cache-speed")?.takeIf { it > 0 }
    val dropped = listOfNotNull(controller.int("frame-drop-count"), controller.int("vo-drop-frame-count"))
        .sum()
        .takeIf { it > 0 }
    val audioTrack = controller.string("current-tracks/audio/title")
        ?: controller.string("current-tracks/audio/lang")
    val subtitle = controller.string("current-tracks/sub/title")
        ?: controller.string("current-tracks/sub/lang")
        ?: controller.string("current-tracks/sub/codec")
    PlaybackStatsCard(
        sections = listOf(
            StatSection(
                "Session",
                listOfNotNull(
                    StatLine("Title", plan.item.name),
                    StatLine("Playhead", "${clockText(position)} / ${clockText(duration)}"),
                    StatLine("Rate", String.format(Locale.US, "%.2fx", speed)),
                    StatLine("Stream", streamMethodLabel(plan, local)),
                    StatLine("Player", "MPV"),
                    StatLine("Zoom", if (fillsScreen) "Fill" else "Fit"),
                ),
            ),
            StatSection(
                "Video",
                listOfNotNull(
                    StatLine(
                        "Codec",
                        prettyVideoCodec(controller.string("video-format") ?: controller.string("video-codec") ?: plan.videoCodec),
                    ),
                    if (videoW != null && videoH != null) StatLine("Size", "${videoW}×${videoH}") else null,
                    if (displayW != null && displayH != null && displayW > 0) StatLine("Display", "${displayW}×${displayH}") else null,
                    fps?.let { StatLine("Frame rate", String.format(Locale.US, "%.3f fps", it)) },
                    bitrateBits(controller.double("video-bitrate"))?.let { StatLine("Bitrate", it) },
                    StatLine("Range", mpvRange(controller)),
                    StatLine("Decoder", prettyHwdec(controller.string("hwdec-current"))),
                    StatLine("Pixel", controller.string("video-params/pixelformat") ?: "—"),
                    StatLine("Container", (controller.string("file-format") ?: plan.container)?.uppercase() ?: "—"),
                    dropped?.let { StatLine("Dropped", "$it frames") },
                ),
            ),
            StatSection(
                "Audio",
                listOfNotNull(
                    audioTrack?.let { StatLine("Track", it) },
                    StatLine(
                        "Codec",
                        prettyAudioCodec(controller.string("audio-codec-name") ?: controller.string("audio-codec")),
                    ),
                    controller.int("audio-params/channel-count")?.takeIf { it > 0 }?.let { StatLine("Layout", layoutName(it)) },
                    controller.int("audio-params/samplerate")?.takeIf { it > 0 }?.let { StatLine("Sample rate", "${it / 1000.0} kHz") },
                    bitrateBits(controller.double("audio-bitrate"))?.let { StatLine("Bitrate", it) },
                    controller.string("audio-params/format")?.let { StatLine("Format", it) },
                ),
            ),
            StatSection(
                "Subtitles",
                listOfNotNull(
                    StatLine("Track", subtitle ?: if (plan.subtitlesOff) "Off" else "—"),
                    controller.string("current-tracks/sub/codec")?.let { StatLine("Format", it.uppercase()) },
                ),
            ),
            StatSection(
                "Network",
                listOfNotNull(
                    StatLine("Host", if (local) "This device" else host ?: "—"),
                    cache?.let { StatLine("Buffer", String.format(Locale.US, "%.1f s", it)) },
                    cacheSpeed?.let { StatLine("Cache", throughputText(it)) },
                    StatLine("Loading", if (controller.bool("paused-for-cache") == true) "Yes" else "No"),
                ),
            ),
        ),
        modifier = modifier,
    )
}

@Composable
internal fun playerStatsMaxHeight(chromeVisible: Boolean): Dp {
    val screen = LocalConfiguration.current.screenHeightDp.dp
    val bottom = if (chromeVisible) 88.dp else 16.dp
    return minOf(420.dp, (screen - 80.dp - bottom).coerceAtLeast(160.dp))
}

@Composable
private fun PlaybackStatsCard(sections: List<StatSection>, modifier: Modifier = Modifier) {
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

private fun streamMethodLabel(plan: PlaybackPlan, local: Boolean): String = when {
    local -> "Downloaded file"
    plan.method == PlaybackMethod.DirectPlay -> "Direct Play"
    plan.method == PlaybackMethod.Remux -> "Direct Stream"
    else -> "Transcode"
}

private fun bitrateText(bits: Int?): String? {
    if (bits == null || bits <= 0 || bits == Format.NO_VALUE) return null
    return bitrateBits(bits.toDouble())
}

private fun bitrateBits(bits: Double?): String? {
    if (bits == null || bits <= 0) return null
    return if (bits >= 1_000_000) String.format(Locale.US, "%.1f Mbps", bits / 1_000_000.0) else "${(bits / 1000).toInt()} kbps"
}

private fun throughputText(bytesPerSecond: Double): String {
    val bits = bytesPerSecond * 8
    return if (bits >= 1_000_000) String.format(Locale.US, "%.1f Mbps", bits / 1_000_000.0) else "${(bits / 1000).toInt()} kbps"
}

private fun prettyVideoCodec(raw: String?): String {
    val value = raw?.lowercase().orEmpty()
    return when {
        value.isEmpty() -> "—"
        "dolby" in value || value.contains("dvhe") -> "Dolby Vision"
        value.contains("hevc") || value.contains("h265") || value.contains("h.265") -> "HEVC"
        value.contains("avc") || value.contains("h264") || value.contains("h.264") -> "H.264"
        value.contains("av1") -> "AV1"
        value.contains("vp9") -> "VP9"
        value.contains("vp8") -> "VP8"
        else -> raw?.substringBefore('(')?.trim()?.uppercase() ?: "—"
    }
}

private fun prettyAudioCodec(raw: String?): String {
    val value = raw?.lowercase().orEmpty()
    return when {
        value.isEmpty() -> "—"
        value.contains("truehd") -> "TrueHD"
        value.contains("eac3") || value.contains("e-ac-3") || value.contains("ec-3") -> "Dolby Digital+"
        value.contains("ac3") || value.contains("ac-3") -> "Dolby Digital"
        value.contains("dts") -> "DTS"
        value.contains("opus") -> "Opus"
        value.contains("flac") -> "FLAC"
        value.contains("aac") -> "AAC"
        value.contains("mp3") -> "MP3"
        else -> raw?.substringBefore('(')?.trim()?.uppercase() ?: "—"
    }
}

private fun prettyHwdec(raw: String?): String = when (raw?.lowercase()) {
    null, "", "no" -> "Software"
    "mediacodec-copy" -> "MediaCodec (copy)"
    "mediacodec" -> "MediaCodec"
    else -> raw
}

private fun mpvRange(controller: MpvController): String {
    val dovi = controller.bool("video-params/dovi") == true ||
        controller.string("video-params/dovi").equals("yes", true)
    val profile = controller.int("video-params/dovi-profile") ?: controller.int("dovi-profile")
    val gamma = controller.string("video-params/gamma").orEmpty().lowercase()
    val primaries = controller.string("video-params/primaries").orEmpty().lowercase()
    val displayed = when {
        gamma.contains("pq") || gamma.contains("st2084") -> "HDR10"
        gamma.contains("hlg") -> "HLG"
        primaries.contains("bt.2020") && gamma.isNotEmpty() -> "HDR"
        else -> "SDR"
    }
    if (dovi || (profile != null && profile > 0)) {
        val name = "Dolby Vision" + (profile?.takeIf { it > 0 }?.let { " P$it" } ?: "")
        return if (displayed == "SDR") name else "$name → $displayed"
    }
    return displayed
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
