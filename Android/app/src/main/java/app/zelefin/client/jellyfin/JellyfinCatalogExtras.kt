package app.zelefin.client.jellyfin

import app.zelefin.core.ItemMapper
import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind
import app.zelefin.core.TrickplayInfo
import java.util.UUID
import kotlin.math.abs
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.jellyfin.sdk.api.client.extensions.itemLookupApi
import org.jellyfin.sdk.api.client.extensions.itemUpdateApi
import org.jellyfin.sdk.api.client.extensions.itemsApi
import org.jellyfin.sdk.api.client.extensions.playlistsApi
import org.jellyfin.sdk.api.client.extensions.userLibraryApi
import org.jellyfin.sdk.api.client.extensions.videosApi
import org.jellyfin.sdk.model.api.BaseItemDto
import org.jellyfin.sdk.model.api.BaseItemKind
import org.jellyfin.sdk.model.api.CreatePlaylistDto
import org.jellyfin.sdk.model.api.ItemSortBy
import org.jellyfin.sdk.model.api.MediaType
import org.jellyfin.sdk.model.api.MovieInfo
import org.jellyfin.sdk.model.api.MovieInfoRemoteSearchQuery
import org.jellyfin.sdk.model.api.RemoteSearchResult
import org.jellyfin.sdk.model.api.SeriesInfo
import org.jellyfin.sdk.model.api.SeriesInfoRemoteSearchQuery
import org.jellyfin.sdk.model.api.request.GetItemsRequest

const val WatchlistPlaylistName = "Watchlist"

data class RemoteIdentifyHit(
    val name: String,
    val year: Int?,
    val overview: String?,
    val providerIds: Map<String, String>,
    val imageUrl: String?,
    val raw: RemoteSearchResult,
)

data class ItemMetadataDraft(
    val name: String,
    val overview: String,
    val year: String,
    val officialRating: String,
    val genres: String,
    val tags: String,
)

fun itemMetadataDraft(item: MediaItem, tags: List<String> = emptyList()) = ItemMetadataDraft(
    name = item.name,
    overview = item.overview.orEmpty(),
    year = item.year?.toString().orEmpty(),
    officialRating = item.officialRating.orEmpty(),
    genres = item.genres.joinToString(", "),
    tags = tags.joinToString(", "),
)

fun BaseItemDto.trickplayInfo(sourceId: String?): TrickplayInfo? {
    val manifest = trickplay ?: return null
    if (manifest.isEmpty()) return null
    val sourceKey = sourceId?.takeIf { manifest.containsKey(it) } ?: manifest.keys.sorted().firstOrNull() ?: return null
    val widths = manifest[sourceKey] ?: return null
    if (widths.isEmpty()) return null
    val chosen = widths.minByOrNull { entry ->
        val width = entry.key.toIntOrNull() ?: entry.value.width ?: 0
        abs(width - 320)
    } ?: return null
    val width = chosen.key.toIntOrNull() ?: chosen.value.width ?: return null
    val info = chosen.value
    return TrickplayInfo(
        width = width,
        interval = (info.interval ?: 10_000) / 1000.0,
        thumbnailCount = info.thumbnailCount ?: 0,
        tileWidth = info.tileWidth ?: 10,
        tileHeight = info.tileHeight ?: 10,
        thumbnailWidth = info.width ?: width,
        thumbnailHeight = info.height ?: 180,
        mediaSourceId = sourceKey,
    )
}

suspend fun JellyfinLibrary.additionalParts(userId: UUID, itemId: String): List<MediaItem> = withContext(Dispatchers.IO) {
    runCatching {
        sdk.videosApi.getAdditionalPart(UUID.fromString(itemId), userId).content.items.orEmpty()
            .mapNotNull { ItemMapper.mediaItem(it.toSnapshot()) }
    }.getOrDefault(emptyList())
}

suspend fun JellyfinLibrary.randomTitle(userId: UUID, kinds: List<BaseItemKind> = listOf(BaseItemKind.MOVIE, BaseItemKind.SERIES)): MediaItem? =
    withContext(Dispatchers.IO) {
        val result = sdk.itemsApi.getItems(
            GetItemsRequest(
                userId = userId,
                includeItemTypes = kinds,
                recursive = true,
                sortBy = listOf(ItemSortBy.RANDOM),
                limit = 1,
                fields = listOf(
                    org.jellyfin.sdk.model.api.ItemFields.PRIMARY_IMAGE_ASPECT_RATIO,
                    org.jellyfin.sdk.model.api.ItemFields.OVERVIEW,
                    org.jellyfin.sdk.model.api.ItemFields.GENRES,
                ),
            ),
        ).content.items.orEmpty()
        result.firstOrNull()?.toSnapshot()?.let { ItemMapper.mediaItem(it) }
    }

