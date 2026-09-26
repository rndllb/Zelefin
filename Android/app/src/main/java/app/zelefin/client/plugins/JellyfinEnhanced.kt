package app.zelefin.client.plugins

import android.content.Context
import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind
import app.zelefin.core.PlaybackQueueKind
import app.zelefin.core.ZelefinException
import kotlin.math.abs
import kotlin.math.roundToLong
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

object JellyfinEnhancedPlugin {
    fun isInstalled(names: List<String>): Boolean = names.any { name ->
        name.lowercase().filter { it.isLetter() }.contains("jellyfinenhanced")
    }
}

enum class JellyfinEnhancedHomeSurface(val rawValue: String) {
    ContinueWatching("continueWatching"),
    NextUp("nextUp"),
}

object JellyfinEnhancedHomeHide {
    fun surface(queueKind: PlaybackQueueKind): JellyfinEnhancedHomeSurface =
        if (queueKind == PlaybackQueueKind.NextUp) JellyfinEnhancedHomeSurface.NextUp else JellyfinEnhancedHomeSurface.ContinueWatching

    fun menuTitle(surface: JellyfinEnhancedHomeSurface): String = when (surface) {
        JellyfinEnhancedHomeSurface.ContinueWatching -> "Remove from Continue Watching"
        JellyfinEnhancedHomeSurface.NextUp -> "Remove from Next Up"
    }

    fun path(itemId: String, surface: JellyfinEnhancedHomeSurface): String {
        val encoded = PluginHttp.segment(itemId)
        return when (surface) {
            JellyfinEnhancedHomeSurface.ContinueWatching -> "/JellyfinEnhanced/continue-watching/hide/$encoded"
            JellyfinEnhancedHomeSurface.NextUp -> "/JellyfinEnhanced/next-up/hide/$encoded"
        }
    }
}

/**
 * Titles the user removed from a home row. The next home refresh still receives
 * them from Jellyfin until the plugin filter catches up, so this set keeps them out.
 */
object HomeQueueHideStore {
    private const val PREFS = "zelefin.plugins"

    fun ids(context: Context, userId: String, surface: JellyfinEnhancedHomeSurface): Set<String> {
        val raw = prefs(context).getString(key(userId, surface), null).orEmpty()
        return raw.split(",").filter { it.isNotEmpty() }.toSet()
    }

    fun insert(context: Context, itemId: String, userId: String, surface: JellyfinEnhancedHomeSurface) {
        write(context, ids(context, userId, surface) + itemId, userId, surface)
    }

    fun remove(context: Context, itemId: String, userId: String) {
        for (surface in JellyfinEnhancedHomeSurface.entries) {
            val hidden = ids(context, userId, surface)
            if (itemId !in hidden) continue
            write(context, hidden - itemId, userId, surface)
        }
    }

    fun filter(context: Context, items: List<MediaItem>, userId: String?, surface: JellyfinEnhancedHomeSurface): List<MediaItem> {
        if (userId == null) return items
        val hidden = ids(context, userId, surface)
        if (hidden.isEmpty()) return items
        return items.filter { it.id !in hidden }
    }

