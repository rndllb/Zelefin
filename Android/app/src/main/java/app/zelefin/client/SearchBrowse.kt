package app.zelefin.client

import android.content.Context
import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind
import org.json.JSONArray
import org.json.JSONObject

enum class SearchScope(val title: String, val prompt: String) {
    Library("Library", "Shows, Movies, and More"),
    Discover("Discover", "Request movies and shows"),
}

enum class SearchHitKind { Title, Person, Genre, Studio }

data class SearchHit(
    val id: String,
    val name: String,
    val subtitle: String?,
    val kind: SearchHitKind,
    val item: MediaItem,
)

data class LibrarySearchState(
    val term: String = "",
    val hits: List<SearchHit> = emptyList(),
    val loading: Boolean = false,
    val genres: List<LibraryGenre> = emptyList(),
    val genresLoading: Boolean = false,
    val recents: List<MediaItem> = emptyList(),
)

const val SearchMinimumLength = 2
const val SearchDebounceMillis = 220L

/** "Game Show" and "Game-Show" are the same genre. */
fun genreKey(name: String): String {
    val lower = name.lowercase()
    return lower.filter(Char::isLetter) + lower.filter(Char::isDigit)
}

/** Music genres and the combined Action & Adventure shelf are not a browsable catalog. */
fun isBrowsableGenre(name: String): Boolean = when (genreKey(name)) {
    "music", "musicvideo", "musicvideos", "actionadventure", "actionandadventure", "adventureaction", "adventureandaction" -> false
    else -> true
}

fun List<LibraryGenre>.collapsedGenres(): List<LibraryGenre> {
    val chosen = linkedMapOf<String, LibraryGenre>()
    for (genre in this) {
        val key = genreKey(genre.name)
        if (key.isEmpty() || !isBrowsableGenre(genre.name)) continue
        val existing = chosen[key]
        if (existing == null || prefersGenreName(genre.name, existing.name)) chosen[key] = genre
    }
    return chosen.values.toList()
}

private fun prefersGenreName(candidate: String, current: String): Boolean {
    val candidateSplit = candidate.contains("-")
    val currentSplit = current.contains("-")
    if (currentSplit && !candidateSplit) return true
    if (candidateSplit && !currentSplit) return false
    return candidate.length < current.length
}

/** Titles opened from Search, newest first. Same key and limit as iOS. */
class SearchHistoryStore(context: Context) {
    private val prefs = context.getSharedPreferences("zelefin.search", Context.MODE_PRIVATE)

    fun load(): List<MediaItem> {
        val raw = prefs.getString(KEY, null) ?: return emptyList()
        return runCatching {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { decode(array.getJSONObject(it)) }
        }.getOrDefault(emptyList())
    }

    fun record(item: MediaItem): List<MediaItem> {
        val next = (listOf(item) + load().filter { it.id != item.id }).take(LIMIT)
        save(next)
        return next
    }

    fun remove(id: String): List<MediaItem> {
        val next = load().filter { it.id != id }
        save(next)
        return next
    }

    fun clear() {
        prefs.edit().remove(KEY).apply()
    }

    private fun save(items: List<MediaItem>) {
        val array = JSONArray()
        items.forEach { array.put(encode(it)) }
        prefs.edit().putString(KEY, array.toString()).apply()
    }

    private fun encode(item: MediaItem) = JSONObject().apply {
        put("id", item.id)
        put("name", item.name)
        put("kind", item.kind.name)
        item.year?.let { put("year", it) }
        item.seriesName?.let { put("seriesName", it) }
        item.seriesId?.let { put("seriesId", it) }
        item.primaryImageTag?.let { put("primaryImageTag", it) }
        item.imageItemId?.let { put("imageItemId", it) }
        item.posterUrl?.let { put("posterUrl", it) }
        item.backdropUrl?.let { put("backdropUrl", it) }
        if (item.genres.isNotEmpty()) put("genres", JSONArray(item.genres))
    }

    private fun decode(json: JSONObject): MediaItem? {
        val id = json.optString("id").takeIf { it.isNotEmpty() } ?: return null
        val kind = runCatching { MediaKind.valueOf(json.optString("kind")) }.getOrDefault(MediaKind.Unknown)
        val genres = json.optJSONArray("genres")?.let { array -> (0 until array.length()).map(array::getString) }.orEmpty()
        return MediaItem(
            id = id,
            name = json.optString("name"),
            kind = kind,
            year = json.optInt("year").takeIf { json.has("year") },
            seriesName = json.optString("seriesName").takeIf { json.has("seriesName") },
            seriesId = json.optString("seriesId").takeIf { json.has("seriesId") },
            primaryImageTag = json.optString("primaryImageTag").takeIf { json.has("primaryImageTag") },
            imageItemId = json.optString("imageItemId").takeIf { json.has("imageItemId") },
            posterUrl = json.optString("posterUrl").takeIf { json.has("posterUrl") },
            backdropUrl = json.optString("backdropUrl").takeIf { json.has("backdropUrl") },
            genres = genres,
        )
    }

    private companion object {
        const val KEY = "zelefin.search.recent"
        const val LIMIT = 20
    }
}

fun MediaItem.searchSubtitle(): String {
    val label = when (kind) {
        MediaKind.Movie -> "Movie"
        MediaKind.Series -> "Show"
        MediaKind.Episode -> seriesName ?: "Episode"
        MediaKind.Collection -> "Collection"
        MediaKind.Playlist -> "Playlist"
        MediaKind.LiveTV -> "Live TV"
        MediaKind.Book -> "Book"
        MediaKind.Photo -> "Photo"
        else -> "Title"
    }
    return listOfNotNull(label, genres.firstOrNull(), year?.toString()).joinToString(" · ")
}