suspend fun JellyfinLibrary.watchlistPlaylistId(userId: UUID): String = withContext(Dispatchers.IO) {
    val existing = sdk.itemsApi.getItems(
        GetItemsRequest(
            userId = userId,
            includeItemTypes = listOf(BaseItemKind.PLAYLIST),
            recursive = true,
            searchTerm = WatchlistPlaylistName,
            limit = 20,
        ),
    ).content.items.orEmpty().firstOrNull { it.name.equals(WatchlistPlaylistName, ignoreCase = true) }
    existing?.id?.toString() ?: sdk.playlistsApi.createPlaylist(
        CreatePlaylistDto(
            name = WatchlistPlaylistName,
            ids = emptyList(),
            userId = userId,
            mediaType = MediaType.VIDEO,
            users = emptyList(),
            isPublic = false,
        ),
    ).content.id.ifEmpty { throw app.zelefin.core.ZelefinException.server("Jellyfin did not create a Watchlist playlist.") }
}

suspend fun JellyfinLibrary.watchlistItems(userId: UUID): List<MediaItem> = withContext(Dispatchers.IO) {
    val playlist = runCatching { watchlistPlaylistId(userId) }.getOrNull() ?: return@withContext emptyList()
    sdk.playlistsApi.getPlaylistItems(UUID.fromString(playlist), userId).content.items.orEmpty()
        .mapNotNull { ItemMapper.mediaItem(it.toSnapshot())?.copy(isWatchlisted = true) }
}

suspend fun JellyfinLibrary.watchlistIds(userId: UUID): Set<String> =
    watchlistItems(userId).map { it.id }.toSet()

suspend fun JellyfinLibrary.setWatchlisted(userId: UUID, itemId: String, watchlisted: Boolean) = withContext(Dispatchers.IO) {
    val playlist = watchlistPlaylistId(userId)
    val playlistId = UUID.fromString(playlist)
    if (watchlisted) {
        sdk.playlistsApi.addItemToPlaylist(playlistId, listOf(UUID.fromString(itemId)), userId)
    } else {
        val entries = sdk.playlistsApi.getPlaylistItems(playlistId, userId).content.items.orEmpty()
        val entryIds = entries.filter { it.id?.toString() == itemId }.mapNotNull { it.playlistItemId }
        if (entryIds.isNotEmpty()) {
            sdk.playlistsApi.removeItemFromPlaylist(playlistId.toString(), entryIds)
        }
    }
}

suspend fun JellyfinLibrary.searchIdentify(item: MediaItem): List<RemoteIdentifyHit> = withContext(Dispatchers.IO) {
    when (item.kind) {
        MediaKind.Movie -> {
            val results = sdk.itemLookupApi.getMovieRemoteSearchResults(
                MovieInfoRemoteSearchQuery(
                    searchInfo = MovieInfo(
                        name = item.name,
                        year = item.year,
                        providerIds = item.tmdbId?.let { mapOf("Tmdb" to it.toString()) },
                        isAutomated = false,
                    ),
                    itemId = UUID.fromString(item.id),
                    includeDisabledProviders = false,
                ),
            ).content
            results.map { it.toHit() }
        }
        MediaKind.Series -> {
            val results = sdk.itemLookupApi.getSeriesRemoteSearchResults(
                SeriesInfoRemoteSearchQuery(
                    searchInfo = SeriesInfo(
                        name = item.name,
                        year = item.year,
                        providerIds = item.tmdbId?.let { mapOf("Tmdb" to it.toString()) },
                        isAutomated = false,
                    ),
                    itemId = UUID.fromString(item.id),
                    includeDisabledProviders = false,
                ),
            ).content
            results.map { it.toHit() }
        }
        else -> emptyList()
    }
}

suspend fun JellyfinLibrary.applyIdentify(itemId: String, hit: RemoteIdentifyHit) = withContext(Dispatchers.IO) {
    sdk.itemLookupApi.applySearchCriteria(
        itemId = UUID.fromString(itemId),
        data = hit.raw,
        replaceAllImages = true,
    )
}

suspend fun JellyfinLibrary.updateItemMetadata(userId: UUID, itemId: String, draft: ItemMetadataDraft) = withContext(Dispatchers.IO) {
    val current = sdk.userLibraryApi.getItem(UUID.fromString(itemId), userId).content
    val year = draft.year.trim().toIntOrNull()
    val genres = draft.genres.split(',').map { it.trim() }.filter { it.isNotEmpty() }
    val tags = draft.tags.split(',').map { it.trim() }.filter { it.isNotEmpty() }
    sdk.itemUpdateApi.updateItem(
        itemId = UUID.fromString(itemId),
        data = current.copy(
            name = draft.name.trim().ifEmpty { current.name },
            overview = draft.overview.trim().ifEmpty { null },
            productionYear = year,
            officialRating = draft.officialRating.trim().ifEmpty { null },
            genres = genres,
            tags = tags,
        ),
    )
}

private fun RemoteSearchResult.toHit() = RemoteIdentifyHit(
    name = name?.trim().orEmpty().ifEmpty { "Untitled" },
    year = productionYear,
    overview = overview?.trim()?.ifEmpty { null },
    providerIds = providerIds.orEmpty().mapNotNull { (key, value) -> value?.let { key to it } }.toMap(),
    imageUrl = imageUrl,
    raw = this,
)
