package app.zelefin.client

import android.content.Context
import app.zelefin.core.MediaItem
import java.text.NumberFormat

enum class LibraryKind(val browseLabel: String) {
    Movies("Movies"),
    Shows("Shows"),
    Music("Music"),
    Books("Books"),
    Photos("Photos"),
    LiveTV("Live TV"),
    Playlists("Playlists"),
    HomeVideos("Home videos"),
    Collections("Collections"),
    YouTube("YouTube"),
    Other("Library");

    val appearsInLibrary: Boolean get() = this != Music && this != Books && this != Playlists

    val isHiddenOnLibraryByDefault: Boolean get() = this == LiveTV || this == HomeVideos

    companion object {
        fun inferred(name: String): LibraryKind? {
            val lower = name.lowercase()
            return when {
                "movie" in lower || "film" in lower -> Movies
                "show" in lower || "series" in lower || lower == "tv" -> Shows
                "collection" in lower -> Collections
                "live" in lower -> LiveTV
                else -> null
            }
        }

        fun stored(raw: String?): LibraryKind = entries.firstOrNull { it.name == raw } ?: Other
    }
}

/** Rooms the Library tab lists. Silo's Jellyfin API has no Live TV. */
fun List<LibraryRoom>.libraryTabRooms(isSiloServer: Boolean): List<LibraryRoom> =
    filter { it.kind.appearsInLibrary && !(isSiloServer && it.kind == LibraryKind.LiveTV) }

/** Collections, then Movies, then Shows, then other rooms. Live TV and recordings stay last. */
val LibraryRoom.libraryCardRank: Int
    get() = when {
        isLastOnLibrary -> 4
        kind == LibraryKind.Collections -> 0
        kind == LibraryKind.Movies -> 1
        kind == LibraryKind.Shows -> 2
        else -> 3
    }

val LibraryRoom.isHiddenOnLibraryByDefault: Boolean
    get() = kind.isHiddenOnLibraryByDefault || name.contains("recording", ignoreCase = true)

val LibraryRoom.isLastOnLibrary: Boolean get() = isHiddenOnLibraryByDefault

/** TubeArchivist stores channels as series and videos as episodes; those land in [channels] and [videos]. */
data class LibraryCounts(
    val movies: Int = 0,
    val shows: Int = 0,
    val episodes: Int = 0,
    val channels: Int = 0,
    val videos: Int = 0,
) {
    val total: Int get() = movies + shows + episodes + channels + videos

    val caption: String?
        get() = listOfNotNull(
            phrase(movies, "movie", "movies"),
            phrase(shows, "show", "shows"),
            phrase(episodes, "episode", "episodes"),
            phrase(channels, "channel", "channels"),
            phrase(videos, "video", "videos"),
        ).takeIf { it.isNotEmpty() }?.joinToString(" · ")

    /** Moves YouTube series and episodes out of the show totals and into channels and videos. */
    fun separatingYouTube(youTube: LibraryCounts): LibraryCounts = copy(
        shows = (shows - youTube.channels).coerceAtLeast(0),
        episodes = (episodes - youTube.videos).coerceAtLeast(0),
        channels = youTube.channels,
        videos = youTube.videos,
    )

    private fun phrase(value: Int, singular: String, plural: String): String? =
        if (value <= 0) null else "${formatCount(value)} ${if (value == 1) singular else plural}"
}

fun formatCount(value: Int): String = NumberFormat.getIntegerInstance().format(value)

enum class LibraryPageBlock(val title: String) {
    Favorites("Favorites"),
    Watchlist("Watchlist"),
    Genres("Genres"),
    Collections("Collections"),
}

data class LibraryGenre(val id: String, val name: String)

sealed interface LibraryRoute {
    val title: String

    data class Room(val room: LibraryRoom) : LibraryRoute {
        override val title get() = room.name
    }

    data object Favorites : LibraryRoute {
        override val title get() = "Favorites"
    }

    data object Watchlist : LibraryRoute {
        override val title get() = "Watchlist"
    }

    data object Genres : LibraryRoute {
        override val title get() = "Genres"
    }

    data object Downloaded : LibraryRoute {
        override val title get() = "Downloaded"
    }

    data object AllCollections : LibraryRoute {
        override val title get() = "Collections"
    }

    data class Genre(val genre: LibraryGenre) : LibraryRoute {
        override val title get() = genre.name
    }

    data class Collection(val id: String, val name: String) : LibraryRoute {
        override val title get() = name
    }

