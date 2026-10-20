package app.zelefin.client.jellyfin

import android.content.Context
import app.zelefin.client.network.GatewayHttp
import app.zelefin.core.CreditPerson
import app.zelefin.core.HomeFeed
import app.zelefin.core.HomeRowStyle
import app.zelefin.core.HomeSection
import app.zelefin.client.CatalogBrowseQuery
import app.zelefin.client.CatalogFeatureFilter
import app.zelefin.client.CatalogFilterChoice
import app.zelefin.client.CatalogFilterOptions
import app.zelefin.client.CatalogSortField
import app.zelefin.client.CatalogStatusFilter
import app.zelefin.client.CatalogVideoKind
import app.zelefin.client.LibraryCounts
import app.zelefin.client.LibraryGenre
import app.zelefin.client.LibraryKind
import app.zelefin.client.LibraryRoom
import app.zelefin.client.SearchHit
import app.zelefin.client.plugins.JellyfinTmdbCatalog
import app.zelefin.client.SearchHitKind
import app.zelefin.client.isBrowsableGenre
import app.zelefin.core.ItemMapper
import app.zelefin.core.JellyfinItemSnapshot
import app.zelefin.core.JellyfinStreamSnapshot
import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind
import app.zelefin.core.PlaybackMethod
import app.zelefin.core.PlaybackPlan
import app.zelefin.core.PlaybackQueueKind
import app.zelefin.core.PlaybackResumePolicy
import app.zelefin.core.QuickConnectHandshake
import app.zelefin.core.ServerReachability
import app.zelefin.core.ServerUrl
import app.zelefin.core.StreamResumeUrl
import app.zelefin.core.StreamUrlBuilder
import app.zelefin.core.TitleDetail
import app.zelefin.core.TitleTrailer
import app.zelefin.core.TrailerLinks
import app.zelefin.core.ZelefinException
import java.util.UUID
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.jellyfin.sdk.api.client.ApiClient
import org.jellyfin.sdk.api.client.HttpClientOptions
import org.jellyfin.sdk.api.client.exception.InvalidStatusException
import org.jellyfin.sdk.api.client.extensions.collectionApi
import org.jellyfin.sdk.api.client.extensions.displayPreferencesApi
import org.jellyfin.sdk.api.client.extensions.moviesApi
import org.jellyfin.sdk.model.api.RecommendationType
import org.jellyfin.sdk.api.client.extensions.get
import org.jellyfin.sdk.api.client.extensions.filterApi
import org.jellyfin.sdk.api.client.extensions.genresApi
import org.jellyfin.sdk.api.client.extensions.itemsApi
import org.jellyfin.sdk.api.client.extensions.localizationApi
import org.jellyfin.sdk.api.client.extensions.studiosApi
import org.jellyfin.sdk.api.client.extensions.libraryApi
import org.jellyfin.sdk.api.client.extensions.mediaInfoApi
import org.jellyfin.sdk.api.client.extensions.playStateApi
import org.jellyfin.sdk.api.client.extensions.quickConnectApi
import org.jellyfin.sdk.api.client.extensions.searchApi
import org.jellyfin.sdk.api.client.extensions.systemApi
import org.jellyfin.sdk.api.client.extensions.tvShowsApi
import org.jellyfin.sdk.api.client.extensions.userApi
import org.jellyfin.sdk.api.client.extensions.userLibraryApi
import org.jellyfin.sdk.api.client.extensions.userViewsApi
import org.jellyfin.sdk.api.okhttp.OkHttpFactory
import org.jellyfin.sdk.createJellyfin
import org.jellyfin.sdk.model.ClientInfo
import org.jellyfin.sdk.model.api.AuthenticateUserByName
import org.jellyfin.sdk.model.api.AuthenticationResult
import org.jellyfin.sdk.model.api.BaseItemDto
import org.jellyfin.sdk.model.api.BaseItemDtoQueryResult
import org.jellyfin.sdk.model.api.BaseItemKind
import org.jellyfin.sdk.model.api.DeviceProfile
import org.jellyfin.sdk.model.api.DirectPlayProfile
import org.jellyfin.sdk.model.api.DlnaProfileType
import org.jellyfin.sdk.model.api.EncodingContext
import org.jellyfin.sdk.model.api.ImageType
import org.jellyfin.sdk.model.api.CollectionType
import org.jellyfin.sdk.model.api.CultureDto
import org.jellyfin.sdk.model.api.ItemFields
import org.jellyfin.sdk.model.api.ItemFilter
import org.jellyfin.sdk.model.api.ItemSortBy
import org.jellyfin.sdk.model.api.MediaStreamProtocol
import org.jellyfin.sdk.model.api.MediaStreamType
import org.jellyfin.sdk.model.api.MediaType
import org.jellyfin.sdk.model.api.PlayMethod
import org.jellyfin.sdk.model.api.PlaybackInfoDto
import org.jellyfin.sdk.model.api.PlaybackOrder
import org.jellyfin.sdk.model.api.PlaybackProgressInfo
import org.jellyfin.sdk.model.api.PlaybackStartInfo
import org.jellyfin.sdk.model.api.PlaybackStopInfo
import org.jellyfin.sdk.model.api.QuickConnectDto
import org.jellyfin.sdk.model.api.RepeatMode
import org.jellyfin.sdk.model.api.SearchHint
import org.jellyfin.sdk.model.api.SortOrder
import org.jellyfin.sdk.model.api.VideoType
import org.jellyfin.sdk.model.api.request.GetStudiosRequest
import org.jellyfin.sdk.model.api.SubtitleDeliveryMethod
import org.jellyfin.sdk.model.api.SubtitleProfile
import org.jellyfin.sdk.model.api.TranscodingProfile
import org.jellyfin.sdk.model.api.request.GetEpisodesRequest
import org.jellyfin.sdk.model.api.request.GetGenresRequest
import org.jellyfin.sdk.model.api.request.GetItemsRequest
import org.jellyfin.sdk.model.api.request.GetNextUpRequest
import org.jellyfin.sdk.model.api.request.GetResumeItemsRequest
import org.jellyfin.sdk.model.api.request.GetSeasonsRequest
import org.jellyfin.sdk.model.api.request.GetSimilarItemsRequest

data class JellyfinScope(
    val kinds: List<BaseItemKind>,
    val parentId: String? = null,
    val genreIds: List<String> = emptyList(),
    val personIds: List<String> = emptyList(),
    val studioIds: List<String> = emptyList(),
)

private fun libraryKind(type: CollectionType?, name: String): LibraryKind = when (type) {
    CollectionType.MOVIES -> LibraryKind.Movies
    CollectionType.TVSHOWS -> LibraryKind.Shows
    CollectionType.MUSIC, CollectionType.MUSICVIDEOS -> LibraryKind.Music
    CollectionType.BOOKS -> LibraryKind.Books
    CollectionType.PHOTOS -> LibraryKind.Photos
    CollectionType.LIVETV -> LibraryKind.LiveTV
    CollectionType.PLAYLISTS -> LibraryKind.Playlists
    CollectionType.HOMEVIDEOS -> LibraryKind.HomeVideos
    CollectionType.BOXSETS -> LibraryKind.Collections
    else -> LibraryKind.inferred(name) ?: LibraryKind.Other
}

/** Channels and videos from the TubeArchivist Metadata plugin; needs `ItemFields.PROVIDER_IDS` on the request. */
private fun BaseItemDto.isTubeArchivist(): Boolean =
    providerIds?.keys?.any { it.equals(ItemMapper.TUBE_ARCHIVIST_PROVIDER, ignoreCase = true) } == true

private fun List<BaseItemDto>.withoutTubeArchivist(): List<BaseItemDto> = filterNot { it.isTubeArchivist() }

