package app.zelefin.client.jellyfin

import app.zelefin.core.EmbyItem
import app.zelefin.core.MediaItem
import app.zelefin.core.TitleMoreInfo
import app.zelefin.core.TitleMoreLink
import app.zelefin.core.TitleMoreRow
import java.util.Locale
import org.jellyfin.sdk.model.api.BaseItemDto
import org.jellyfin.sdk.model.api.MediaStreamType

/** What a server says about a title, in the shape both Jellyfin and Emby can fill. */
internal data class FactStream(
    val kind: Kind,
    val language: String? = null,
    val codec: String? = null,
    val channelLayout: String? = null,
    val spatialFormat: String = "",
    val title: String? = null,
    val displayTitle: String? = null,
    val isHearingImpaired: Boolean = false,
    val isForced: Boolean = false,
    val width: Int? = null,
    val height: Int? = null,
    val videoRange: String = "",
    val bitRate: Int? = null,
) {
    enum class Kind { Video, Audio, Subtitle, Other }
}

internal data class FactSource(val container: String?, val bitrate: Int?)

internal data class FactInput(
    val streams: List<FactStream> = emptyList(),
    val sources: List<FactSource> = emptyList(),
    val links: List<TitleMoreLink> = emptyList(),
    val studios: List<String> = emptyList(),
    val originalTitle: String? = null,
    val premiereDate: String? = null,
    val officialRating: String? = null,
    val tags: List<String> = emptyList(),
    val regions: List<String> = emptyList(),
    val status: String? = null,
    val airTime: String? = null,
    val container: String? = null,
)

internal object TitleFacts {
    fun from(dto: BaseItemDto, item: MediaItem): TitleMoreInfo = from(dto.factInput(), item)

    fun from(dto: EmbyItem, item: MediaItem): TitleMoreInfo = from(dto.factInput(), item)

    fun from(input: FactInput, item: MediaItem): TitleMoreInfo {
        val streams = input.streams
        val audio = streams.filter { it.kind == FactStream.Kind.Audio }
        val subtitles = streams.filter { it.kind == FactStream.Kind.Subtitle }
        return TitleMoreInfo(
            information = information(input, item),
            languages = languages(audio, subtitles),
            file = fileRows(input, streams),
            links = input.links.mapNotNull { link ->
                val name = link.name.trim()
                val url = link.url.trim()
                if (name.isEmpty() || url.isEmpty()) null else TitleMoreLink(name, url)
            },
            accessibilityNote = if (subtitles.any { it.isHearingImpaired }) {
                "Closed captions include the spoken dialogue plus relevant non-dialogue information."
            } else {
                null
            },
        )
    }

    private fun BaseItemDto.factInput(): FactInput {
        val streams = mediaStreams.orEmpty().ifEmpty { mediaSources?.firstOrNull()?.mediaStreams.orEmpty() }
        return FactInput(
            streams = streams.map { stream ->
                FactStream(
                    kind = when (stream.type) {
                        MediaStreamType.VIDEO -> FactStream.Kind.Video
                        MediaStreamType.AUDIO -> FactStream.Kind.Audio
                        MediaStreamType.SUBTITLE -> FactStream.Kind.Subtitle
                        else -> FactStream.Kind.Other
                    },
                    language = stream.language,
                    codec = stream.codec,
                    channelLayout = stream.channelLayout,
                    spatialFormat = stream.audioSpatialFormat.serialName,
                    title = stream.title,
                    displayTitle = stream.displayTitle,
                    isHearingImpaired = stream.isHearingImpaired,
                    isForced = stream.isForced,
                    width = stream.width,
                    height = stream.height,
                    videoRange = stream.videoRangeType.serialName,
                    bitRate = stream.bitRate,
                )
            },
            sources = mediaSources.orEmpty().map { FactSource(it.container, it.bitrate) },
            links = externalUrls.orEmpty().map { TitleMoreLink(it.name.orEmpty(), it.url.orEmpty()) },
            studios = studios.orEmpty().mapNotNull { it.name },
            originalTitle = originalTitle,
            premiereDate = premiereDate?.toString(),
            officialRating = officialRating,
            tags = tags.orEmpty(),
            regions = productionLocations.orEmpty(),
            status = status,
            airTime = airTime,
            container = container,
        )
    }

