package app.zelefin.client

import android.content.Context

/** Persists catalog sort and filters per library route, matching AFinity's per-library memory. */
class CatalogQueryStore(context: Context) {
    private val prefs = context.getSharedPreferences("zelefin.catalog-query", Context.MODE_PRIVATE)

    fun load(key: String): CatalogBrowseQuery {
        val raw = prefs.getString(key, null) ?: return CatalogBrowseQuery()
        return decode(raw)
    }

    fun save(key: String, query: CatalogBrowseQuery) {
        prefs.edit().putString(key, encode(query)).apply()
    }

    companion object {
        fun routeKey(route: LibraryRoute): String = when (route) {
            is LibraryRoute.Room -> "room:${route.room.id}"
            LibraryRoute.Favorites -> "favorites"
            LibraryRoute.Watchlist -> "watchlist"
            LibraryRoute.Genres -> "genres"
            LibraryRoute.Downloaded -> "downloaded"
            LibraryRoute.AllCollections -> "collections"
            is LibraryRoute.Genre -> "genre:${route.genre.id}"
            is LibraryRoute.Collection -> "collection:${route.id}"
            is LibraryRoute.Person -> "person:${route.id}"
            is LibraryRoute.Studio -> "studio:${route.id}"
            is LibraryRoute.Discover -> "discover:${route.query.title}"
        }

        fun encode(query: CatalogBrowseQuery): String = listOf(
            query.sort.name,
            if (query.sortAscending) "1" else "0",
            query.statuses.joinToString(",") { it.name },
            query.features.joinToString(",") { it.name },
            query.videoKinds.joinToString(",") { it.name },
            query.genres.joinToString("\u001f"),
            query.officialRatings.joinToString("\u001f"),
            query.tags.joinToString("\u001f"),
            query.years.joinToString(","),
            query.studios.joinToString("\u001f"),
            query.audioLanguages.joinToString(","),
            query.subtitleLanguages.joinToString(","),
        ).joinToString("\u001e")

        fun decode(raw: String): CatalogBrowseQuery {
            val parts = raw.split("\u001e")
            if (parts.size < 12) return CatalogBrowseQuery()
            return CatalogBrowseQuery(
                statuses = parts[2].split(',').mapNotNull { name -> CatalogStatusFilter.entries.firstOrNull { it.name == name } }.toSet(),
                features = parts[3].split(',').mapNotNull { name -> CatalogFeatureFilter.entries.firstOrNull { it.name == name } }.toSet(),
                videoKinds = parts[4].split(',').mapNotNull { name -> CatalogVideoKind.entries.firstOrNull { it.name == name } }.toSet(),
                genres = parts[5].split('\u001f').filter { it.isNotEmpty() }.toSet(),
                officialRatings = parts[6].split('\u001f').filter { it.isNotEmpty() }.toSet(),
                tags = parts[7].split('\u001f').filter { it.isNotEmpty() }.toSet(),
                years = parts[8].split(',').mapNotNull { it.toIntOrNull() }.toSet(),
                studios = parts[9].split('\u001f').filter { it.isNotEmpty() }.toSet(),
                audioLanguages = parts[10].split(',').filter { it.isNotEmpty() }.toSet(),
                subtitleLanguages = parts[11].split(',').filter { it.isNotEmpty() }.toSet(),
                sort = CatalogSortField.entries.firstOrNull { it.name == parts[0] } ?: CatalogSortField.Name,
                sortAscending = parts[1] != "0",
            )
        }
    }
}