class JellyfinLibrary(
    context: Context,
    private val baseUrl: String,
    accessToken: String? = null,
    deviceId: String = app.zelefin.client.session.SessionVault(context.applicationContext).deviceId,
) {
    private val api: ApiClient = jellyfin(context).createApi(
        baseUrl = baseUrl,
        accessToken = accessToken,
        deviceInfo = org.jellyfin.sdk.model.DeviceInfo(
            id = deviceId,
            name = reportedDeviceName(context),
        ),
        httpClientOptions = HttpClientOptions(requestTimeout = 60.seconds, socketTimeout = 60.seconds),
    )

    val serverUrl: String get() = api.baseUrl ?: baseUrl

    internal val sdk: ApiClient get() = api

    suspend fun probe(): ServerReachability = withContext(Dispatchers.IO) {
        try {
            val info = api.systemApi.getPublicSystemInfo().content
            val name = info.serverName?.trim().orEmpty().ifEmpty { "Jellyfin" }
            ServerReachability.Reachable(name, info.version ?: "?")
        } catch (error: InvalidStatusException) {
            ServerReachability.fromStatus(error.status)
        } catch (error: Exception) {
            ServerReachability.from(error)
        }
    }

    suspend fun login(username: String, password: String): AuthenticationResult = withContext(Dispatchers.IO) {
        val result = api.userApi.authenticateUserByName(
            AuthenticateUserByName(username = username, pw = password),
        ).content
        val token = result.accessToken ?: throw ZelefinException.server("Jellyfin did not return an access token.")
        api.update(accessToken = token)
        result
    }

    suspend fun quickConnectEnabled(): Boolean = withContext(Dispatchers.IO) {
        try {
            api.quickConnectApi.getQuickConnectEnabled().content
        } catch (error: InvalidStatusException) {
            when (error.status) {
                401, 403 -> false
                404 -> true
                else -> throw error
            }
        }
    }

    suspend fun startQuickConnect(): QuickConnectHandshake = withContext(Dispatchers.IO) {
        try {
            val result = api.quickConnectApi.initiateQuickConnect().content
            if (result.code.isBlank() || result.secret.isBlank()) throw ZelefinException.quickConnectUnavailable()
            QuickConnectHandshake(result.code, result.secret)
        } catch (error: InvalidStatusException) {
            if (error.status == 401 || error.status == 403) throw ZelefinException.quickConnectDisabled()
            throw error
        }
    }

    suspend fun waitForQuickConnect(handshake: QuickConnectHandshake): AuthenticationResult = withContext(Dispatchers.IO) {
        var secret = handshake.secret
        repeat(150) {
            try {
                val state = api.quickConnectApi.getQuickConnectState(secret).content
                if (state.authenticated) {
                    if (state.secret.isNotBlank()) secret = state.secret
                    val result = api.userApi.authenticateWithQuickConnect(QuickConnectDto(secret)).content
                    val token = result.accessToken ?: throw ZelefinException.server("Jellyfin did not return an access token.")
                    api.update(accessToken = token)
                    return@withContext result
                }
            } catch (error: InvalidStatusException) {
                if (error.status == 404 || error.status == 401) throw ZelefinException.quickConnectExpired()
                throw error
            }
            delay(2_000)
        }
        throw ZelefinException.quickConnectExpired()
    }

    suspend fun home(userId: UUID, hero: HeroContent = HeroContent.RecentlyAdded): HomeFeed = withContext(Dispatchers.IO) {
        val resume = items(userId, PlaybackQueueKind.Resume) {
            api.itemsApi.getResumeItems(
                GetResumeItemsRequest(
                    userId = userId,
                    limit = 20,
                    fields = listFields,
                    mediaTypes = listOf(MediaType.VIDEO),
                    enableUserData = true,
                    enableImageTypes = imageTypes,
                    enableTotalRecordCount = false,
                ),
            ).content.items
        }
        val nextUp = items(userId, PlaybackQueueKind.NextUp) {
            api.tvShowsApi.getNextUp(
                GetNextUpRequest(
                    userId = userId,
                    limit = 20,
                    fields = listFields,
                    enableImages = true,
                    enableImageTypes = imageTypes,
                    enableUserData = true,
                    enableTotalRecordCount = false,
                ),
            ).content.items.withoutTubeArchivist()
        }
        val movies = latest(userId, BaseItemKind.MOVIE)
        val shows = latest(userId, BaseItemKind.SERIES)
        coroutineScope {
            val upcoming = async { upcomingEpisodes(userId) }
            val recommendations = async { movieRecommendations(userId) }
            val collections = async { collectionPreview(userId, limit = 24) }
            val genres = async { homeGenres(userId) }
            val watched = async { recentlyWatched(userId) }
            val heroPool = async {
                when (hero) {
                    HeroContent.Random -> randomTitles(userId)
                    HeroContent.Favorites -> favoriteTitles(userId)
                    else -> emptyList()
                }
            }
            val feed = HomeFeed(
                continueWatching = resume,
                nextUp = nextUp,
                recentMovies = movies,
                recentShows = shows,
                upcoming = upcoming.await(),
                recommendations = recommendations.await(),
                collections = collections.await(),
                genres = genres.await(),
                recentlyWatched = watched.await(),
            )
            feed.copy(featured = heroItems(feed, hero, heroPool.await()))
        }
    }

    /** Hero sources, mirroring iOS `FeaturedHeroContent`. */
    enum class HeroContent { RecentlyAdded, Random, ContinueWatching, NextUp, Recommendations, RecentlyWatched, Favorites }

    private fun heroItems(feed: HomeFeed, hero: HeroContent, pool: List<MediaItem>): List<MediaItem> {
        val recent = app.zelefin.client.ui.HomeHero.recentlyAdded(feed.recentMovies, feed.recentShows)
        val picked = when (hero) {
            HeroContent.RecentlyAdded -> recent
            HeroContent.Random, HeroContent.Favorites -> app.zelefin.client.ui.HomeHero.fromPool(pool)
            HeroContent.ContinueWatching -> app.zelefin.client.ui.HomeHero.fromPool(feed.continueWatching)
            HeroContent.NextUp -> app.zelefin.client.ui.HomeHero.fromPool(feed.nextUp)
            HeroContent.Recommendations -> app.zelefin.client.ui.HomeHero.fromPool(feed.recommendations.flatMap { it.items })
            HeroContent.RecentlyWatched -> app.zelefin.client.ui.HomeHero.fromPool(feed.recentlyWatched)
        }
        return picked.ifEmpty { recent }
    }

    private suspend fun upcomingEpisodes(userId: UUID): List<MediaItem> = items(userId, PlaybackQueueKind.NextUp) {
        api.tvShowsApi.getUpcomingEpisodes(
            userId = userId,
            limit = 20,
            fields = listFields,
            enableImages = true,
            enableImageTypes = imageTypes,
            enableUserData = true,
        ).content.items.withoutTubeArchivist()
    }

    private suspend fun movieRecommendations(userId: UUID): List<HomeSection> = runCatching {
        api.moviesApi.getMovieRecommendations(
            userId = userId,
            fields = listFields,
            categoryLimit = 5,
            itemLimit = 16,
        ).content.mapIndexedNotNull { index, row ->
            val items = row.items.orEmpty().mapNotNull { ItemMapper.mediaItem(it.toSnapshot()) }
            if (items.isEmpty()) return@mapIndexedNotNull null
            HomeSection(
                id = "recommend-${row.categoryId ?: index}",
                title = recommendationTitle(row.recommendationType, row.baselineItemName),
                style = HomeRowStyle.Portrait,
                items = items,
            )
        }
    }.getOrDefault(emptyList())

    private fun recommendationTitle(type: RecommendationType, baseline: String?): String {
        val name = baseline?.trim().orEmpty()
        return when (type) {
            RecommendationType.SIMILAR_TO_RECENTLY_PLAYED -> if (name.isEmpty()) "Because You Watched" else "Because You Watched $name"
            RecommendationType.SIMILAR_TO_LIKED_ITEM -> if (name.isEmpty()) "Because You Liked" else "Because You Liked $name"
            RecommendationType.HAS_DIRECTOR_FROM_RECENTLY_PLAYED, RecommendationType.HAS_LIKED_DIRECTOR ->
                if (name.isEmpty()) "More From This Director" else "Directed Like $name"
            RecommendationType.HAS_ACTOR_FROM_RECENTLY_PLAYED, RecommendationType.HAS_LIKED_ACTOR ->
                if (name.isEmpty()) "More From This Cast" else "Starring Like $name"
        }
    }

    private suspend fun homeGenres(userId: UUID): List<MediaItem> = runCatching {
        genres(userId, limit = 48)
            .filter { isBrowsableGenre(it.name) }
            .distinctBy { genre -> genre.name.lowercase().filter { it.isLetterOrDigit() } }
            .take(24)
            .map { MediaItem(id = it.id, name = it.name, kind = MediaKind.Genre) }
    }.getOrDefault(emptyList())

    /** Played movies and episodes, newest first, one card per show (iOS `collapseRecentlyWatched`). */
    private suspend fun recentlyWatched(userId: UUID): List<MediaItem> = runCatching {
        val items = api.itemsApi.getItems(
            GetItemsRequest(
                userId = userId,
                recursive = true,
                includeItemTypes = listOf(BaseItemKind.MOVIE, BaseItemKind.EPISODE),
                filters = listOf(ItemFilter.IS_PLAYED),
                isPlayed = true,
                mediaTypes = listOf(MediaType.VIDEO),
                sortBy = listOf(ItemSortBy.DATE_PLAYED),
                sortOrder = listOf(SortOrder.DESCENDING),
                limit = 40,
                fields = listFields,
                enableUserData = true,
                enableImageTypes = imageTypes,
                enableTotalRecordCount = false,
            ),
        ).content.items.mapNotNull { ItemMapper.mediaItem(it.toSnapshot()) }
        val seenSeries = mutableSetOf<String>()
        items.filter { item ->
            val series = item.seriesId?.takeIf { item.kind == MediaKind.Episode }
            series == null || seenSeries.add(series)
        }.take(20)
    }.getOrDefault(emptyList())

    private suspend fun randomTitles(userId: UUID): List<MediaItem> = titleSample(userId, ItemSortBy.RANDOM, favorites = false)

    private suspend fun favoriteTitles(userId: UUID): List<MediaItem> = titleSample(userId, ItemSortBy.DATE_CREATED, favorites = true)

    private suspend fun titleSample(userId: UUID, sort: ItemSortBy, favorites: Boolean): List<MediaItem> = runCatching {
        api.itemsApi.getItems(
            GetItemsRequest(
                userId = userId,
                recursive = true,
                includeItemTypes = listOf(BaseItemKind.MOVIE, BaseItemKind.SERIES),
                filters = if (favorites) listOf(ItemFilter.IS_FAVORITE) else null,
                sortBy = listOf(sort),
                sortOrder = listOf(SortOrder.DESCENDING),
                limit = if (favorites) 48 else 24,
                fields = listFields,
                enableUserData = true,
                enableImageTypes = imageTypes,
                enableTotalRecordCount = false,
            ),
        ).content.items.withoutTubeArchivist().mapNotNull { ItemMapper.mediaItem(it.toSnapshot()) }
    }.getOrDefault(emptyList())

    /** Interface choices synced through Jellyfin display preferences, shared with iOS (`DisplayPreferencesSync`). */
    suspend fun displayPreferenceCustomPrefs(userId: UUID): Map<String, String> = withContext(Dispatchers.IO) {
        api.displayPreferencesApi.getDisplayPreferences(DisplayPreferencesId, userId, ClientName).content.customPrefs.orEmpty()
            .mapNotNull { (key, value) -> value?.let { key to it } }
            .toMap()
    }

    suspend fun updateDisplayPreferenceCustomPrefs(userId: UUID, prefs: Map<String, String>) = withContext(Dispatchers.IO) {
        val current = api.displayPreferencesApi.getDisplayPreferences(DisplayPreferencesId, userId, ClientName).content
        val merged = current.customPrefs.orEmpty().mapNotNull { (key, value) -> value?.let { key to it } }.toMap() + prefs
        api.displayPreferencesApi.updateDisplayPreferences(
            DisplayPreferencesId,
            userId,
            ClientName,
            current.copy(id = DisplayPreferencesId, client = ClientName, customPrefs = merged),
        )
    }

    suspend fun libraries(userId: UUID): List<LibraryRoom> = withContext(Dispatchers.IO) {
        val views = api.userViewsApi.getUserViews(userId = userId, includeHidden = true).content.items
        coroutineScope {
            views.map { dto ->
                async {
                    val name = dto.name?.trim().orEmpty()
                    if (name.isEmpty()) return@async null
                    val kind = libraryKind(dto.collectionType, name)
                    val youTube = kind == LibraryKind.Shows && isTubeArchivistLibrary(userId, dto.id)
                    LibraryRoom(id = dto.id.toString(), name = name, kind = if (youTube) LibraryKind.YouTube else kind)
                }
            }.awaitAll().filterNotNull()
        }
    }

    /** A Shows library whose series carry the TubeArchivist provider ID (TubeArchivist Metadata plugin). */
    private suspend fun isTubeArchivistLibrary(userId: UUID, libraryId: UUID): Boolean = runCatching {
        api.itemsApi.getItems(
            GetItemsRequest(
                userId = userId,
                parentId = libraryId,
                recursive = true,
                includeItemTypes = listOf(BaseItemKind.SERIES),
                limit = 1,
                fields = listOf(ItemFields.PROVIDER_IDS),
                enableImages = false,
                enableUserData = false,
                enableTotalRecordCount = false,
            ),
        ).content.items.any { it.isTubeArchivist() }
    }.getOrDefault(false)

    /** Channel and video totals across the given YouTube libraries. */
    suspend fun youTubeCounts(userId: UUID, rooms: List<LibraryRoom>): LibraryCounts = withContext(Dispatchers.IO) {
        coroutineScope {
            rooms.filter { it.kind == LibraryKind.YouTube }
                .map { room -> async { roomCounts(userId, room) } }
                .awaitAll()
                .fold(LibraryCounts()) { sum, next ->
                    sum.copy(channels = sum.channels + next.channels, videos = sum.videos + next.videos)
                }
        }
    }

    fun scope(room: LibraryRoom): JellyfinScope = JellyfinScope(
        kinds = when (room.kind) {
            LibraryKind.Movies -> listOf(BaseItemKind.MOVIE, BaseItemKind.BOX_SET)
            LibraryKind.Shows, LibraryKind.YouTube -> listOf(BaseItemKind.SERIES)
            LibraryKind.Collections -> listOf(BaseItemKind.BOX_SET)
            LibraryKind.Books -> listOf(BaseItemKind.BOOK)
            LibraryKind.Photos -> listOf(BaseItemKind.PHOTO, BaseItemKind.PHOTO_ALBUM)
            LibraryKind.LiveTV -> listOf(BaseItemKind.TV_CHANNEL)
            LibraryKind.Playlists -> listOf(BaseItemKind.PLAYLIST)
            LibraryKind.HomeVideos -> listOf(BaseItemKind.VIDEO, BaseItemKind.MOVIE)
            else -> listOf(BaseItemKind.MOVIE, BaseItemKind.SERIES)
        },
        parentId = room.id,
    )

    suspend fun serverCounts(userId: UUID): LibraryCounts = withContext(Dispatchers.IO) {
        runCatching {
            val counts = api.libraryApi.getItemCounts(userId = userId).content
            LibraryCounts(counts.movieCount ?: 0, counts.seriesCount ?: 0, counts.episodeCount ?: 0)
        }.getOrElse {
            LibraryCounts(
                countItems(userId, listOf(BaseItemKind.MOVIE), null),
                countItems(userId, listOf(BaseItemKind.SERIES), null),
                countItems(userId, listOf(BaseItemKind.EPISODE), null),
            )
        }
    }

    suspend fun roomCounts(userId: UUID, room: LibraryRoom): LibraryCounts = withContext(Dispatchers.IO) {
        val movies = suspend { countItems(userId, listOf(BaseItemKind.MOVIE), room.id) }
        val shows = suspend { countItems(userId, listOf(BaseItemKind.SERIES), room.id) }
        val episodes = suspend { countItems(userId, listOf(BaseItemKind.EPISODE), room.id) }
        when (room.kind) {
            LibraryKind.Movies -> LibraryCounts(movies = movies())
            LibraryKind.Shows -> LibraryCounts(shows = shows(), episodes = episodes())
            LibraryKind.YouTube -> LibraryCounts(channels = shows(), videos = episodes())
            LibraryKind.LiveTV -> LibraryCounts()
            else -> LibraryCounts(movies(), shows(), episodes())
        }
    }

    private suspend fun countItems(userId: UUID, kinds: List<BaseItemKind>, parentId: String?): Int = runCatching {
        api.itemsApi.getItems(
            GetItemsRequest(
                userId = userId,
                parentId = parentId?.let(UUID::fromString),
                recursive = true,
                includeItemTypes = kinds,
                limit = 0,
                enableTotalRecordCount = true,
            ),
        ).content.totalRecordCount
    }.getOrDefault(0)

    suspend fun previewItems(userId: UUID, room: LibraryRoom, limit: Int = 8): List<MediaItem> = withContext(Dispatchers.IO) {
        runCatching {
            api.itemsApi.getItems(
                GetItemsRequest(
                    userId = userId,
                    parentId = UUID.fromString(room.id),
                    recursive = true,
                    includeItemTypes = scope(room).kinds,
                    sortBy = listOf(ItemSortBy.DATE_CREATED),
                    sortOrder = listOf(SortOrder.DESCENDING),
                    limit = limit,
                    fields = listFields,
                    enableUserData = true,
                    enableImageTypes = imageTypes,
                    enableTotalRecordCount = false,
                ),
            ).content.items.mapNotNull { ItemMapper.mediaItem(it.toSnapshot()) }
        }.getOrDefault(emptyList())
    }

    suspend fun genres(userId: UUID, limit: Int? = null): List<LibraryGenre> = withContext(Dispatchers.IO) {
        api.genresApi.getGenres(
            GetGenresRequest(
                userId = userId,
                limit = limit,
                includeItemTypes = listOf(BaseItemKind.MOVIE, BaseItemKind.SERIES),
                sortBy = listOf(ItemSortBy.SORT_NAME),
                enableImages = false,
                enableTotalRecordCount = false,
            ),
        ).content.items.mapNotNull { dto ->
            val name = dto.name?.trim().orEmpty()
            if (name.isEmpty()) null else LibraryGenre(dto.id.toString(), name)
        }
    }

    suspend fun tmdbCatalog(userId: UUID): JellyfinTmdbCatalog = withContext(Dispatchers.IO) {
        val items = api.itemsApi.getItems(
            GetItemsRequest(
                userId = userId,
                recursive = true,
                includeItemTypes = listOf(BaseItemKind.MOVIE, BaseItemKind.SERIES),
                fields = listOf(ItemFields.PROVIDER_IDS),
                enableImages = false,
                enableUserData = false,
                enableTotalRecordCount = false,
            ),
        ).content.items
        val movies = mutableSetOf<Int>()
        val series = mutableSetOf<Int>()
        items.forEach { dto ->
            val ids = dto.providerIds?.mapNotNull { (key, value) -> value?.let { key to it } }?.toMap()
            val tmdb = JellyfinTmdbCatalog.tmdbId(ids) ?: return@forEach
            if (dto.type == BaseItemKind.SERIES) series += tmdb else movies += tmdb
        }
        JellyfinTmdbCatalog(movies, series)
    }

    suspend fun searchHints(userId: UUID, term: String): List<SearchHit> = withContext(Dispatchers.IO) {
        val trimmed = term.trim()
        if (trimmed.isEmpty()) return@withContext emptyList()
        val hints = api.searchApi.getSearchHints(
            limit = 24,
            userId = userId,
            searchTerm = trimmed,
            includeItemTypes = listOf(
                BaseItemKind.MOVIE, BaseItemKind.SERIES, BaseItemKind.EPISODE, BaseItemKind.BOX_SET,
                BaseItemKind.PERSON, BaseItemKind.GENRE, BaseItemKind.STUDIO, BaseItemKind.TV_CHANNEL,
            ),
            includePeople = true,
            includeMedia = true,
            includeGenres = true,
            includeStudios = true,
            includeArtists = false,
        ).content.searchHints
        val seen = mutableSetOf<String>()
        hints.mapNotNull { hint ->
            val hit = searchHit(hint) ?: return@mapNotNull null
            if (seen.add(hit.id)) hit else null
        }
    }

    private fun searchHit(hint: SearchHint): SearchHit? {
        val id = hint.id.toString()
        val name = hint.name?.takeIf { it.isNotBlank() } ?: return null
        val (kind, mediaKind) = when (hint.type) {
            BaseItemKind.MOVIE -> SearchHitKind.Title to MediaKind.Movie
            BaseItemKind.SERIES -> SearchHitKind.Title to MediaKind.Series
            BaseItemKind.EPISODE -> SearchHitKind.Title to MediaKind.Episode
            BaseItemKind.BOX_SET -> SearchHitKind.Title to MediaKind.Collection
            BaseItemKind.TV_CHANNEL, BaseItemKind.LIVE_TV_PROGRAM, BaseItemKind.TV_PROGRAM -> SearchHitKind.Title to MediaKind.LiveTV
            BaseItemKind.PERSON -> SearchHitKind.Person to MediaKind.Unknown
            BaseItemKind.GENRE -> if (isBrowsableGenre(name)) SearchHitKind.Genre to MediaKind.Genre else return null
            BaseItemKind.STUDIO -> SearchHitKind.Studio to MediaKind.Unknown
            else -> return null
        }
        val label = when (kind) {
            SearchHitKind.Title -> when (mediaKind) {
                MediaKind.Movie -> "Movie"
                MediaKind.Series -> "Show"
                MediaKind.Episode -> hint.series ?: "Episode"
                MediaKind.Collection -> "Collection"
                MediaKind.LiveTV -> "Live TV"
                else -> "Title"
            }
            SearchHitKind.Person -> "Person"
            SearchHitKind.Genre -> "Genre"
            SearchHitKind.Studio -> "Studio"
        }
        val item = MediaItem(
            id = id,
            name = name,
            kind = mediaKind,
            year = hint.productionYear,
            seriesName = hint.series,
            primaryImageTag = hint.primaryImageTag,
        )
        return SearchHit(
            id = id,
            name = name,
            subtitle = listOfNotNull(label, hint.productionYear?.toString()).joinToString(" · "),
            kind = kind,
            item = item,
        )
    }

    suspend fun collectionPreview(userId: UUID, limit: Int = 12): List<MediaItem> = withContext(Dispatchers.IO) {
        runCatching {
            api.itemsApi.getItems(
                GetItemsRequest(
                    userId = userId,
                    recursive = true,
                    includeItemTypes = listOf(BaseItemKind.BOX_SET),
                    sortBy = listOf(ItemSortBy.SORT_NAME),
                    sortOrder = listOf(SortOrder.ASCENDING),
                    limit = limit,
                    fields = listFields,
                    enableUserData = true,
                    enableImageTypes = imageTypes,
                    enableTotalRecordCount = false,
                ),
            ).content.items.mapNotNull { ItemMapper.mediaItem(it.toSnapshot()) }
        }.getOrDefault(emptyList())
    }

    suspend fun catalog(
        userId: UUID,
        kind: BaseItemKind,
        query: CatalogBrowseQuery = CatalogBrowseQuery(),
        onPage: (List<MediaItem>) -> Unit = {},
    ): List<MediaItem> = browse(userId, JellyfinScope(listOf(kind)), query, onPage)

    suspend fun browse(
        userId: UUID,
        scope: JellyfinScope,
        query: CatalogBrowseQuery = CatalogBrowseQuery(),
        onPage: (List<MediaItem>) -> Unit = {},
    ): List<MediaItem> = withContext(Dispatchers.IO) {
        val passes = query.resolutionPasses()
        if (passes.size == 1) {
            val (isHd, is4k) = passes.first()
            val items = catalogPass(userId, scope, query, isHd, is4k, onPage)
            return@withContext if (query.sort == CatalogSortField.Random) items.shuffled() else items
        }
        val merged = LinkedHashMap<String, MediaItem>()
        for ((isHd, is4k) in passes) {
            for (item in catalogPass(userId, scope, query, isHd, is4k) {}) {
                merged.putIfAbsent(item.id, item)
            }
            onPage(merged.values.toList())
        }
        merged.values.toList()
    }

    suspend fun catalogFilters(userId: UUID, kind: BaseItemKind): CatalogFilterOptions =
        catalogFilters(userId, JellyfinScope(listOf(kind)))

    suspend fun catalogFilters(userId: UUID, scope: JellyfinScope): CatalogFilterOptions = withContext(Dispatchers.IO) {
        val kinds = scope.kinds.takeIf { it.isNotEmpty() }
        val parent = scope.parentId?.let(UUID::fromString)
        val filters = runCatching {
            api.filterApi.getQueryFiltersLegacy(userId = userId, parentId = parent, includeItemTypes = kinds).content
        }.getOrNull()
        val studios = runCatching {
            api.studiosApi.getStudios(
                GetStudiosRequest(
                    userId = userId,
                    parentId = parent,
                    includeItemTypes = kinds,
                    enableImages = false,
                    enableTotalRecordCount = false,
                ),
            ).content.items.mapNotNull { it.name?.trim()?.takeIf { name -> name.isNotEmpty() } }
        }.getOrDefault(emptyList())
        val languages = runCatching {
            api.localizationApi.getCultures().content.mapNotNull { it.toChoice() }
        }.getOrDefault(emptyList()).sortedBy { it.name.lowercase() }
        CatalogFilterOptions(
            genres = filters?.genres.orEmpty().toChoices(),
            officialRatings = filters?.officialRatings.orEmpty().toChoices(),
            tags = filters?.tags.orEmpty().toChoices(),
            years = filters?.years.orEmpty().sortedDescending().map { CatalogFilterChoice(it.toString(), it.toString()) },
            studios = studios.distinct().sortedBy { it.lowercase() }.map { CatalogFilterChoice(it, it) },
            languages = languages,
        )
    }

    private suspend fun catalogPass(
        userId: UUID,
        scope: JellyfinScope,
        query: CatalogBrowseQuery,
        isHd: Boolean?,
        is4k: Boolean?,
        onPage: (List<MediaItem>) -> Unit,
    ): List<MediaItem> {
        val audio = query.audioLanguages.takeIf { it.isNotEmpty() }?.sorted()?.joinToString(",")
        val subtitles = query.subtitleLanguages.takeIf { it.isNotEmpty() }?.sorted()?.joinToString(",")
        val collected = LinkedHashMap<String, MediaItem>()
        var start = 0
        while (start < CatalogMaxItems) {
            val request = catalogRequest(userId, scope, query, isHd, is4k, start)
            val page = try {
                if (audio == null && subtitles == null) {
                    api.itemsApi.getItems(request).content
                } else {
                    api.get<BaseItemDtoQueryResult>(
                        "/Items",
                        pathParameters = emptyMap(),
                        queryParameters = catalogQueryParameters(request, audio, subtitles),
                    ).content
                }
            } catch (error: Exception) {
                if (collected.isEmpty()) throw error
                break
            }
            if (page.items.isEmpty()) break
            val rows = if (scope.parentId == null) page.items.withoutTubeArchivist() else page.items
            for (item in rows.mapNotNull { ItemMapper.mediaItem(it.toSnapshot()) }) {
                collected.putIfAbsent(item.id, item)
            }
            onPage(collected.values.toList())
            val fetched = page.items.size
            val next = start + fetched
            val total = page.totalRecordCount
            val finished = if (total > 0) {
                next >= total
            } else {
                fetched < CatalogPageSize
            }
            if (finished || next == start) break
            start = next
        }
        return collected.values.toList()
    }

    private fun catalogRequest(
        userId: UUID,
        scope: JellyfinScope,
        query: CatalogBrowseQuery,
        isHd: Boolean?,
        is4k: Boolean?,
        start: Int,
    ): GetItemsRequest {
        val played = CatalogStatusFilter.Played in query.statuses
        val unplayed = CatalogStatusFilter.Unplayed in query.statuses
        val filters = buildList {
            if (played && !unplayed) add(ItemFilter.IS_PLAYED)
            if (unplayed && !played) add(ItemFilter.IS_UNPLAYED)
            if (CatalogStatusFilter.Favorite in query.statuses) add(ItemFilter.IS_FAVORITE)
            if (CatalogStatusFilter.ContinueWatching in query.statuses) add(ItemFilter.IS_RESUMABLE)
        }
        val discs = query.videoKinds.mapNotNull { kind ->
            when (kind) {
                CatalogVideoKind.Dvd -> VideoType.DVD
                CatalogVideoKind.BluRay -> VideoType.BLU_RAY
                CatalogVideoKind.Iso -> VideoType.ISO
                else -> null
            }
        }
        return GetItemsRequest(
            userId = userId,
            parentId = scope.parentId?.let(UUID::fromString),
            recursive = true,
            includeItemTypes = scope.kinds.takeIf { it.isNotEmpty() },
            genreIds = scope.genreIds.map(UUID::fromString).takeIf { it.isNotEmpty() },
            personIds = scope.personIds.map(UUID::fromString).takeIf { it.isNotEmpty() },
            studioIds = scope.studioIds.map(UUID::fromString).takeIf { it.isNotEmpty() },
            sortBy = listOf(query.sort.toItemSort()),
            sortOrder = if (query.sort.allowsDirection) {
                listOf(if (query.sortAscending) SortOrder.ASCENDING else SortOrder.DESCENDING)
            } else {
                null
            },
            startIndex = start,
            limit = CatalogPageSize,
            filters = filters.takeIf { it.isNotEmpty() },
            hasSubtitles = true.takeIf { CatalogFeatureFilter.Subtitles in query.features },
            hasTrailer = true.takeIf { CatalogFeatureFilter.Trailers in query.features },
            hasSpecialFeature = true.takeIf { CatalogFeatureFilter.Extras in query.features },
            hasThemeSong = true.takeIf { CatalogFeatureFilter.ThemeSongs in query.features },
            hasThemeVideo = true.takeIf { CatalogFeatureFilter.ThemeVideos in query.features },
            isHd = isHd,
            is4k = is4k,
            is3d = true.takeIf { CatalogVideoKind.ThreeD in query.videoKinds },
            videoTypes = discs.takeIf { it.isNotEmpty() },
            genres = query.genres.sorted().takeIf { it.isNotEmpty() },
            officialRatings = query.officialRatings.sorted().takeIf { it.isNotEmpty() },
            tags = query.tags.sorted().takeIf { it.isNotEmpty() },
            years = query.years.sorted().takeIf { it.isNotEmpty() },
            studios = query.studios.sorted().takeIf { it.isNotEmpty() },
            fields = catalogFields,
            enableUserData = true,
            enableImageTypes = imageTypes,
            enableTotalRecordCount = true,
        )
    }

    private fun catalogQueryParameters(request: GetItemsRequest, audio: String?, subtitles: String?): Map<String, Any?> =
        buildMap {
            put("userId", request.userId)
            put("parentId", request.parentId)
            put("genreIds", request.genreIds)
            put("personIds", request.personIds)
            put("studioIds", request.studioIds)
            put("startIndex", request.startIndex)
            put("limit", request.limit)
            put("recursive", request.recursive)
            put("includeItemTypes", request.includeItemTypes)
            put("sortBy", request.sortBy)
            put("sortOrder", request.sortOrder)
            put("filters", request.filters)
            put("fields", request.fields)
            put("enableUserData", request.enableUserData)
            put("enableImageTypes", request.enableImageTypes)
            put("enableTotalRecordCount", request.enableTotalRecordCount)
            put("hasSubtitles", request.hasSubtitles)
            put("hasTrailer", request.hasTrailer)
            put("hasSpecialFeature", request.hasSpecialFeature)
            put("hasThemeSong", request.hasThemeSong)
            put("hasThemeVideo", request.hasThemeVideo)
            put("isHd", request.isHd)
            put("is4K", request.is4k)
            put("is3D", request.is3d)
            put("videoTypes", request.videoTypes)
            put("genres", request.genres)
            put("officialRatings", request.officialRatings)
            put("tags", request.tags)
            put("years", request.years)
            put("studios", request.studios)
            put("audioLanguages", audio)
            put("subtitleLanguages", subtitles)
        }

    suspend fun mediaItem(userId: UUID, id: String): MediaItem? = withContext(Dispatchers.IO) {
        val dto = runCatching { api.userLibraryApi.getItem(UUID.fromString(id), userId).content }.getOrNull() ?: return@withContext null
        ItemMapper.mediaItem(dto.toSnapshot())
    }

    /** Movies and episodes play as-is. A series or season resolves to the resume / next episode. */
    suspend fun playableItem(userId: UUID, item: MediaItem): MediaItem = withContext(Dispatchers.IO) {
        if (item.kind != MediaKind.Series && item.kind != MediaKind.Season) return@withContext item
        val seriesId = if (item.kind == MediaKind.Season) item.seriesId ?: item.id else item.id
        val episodeDtos = api.tvShowsApi.getEpisodes(
            GetEpisodesRequest(
                seriesId = UUID.fromString(seriesId),
                userId = userId,
                fields = listFields,
                enableUserData = true,
                enableImageTypes = imageTypes,
            ),
        ).content.items ?: emptyList()
        val episodes = MediaItem.orderedEpisodes(episodeDtos.mapNotNull { ItemMapper.mediaItem(it.toSnapshot()) })
        val hero = MediaItem.heroPlaybackItem(item, episodes)
        if (hero.kind != MediaKind.Episode) {
            throw ZelefinException.server("This show has no playable episodes.")
        }
        hero
    }

    suspend fun detail(userId: UUID, id: String): TitleDetail = withContext(Dispatchers.IO) {
        val itemId = UUID.fromString(id)
        val dto = api.userLibraryApi.getItem(itemId, userId).content
        val item = ItemMapper.mediaItem(dto.toSnapshot()) ?: throw ZelefinException.server("This title could not be read.")
        if (item.isYouTube) return@withContext youTubeDetail(userId, dto, item)
        val episodeDtos = if (item.kind == MediaKind.Series) {
            api.tvShowsApi.getEpisodes(
                GetEpisodesRequest(
                    seriesId = itemId,
                    userId = userId,
                    fields = listFields,
                    enableUserData = true,
                    enableImageTypes = imageTypes,
                ),
            ).content.items
        } else {
            emptyList()
        }
        val episodes = episodeDtos.mapNotNull { ItemMapper.mediaItem(it.toSnapshot()) }
        val seasons = if (item.kind == MediaKind.Series) {
            api.tvShowsApi.getSeasons(
                GetSeasonsRequest(seriesId = itemId, userId = userId, enableUserData = true, fields = listFields),
            ).content.items.mapNotNull { ItemMapper.mediaItem(it.toSnapshot()) }
        } else {
            emptyList()
        }
        val related = runCatching {
            api.libraryApi.getSimilarItems(
                GetSimilarItemsRequest(itemId = itemId, userId = userId, limit = 12, fields = listFields),
            ).content.items.mapNotNull { ItemMapper.mediaItem(it.toSnapshot()) }
        }.getOrDefault(emptyList())
        val trailers = if (item.kind == MediaKind.Movie || item.kind == MediaKind.Series) trailers(userId, itemId, dto) else emptyList()
        val orderedEpisodes = MediaItem.orderedEpisodes(episodes)
        var facts = TitleFacts.from(dto, item)
        if (facts.languages.isEmpty() && facts.file.isEmpty()) {
            val hero = MediaItem.heroPlaybackItem(item, orderedEpisodes)
            val heroDto = episodeDtos.firstOrNull { it.id?.toString() == hero.id }
            if (heroDto != null) facts = facts.withMedia(TitleFacts.from(heroDto, hero))
        }
        val parts = if (item.kind == MediaKind.Movie) additionalParts(userId, id) else emptyList()
        TitleDetail(
            item = item,
            seasons = seasons,
            episodes = orderedEpisodes,
            related = related,
            trailers = trailers,
            moreInfo = facts,
            additionalParts = parts,
        )
    }

    /** A TubeArchivist channel or video page: the channel plus every video, newest first. */
    private suspend fun youTubeDetail(userId: UUID, dto: BaseItemDto, item: MediaItem): TitleDetail = coroutineScope {
        val channelId = if (item.kind == MediaKind.Series) item.id else item.seriesId
        val channel = async {
            when {
                item.kind == MediaKind.Series -> item
                channelId == null -> null
                else -> runCatching { api.userLibraryApi.getItem(UUID.fromString(channelId), userId).content }
                    .getOrNull()?.let { ItemMapper.mediaItem(it.toSnapshot()) }
            }
        }
        val videos = async {
            if (channelId == null) return@async emptyList()
            runCatching {
                api.tvShowsApi.getEpisodes(
                    GetEpisodesRequest(
                        seriesId = UUID.fromString(channelId),
                        userId = userId,
                        fields = listFields,
                        enableUserData = true,
                        enableImageTypes = imageTypes,
                    ),
                ).content.items.mapNotNull { ItemMapper.mediaItem(it.toSnapshot()) }
            }.getOrDefault(emptyList())
                .sortedWith(compareByDescending<MediaItem> { it.premiereDate.orEmpty() }.thenByDescending { it.episodeIndex ?: 0 })
        }
        val channelVideos = videos.await()
        TitleDetail(
            item = item,
            episodes = if (item.kind == MediaKind.Series) MediaItem.orderedEpisodes(channelVideos) else emptyList(),
            moreInfo = TitleFacts.from(dto, item),
            channel = channel.await(),
            channelVideos = channelVideos,
        )
    }

    /**
     * A title lists a person without a Primary tag until Jellyfin has refreshed that person.
     * Reading the person item is what makes Jellyfin fetch the portrait on demand, so this does
     * what tapping each cast member used to do and reports every batch so the row fills in.
     */
    suspend fun peopleWithPhotos(
        userId: UUID,
        people: List<CreditPerson>,
        onBatch: suspend (List<CreditPerson>) -> Unit,
    ) {
        val missing = people.filter { it.imageTag.isNullOrBlank() && it.imageUrl.isNullOrBlank() && it.id.isNotBlank() }
        if (missing.isEmpty()) return
        val found = mutableMapOf<String, CreditPerson>()
        for (batch in missing.chunked(6)) {
            val rows = coroutineScope {
                batch.map { person ->
                    async { person.id to runCatching { person(userId, person.id) }.getOrNull() }
                }.awaitAll()
            }
            var changed = false
            rows.forEach { (id, profile) ->
                if (profile != null && !profile.imageTag.isNullOrBlank()) {
                    found[id] = profile
                    changed = true
                }
            }
            if (!changed) continue
            onBatch(
                people.map { person ->
                    val profile = found[person.id] ?: return@map person
                    person.copy(imageTag = profile.imageTag, overview = profile.overview, birthYear = profile.birthYear)
                },
            )
        }
    }

    suspend fun person(userId: UUID, id: String): CreditPerson? = withContext(Dispatchers.IO) {
        val dto = runCatching { api.userLibraryApi.getItem(UUID.fromString(id), userId).content }.getOrNull() ?: return@withContext null
        val snapshot = dto.toSnapshot()
        val personName = snapshot.name?.trim().orEmpty()
        if (personName.isEmpty()) return@withContext null
        CreditPerson(
            id = snapshot.id ?: id,
            name = personName,
            roleLabel = "Cast & Crew",
            imageTag = snapshot.primaryImageTag,
            overview = snapshot.overview?.trim()?.ifEmpty { null },
            birthYear = snapshot.productionYear,
        )
    }

    private suspend fun trailers(userId: UUID, itemId: UUID, dto: org.jellyfin.sdk.model.api.BaseItemDto): List<TitleTrailer> {
        val local = runCatching { api.userLibraryApi.getLocalTrailers(itemId = itemId, userId = userId).content }
            .getOrDefault(emptyList())
            .mapNotNull { ItemMapper.mediaItem(it.toSnapshot()) }
        if (local.isNotEmpty()) {
            return local.map { trailer ->
                TitleTrailer(id = "jf-${trailer.id}", title = trailer.name, caption = "From your server", localItem = trailer)
            }
        }
        val seen = linkedSetOf<String>()
        return dto.remoteTrailers.orEmpty().mapNotNull { remote ->
            val trailer = TrailerLinks.remote(remote.url, remote.name) ?: return@mapNotNull null
            if (!seen.add(trailer.id)) null else trailer
        }
    }

    /**
     * [bitrate] turns the source file bitrate (when known) into the stream cap, so adaptive
     * bitrate can Direct Play files that fit. Language preferences pick the audio / subtitle
     * streams Jellyfin bakes into a transcode.
     */
    suspend fun playback(
        userId: UUID,
        item: MediaItem,
        audioLanguage: String = app.zelefin.client.PlaybackPreferences.AUTOMATIC,
        subtitleLanguage: String = app.zelefin.client.PlaybackPreferences.AUTOMATIC,
        preferSdh: Boolean = false,
        bitrate: suspend (sourceBitrate: Int?) -> Int = { MAX_BITRATE },
    ): PlaybackPlan = withContext(Dispatchers.IO) {
        val target = item
        val resume = if (target.playbackPosition > PlaybackResumePolicy.THRESHOLD) target.playbackPosition else 0.0
        val itemDto = runCatching { api.userLibraryApi.getItem(UUID.fromString(target.id), userId).content }.getOrNull()
        val firstSource = itemDto?.mediaSources?.firstOrNull()
        val streams = firstSource?.mediaStreams ?: itemDto?.mediaStreams.orEmpty()
        val sourceBitrate = firstSource?.bitrate?.takeIf { it > 0 }
            ?: streams.filter { it.type == MediaStreamType.VIDEO || it.type == MediaStreamType.AUDIO }
                .sumOf { it.bitRate ?: 0 }.takeIf { it > 0 }
        fun languageTracks(type: MediaStreamType, defaultIndex: Int?, sourceStreams: List<org.jellyfin.sdk.model.api.MediaStream> = streams) =
            sourceStreams.filter { it.type == type }.map { stream ->
                app.zelefin.client.LanguageTrack(
                    index = stream.index,
                    language = stream.language,
                    // A user-scoped source already applied the user's Jellyfin settings; a null default
                    // there means "none", not "fall back to the file's flag".
                    isSelected = if (firstSource != null) stream.index == defaultIndex else stream.isDefault,
                    title = stream.displayTitle ?: stream.title.orEmpty(),
                    isHearingImpaired = stream.isHearingImpaired == true,
                )
            }
        val audioIndex = app.zelefin.client.PlaybackLanguage.audioIndex(
            languageTracks(MediaStreamType.AUDIO, firstSource?.defaultAudioStreamIndex),
            audioLanguage,
        )
        val subtitleIndex = app.zelefin.client.PlaybackLanguage.subtitleIndex(
            languageTracks(MediaStreamType.SUBTITLE, firstSource?.defaultSubtitleStreamIndex),
            subtitleLanguage,
        )
        val maxBitrate = bitrate(sourceBitrate).coerceIn(1, MAX_BITRATE)
        val explicitSubtitle = subtitleLanguage != app.zelefin.client.PlaybackPreferences.AUTOMATIC &&
            subtitleLanguage.isNotEmpty()
        val preferences = runCatching { playbackPreferences() }.getOrNull()
        val itemSubtitleTracks = languageTracks(MediaStreamType.SUBTITLE, firstSource?.defaultSubtitleStreamIndex)
        val plannedSubtitle = when {
            subtitleLanguage == app.zelefin.client.PlaybackPreferences.OFF -> -1
            explicitSubtitle -> subtitleIndex
            else -> app.zelefin.client.PlaybackLanguage.startingSubtitleIndex(
                tracks = itemSubtitleTracks,
                serverIndex = firstSource?.defaultSubtitleStreamIndex,
                mode = preferences?.subtitleMode ?: org.jellyfin.sdk.model.api.SubtitlePlaybackMode.DEFAULT,
                preferredLanguage = preferences?.subtitleLanguage.orEmpty(),
                audioLanguage = languageTracks(MediaStreamType.AUDIO, firstSource?.defaultAudioStreamIndex)
                    .firstOrNull { it.index == audioIndex }?.language,
                preferSdh = preferSdh,
                deviceLanguage = java.util.Locale.getDefault().language,
            )
        }
        val response = api.mediaInfoApi.getPostedPlaybackInfo(
            itemId = UUID.fromString(target.id),
            data = PlaybackInfoDto(
                userId = userId,
                maxStreamingBitrate = maxBitrate,
                startTimeTicks = app.zelefin.core.TickClock.ticks(resume),
                audioStreamIndex = audioIndex,
                subtitleStreamIndex = when {
                    subtitleLanguage == app.zelefin.client.PlaybackPreferences.OFF -> -1
                    explicitSubtitle -> subtitleIndex
                    plannedSubtitle != null -> plannedSubtitle
                    else -> null
                },
                deviceProfile = deviceProfile(maxBitrate),
                enableDirectPlay = true,
                enableDirectStream = true,
                enableTranscoding = true,
                autoOpenLiveStream = true,
            ),
        ).content
        val source = response.mediaSources.firstOrNull() ?: throw ZelefinException.server("The server did not return a playable stream.")
        val method = when {
            source.supportsDirectPlay -> PlaybackMethod.DirectPlay
            source.supportsDirectStream && !source.transcodingUrl.isNullOrBlank() -> PlaybackMethod.Remux
            source.supportsTranscoding -> PlaybackMethod.Transcode
            else -> PlaybackMethod.DirectPlay
        }
        val base = api.baseUrl ?: throw ZelefinException.missingStreamUrl()
        val rawUrl = if (method != PlaybackMethod.DirectPlay && !source.transcodingUrl.isNullOrBlank()) {
            StreamUrlBuilder.transcode(base, source.transcodingUrl!!, api.accessToken)
        } else {
            StreamUrlBuilder.directPlay(
                base = base,
                itemId = target.id,
                sourceId = source.id,
                token = api.accessToken,
                container = source.container?.ifBlank { null } ?: "mkv",
            )
        } ?: throw ZelefinException.missingStreamUrl()
        val url = StreamResumeUrl.strippingStartTimeTicks(rawUrl)
        val chapters = runCatching {
            (itemDto ?: api.userLibraryApi.getItem(UUID.fromString(target.id), userId).content).chapters.orEmpty()
                .mapIndexedNotNull { index, chapter ->
                    val ticks = chapter.startPositionTicks
                    app.zelefin.core.PlaybackChapter(
                        startSeconds = app.zelefin.core.TickClock.seconds(ticks),
                        name = chapter.name?.takeIf { it.isNotBlank() } ?: "Chapter ${index + 1}",
                    )
                }
                .sortedBy { it.startSeconds }
        }.getOrDefault(emptyList())
        // Direct play already carries embedded tracks, so only sideload files that live beside the video.
        val externalSubtitles = source.mediaStreams.orEmpty()
            .filter { it.type == MediaStreamType.SUBTITLE && it.deliveryMethod == SubtitleDeliveryMethod.EXTERNAL }
            .filter { method != PlaybackMethod.DirectPlay || it.isExternal }
            .mapNotNull { stream ->
                val path = stream.deliveryUrl?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
                val mime = when (stream.codec?.lowercase()) {
                    "srt", "subrip" -> androidx.media3.common.MimeTypes.APPLICATION_SUBRIP
                    "vtt", "webvtt" -> androidx.media3.common.MimeTypes.TEXT_VTT
                    "ass", "ssa" -> androidx.media3.common.MimeTypes.TEXT_SSA
                    else -> return@mapNotNull null
                }
                val subtitleUrl = ServerUrl.resolve(base, path, api.accessToken) ?: return@mapNotNull null
                app.zelefin.core.ExternalSubtitle(
                    url = subtitleUrl,
                    mimeType = mime,
                    language = stream.language,
                    title = stream.displayTitle ?: stream.title ?: stream.language ?: "Subtitle",
                    id = externalSubtitleId(stream.index),
                )
            }
        // The server echoes the streams it settled on after applying this user's Jellyfin
        // settings, so these are what the player must start with on a Direct Play too.
        val playbackStreams = source.mediaStreams.orEmpty()
        val sourceStreams = if (playbackStreams.any { it.type == MediaStreamType.SUBTITLE } || streams.none { it.type == MediaStreamType.SUBTITLE }) {
            playbackStreams.ifEmpty { streams }
        } else {
            val merged = playbackStreams.associateBy { it.index }.toMutableMap()
            streams.forEach { stream -> if (stream.index !in merged) merged[stream.index] = stream }
            merged.values.sortedBy { it.index }
        }
        val chosenAudio = source.defaultAudioStreamIndex ?: audioIndex
        val subtitleTracks = languageTracks(
            MediaStreamType.SUBTITLE,
            source.defaultSubtitleStreamIndex,
            sourceStreams,
        ).ifEmpty { itemSubtitleTracks }
        val audioLanguageCode = languageTracks(
            MediaStreamType.AUDIO,
            source.defaultAudioStreamIndex,
            sourceStreams,
        ).firstOrNull { it.index == chosenAudio }?.language
        val serverSubtitle = when {
            subtitleLanguage == app.zelefin.client.PlaybackPreferences.OFF -> null
            explicitSubtitle -> subtitleIndex?.takeIf { it >= 0 }
            else -> source.defaultSubtitleStreamIndex?.takeIf { it >= 0 } ?: plannedSubtitle?.takeIf { it >= 0 }
        }
        val chosenSubtitle = when {
            subtitleLanguage == app.zelefin.client.PlaybackPreferences.OFF -> -1
            else -> app.zelefin.client.PlaybackLanguage.startingSubtitleIndex(
                tracks = subtitleTracks,
                serverIndex = serverSubtitle,
                mode = preferences?.subtitleMode ?: org.jellyfin.sdk.model.api.SubtitlePlaybackMode.DEFAULT,
                preferredLanguage = preferences?.subtitleLanguage.orEmpty(),
                audioLanguage = audioLanguageCode,
                preferSdh = preferSdh,
                deviceLanguage = java.util.Locale.getDefault().language,
                forcedByUser = explicitSubtitle,
            )
        }
        PlaybackPlan(
            item = target,
            streamUrl = url,
            playSessionId = response.playSessionId,
            mediaSourceId = source.id,
            method = method,
            container = source.container,
            videoCodec = source.mediaStreams?.firstOrNull { it.type == MediaStreamType.VIDEO }?.codec,
            startTimeSeconds = resume,
            headers = app.zelefin.client.network.GatewayCredentials.headers(),
            clientOwnsPlayhead = true,
            chapters = chapters,
            externalSubtitles = externalSubtitles,
            appliedBitrate = maxBitrate,
            sourceBitrate = source.bitrate?.takeIf { it > 0 } ?: sourceBitrate,
            // A transcode or remux already carries only the chosen audio; only a Direct Play needs steering.
            audioChoice = if (method == PlaybackMethod.DirectPlay) trackChoice(sourceStreams, MediaStreamType.AUDIO, chosenAudio) else null,
            subtitleChoice = if (chosenSubtitle == -1) {
                null
            } else {
                trackChoice(sourceStreams, MediaStreamType.SUBTITLE, chosenSubtitle)
                    ?.takeIf { method == PlaybackMethod.DirectPlay || it.externalId != null }
            },
            subtitlesOff = chosenSubtitle == -1 || chosenSubtitle == null,
            trickplay = runCatching {
                (itemDto ?: api.userLibraryApi.getItem(UUID.fromString(target.id), userId).content)
                    .trickplayInfo(source.id)
            }.getOrNull(),
        )
    }

    private fun externalSubtitleId(index: Int) = "jf-ext-$index"

    private fun trackChoice(
        streams: List<org.jellyfin.sdk.model.api.MediaStream>,
        type: MediaStreamType,
        index: Int?,
    ): app.zelefin.core.TrackChoice? {
        index ?: return null
        val ofType = streams.filter { it.type == type }.sortedBy { it.index }
        val ordinal = ofType.indexOfFirst { it.index == index }
        if (ordinal < 0) return null
        val stream = ofType[ordinal]
        val sideloaded = type == MediaStreamType.SUBTITLE &&
            (stream.deliveryMethod == SubtitleDeliveryMethod.EXTERNAL || stream.isExternal)
        return app.zelefin.core.TrackChoice(
            // Embedded tracks keep file order in both ffmpeg and the player, so count only those.
            ordinal = ofType.take(ordinal).count { !(type == MediaStreamType.SUBTITLE && (it.deliveryMethod == SubtitleDeliveryMethod.EXTERNAL || it.isExternal)) },
            language = stream.language,
            externalId = if (sideloaded) externalSubtitleId(stream.index) else null,
        )
    }

    /** Times a `/Playback/BitrateTest` download, like iOS `measureStreamingBitrate`. */
    suspend fun measureBitrate(
        size: Int,
        timeoutMillis: Long,
        transport: app.zelefin.client.NetworkTransport,
    ): app.zelefin.client.BitrateProbeResult? = withContext(Dispatchers.IO) {
        val base = api.baseUrl ?: return@withContext null
        val url = ServerUrl.resolve(base, "/Playback/BitrateTest?size=$size", null) ?: return@withContext null
        val client = app.zelefin.client.network.GatewayHttp.client.newBuilder()
            .callTimeout(timeoutMillis, java.util.concurrent.TimeUnit.MILLISECONDS)
            .build()
        val token = api.accessToken.orEmpty()
        // Jellyfin 10.11 turns off the legacy X-Emby-Token header by default, so send the
        // MediaBrowser Authorization header as well.
        val request = okhttp3.Request.Builder()
            .url(url)
            .header("Authorization", "MediaBrowser Token=\"$token\"")
            .header("X-Emby-Token", token)
            .build()
        val started = System.nanoTime()
        val response = runCatching { client.newCall(request).execute() }.getOrNull() ?: return@withContext null
        response.use {
            if (!it.isSuccessful) {
                throw ZelefinException.server("Jellyfin did not send the test file (HTTP ${it.code}). Check the connection and try again.")
            }
            val bytes = runCatching { it.body?.bytes()?.size ?: 0 }.getOrDefault(0)
            if (bytes < 16_000) return@withContext null
            app.zelefin.client.BitrateProbeResult.from(bytes, System.nanoTime() - started, transport)
        }
    }

    /** Mirrors iOS `SessionStore.applyPlaybackLanguages` for the signed-in Jellyfin user. */
    suspend fun applyPlaybackLanguages(userId: UUID, audioCode: String, subtitleCode: String) = withContext(Dispatchers.IO) {
        val automatic = app.zelefin.client.PlaybackPreferences.AUTOMATIC
        val off = app.zelefin.client.PlaybackPreferences.OFF
        val current = runCatching { api.userApi.getCurrentUser().content.configuration }.getOrNull() ?: return@withContext
        val audio = if (audioCode == automatic) "" else app.zelefin.client.ServerLanguageCode.toServer(audioCode)
        val subtitle = if (subtitleCode == automatic || subtitleCode == off) "" else app.zelefin.client.ServerLanguageCode.toServer(subtitleCode)
        val mode = when {
            subtitleCode == off -> org.jellyfin.sdk.model.api.SubtitlePlaybackMode.NONE
            subtitle.isEmpty() -> org.jellyfin.sdk.model.api.SubtitlePlaybackMode.DEFAULT
            else -> org.jellyfin.sdk.model.api.SubtitlePlaybackMode.SMART
        }
        val updated = current.copy(
            audioLanguagePreference = audio,
            playDefaultAudioTrack = audio.isEmpty(),
            subtitleLanguagePreference = subtitle,
            subtitleMode = mode,
        )
        runCatching { api.userApi.updateUserConfiguration(userId = userId, data = updated) }
        Unit
    }

    /** The signed-in user's Jellyfin audio and subtitle settings (Settings → Playback). */
    suspend fun playbackPreferences(): app.zelefin.client.JellyfinPlaybackPreferences = withContext(Dispatchers.IO) {
        val configuration = api.userApi.getCurrentUser().content.configuration
            ?: throw ZelefinException.server("Jellyfin did not return this user's settings.")
        app.zelefin.client.JellyfinPlaybackPreferences.from(configuration)
    }

    suspend fun savePlaybackPreferences(userId: UUID, preferences: app.zelefin.client.JellyfinPlaybackPreferences) = withContext(Dispatchers.IO) {
        val current = api.userApi.getCurrentUser().content.configuration
            ?: throw ZelefinException.server("Jellyfin did not return this user's settings.")
        api.userApi.updateUserConfiguration(userId = userId, data = preferences.applyTo(current))
        Unit
    }

    suspend fun reportStart(plan: PlaybackPlan, position: Double) = report(plan, position, paused = false, kind = ReportKind.Start)

    suspend fun reportProgress(plan: PlaybackPlan, position: Double, paused: Boolean) =
        report(plan, position, paused, ReportKind.Progress)

    suspend fun reportStop(plan: PlaybackPlan, position: Double) = report(plan, position, paused = true, ReportKind.Stop)

    private suspend fun report(plan: PlaybackPlan, position: Double, paused: Boolean, kind: ReportKind) {
        withContext(Dispatchers.IO) {
            val itemId = UUID.fromString(plan.item.id)
            val ticks = app.zelefin.core.TickClock.ticks(position)
            val playMethod = when (plan.method) {
                PlaybackMethod.DirectPlay -> PlayMethod.DIRECT_PLAY
                PlaybackMethod.Remux -> PlayMethod.DIRECT_STREAM
                PlaybackMethod.Transcode -> PlayMethod.TRANSCODE
            }
            when (kind) {
                ReportKind.Start -> api.playStateApi.reportPlaybackStart(
                    PlaybackStartInfo(
                        canSeek = true,
                        itemId = itemId,
                        mediaSourceId = plan.mediaSourceId,
                        isPaused = false,
                        isMuted = false,
                        positionTicks = ticks,
                        playMethod = playMethod,
                        playSessionId = plan.playSessionId,
                        repeatMode = RepeatMode.REPEAT_NONE,
                        playbackOrder = PlaybackOrder.DEFAULT,
                    ),
                )
                ReportKind.Progress -> api.playStateApi.reportPlaybackProgress(
                    PlaybackProgressInfo(
                        canSeek = true,
                        itemId = itemId,
                        mediaSourceId = plan.mediaSourceId,
                        isPaused = paused,
                        isMuted = false,
                        positionTicks = ticks,
                        playMethod = playMethod,
                        playSessionId = plan.playSessionId,
                        repeatMode = RepeatMode.REPEAT_NONE,
                        playbackOrder = PlaybackOrder.DEFAULT,
                    ),
                )
                ReportKind.Stop -> api.playStateApi.reportPlaybackStopped(
                    PlaybackStopInfo(
                        itemId = itemId,
                        mediaSourceId = plan.mediaSourceId,
                        positionTicks = ticks,
                        playSessionId = plan.playSessionId,
                        failed = false,
                    ),
                )
            }
        }
    }

    private suspend fun latest(userId: UUID, kind: BaseItemKind): List<MediaItem> = runCatching {
        api.itemsApi.getItems(
            GetItemsRequest(
                userId = userId,
                recursive = true,
                includeItemTypes = listOf(kind),
                sortBy = listOf(ItemSortBy.DATE_CREATED),
                sortOrder = listOf(SortOrder.DESCENDING),
                limit = 24,
                fields = listFields,
                enableUserData = true,
                enableImageTypes = imageTypes,
            ),
        ).content.items.withoutTubeArchivist().mapNotNull { ItemMapper.mediaItem(it.toSnapshot()) }
    }.getOrDefault(emptyList())

    private suspend fun items(
        userId: UUID,
        queue: PlaybackQueueKind,
        load: suspend () -> List<BaseItemDto>,
    ): List<MediaItem> = runCatching {
        load().mapNotNull { ItemMapper.mediaItem(it.toSnapshot(), queue) }
    }.getOrDefault(emptyList())

    private enum class ReportKind { Start, Progress, Stop }

    companion object {
        const val MAX_BITRATE = 200_000_000
        private const val ClientName = "Zelefin"
        private const val DisplayPreferencesId = "zelefin"

        private val listFields = listOf(
            ItemFields.OVERVIEW,
            ItemFields.GENRES,
            ItemFields.MEDIA_STREAMS,
            ItemFields.PROVIDER_IDS,
            ItemFields.WIDTH,
            ItemFields.HEIGHT,
            ItemFields.PEOPLE,
        )
        private val imageTypes = listOf(ImageType.PRIMARY, ImageType.THUMB, ImageType.BACKDROP, ImageType.LOGO)
        private val catalogFields = listOf(ItemFields.GENRES, ItemFields.MEDIA_STREAMS, ItemFields.PROVIDER_IDS, ItemFields.WIDTH, ItemFields.HEIGHT)
        private const val CatalogPageSize = 200
        private const val CatalogMaxItems = 20_000

        fun jellyfin(context: Context) = createJellyfin {
            this.context = context.applicationContext
            clientInfo = ClientInfo(name = "Zelefin", version = app.zelefin.client.BuildConfig.VERSION_NAME)
            val factory = OkHttpFactory(GatewayHttp.client)
            apiClientFactory = factory
            socketConnectionFactory = factory
        }

        private fun reportedDeviceName(context: Context): String {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N_MR1) {
                val name = android.provider.Settings.Global.getString(
                    context.contentResolver,
                    android.provider.Settings.Global.DEVICE_NAME,
                )
                if (!name.isNullOrBlank()) return name
            }
            return android.os.Build.MODEL?.takeIf { it.isNotBlank() } ?: "Android"
        }

        fun deviceProfile(maxBitrate: Int = MAX_BITRATE): DeviceProfile {
            val videoCodecs = "h264,hevc,av1,vp9,vp8,mpeg4,mpeg2video"
            val audioCodecs = "aac,aac_latm,ac3,eac3,mp3,flac,opus,vorbis,truehd,dts"
            val containers = "mp4,m4v,mov,mkv,matroska,webm,ts,mpegts,avi"
            return DeviceProfile(
                name = "Zelefin",
                maxStreamingBitrate = maxBitrate,
                maxStaticBitrate = maxBitrate,
                maxStaticMusicBitrate = MAX_BITRATE,
                musicStreamingTranscodingBitrate = MAX_BITRATE,
                directPlayProfiles = listOf(
                    DirectPlayProfile(
                        container = containers,
                        audioCodec = audioCodecs,
                        videoCodec = videoCodecs,
                        type = DlnaProfileType.VIDEO,
                    ),
                ),
                transcodingProfiles = listOf(
                    TranscodingProfile(
                        container = "mp4",
                        type = DlnaProfileType.VIDEO,
                        videoCodec = "hevc,h264,av1",
                        audioCodec = "aac,ac3,eac3",
                        protocol = MediaStreamProtocol.HLS,
                        context = EncodingContext.STREAMING,
                        enableSubtitlesInManifest = true,
                        maxAudioChannels = "8",
                        minSegments = 2,
                        segmentLength = 6,
                        conditions = emptyList(),
                    ),
                ),
                containerProfiles = emptyList(),
                codecProfiles = emptyList(),
                subtitleProfiles = listOf(
                    SubtitleProfile(format = "vtt", method = SubtitleDeliveryMethod.HLS),
                    SubtitleProfile(format = "vtt", method = SubtitleDeliveryMethod.EXTERNAL),
                    SubtitleProfile(format = "webvtt", method = SubtitleDeliveryMethod.EXTERNAL),
                    SubtitleProfile(format = "srt", method = SubtitleDeliveryMethod.EXTERNAL),
                    SubtitleProfile(format = "srt", method = SubtitleDeliveryMethod.EMBED),
                    SubtitleProfile(format = "subrip", method = SubtitleDeliveryMethod.EXTERNAL),
                    SubtitleProfile(format = "subrip", method = SubtitleDeliveryMethod.EMBED),
                    SubtitleProfile(format = "ass", method = SubtitleDeliveryMethod.EXTERNAL),
                    SubtitleProfile(format = "ass", method = SubtitleDeliveryMethod.EMBED),
                    SubtitleProfile(format = "ssa", method = SubtitleDeliveryMethod.EXTERNAL),
                    SubtitleProfile(format = "pgssub", method = SubtitleDeliveryMethod.EXTERNAL),
                    SubtitleProfile(format = "pgs", method = SubtitleDeliveryMethod.EXTERNAL),
                    SubtitleProfile(format = "dvdsub", method = SubtitleDeliveryMethod.EXTERNAL),
                    SubtitleProfile(format = "dvbsub", method = SubtitleDeliveryMethod.EXTERNAL),
                ),
            )
        }
    }

    suspend fun markPlayed(itemId: String) = withContext(Dispatchers.IO) {
        api.playStateApi.markPlayedItem(itemId = UUID.fromString(itemId))
    }

    suspend fun markUnplayed(itemId: String) = withContext(Dispatchers.IO) {
        api.playStateApi.markUnplayedItem(itemId = UUID.fromString(itemId))
    }

    suspend fun setFavorite(itemId: String, favorite: Boolean) = withContext(Dispatchers.IO) {
        val id = UUID.fromString(itemId)
        if (favorite) api.userLibraryApi.markFavoriteItem(itemId = id) else api.userLibraryApi.unmarkFavoriteItem(itemId = id)
    }

    suspend fun collectionsContaining(userId: UUID, itemId: String): List<app.zelefin.core.TitleCollection> = withContext(Dispatchers.IO) {
        val known = collectionDtosContaining(userId, itemId)
        val sets = known ?: boxSets(userId).take(24)
        if (sets.isEmpty()) return@withContext emptyList()
        coroutineScope {
            sets.map { collection ->
                async {
                    val members = collectionMembers(userId, collection.id)
                    if (known == null && members.none { it.id == itemId }) null
                    else if (members.isEmpty()) null
                    else app.zelefin.core.TitleCollection(collection, members)
                }
            }.awaitAll().filterNotNull().sortedBy { it.collection.name.lowercase() }
        }
    }

    suspend fun collectionEditor(userId: UUID, itemId: String): CollectionEditor = withContext(Dispatchers.IO) {
        val collections = boxSets(userId)
        CollectionEditor(collections, collectionIdsContaining(userId, itemId, collections))
    }

    suspend fun addToCollection(collectionId: String, itemId: String) = withContext(Dispatchers.IO) {
        api.collectionApi.addToCollection(UUID.fromString(collectionId), listOf(UUID.fromString(itemId)))
    }

    suspend fun removeFromCollection(collectionId: String, itemId: String) = withContext(Dispatchers.IO) {
        api.collectionApi.removeFromCollection(UUID.fromString(collectionId), listOf(UUID.fromString(itemId)))
    }

    suspend fun createCollection(name: String, itemId: String) = withContext(Dispatchers.IO) {
        api.collectionApi.createCollection(name = name, ids = listOf(itemId))
    }

    private suspend fun boxSets(userId: UUID): List<MediaItem> = runCatching {
        api.itemsApi.getItems(
            GetItemsRequest(
                userId = userId,
                recursive = true,
                includeItemTypes = listOf(BaseItemKind.BOX_SET),
                sortBy = listOf(ItemSortBy.SORT_NAME),
                sortOrder = listOf(SortOrder.ASCENDING),
                limit = 80,
                fields = listFields,
                enableUserData = true,
                enableImageTypes = imageTypes,
            ),
        ).content.items.mapNotNull { ItemMapper.mediaItem(it.toSnapshot()) }
    }.getOrDefault(emptyList())

    private suspend fun collectionDtosContaining(userId: UUID, itemId: String): List<MediaItem>? {
        return try {
            api.get<BaseItemDtoQueryResult>(
                "/Items/{itemId}/Collections",
                pathParameters = mapOf("itemId" to UUID.fromString(itemId)),
                queryParameters = mapOf("userId" to userId),
            ).content.items.mapNotNull { ItemMapper.mediaItem(it.toSnapshot()) }
        } catch (error: InvalidStatusException) {
            if (error.status !in 400..404 && error.status != 501) throw error
            null
        }
    }

    private suspend fun collectionMembers(userId: UUID, parentId: String): List<MediaItem> {
        val parent = runCatching { UUID.fromString(parentId) }.getOrNull() ?: return emptyList()
        val direct = memberItems(userId, parent, recursive = false)
        if (direct.isNotEmpty()) return direct
        return memberItems(userId, parent, recursive = true)
    }

    /** Children that can fill a collection card. Untagged box sets otherwise show Jellyfin’s generated collage, which leaves a grey quadrant for any child without a poster. */
    suspend fun collectionPosterMembers(userId: UUID, parentId: String): List<MediaItem> =
        collectionMembers(userId, parentId).filter { !it.primaryImageTag.isNullOrBlank() }.take(4)

    private suspend fun memberItems(userId: UUID, parentId: UUID, recursive: Boolean): List<MediaItem> = runCatching {
        api.itemsApi.getItems(
            GetItemsRequest(
                userId = userId,
                parentId = parentId,
                recursive = recursive,
                includeItemTypes = listOf(BaseItemKind.MOVIE, BaseItemKind.SERIES, BaseItemKind.VIDEO),
                sortBy = listOf(ItemSortBy.SORT_NAME),
                sortOrder = listOf(SortOrder.ASCENDING),
                limit = 40,
                fields = listFields,
                enableUserData = true,
                enableImageTypes = imageTypes,
            ),
        ).content.items.mapNotNull { ItemMapper.mediaItem(it.toSnapshot()) }
    }.getOrDefault(emptyList())

    private suspend fun collectionIdsContaining(userId: UUID, itemId: String, boxSets: List<MediaItem>): Set<String> {
        val itemUuid = UUID.fromString(itemId)
        try {
            val result = api.get<BaseItemDtoQueryResult>(
                "/Items/{itemId}/Collections",
                pathParameters = mapOf("itemId" to itemUuid),
                queryParameters = mapOf("userId" to userId),
            ).content
            return result.items.map { it.id.toString() }.toSet()
        } catch (error: InvalidStatusException) {
            if (error.status !in 400..404 && error.status != 501) throw error
        }
        if (boxSets.isEmpty()) return emptySet()
        return coroutineScope {
            boxSets.chunked(6).flatMap { chunk ->
                chunk.map { collection ->
                    async {
                        val parentId = runCatching { UUID.fromString(collection.id) }.getOrNull() ?: return@async null
                        val hit = runCatching {
                            api.itemsApi.getItems(
                                GetItemsRequest(
                                    userId = userId,
                                    parentId = parentId,
                                    ids = listOf(itemUuid),
                                    recursive = true,
                                    limit = 1,
                                ),
                            ).content.items
                        }.getOrDefault(emptyList())
                        if (hit.isNotEmpty()) collection.id else null
                    }
                }.awaitAll()
            }.filterNotNull().toSet()
        }
    }
}

