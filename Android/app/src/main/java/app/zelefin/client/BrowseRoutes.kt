package app.zelefin.client

import app.zelefin.core.CreditPerson
import app.zelefin.core.MediaItem
import app.zelefin.core.TitleTrailer

/** Home rows that open a full page from their header chevron (iOS `MediaRow.sectionDestination`). */
enum class HomeShelf(val title: String, val queue: Boolean) {
    ContinueWatching("Continue Watching", queue = true),
    NextUp("Next Up", queue = true),
    RecentMovies("Recently Added Movies", queue = false),
    RecentShows("Recently Added Shows", queue = false),
}

/** Full-page lists pushed from a row chevron on Home or a title page. */
sealed interface BrowsePage {
    val title: String

    data class Home(val shelf: HomeShelf) : BrowsePage {
        override val title get() = shelf.title
    }

    data class Shelf(override val title: String, val items: List<MediaItem>) : BrowsePage

    data class Trailers(val trailers: List<TitleTrailer>, val owner: MediaItem) : BrowsePage {
        override val title get() = "Trailers"
    }

    data class Cast(val people: List<CreditPerson>) : BrowsePage {
        override val title get() = "Cast & Crew"
    }

    data class Library(val route: LibraryRoute) : BrowsePage {
        override val title get() = route.title
    }
}
