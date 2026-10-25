package app.zelefin.client

import app.zelefin.core.MediaItem
import app.zelefin.core.VideoResolution

enum class CatalogStatusFilter(val title: String) {
    Played("Played"),
    Unplayed("Unplayed"),
    Favorite("Favorite"),
    ContinueWatching("Continue Watching"),
}

enum class CatalogFeatureFilter(val title: String) {
    Subtitles("Subtitles"),
    Trailers("Trailers"),
    Extras("Extras"),
    ThemeSongs("Theme Songs"),
    ThemeVideos("Theme Videos"),
}

enum class CatalogVideoKind(val title: String) {
    Sd("SD"),
    Hd("HD"),
    FourK("4K"),
    ThreeD("3D"),
    Dvd("DVD"),
    BluRay("Blu-ray"),
    Iso("ISO"),
    ;

    val isResolution: Boolean
        get() = this == Sd || this == Hd || this == FourK

    val isDisc: Boolean
        get() = this == Dvd || this == BluRay || this == Iso
}

enum class CatalogSortField(val title: String) {
    Name("Name"),
    Random("Random"),
    CommunityRating("Community Rating"),
    CriticRating("Critics Rating"),
    DateAdded("Date Added"),
    DatePlayed("Date Played"),
    ParentalRating("Parental Rating"),
    PlayCount("Play Count"),
    ReleaseDate("Release Date"),
    Runtime("Runtime"),
    ;

    val allowsDirection: Boolean get() = this != Random
}

data class CatalogFilterChoice(val id: String, val name: String)

data class CatalogFilterOptions(
    val genres: List<CatalogFilterChoice> = emptyList(),
    val officialRatings: List<CatalogFilterChoice> = emptyList(),
    val tags: List<CatalogFilterChoice> = emptyList(),
    val years: List<CatalogFilterChoice> = emptyList(),
    val studios: List<CatalogFilterChoice> = emptyList(),
    val languages: List<CatalogFilterChoice> = emptyList(),
    val sorts: List<CatalogSortField> = CatalogSortField.entries,
    /** Features and Video Type, which filter on what the media files carry. */
    val fileFilters: Boolean = true,
) {
    /** Silo's Jellyfin API ignores tag, studio-name, feature and video-type filters and the other sorts. */
    fun forSiloServer(): CatalogFilterOptions = copy(
        tags = emptyList(),
        studios = emptyList(),
        sorts = SiloSorts,
        fileFilters = false,
    )

    /** Emby has no audio or subtitle language filters. */
    fun forEmbyServer(): CatalogFilterOptions = copy(languages = emptyList())

    companion object {
        val SiloSorts = listOf(
            CatalogSortField.Name,
            CatalogSortField.Random,
            CatalogSortField.CommunityRating,
            CatalogSortField.DateAdded,
            CatalogSortField.ReleaseDate,
        )
    }
}

data class CatalogBrowseQuery(
    val statuses: Set<CatalogStatusFilter> = emptySet(),
    val features: Set<CatalogFeatureFilter> = emptySet(),
    val videoKinds: Set<CatalogVideoKind> = emptySet(),
    val genres: Set<String> = emptySet(),
    val officialRatings: Set<String> = emptySet(),
    val tags: Set<String> = emptySet(),
    val years: Set<Int> = emptySet(),
    val studios: Set<String> = emptySet(),
    val audioLanguages: Set<String> = emptySet(),
    val subtitleLanguages: Set<String> = emptySet(),
    val sort: CatalogSortField = CatalogSortField.Name,
    val sortAscending: Boolean = true,
) {
    val isDefault: Boolean
        get() = activeFilterCount == 0 && sort == CatalogSortField.Name && sortAscending

    val activeFilterCount: Int
        get() = statuses.size + features.size + videoKinds.size + genres.size +
            officialRatings.size + tags.size + years.size + studios.size +
            audioLanguages.size + subtitleLanguages.size

    fun cleared(): CatalogBrowseQuery = copy(
        statuses = emptySet(),
        features = emptySet(),
        videoKinds = emptySet(),
        genres = emptySet(),
        officialRatings = emptySet(),
        tags = emptySet(),
        years = emptySet(),
        studios = emptySet(),
        audioLanguages = emptySet(),
        subtitleLanguages = emptySet(),
    )

    /** Drops what [CatalogFilterOptions.forSiloServer] hides, so a saved query cannot return an unfiltered grid. */
    fun forSiloServer(): CatalogBrowseQuery = copy(
        features = emptySet(),
        videoKinds = emptySet(),
        tags = emptySet(),
        studios = emptySet(),
        sort = if (sort in CatalogFilterOptions.SiloSorts) sort else CatalogSortField.Name,
    )

    /** Drops what [CatalogFilterOptions.forEmbyServer] hides. */
    fun forEmbyServer(): CatalogBrowseQuery = copy(audioLanguages = emptySet(), subtitleLanguages = emptySet())

    /** SD+4K cannot be one Jellyfin query, so those two resolutions are fetched separately. */
    fun resolutionPasses(): List<Pair<Boolean?, Boolean?>> {
        val picked = videoKinds.filter { it.isResolution }.toSet()
        if (picked.isEmpty()) return listOf(null to null)
        if (CatalogVideoKind.Sd in picked && CatalogVideoKind.Hd in picked) return listOf(null to null)
        if (picked == setOf(CatalogVideoKind.Sd, CatalogVideoKind.FourK)) return listOf(false to null, null to true)
        if (CatalogVideoKind.FourK in picked && CatalogVideoKind.Hd !in picked && CatalogVideoKind.Sd !in picked) {
            return listOf(null to true)
        }
        if (CatalogVideoKind.Hd in picked) return listOf(true to null)
        if (CatalogVideoKind.Sd in picked) return listOf(false to null)
        return listOf(null to null)
    }
}