    private fun EmbyItem.factInput(): FactInput = FactInput(
        streams = streams.map { stream ->
            FactStream(
                kind = when {
                    stream.isVideo -> FactStream.Kind.Video
                    stream.isAudio -> FactStream.Kind.Audio
                    stream.isSubtitle -> FactStream.Kind.Subtitle
                    else -> FactStream.Kind.Other
                },
                language = stream.language,
                codec = stream.codec,
                channelLayout = stream.channelLayout,
                title = stream.title,
                displayTitle = stream.displayTitle,
                isHearingImpaired = stream.isHearingImpaired,
                isForced = stream.isForced,
                width = stream.width,
                height = stream.height,
                videoRange = stream.rangeLabel.orEmpty(),
                bitRate = stream.bitRate,
            )
        },
        sources = mediaSources.map { FactSource(it.container, it.bitrate) },
        links = externalUrls.map { TitleMoreLink(it.name.orEmpty(), it.url.orEmpty()) },
        studios = studios.mapNotNull { it.name },
        originalTitle = originalTitle,
        premiereDate = premiereDate,
        officialRating = officialRating,
        tags = tagItems.mapNotNull { it.name },
        regions = productionLocations,
        status = status,
        airTime = airTime,
        container = container,
    )

    private fun information(input: FactInput, item: MediaItem): List<TitleMoreRow> = buildList {
        val studios = input.studios.mapNotNull { it.trim().ifEmpty { null } }
        if (studios.isNotEmpty()) add(TitleMoreRow("Studio", studios.joinToString(", ")))
        val original = input.originalTitle?.trim()?.ifEmpty { null }
        if (original != null && original != item.name) add(TitleMoreRow("Original Title", original))
        released(input.premiereDate, item.year)?.let { add(TitleMoreRow("Released", it)) }
        item.runtimeLabel?.let { add(TitleMoreRow("Run Time", it)) }
        val rated = input.officialRating?.trim()?.ifEmpty { null } ?: item.officialRating?.trim()?.ifEmpty { null }
        if (rated != null) add(TitleMoreRow("Rated", rated))
        val tags = input.tags.mapNotNull { it.trim().ifEmpty { null } }
        if (tags.isNotEmpty()) add(TitleMoreRow("Content Advisories", tags.joinToString(", ")))
        val regions = input.regions.mapNotNull { it.trim().ifEmpty { null } }
        if (regions.isNotEmpty()) add(TitleMoreRow("Regions of Origin", regions.joinToString(", ")))
        input.status?.trim()?.ifEmpty { null }?.let { add(TitleMoreRow("Status", it.replaceFirstChar { char -> char.uppercase() })) }
        input.airTime?.trim()?.ifEmpty { null }?.let { add(TitleMoreRow("Airs", it)) }
    }

    private fun languages(audio: List<FactStream>, subtitles: List<FactStream>): List<TitleMoreRow> = buildList {
        val original = audio.map { languageName(it.language) }.distinct()
        if (original.isNotEmpty()) add(TitleMoreRow("Original Audio", original.joinToString(", ")))
        val grouped = linkedMapOf<String, MutableList<String>>()
        audio.forEach { stream ->
            val language = languageName(stream.language)
            val format = audioFormatName(stream.codec, stream.channelLayout, stream.spatialFormat)
            val formats = grouped.getOrPut(language) { mutableListOf() }
            if (format.isNotEmpty() && format !in formats) formats += format
            val described = listOfNotNull(stream.title, stream.displayTitle).joinToString(" ").lowercase()
            if ((described.contains("audio description") || described.contains("described")) && "AD" !in formats) {
                formats += "AD"
            }
        }
        if (grouped.isNotEmpty()) {
            add(TitleMoreRow("Audio", grouped.entries.joinToString(", ") { (language, formats) ->
                if (formats.isEmpty()) language else "$language (${formats.joinToString(", ")})"
            }))
        }
        val captions = subtitles.map { stream ->
            val mark = when {
                stream.isHearingImpaired -> "CC"
                stream.isForced -> "Forced"
                else -> null
            }
            val name = languageName(stream.language)
            if (mark == null) name else "$name ($mark)"
        }.distinct()
        if (captions.isNotEmpty()) add(TitleMoreRow("Subtitles", captions.joinToString(", ")))
    }

    private fun fileRows(input: FactInput, streams: List<FactStream>): List<TitleMoreRow> = buildList {
        val sources = input.sources
        val versions = sources.mapNotNull { containerLabel(it.container) }
        when {
            versions.size > 1 -> add(TitleMoreRow("Versions", versions.joinToString("\n")))
            versions.size == 1 -> add(TitleMoreRow("File", versions.first()))
            else -> containerLabel(input.container)?.let { add(TitleMoreRow("Format", it)) }
        }
        videoLine(streams.firstOrNull { it.kind == FactStream.Kind.Video })?.let { add(TitleMoreRow("Video", it)) }
        val bitrate = sources.firstNotNullOfOrNull { it.bitrate } ?: streams.firstOrNull { it.kind == FactStream.Kind.Video }?.bitRate
        if (bitrate != null && bitrate > 0) add(TitleMoreRow("Bitrate", bitrateLabel(bitrate)))
    }

