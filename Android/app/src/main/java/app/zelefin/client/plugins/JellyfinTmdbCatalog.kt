package app.zelefin.client.plugins

/** TMDB identifiers for movies and series already in the signed-in Jellyfin library. */
data class JellyfinTmdbCatalog(
    val movieIds: Set<Int> = emptySet(),
    val seriesIds: Set<Int> = emptySet(),
    /** The library item for each TMDB identifier, so a Discover title can open its library page. */
    val movieItemIds: Map<Int, String> = emptyMap(),
    val seriesItemIds: Map<Int, String> = emptyMap(),
) {
    fun contains(title: SeerrTitle): Boolean = when (title.kind) {
        SeerrTitle.Kind.Movie -> title.tmdbId in movieIds
        SeerrTitle.Kind.Tv -> title.tmdbId in seriesIds
    }

    /** The library item that is [title], when the catalog knows it. */
    fun itemId(title: SeerrTitle): String? = when (title.kind) {
        SeerrTitle.Kind.Movie -> movieItemIds[title.tmdbId]
        SeerrTitle.Kind.Tv -> seriesItemIds[title.tmdbId]
    }

    companion object {
        val Empty = JellyfinTmdbCatalog()

        fun of(movies: Map<Int, String>, series: Map<Int, String>) =
            JellyfinTmdbCatalog(movies.keys, series.keys, movies, series)

        /** Returns the TMDB identifier stored in Jellyfin provider IDs. */
        fun tmdbId(providerIds: Map<String, String>?): Int? {
            providerIds ?: return null
            for ((key, raw) in providerIds) {
                if (!isTmdbKey(key)) continue
                raw.trim().toIntOrNull()?.let { return it }
            }
            return null
        }

        fun isTmdbKey(key: String): Boolean {
            val compact = key.lowercase().filter { it.isLetter() }
            return compact == "tmdb" ||
                compact == "tmdbid" ||
                compact == "themoviedb" ||
                compact == "moviedb" ||
                compact == "themoviedatabase"
        }

        /** Returns the IMDb identifier stored in Jellyfin provider IDs (`tt1375666`). */
        fun imdbId(providerIds: Map<String, String>?): String? {
            providerIds ?: return null
            for ((key, raw) in providerIds) {
                if (!key.equals("Imdb", ignoreCase = true)) continue
                val trimmed = raw.trim()
                if (trimmed.startsWith("tt") && trimmed.drop(2).all { it.isDigit() }) return trimmed
                if (trimmed.isNotEmpty() && trimmed.all { it.isDigit() }) return "tt$trimmed"
            }
            return null
        }
    }
}