fun List<MediaItem>.matchesCatalog(query: CatalogBrowseQuery): List<MediaItem> = filter { item ->
    val played = CatalogStatusFilter.Played in query.statuses
    val unplayed = CatalogStatusFilter.Unplayed in query.statuses
    if (played && !unplayed && !item.isPlayed) return@filter false
    if (unplayed && !played && item.isPlayed) return@filter false
    if (CatalogStatusFilter.Favorite in query.statuses && !item.isFavorite) return@filter false
    if (CatalogStatusFilter.ContinueWatching in query.statuses && !(item.playbackPosition > 5 && !item.isWatched)) {
        return@filter false
    }
    if (CatalogFeatureFilter.Subtitles in query.features && !item.hasClosedCaptions) return@filter false
    val resolutions = query.videoKinds.filter { it.isResolution }
    if (resolutions.isNotEmpty()) {
        val matches = resolutions.any { kind ->
            when (kind) {
                CatalogVideoKind.Sd -> item.videoResolution == VideoResolution.Sd
                CatalogVideoKind.Hd -> item.videoResolution == VideoResolution.Hd
                CatalogVideoKind.FourK -> item.videoResolution == VideoResolution.FourK
                else -> false
            }
        }
        if (!matches) return@filter false
    }
    if (query.genres.isNotEmpty() && query.genres.none { it in item.genres }) return@filter false
    if (query.years.isNotEmpty() && item.year !in query.years) return@filter false
    if (query.officialRatings.isNotEmpty() && item.officialRating !in query.officialRatings) return@filter false
    true
}

fun List<MediaItem>.orderedForCatalog(query: CatalogBrowseQuery): List<MediaItem> {
    if (query.sort == CatalogSortField.Random) return shuffled()
    val sorted = when (query.sort) {
        CatalogSortField.Name -> sortedBy { it.name.lowercase() }
        CatalogSortField.CommunityRating -> sortedBy { it.communityRating ?: -1.0 }
        CatalogSortField.CriticRating -> sortedBy { it.criticRating ?: -1.0 }
        CatalogSortField.ReleaseDate -> sortedBy { it.year ?: 0 }
        CatalogSortField.Runtime -> sortedBy { it.runtime ?: 0.0 }
        CatalogSortField.ParentalRating -> sortedBy { it.officialRating.orEmpty() }
        else -> return this
    }
    return if (query.sortAscending) sorted else sorted.asReversed()
}

fun catalogOptionsFromItems(items: List<MediaItem>): CatalogFilterOptions {
    fun choices(names: List<String>) = names
        .map { it.trim() }
        .filter { it.isNotEmpty() }
        .distinctBy { it.lowercase() }
        .sortedBy { it.lowercase() }
        .map { CatalogFilterChoice(it, it) }
    val years = items.mapNotNull { it.year }.distinct().sortedDescending().map { CatalogFilterChoice(it.toString(), it.toString()) }
    return CatalogFilterOptions(
        genres = choices(items.flatMap { it.genres }),
        officialRatings = choices(items.mapNotNull { it.officialRating }),
        years = years,
    )
}

fun <T> Set<T>.toggled(value: T): Set<T> = if (value in this) this - value else this + value