    data class Person(val id: String, val name: String) : LibraryRoute {
        override val title get() = name
    }

    data class Studio(val id: String, val name: String) : LibraryRoute {
        override val title get() = name
    }

    data class Discover(val query: app.zelefin.client.plugins.DiscoverQuery) : LibraryRoute {
        override val title get() = query.title
    }
}

data class LibraryGridState(
    val items: List<MediaItem> = emptyList(),
    val query: CatalogBrowseQuery = CatalogBrowseQuery(),
    val filters: CatalogFilterOptions = CatalogFilterOptions(),
    val loading: Boolean = true,
    val refreshing: Boolean = false,
)

data class LibraryOverview(
    val counts: LibraryCounts? = null,
    val roomCounts: Map<String, LibraryCounts> = emptyMap(),
    val covers: Map<String, List<MediaItem>> = emptyMap(),
    val collections: List<MediaItem> = emptyList(),
    val genres: List<LibraryGenre> = emptyList(),
    val genresLoading: Boolean = false,
)

data class LibraryLayout(
    val order: List<String> = emptyList(),
    val hidden: Set<String> = emptySet(),
    val hiddenBlocks: Set<LibraryPageBlock> = setOf(LibraryPageBlock.Collections),
    val usesDefaultHidden: Boolean = true,
) {
    fun arranged(rooms: List<LibraryRoom>): List<LibraryRoom> {
        val remaining = rooms.associateBy { it.id }.toMutableMap()
        val ordered = order.mapNotNull { remaining.remove(it) }
        val leftovers = rooms.withIndex()
            .filter { it.value.id in remaining }
            .sortedWith(compareBy({ it.value.libraryCardRank }, { it.index }))
            .map { it.value }
        return ordered + leftovers
    }

    fun resolvedHidden(rooms: List<LibraryRoom>): Set<String> =
        if (usesDefaultHidden) rooms.filter { it.isHiddenOnLibraryByDefault }.map { it.id }.toSet() else hidden

    fun displayed(rooms: List<LibraryRoom>): List<LibraryRoom> {
        val hiddenIds = resolvedHidden(rooms)
        return arranged(rooms).filter { it.id !in hiddenIds }
    }

    fun encodedHidden(): String = when {
        usesDefaultHidden -> ""
        hidden.isEmpty() -> SHOWN_ALL
        else -> hidden.sorted().joinToString(",")
    }

    companion object {
        const val SHOWN_ALL = "none"

        fun parseHidden(raw: String): Pair<Set<String>, Boolean> = when (val trimmed = raw.trim()) {
            "" -> emptySet<String>() to true
            SHOWN_ALL -> emptySet<String>() to false
            else -> trimmed.split(',').map { it.trim() }.filter { it.isNotEmpty() }.toSet() to false
        }
    }
}

/** Same keys and encoding as iOS `LibraryLayoutPreferences`. */
class LibraryLayoutStore(context: Context) {
    private val prefs = context.getSharedPreferences("zelefin.library-layout", Context.MODE_PRIVATE)

    fun load(): LibraryLayout {
        val order = prefs.getString(ORDER, "").orEmpty().split(",").filter { it.isNotEmpty() }
        val (hidden, usesDefaultHidden) = LibraryLayout.parseHidden(prefs.getString(HIDDEN, "").orEmpty())
        val pageRaw = prefs.getString(PAGE_HIDDEN, "").orEmpty()
        val blocks = when (pageRaw) {
            "" -> setOf(LibraryPageBlock.Collections)
            LibraryLayout.SHOWN_ALL -> emptySet()
            else -> pageRaw.split(",").mapNotNull { raw -> LibraryPageBlock.entries.firstOrNull { it.name.lowercase() == raw } }.toSet()
        }
        return LibraryLayout(order, hidden, blocks, usesDefaultHidden)
    }

    fun save(layout: LibraryLayout) {
        prefs.edit()
            .putString(ORDER, layout.order.joinToString(","))
            .putString(HIDDEN, layout.encodedHidden())
            .putString(
                PAGE_HIDDEN,
                if (layout.hiddenBlocks.isEmpty()) LibraryLayout.SHOWN_ALL else layout.hiddenBlocks.map { it.name.lowercase() }.sorted().joinToString(","),
            )
            .apply()
    }

    fun reset() {
        prefs.edit().clear().apply()
    }

    private companion object {
        const val ORDER = "zelefin.library-order"
        const val HIDDEN = "zelefin.library-hidden"
        const val PAGE_HIDDEN = "zelefin.library-page-hidden"
    }
}
