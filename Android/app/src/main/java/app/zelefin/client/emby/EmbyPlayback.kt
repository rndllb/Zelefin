package app.zelefin.client.emby

import app.zelefin.client.LanguageTrack
import app.zelefin.client.plugins.SkipSegment
import app.zelefin.core.EmbyChapter
import app.zelefin.core.EmbyMediaSource
import app.zelefin.core.EmbyMediaStream
import app.zelefin.core.EmbyPlaybackInfo
import app.zelefin.core.ExternalSubtitle
import app.zelefin.core.PlaybackChapter
import app.zelefin.core.PlaybackMethod
import app.zelefin.core.ServerUrl
import app.zelefin.core.StreamResumeUrl
import app.zelefin.core.TickClock
import app.zelefin.core.TrackChoice

/** The parts of an Emby `PlaybackInfo` answer that become a `PlaybackPlan`. */
object EmbyPlayback {
    /** The version that was asked for (its id is `mediasource_<n>`, not the item id), else the first. */
    fun source(info: EmbyPlaybackInfo, wantedSourceId: String?): EmbyMediaSource? =
        info.mediaSources.firstOrNull { wantedSourceId != null && it.id == wantedSourceId } ?: info.mediaSources.firstOrNull()

    fun method(source: EmbyMediaSource): PlaybackMethod = when {
        source.supportsDirectPlay -> PlaybackMethod.DirectPlay
        source.supportsDirectStream && !source.transcodingUrl.isNullOrBlank() -> PlaybackMethod.Remux
        source.supportsTranscoding && !source.transcodingUrl.isNullOrBlank() -> PlaybackMethod.Transcode
        else -> PlaybackMethod.DirectPlay
    }

    /** HLS opens at t=0 and the player seeks, as on Jellyfin. */
    fun streamUrl(
        base: String,
        token: String?,
        itemId: String,
        source: EmbyMediaSource,
        method: PlaybackMethod,
        deviceId: String,
        playSessionId: String?,
    ): String? {
        val raw = if (method != PlaybackMethod.DirectPlay && !source.transcodingUrl.isNullOrBlank()) {
            ServerUrl.resolve(base, source.transcodingUrl!!, token)
        } else {
            source.directStreamUrl?.takeIf { it.isNotBlank() }?.let { ServerUrl.resolve(base, it, token) }
                ?: directUrl(base, token, itemId, source, deviceId, playSessionId)
        }
        return raw?.let(StreamResumeUrl::strippingStartTimeTicks)
    }

    private fun directUrl(base: String, token: String?, itemId: String, source: EmbyMediaSource, deviceId: String, playSessionId: String?): String? {
        val container = source.container?.substringBefore(',')?.trim()?.ifBlank { null } ?: "mkv"
        val query = buildList {
            add("Static=true")
            source.id?.takeIf { it.isNotBlank() }?.let { add("MediaSourceId=$it") }
            add("DeviceId=$deviceId")
            playSessionId?.takeIf { it.isNotBlank() }?.let { add("PlaySessionId=$it") }
        }.joinToString("&")
        return ServerUrl.resolve(base, "/Videos/$itemId/stream.$container?$query", token)
    }

    /** Direct play already carries embedded tracks, so only files beside the video are sideloaded. */
    fun externalSubtitles(base: String, token: String?, itemId: String, source: EmbyMediaSource, method: PlaybackMethod): List<ExternalSubtitle> =
        source.mediaStreams
            .filter { it.isSubtitle && it.isExternalDelivery }
            .filter { method != PlaybackMethod.DirectPlay || it.isExternal }
            .mapNotNull { stream ->
                val format = subtitleFormat(stream) ?: return@mapNotNull null
                val mime = when (format) {
                    "srt", "subrip" -> androidx.media3.common.MimeTypes.APPLICATION_SUBRIP
                    "vtt", "webvtt" -> androidx.media3.common.MimeTypes.TEXT_VTT
                    "ass", "ssa" -> androidx.media3.common.MimeTypes.TEXT_SSA
                    else -> return@mapNotNull null
                }
                val path = stream.deliveryUrl?.takeIf { it.isNotBlank() }
                    ?: "/Videos/$itemId/${source.id ?: itemId}/Subtitles/${stream.index}/Stream.$format"
                val url = ServerUrl.resolve(base, path, token) ?: return@mapNotNull null
                ExternalSubtitle(
                    url = url,
                    mimeType = mime,
                    language = stream.language,
                    title = stream.displayTitle ?: stream.title ?: stream.language ?: "Subtitle",
                    id = externalSubtitleId(stream.index),
                )
            }