    private fun write(context: Context, hidden: Set<String>, userId: String, surface: JellyfinEnhancedHomeSurface) {
        prefs(context).edit().putString(key(userId, surface), hidden.sorted().joinToString(",")).apply()
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun key(userId: String, surface: JellyfinEnhancedHomeSurface) = "zelefin.hidden-home.$userId.${surface.rawValue}"
}

data class JellyfinEnhancedReviewTarget(val mediaType: String, val tmdbId: String)

object JellyfinEnhancedReviewKey {
    fun target(kind: MediaKind, tmdbId: Int?): JellyfinEnhancedReviewTarget? {
        if (tmdbId == null || tmdbId <= 0) return null
        return when (kind) {
            MediaKind.Movie -> JellyfinEnhancedReviewTarget("movie", "$tmdbId")
            MediaKind.Series, MediaKind.Season, MediaKind.Episode -> JellyfinEnhancedReviewTarget("tv", "$tmdbId")
            else -> null
        }
    }
}

data class JellyfinEnhancedReview(
    val userId: String,
    val userName: String,
    val content: String,
    val rating: Double?,
    val createdAt: String?,
    val updatedAt: String?,
) {
    val id: String get() = userId

    val hasText: Boolean get() = content.isNotBlank()

    fun isAuthoredBy(userId: String): Boolean = normalizedUserId(this.userId) == normalizedUserId(userId)

    companion object {
        fun normalizedUserId(value: String): String = value.filter { it != '-' }.lowercase()

        fun averageRating(reviews: List<JellyfinEnhancedReview>): Double? {
            val scores = reviews.mapNotNull { it.rating }
            if (scores.isEmpty()) return null
            return scores.sum() / scores.size
        }
    }
}

object JellyfinEnhancedReviewPayload {
    fun isValid(content: String, rating: Double?): Boolean {
        val trimmed = content.trim()
        if (trimmed.length > 2000) return false
        if (rating != null) {
            if (rating < 1 || rating > 5) return false
            val steps = (rating * 2).roundToLong().toDouble()
            if (abs(rating * 2 - steps) >= 0.001) return false
        }
        return rating != null || trimmed.isNotEmpty()
    }