data class CollectionEditor(
    val collections: List<MediaItem>,
    val memberIds: Set<String>,
)

private fun CatalogSortField.toItemSort(): ItemSortBy = when (this) {
    CatalogSortField.Name -> ItemSortBy.SORT_NAME
    CatalogSortField.Random -> ItemSortBy.RANDOM
    CatalogSortField.CommunityRating -> ItemSortBy.COMMUNITY_RATING
    CatalogSortField.CriticRating -> ItemSortBy.CRITIC_RATING
    CatalogSortField.DateAdded -> ItemSortBy.DATE_CREATED
    CatalogSortField.DatePlayed -> ItemSortBy.DATE_PLAYED
    CatalogSortField.ParentalRating -> ItemSortBy.OFFICIAL_RATING
    CatalogSortField.PlayCount -> ItemSortBy.PLAY_COUNT
    CatalogSortField.ReleaseDate -> ItemSortBy.PREMIERE_DATE
    CatalogSortField.Runtime -> ItemSortBy.RUNTIME
}

private fun List<String>.toChoices(): List<CatalogFilterChoice> = map { it.trim() }
    .filter { it.isNotEmpty() }
    .distinct()
    .sortedBy { it.lowercase() }
    .map { CatalogFilterChoice(it, it) }

private fun CultureDto.toChoice(): CatalogFilterChoice? {
    val code = (threeLetterIsoLanguageName ?: twoLetterIsoLanguageName).trim().lowercase()
    if (code.isEmpty()) return null
    val label = displayName.trim().ifEmpty { code.uppercase() }
    return CatalogFilterChoice(code, label)
}