    private fun subtitleFormat(stream: EmbyMediaStream): String? {
        val fromUrl = stream.deliveryUrl?.substringBefore('?')?.substringAfterLast("Stream.", "")?.lowercase()?.ifBlank { null }
        return fromUrl ?: stream.codec?.lowercase()
    }

    /** The player finds sideloaded tracks by this prefix, so it matches Jellyfin's. */
    private const val ExternalPrefix = "jf-ext-"

    fun externalSubtitleId(index: Int) = "$ExternalPrefix$index"

    fun languageTracks(streams: List<EmbyMediaStream>, subtitles: Boolean, selectedIndex: Int?, scoped: Boolean): List<LanguageTrack> =
        streams.filter { if (subtitles) it.isSubtitle else it.isAudio }.map { stream ->
            LanguageTrack(
                index = stream.index,
                language = stream.language,
                isSelected = if (scoped) stream.index == selectedIndex else stream.isDefault,
                title = stream.displayTitle ?: stream.title.orEmpty(),
                isHearingImpaired = stream.isHearingImpaired,
            )
        }

    /**
     * Emby can mark an embedded subtitle `External` even on a direct play, so [sideloaded] (the
     * indexes handed to the player as files) decides which tracks live outside the container.
     */
    fun trackChoice(streams: List<EmbyMediaStream>, subtitles: Boolean, index: Int?, sideloaded: Set<Int> = emptySet()): TrackChoice? {
        index ?: return null
        val ofType = streams.filter { if (subtitles) it.isSubtitle else it.isAudio }.sortedBy { it.index }
        val ordinal = ofType.indexOfFirst { it.index == index }
        if (ordinal < 0) return null
        val stream = ofType[ordinal]
        fun outsideContainer(candidate: EmbyMediaStream) = subtitles && (candidate.isExternal || candidate.index in sideloaded)
        return TrackChoice(
            ordinal = ofType.take(ordinal).count { !outsideContainer(it) },
            language = stream.language,
            externalId = if (subtitles && stream.index in sideloaded) externalSubtitleId(stream.index) else null,
        )
    }

    fun sideloadedIndexes(subtitles: List<ExternalSubtitle>): Set<Int> =
        subtitles.mapNotNull { it.id?.removePrefix(ExternalPrefix)?.toIntOrNull() }.toSet()

    /** Timeline ticks; Emby's intro and credit markers become skip buttons instead. */
    fun chapters(chapters: List<EmbyChapter>): List<PlaybackChapter> =
        chapters.filterNot { it.isMarker }
            .mapIndexed { index, chapter ->
                PlaybackChapter(
                    startSeconds = TickClock.seconds(chapter.startPositionTicks),
                    name = chapter.name?.takeIf { it.isNotBlank() } ?: "Chapter ${index + 1}",
                )
            }
            .sortedBy { it.startSeconds }

    /** `IntroStart`..`IntroEnd` is the intro; `CreditsStart` runs to the end of the title. */
    fun skipSegments(chapters: List<EmbyChapter>, runtimeSeconds: Double?): List<SkipSegment> {
        fun at(type: String) = chapters.firstOrNull { it.markerType.equals(type, ignoreCase = true) }
            ?.let { TickClock.seconds(it.startPositionTicks) }
        val segments = mutableListOf<SkipSegment>()
        val introStart = at("IntroStart")
        val introEnd = at("IntroEnd")
        if (introEnd != null) segments += SkipSegment(SkipSegment.Kind.Intro, introStart ?: 0.0, introEnd)
        val credits = at("CreditsStart")
        val end = runtimeSeconds?.takeIf { it > 0 }
        if (credits != null && end != null) segments += SkipSegment(SkipSegment.Kind.Outro, credits, end)
        return segments.filter { it.end - it.start >= SkipSegment.MIN_LENGTH }
    }
}