    fun body(content: String, rating: Double?): JsonObject = buildJsonObject {
        val trimmed = content.trim()
        if (trimmed.isNotEmpty()) put("content", trimmed)
        if (rating != null) put("rating", rating)
    }
}

data class JellyfinEnhancedAward(
    val name: String,
    val result: String,
    val year: Int?,
    val recipients: List<String>,
    val works: List<String>,
) {
    val id: String get() = "$name-$result-${year ?: 0}-${recipients.joinToString(",")}"

    val isWin: Boolean get() = result.equals("Won", ignoreCase = true)

    val detailLine: String?
        get() {
            val people = recipients.filter { it.isNotEmpty() }
            if (people.isNotEmpty()) return people.joinToString(", ")
            val titles = works.filter { it.isNotEmpty() }
            if (titles.isNotEmpty()) return titles.joinToString(", ")
            return null
        }
}

data class JellyfinEnhancedAwards(
    val found: Boolean,
    val wins: Int,
    val nominations: Int,
    val awards: List<JellyfinEnhancedAward>,
) {
    val isEmpty: Boolean get() = !found || (wins == 0 && nominations == 0 && awards.isEmpty())

    val summary: String
        get() {
            val parts = mutableListOf<String>()
            if (wins > 0) parts += if (wins == 1) "1 win" else "$wins wins"
            if (nominations > 0) parts += if (nominations == 1) "1 nomination" else "$nominations nominations"
            if (parts.isEmpty() && awards.isNotEmpty()) {
                parts += if (awards.size == 1) "1 award" else "${awards.size} awards"
            }
            return parts.joinToString(" · ")
        }
}

data class TmdbUserReview(
    val id: String,
    val author: String,
    val content: String,
    val rating: Double?,
) {
    /** TMDB scores are out of 10; title-page stars are out of 5. */
    val starsOutOfFive: Double? get() = rating?.let { (it / 2).coerceIn(0.0, 5.0) }

    companion object {
        fun averageStars(reviews: List<TmdbUserReview>): Double? {
            val scores = reviews.mapNotNull { it.starsOutOfFive }
            if (scores.isEmpty()) return null
            return scores.sum() / scores.size
        }
    }
}

class JellyfinEnhancedClient(
    private val baseUrl: String,
    private val accessToken: String,
    private val userId: String = "",
) {
    suspend fun isReachable(): Boolean = runCatchingNonCancel { send("GET", "/JellyfinEnhanced/version", setOf(200)) } != null

    suspend fun version(): String? {
        val body = runCatchingNonCancel { send("GET", "/JellyfinEnhanced/version", setOf(200)) } ?: return null
        val obj = PluginJson.obj(body)
        if (obj != null) return PluginJson.string(obj, "version", "Version")
        return body.trim().trim('"').takeIf { it.isNotEmpty() && !it.startsWith("<") }
    }

    suspend fun hideFromHome(itemId: String, surface: JellyfinEnhancedHomeSurface) {
        send("POST", JellyfinEnhancedHomeHide.path(itemId, surface), setOf(200, 201, 204))
    }

    /** Dashboard switch labeled Enable "Remove from Continue Watching". */
    suspend fun removeContinueWatchingEnabled(): Boolean {
        val body = runCatchingNonCancel { send("GET", "/JellyfinEnhanced/public-config", setOf(200)) } ?: return false
        return parseRemoveContinueWatchingEnabled(body)
    }

    suspend fun reviews(mediaType: String, tmdbId: String): List<JellyfinEnhancedReview> {
        val body = send("GET", reviewsPath(mediaType, tmdbId), setOf(200))
        return parseReviews(body)
    }

    suspend fun saveReview(mediaType: String, tmdbId: String, content: String, rating: Double?) {
        if (!JellyfinEnhancedReviewPayload.isValid(content, rating)) {
            throw ZelefinException.server("Add a star rating or a few words.")
        }
        val body = JellyfinEnhancedReviewPayload.body(content, rating).toString()
        send("POST", reviewsPath(mediaType, tmdbId), setOf(200, 201, 204), body)
    }

    suspend fun deleteOwnReview(mediaType: String, tmdbId: String) {
        send("DELETE", reviewsPath(mediaType, tmdbId), setOf(200, 204))
    }

    /** Admin delete of another user's review. */
    suspend fun deleteReview(reviewUserId: String, mediaType: String, tmdbId: String) {
        val compact = JellyfinEnhancedReview.normalizedUserId(reviewUserId)
        val path = "/JellyfinEnhanced/reviews/admin/$compact/$mediaType/${PluginHttp.segment(tmdbId)}"
        send("DELETE", path, setOf(200, 204))
    }

    suspend fun awards(mediaType: String, tmdbId: String): JellyfinEnhancedAwards? {
        val path = "/JellyfinEnhanced/awards/$mediaType/${PluginHttp.segment(tmdbId)}"
        val body = runCatchingNonCancel { send("GET", path, setOf(200)) } ?: return null
        return parseAwards(body).takeUnless { it.isEmpty }
    }

    suspend fun tmdbReviews(mediaType: String, tmdbId: String): List<TmdbUserReview> {
        val path = "/JellyfinEnhanced/tmdb/$mediaType/${PluginHttp.segment(tmdbId)}/reviews?language=en-US&page=1"
        val body = runCatchingNonCancel { send("GET", path, setOf(200)) } ?: return emptyList()
        return parseTmdbReviews(body)
    }

    fun isOwnReview(review: JellyfinEnhancedReview): Boolean = userId.isNotEmpty() && review.isAuthoredBy(userId)

    private fun reviewsPath(mediaType: String, tmdbId: String) =
        "/JellyfinEnhanced/reviews/$mediaType/${PluginHttp.segment(tmdbId)}"

    // Auth stays in headers only: the TMDB proxy forwards the query string to themoviedb.org,
    // and a Jellyfin api_key there makes TMDB reject the request.
    private suspend fun send(method: String, path: String, ok: Set<Int>, jsonBody: String? = null): String {
        val response = PluginHttp.send(baseUrl, accessToken, method, path, jsonBody)
        if (response.isGatewayChallenge) throw ZelefinException.accessGateway()
        if (response.status !in ok) throw ZelefinException.server(failureMessage(response.status, response.body))
        return response.body
    }

    private suspend fun <T> runCatchingNonCancel(block: suspend () -> T): T? = try {
        block()
    } catch (cancel: kotlin.coroutines.cancellation.CancellationException) {
        throw cancel
    } catch (_: Exception) {
        null
    }

    companion object {
        const val TMDB_REVIEW_LIMIT = 12

        fun failureMessage(statusCode: Int, body: String): String {
            PluginJson.obj(body)?.let { obj ->
                PluginJson.string(obj, "message", "Message")?.let { return it }
            }
            val text = body.trim()
            if (text.isNotEmpty() && !text.startsWith("<")) return text
            return "The server returned $statusCode."
        }

        fun parseRemoveContinueWatchingEnabled(body: String): Boolean {
            val obj = PluginJson.obj(body) ?: return false
            return PluginJson.bool(obj, "RemoveContinueWatchingEnabled", "removeContinueWatchingEnabled") ?: false
        }

        fun parseReviews(body: String): List<JellyfinEnhancedReview> {
            val obj = PluginJson.obj(body) ?: return emptyList()
            val rows = PluginJson.value(obj, "reviews", "Reviews") as? JsonArray ?: return emptyList()
            return rows.mapNotNull { element ->
                val row = element as? JsonObject ?: return@mapNotNull null
                val reviewUserId = PluginJson.string(row, "userId", "UserId") ?: return@mapNotNull null
                JellyfinEnhancedReview(
                    userId = reviewUserId,
                    userName = PluginJson.string(row, "userName", "UserName") ?: "Someone",
                    content = PluginJson.string(row, "content", "Content") ?: "",
                    rating = PluginJson.double(row, "rating", "Rating"),
                    createdAt = PluginJson.string(row, "createdAt", "CreatedAt"),
                    updatedAt = PluginJson.string(row, "updatedAt", "UpdatedAt"),
                )
            }
        }

        fun parseAwards(body: String): JellyfinEnhancedAwards {
            val obj = PluginJson.obj(body) ?: return JellyfinEnhancedAwards(false, 0, 0, emptyList())
            val rows = PluginJson.value(obj, "awards", "Awards") as? JsonArray
            val awards = rows.orEmpty().mapNotNull { element ->
                val row = element as? JsonObject ?: return@mapNotNull null
                val name = PluginJson.string(row, "name", "Name") ?: return@mapNotNull null
                JellyfinEnhancedAward(
                    name = name,
                    result = PluginJson.string(row, "result", "Result") ?: "",
                    year = PluginJson.int(row, "year", "Year"),
                    recipients = PluginJson.stringList(row, "recipients", "Recipients"),
                    works = PluginJson.stringList(row, "works", "Works"),
                )
            }
            return JellyfinEnhancedAwards(
                found = PluginJson.bool(obj, "found", "Found") ?: awards.isNotEmpty(),
                wins = PluginJson.int(obj, "wins", "Wins") ?: awards.count { it.isWin },
                nominations = PluginJson.int(obj, "nominations", "Nominations") ?: awards.count { !it.isWin },
                awards = awards,
            )
        }

        fun parseTmdbReviews(body: String): List<TmdbUserReview> {
            val root = PluginJson.parse(body)
            val rows = when {
                root is JsonObject && PluginJson.value(root, "results", "Results") is JsonArray ->
                    PluginJson.value(root, "results", "Results") as JsonArray
                root is JsonArray -> root
                else -> return emptyList()
            }
            return rows.take(TMDB_REVIEW_LIMIT).mapNotNull { element ->
                val row = element as? JsonObject ?: return@mapNotNull null
                val content = PluginJson.string(row, "content", "Content") ?: return@mapNotNull null
                val details = PluginJson.value(row, "author_details", "authorDetails", "AuthorDetails") as? JsonObject
                TmdbUserReview(
                    id = PluginJson.string(row, "id", "Id") ?: content,
                    author = PluginJson.string(row, "author", "Author")
                        ?: details?.let { PluginJson.string(it, "username", "name", "Username", "Name") }
                        ?: "TMDB",
                    content = content,
                    rating = details?.let { PluginJson.double(it, "rating", "Rating") },
                )
            }
        }
    }
}