internal fun BaseItemDto.toSnapshot(): JellyfinItemSnapshot {
    val tags = imageTags.orEmpty().entries.associate { (type, tag) -> type.serialName to tag }
    return JellyfinItemSnapshot(
        id = id.toString(),
        name = name,
        type = type.serialName,
        overview = overview,
        productionYear = productionYear,
        runTimeTicks = runTimeTicks,
        officialRating = officialRating,
        genres = genres.orEmpty(),
        seriesName = seriesName,
        seriesId = seriesId?.toString(),
        indexNumber = indexNumber,
        parentIndexNumber = parentIndexNumber,
        playbackPositionTicks = userData?.playbackPositionTicks ?: 0,
        unplayedItemCount = userData?.unplayedItemCount,
        played = userData?.played == true,
        favorite = userData?.isFavorite == true,
        primaryImageTag = tags["Primary"],
        imageTags = tags,
        backdropImageTags = backdropImageTags.orEmpty(),
        parentBackdropItemId = parentBackdropItemId?.toString(),
        parentThumbItemId = parentThumbItemId?.toString(),
        parentThumbImageTag = parentThumbImageTag,
        parentLogoItemId = parentLogoItemId?.toString(),
        parentLogoImageTag = parentLogoImageTag,
        seriesThumbImageTag = seriesThumbImageTag,
        parentPrimaryImageItemId = parentPrimaryImageItemId?.toString(),
        parentPrimaryImageTag = parentPrimaryImageTag,
        seriesPrimaryImageTag = seriesPrimaryImageTag,
        communityRating = communityRating?.toDouble(),
        criticRating = criticRating?.toDouble(),
        providerIds = providerIds.orEmpty().mapNotNull { (key, value) -> value?.let { key to it } }.toMap(),
        premiereDate = premiereDate?.toString(),
        people = people.orEmpty()
            .sortedBy { creditRankType(it.type.serialName) }
            .mapNotNull { person ->
                val personName = person.name?.trim().orEmpty()
                if (personName.isEmpty()) return@mapNotNull null
                CreditPerson(
                    id = person.id.toString(),
                    name = personName,
                    roleLabel = person.role?.trim()?.ifEmpty { null } ?: creditRole(person.type.serialName),
                    imageTag = person.primaryImageTag,
                )
            }
            .distinctBy { it.id },
        streams = mediaStreams.orEmpty().map { stream ->
            JellyfinStreamSnapshot(
                type = stream.type.serialName,
                videoRange = stream.videoRangeType.serialName.ifBlank { stream.videoRange.serialName },
                codec = stream.codec,
                channels = stream.channels,
                width = stream.width,
                height = stream.height,
                isDefault = stream.isDefault,
                title = stream.title,
                displayTitle = stream.displayTitle,
                channelLayout = stream.channelLayout,
            )
        },
        width = width,
        height = height,
    )
}

fun ServerUrl.normalizeOrThrow(raw: String): String = normalize(raw)

private fun creditRole(type: String): String = when (type.lowercase()) {
    "director" -> "Director"
    "writer" -> "Writer"
    "producer" -> "Producer"
    "creator" -> "Creator"
    "composer" -> "Composer"
    "gueststar" -> "Guest Star"
    else -> "Cast"
}

private fun creditRankType(type: String): Int = when (type.lowercase()) {
    "actor", "gueststar" -> 0
    "director" -> 1
    "creator" -> 2
    "writer" -> 3
    "producer" -> 4
    "composer" -> 5
    else -> 8
}
