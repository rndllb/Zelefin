package app.zelefin.client.plugins

import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.longOrNull
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

/**
 * TheIntroDB's community skip times, for titles the server has no markers for: every Emby title,
 * and Jellyfin without a skip plugin. Jellyfin's TheIntroDB plugin and Silo write the same data into
 * media segments, so those servers usually answer before this is asked. Mirrors iOS `TheIntroDB`.
 */
object TheIntroDB {
    data class Lookup(
        val tvdbId: Int? = null,
        val tmdbId: Int? = null,
        val imdbId: String? = null,
        val season: Int? = null,
        val episode: Int? = null,
        /** Picks the matching release (theatrical, extended, a DVD cut) when the API knows several. */
        val durationMs: Long? = null,
    ) {
        val hasIdentity: Boolean get() = tvdbId != null || tmdbId != null || imdbId != null
    }

    private const val ENDPOINT = "https://api.theintrodb.org/v4/media"
    private val http = OkHttpClient.Builder().callTimeout(8, TimeUnit.SECONDS).build()

    /** One lookup per title per launch: replays and quality reloads would otherwise spend the rate limit. */
    private val cache = mutableMapOf<Lookup, List<SkipSegment>>()
    private val cacheLock = Mutex()

    /** Episodes are looked up by their show plus season and episode, which costs one library request. */
    suspend fun segments(item: MediaItem, loadItem: suspend (String) -> MediaItem?): List<SkipSegment> {
        val lookup = lookup(item, loadItem) ?: return emptyList()
        return segments(lookup, item.runtime)
    }

    suspend fun lookup(item: MediaItem, loadItem: suspend (String) -> MediaItem?): Lookup? {
        val duration = item.runtime?.let { (it * 1000).toLong() }
        val lookup = when (item.kind) {
            MediaKind.Movie -> Lookup(item.tvdbId, item.tmdbId, item.imdbId, durationMs = duration)
            MediaKind.Episode -> {
                val seriesId = item.seriesId ?: return null
                val season = item.seasonIndex ?: return null
                val episode = item.episodeIndex ?: return null
                val series = loadItem(seriesId) ?: return null
                Lookup(series.tvdbId, series.tmdbId, series.imdbId, season, episode, duration)
            }
            else -> return null
        }
        return lookup.takeIf { it.hasIdentity }
    }

    suspend fun segments(lookup: Lookup, runtime: Double?): List<SkipSegment> {
        cacheLock.withLock { cache[lookup] }?.let { return it }
        val url = url(lookup) ?: return emptyList()
        val (status, body) = withContext(Dispatchers.IO) {
            runCatching {
                http.newCall(Request.Builder().url(url).header("Accept", "application/json").build()).execute().use {
                    it.code to it.body?.string().orEmpty()
                }
            }.getOrNull()
        } ?: return emptyList()
        // 404 is "no submissions for this media": a real answer, worth remembering. A 429 or an
        // outage is not, so the next play asks again.
        if (status != 200 && status != 404) return emptyList()
        val segments = if (status == 200) parse(body, runtime) else emptyList()
        cacheLock.withLock {
            if (cache.size > 200) cache.clear()
            cache[lookup] = segments
        }
        return segments
    }

    fun url(lookup: Lookup): String? {
        if (!lookup.hasIdentity) return null
        val builder = ENDPOINT.toHttpUrl().newBuilder()
        lookup.tvdbId?.let { builder.addQueryParameter("tvdb_id", it.toString()) }
        lookup.tmdbId?.let { builder.addQueryParameter("tmdb_id", it.toString()) }
        lookup.imdbId?.let { builder.addQueryParameter("imdb_id", it) }
        if (lookup.season != null && lookup.episode != null) {
            builder.addQueryParameter("season", lookup.season.toString())
            builder.addQueryParameter("episode", lookup.episode.toString())
        }
        lookup.durationMs?.takeIf { it > 0 }?.let { builder.addQueryParameter("duration_ms", it.toString()) }
        return builder.build().toString()
    }

    /**
     * A null start runs from the beginning and a null end to the end of the title, so open-ended
     * credits need the runtime; without one they are dropped rather than guessed.
     */
    fun parse(body: String, runtime: Double?): List<SkipSegment> {
        val root = runCatching { Json.parseToJsonElement(body) as? JsonObject }.getOrNull() ?: return emptyList()
        val groups = listOf(
            SkipSegment.Kind.Recap to "recap",
            SkipSegment.Kind.Intro to "intro",
            SkipSegment.Kind.Outro to "credits",
            SkipSegment.Kind.Preview to "preview",
        )
        return groups.flatMap { (kind, key) ->
            (root[key] as? JsonArray).orEmpty().mapNotNull { element ->
                val stamp = element as? JsonObject ?: return@mapNotNull null
                val start = millis(stamp["start_ms"])?.div(1000.0) ?: 0.0
                val end = millis(stamp["end_ms"])?.div(1000.0) ?: runtime ?: return@mapNotNull null
                if (end - start < SkipSegment.MIN_LENGTH) null else SkipSegment(kind, start, end)
            }
        }.sortedBy { it.start }
    }

    private fun millis(value: Any?): Double? = when (value) {
        null, JsonNull -> null
        is JsonPrimitive -> value.longOrNull?.toDouble()
        else -> null
    }
}
