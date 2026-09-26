package app.zelefin.client.jellyfin

import app.zelefin.core.MediaItem
import app.zelefin.core.TitleMoreInfo
import app.zelefin.core.TitleMoreLink
import app.zelefin.core.TitleMoreRow
import java.util.Locale
import org.jellyfin.sdk.model.api.BaseItemDto
import org.jellyfin.sdk.model.api.MediaStream
import org.jellyfin.sdk.model.api.MediaStreamType

internal object TitleFacts {
    fun from(dto: BaseItemDto, item: MediaItem): TitleMoreInfo {
        val streams = dto.mediaStreams.orEmpty().ifEmpty { dto.mediaSources?.firstOrNull()?.mediaStreams.orEmpty() }
        val audio = streams.filter { it.type == MediaStreamType.AUDIO }
        val subtitles = streams.filter { it.type == MediaStreamType.SUBTITLE }
        return TitleMoreInfo(
            information = information(dto, item),
            languages = languages(audio, subtitles),
            file = fileRows(dto, streams),
            links = dto.externalUrls.orEmpty().mapNotNull { link ->
                val name = link.name?.trim().orEmpty()
                val url = link.url?.trim().orEmpty()
                if (name.isEmpty() || url.isEmpty()) null else TitleMoreLink(name, url)
            },
            accessibilityNote = if (subtitles.any { it.isHearingImpaired }) {
                "Closed captions include the spoken dialogue plus relevant non-dialogue information."
            } else {
                null
            },
        )
    }

    private fun information(dto: BaseItemDto, item: MediaItem): List<TitleMoreRow> = buildList {
        val studios = dto.studios.orEmpty().mapNotNull { it.name?.trim()?.ifEmpty { null } }
        if (studios.isNotEmpty()) add(TitleMoreRow("Studio", studios.joinToString(", ")))
        val original = dto.originalTitle?.trim()?.ifEmpty { null }
        if (original != null && original != item.name) add(TitleMoreRow("Original Title", original))
        released(dto.premiereDate?.toString(), item.year)?.let { add(TitleMoreRow("Released", it)) }
        item.runtimeLabel?.let { add(TitleMoreRow("Run Time", it)) }
        val rated = dto.officialRating?.trim()?.ifEmpty { null } ?: item.officialRating?.trim()?.ifEmpty { null }
        if (rated != null) add(TitleMoreRow("Rated", rated))
        val tags = dto.tags.orEmpty().mapNotNull { it.trim().ifEmpty { null } }
        if (tags.isNotEmpty()) add(TitleMoreRow("Content Advisories", tags.joinToString(", ")))
        val regions = dto.productionLocations.orEmpty().mapNotNull { it.trim().ifEmpty { null } }
        if (regions.isNotEmpty()) add(TitleMoreRow("Regions of Origin", regions.joinToString(", ")))
        dto.status?.trim()?.ifEmpty { null }?.let { add(TitleMoreRow("Status", it.replaceFirstChar { char -> char.uppercase() })) }
        dto.airTime?.trim()?.ifEmpty { null }?.let { add(TitleMoreRow("Airs", it)) }
    }

    private fun languages(audio: List<MediaStream>, subtitles: List<MediaStream>): List<TitleMoreRow> = buildList {
        val original = audio.map { languageName(it.language) }.distinct()
        if (original.isNotEmpty()) add(TitleMoreRow("Original Audio", original.joinToString(", ")))
        val grouped = linkedMapOf<String, MutableList<String>>()
        audio.forEach { stream ->
            val language = languageName(stream.language)
            val format = audioFormatName(stream.codec, stream.channelLayout, stream.audioSpatialFormat.serialName)
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

    private fun fileRows(dto: BaseItemDto, streams: List<MediaStream>): List<TitleMoreRow> = buildList {
        val sources = dto.mediaSources.orEmpty()
        val versions = sources.mapNotNull { containerLabel(it.container) }
        when {
            versions.size > 1 -> add(TitleMoreRow("Versions", versions.joinToString("\n")))
            versions.size == 1 -> add(TitleMoreRow("File", versions.first()))
            else -> containerLabel(dto.container)?.let { add(TitleMoreRow("Format", it)) }
        }
        videoLine(streams.firstOrNull { it.type == MediaStreamType.VIDEO })?.let { add(TitleMoreRow("Video", it)) }
        val bitrate = sources.firstNotNullOfOrNull { it.bitrate } ?: streams.firstOrNull { it.type == MediaStreamType.VIDEO }?.bitRate
        if (bitrate != null && bitrate > 0) add(TitleMoreRow("Bitrate", bitrateLabel(bitrate)))
    }

    private fun videoLine(stream: MediaStream?): String? {
        stream ?: return null
        val parts = mutableListOf<String>()
        val width = stream.width
        val height = stream.height
        if (width != null && height != null && width > 0 && height > 0) parts += "${width}×${height}"
        videoCodecName(stream.codec)?.let { parts += it }
        val range = stream.videoRangeType.serialName.lowercase()
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
