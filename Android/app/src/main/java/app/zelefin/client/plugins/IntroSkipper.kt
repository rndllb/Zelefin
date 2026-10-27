package app.zelefin.client.plugins

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlin.math.max

data class SkipSegment(val kind: Kind, val start: Double, val end: Double) {
    /** The four kinds TheIntroDB and Jellyfin's media segments share. `Outro` is the credits. */
    enum class Kind { Recap, Intro, Outro, Preview }

    val title: String
        get() = when (kind) {
            Kind.Recap -> "Skip Recap"
            Kind.Intro -> "Skip Intro"
            Kind.Outro -> "Skip Credits"
            Kind.Preview -> "Skip Preview"
        }

    val seekTime: Double get() = max(end, start)

    fun isActive(timeSeconds: Double): Boolean {
        if (end - start < MIN_LENGTH) return false
        return timeSeconds >= (start - 0.35) && timeSeconds < (end - 0.8)
    }

    companion object {
        const val MIN_LENGTH = 3.0

        /** The earliest-starting segment playing now; overlapping sources settle on one button. */
        fun prompt(segments: List<SkipSegment>, timeSeconds: Double): SkipPrompt? =
            segments.filter { it.isActive(timeSeconds) }.minByOrNull { it.start }?.let(::SkipPrompt)

        fun fromPluginTimestamps(intro: IntroTimestampPayload?, credits: IntroTimestampPayload?): List<SkipSegment> =
            listOfNotNull(intro?.segment(Kind.Intro), credits?.segment(Kind.Outro))
    }
}

data class SkipPrompt(val segment: SkipSegment) {
    val kind: SkipSegment.Kind get() = segment.kind
    val title: String get() = segment.title
    val seekTo: Double get() = segment.seekTime
}

data class IntroTimestampPayload(
    val introStart: Double?,
    val introEnd: Double?,
    val valid: Boolean? = true,
) {
    fun segment(kind: SkipSegment.Kind): SkipSegment? {
        if (valid == false) return null
        val start = introStart ?: return null
        val end = introEnd ?: return null
        if (end - start < SkipSegment.MIN_LENGTH) return null
        return SkipSegment(kind, start, end)
    }

    companion object {
        fun parse(obj: JsonObject): IntroTimestampPayload = IntroTimestampPayload(
            introStart = number(obj, "IntroStart", "introStart"),
            introEnd = number(obj, "IntroEnd", "introEnd"),
            valid = (obj["Valid"] ?: obj["valid"])?.let { PluginJson.bool(obj, "Valid", "valid") },
        )

        private fun number(obj: JsonObject, pascal: String, camel: String): Double? =
            obj[pascal]?.let { PluginJson.double(obj, pascal) } ?: obj[camel]?.let { PluginJson.double(obj, camel) }
    }
}

/** TheIntroDB's Jellyfin plugin, which fills media segments from TheIntroDB's community timestamps. */
object TheIntroDBPlugin {
    fun isInstalled(names: List<String>): Boolean = names.any { it.lowercase().filter(Char::isLetter).contains("theintrodb") }
}

object IntroSkipperPlugin {
    fun isInstalled(names: List<String>): Boolean = names.any { name ->
        val lower = name.lowercase()
        lower.contains("intro skip") || lower.contains("introskipper")
    }
}

class IntroSkipperClient(private val baseUrl: String, private val accessToken: String) {
    suspend fun isInstalled(): Boolean = IntroSkipperPlugin.isInstalled(JellyfinPlugins.activeNames(baseUrl, accessToken))

    /** Jellyfin media segments first, then Intro Skipper plugin endpoints. Empty when nothing usable. */
    suspend fun segments(itemId: String): List<SkipSegment> {
        if (itemId.isBlank()) return emptyList()
        mediaSegments(itemId)?.takeIf { it.isNotEmpty() }?.let { return it }
        pluginSegments(itemId)?.takeIf { it.isNotEmpty() }?.let { return it }
        return emptyList()
    }

    private suspend fun mediaSegments(itemId: String): List<SkipSegment>? {
        val path = "/MediaSegments/${PluginHttp.segment(itemId)}" +
            "?includeSegmentTypes=Recap&includeSegmentTypes=Intro&includeSegmentTypes=Outro&includeSegmentTypes=Preview"
        val response = PluginHttp.sendOrNull(baseUrl, accessToken, "GET", path) ?: return null
        if (!response.isSuccess) return null
        val root = PluginJson.obj(response.body) ?: return null
        val items = PluginJson.value(root, "Items") as? JsonArray ?: return emptyList()
        return items.mapNotNull { element ->
            val dto = element as? JsonObject ?: return@mapNotNull null
            val startTicks = PluginJson.long(dto, "StartTicks") ?: return@mapNotNull null
            val endTicks = PluginJson.long(dto, "EndTicks") ?: return@mapNotNull null
            val kind = when (PluginJson.string(dto, "Type")?.lowercase()) {
                "recap" -> SkipSegment.Kind.Recap
                "intro" -> SkipSegment.Kind.Intro
                "outro" -> SkipSegment.Kind.Outro
                "preview" -> SkipSegment.Kind.Preview
                else -> return@mapNotNull null
            }
            SkipSegment(kind, startTicks / TICKS_PER_SECOND, endTicks / TICKS_PER_SECOND)
        }.filter { it.end - it.start >= SkipSegment.MIN_LENGTH }
    }

    private suspend fun pluginSegments(itemId: String): List<SkipSegment>? {
        val id = PluginHttp.segment(itemId)
        for (path in listOf("/Episode/$id/IntroSkipperSegments", "/Episode/$id/Timestamps")) {
            val root = getObject(path) ?: continue
            val segments = parsePluginSegments(root)
            if (segments.isNotEmpty()) return segments
        }
        val intro = getObject("/Episode/$id/IntroTimestamps")?.let(IntroTimestampPayload::parse)
        intro?.segment(SkipSegment.Kind.Intro)?.let { return listOf(it) }
        return null
    }

    private suspend fun getObject(path: String): JsonObject? {
        val response = PluginHttp.sendOrNull(baseUrl, accessToken, "GET", path) ?: return null
        if (!response.isSuccess) return null
        return PluginJson.obj(response.body)
    }

    companion object {
        private const val TICKS_PER_SECOND = 10_000_000.0

        fun prompt(segments: List<SkipSegment>, timeSeconds: Double): SkipPrompt? =
            SkipSegment.prompt(segments, timeSeconds)

        /** Grouped `{Introduction, Credits}` response, or a map keyed by segment type. */
        fun parsePluginSegments(root: JsonObject): List<SkipSegment> {
            fun payload(vararg keys: String): IntroTimestampPayload? =
                keys.firstNotNullOfOrNull { root[it] as? JsonObject }?.let(IntroTimestampPayload::parse)
            val intro = payload("Introduction", "introduction", "Intro")
            val credits = payload("Credits", "credits", "Outro", "outro")
            return SkipSegment.fromPluginTimestamps(intro, credits)
        }
    }
}
