package app.zelefin.client.plugins

import app.zelefin.core.dbl
import app.zelefin.core.objects
import app.zelefin.core.str
import java.util.concurrent.TimeUnit
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * Title logos from TMDB, for Discover titles the library doesn't have. Seerr and Ombi pass on
 * posters and backdrops but no logos, so this needs the user's own TMDB key: a v3 API key, or a
 * v4 read access token (which starts with `eyJ`). Mirrors iOS `TMDBLogos`.
 */
object TmdbLogos {
    private val http = OkHttpClient.Builder().callTimeout(10, TimeUnit.SECONDS).build()

    suspend fun logoUrl(title: SeerrTitle, key: String): String? {
        val media = if (title.kind == SeerrTitle.Kind.Tv) "tv" else "movie"
        val json = fetch("$media/${title.tmdbId}/images", key, mapOf("include_image_language" to "en,null")) ?: return null
        val path = best(json.objects("logos").map { Logo(it.str("file_path"), it.str("iso_639_1"), it.dbl("vote_average")) })?.filePath
        return path?.let { "https://image.tmdb.org/t/p/w500$it" }
    }

    /** Whether TMDB accepts the key. */
    suspend fun accepts(key: String): Boolean = fetch("configuration", key) != null

    data class Logo(val filePath: String?, val language: String?, val voteAverage: Double?)

    /** English first, then a logo with no language (a picture-only mark), the best rated of each. */
    fun best(logos: List<Logo>): Logo? {
        val ranked = logos.filter { !it.filePath.isNullOrBlank() }.sortedByDescending { it.voteAverage ?: 0.0 }
        return ranked.firstOrNull { it.language == "en" } ?: ranked.firstOrNull { it.language == null } ?: ranked.firstOrNull()
    }

    private suspend fun fetch(path: String, key: String, query: Map<String, String> = emptyMap()): JsonObject? = withContext(Dispatchers.IO) {
        val trimmed = key.trim()
        if (trimmed.isEmpty()) return@withContext null
        val readToken = trimmed.startsWith("eyJ")
        val url = "https://api.themoviedb.org/3/$path".toHttpUrl().newBuilder().apply {
            query.forEach { (name, value) -> addQueryParameter(name, value) }
            if (!readToken) addQueryParameter("api_key", trimmed)
        }.build()
        val request = Request.Builder().url(url).header("Accept", "application/json").apply {
            if (readToken) header("Authorization", "Bearer $trimmed")
        }.build()
        try {
            http.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@use null
                Json.parseToJsonElement(response.body?.string().orEmpty()).jsonObject
            }
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (_: Exception) {
            null
        }
    }
}
