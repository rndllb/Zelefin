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
    Other("Library");

    val appearsInLibrary: Boolean get() = this != Music && this != Books && this != Playlists

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

        fun fromSilo(raw: String?): LibraryKind = when (raw?.lowercase()) {
            "movie", "movies" -> Movies
            "show", "shows", "series", "tv" -> Shows
            "collection", "collections" -> Collections
            "live", "livetv", "live_tv" -> LiveTV
            "music", "musicvideo", "musicvideos", "audio" -> Music
            else -> Other
        }

        fun stored(raw: String?): LibraryKind = entries.firstOrNull { it.name == raw } ?: Other
    }
}

/** Rooms the Library tab lists. Silo has no Live TV guide on this client. */
fun List<LibraryRoom>.libraryTabRooms(silo: Boolean): List<LibraryRoom> =
    filter { it.kind.appearsInLibrary && !(silo && it.kind == LibraryKind.LiveTV) }

data class LibraryCounts(val movies: Int = 0, val shows: Int = 0, val episodes: Int = 0) {
    val total: Int get() = movies + shows + episodes

    val caption: String?
        get() = listOfNotNull(
            phrase(movies, "movie", "movies"),
            phrase(shows, "show", "shows"),
            phrase(episodes, "episode", "episodes"),
        ).takeIf { it.isNotEmpty() }?.joinToString(" · ")

    private fun phrase(value: Int, singular: String, plural: String): String? =
        if (value <= 0) null else "${formatCount(value)} ${if (value == 1) singular else plural}"
}

fun formatCount(value: Int): String = NumberFormat.getIntegerInstance().format(value)

enum class LibraryPageBlock(val title: String) {
    Favorites("Favorites"),
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

    data object Genres : LibraryRoute {
        override val title get() = "Genres"
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
) {
    fun arranged(rooms: List<LibraryRoom>): List<LibraryRoom> {
        val remaining = rooms.associateBy { it.id }.toMutableMap()
        val ordered = order.mapNotNull { remaining.remove(it) }
        return ordered + rooms.filter { it.id in remaining }
    }

    fun displayed(rooms: List<LibraryRoom>): List<LibraryRoom> = arranged(rooms).filter { it.id !in hidden }
}

/** Same keys and encoding as iOS `LibraryLayoutPreferences`. */
class LibraryLayoutStore(context: Context) {
    private val prefs = context.getSharedPreferences("zelefin.library-layout", Context.MODE_PRIVATE)

    fun load(): LibraryLayout {
        val order = prefs.getString(ORDER, "").orEmpty().split(",").filter { it.isNotEmpty() }
        val hidden = prefs.getString(HIDDEN, "").orEmpty().split(",").filter { it.isNotEmpty() }.toSet()
        val pageRaw = prefs.getString(PAGE_HIDDEN, "").orEmpty()
        val blocks = when (pageRaw) {
            "" -> setOf(LibraryPageBlock.Collections)
            SHOWN_ALL -> emptySet()
            else -> pageRaw.split(",").mapNotNull { raw -> LibraryPageBlock.entries.firstOrNull { it.name.lowercase() == raw } }.toSet()
        }
        return LibraryLayout(order, hidden, blocks)
    }

    fun save(layout: LibraryLayout) {
        prefs.edit()
            .putString(ORDER, layout.order.joinToString(","))
            .putString(HIDDEN, layout.hidden.sorted().joinToString(","))
            .putString(
                PAGE_HIDDEN,
                if (layout.hiddenBlocks.isEmpty()) SHOWN_ALL else layout.hiddenBlocks.map { it.name.lowercase() }.sorted().joinToString(","),
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
        const val SHOWN_ALL = "none"
    }
}