    private fun videoLine(stream: FactStream?): String? {
        stream ?: return null
        val parts = mutableListOf<String>()
        val width = stream.width
        val height = stream.height
        if (width != null && height != null && width > 0 && height > 0) parts += "${width}×${height}"
        videoCodecName(stream.codec)?.let { parts += it }
        val range = stream.videoRange.lowercase()
        when {
            range.contains("dolby") || range.contains("dovi") -> parts += "Dolby Vision"
            range.contains("hdr10+") || range.contains("hdr10plus") -> parts += "HDR10+"
            range.contains("hlg") -> parts += "HLG"
            range.contains("hdr") -> parts += "HDR"
        }
        return parts.takeIf { it.isNotEmpty() }?.joinToString(" · ")
    }

    private fun released(raw: String?, year: Int?): String? {
        val date = raw?.take(10)
        if (date != null && date.length == 10 && date[4] == '-') return date
        return year?.toString()
    }

    private fun languageName(code: String?): String {
        val trimmed = code?.trim().orEmpty()
        if (trimmed.isEmpty() || trimmed.equals("und", true)) return "Unknown"
        val mapped = ISO639[trimmed.lowercase()] ?: trimmed
        val display = Locale.forLanguageTag(mapped).getDisplayLanguage(Locale.getDefault())
        return if (display.isNotBlank() && !display.equals(mapped, true)) display else trimmed
    }

    private fun audioFormatName(codec: String?, layout: String?, spatial: String): String {
        if (spatial.contains("atmos", true) || layout.orEmpty().contains("atmos", true)) return "Dolby Atmos"
        val raw = codec?.trim()?.lowercase().orEmpty()
        return when (raw) {
            "eac3" -> layoutLabel("Dolby Digital Plus", layout)
            "ac3" -> layoutLabel("Dolby Digital", layout)
            "truehd", "mlp" -> "Dolby TrueHD"
            "dca", "dts" -> layoutLabel("DTS", layout)
            "aac", "aac_latm" -> "AAC"
            "opus" -> "Opus"
            "flac" -> "FLAC"
            "mp3" -> "MP3"
            "" -> layout?.trim().orEmpty()
            else -> if (raw.startsWith("pcm")) "PCM" else layoutLabel(raw.uppercase(), layout)
        }
    }

    private fun layoutLabel(codec: String, layout: String?): String {
        val cleaned = layout?.trim().orEmpty()
        if (cleaned.isEmpty() || codec.contains(cleaned, true)) return codec
        return "$codec $cleaned"
    }

    private fun videoCodecName(codec: String?): String? = when (codec?.lowercase()) {
        "hevc", "h265" -> "HEVC"
        "h264", "avc" -> "H.264"
        "av1" -> "AV1"
        "vp9" -> "VP9"
        "mpeg2video" -> "MPEG-2"
        "mpeg4" -> "MPEG-4"
        null, "" -> null
        else -> codec.uppercase()
    }

    private fun containerLabel(raw: String?): String? {
        val first = raw?.trim()?.substringBefore(',')?.trim().orEmpty()
        return first.ifEmpty { null }?.uppercase()
    }

    private fun bitrateLabel(bitsPerSecond: Int): String {
        val mbps = bitsPerSecond / 1_000_000.0
        return when {
            mbps >= 10 -> "${mbps.toInt()} Mbps"
            mbps >= 1 -> String.format("%.1f Mbps", mbps)
            else -> "${(bitsPerSecond / 1_000.0).toInt()} kbps"
        }
    }

    private val ISO639 = mapOf(
        "eng" to "en", "jpn" to "ja", "kor" to "ko", "fra" to "fr", "fre" to "fr",
        "spa" to "es", "deu" to "de", "ger" to "de", "ita" to "it", "por" to "pt",
        "rus" to "ru", "zho" to "zh", "chi" to "zh", "nld" to "nl", "swe" to "sv",
        "nor" to "no", "dan" to "da", "fin" to "fi", "pol" to "pl", "hun" to "hu",
        "ces" to "cs", "ara" to "ar", "hin" to "hi", "tha" to "th", "vie" to "vi",
        "tur" to "tr", "ell" to "el",
    )
}

internal fun TitleMoreInfo.withMedia(media: TitleMoreInfo): TitleMoreInfo = copy(
    languages = if (languages.isEmpty()) media.languages else languages,
    file = if (file.isEmpty()) media.file else file,
    accessibilityNote = accessibilityNote ?: media.accessibilityNote,
)
