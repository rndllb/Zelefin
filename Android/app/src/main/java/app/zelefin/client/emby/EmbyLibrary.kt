package app.zelefin.client.emby

import android.content.Context
import app.zelefin.client.BitrateProbeResult
import app.zelefin.client.BuildConfig
import app.zelefin.client.CatalogBrowseQuery
import app.zelefin.client.CatalogFeatureFilter
import app.zelefin.client.CatalogFilterChoice
import app.zelefin.client.CatalogFilterOptions
import app.zelefin.client.CatalogSortField
import app.zelefin.client.CatalogStatusFilter
import app.zelefin.client.CatalogVideoKind
import app.zelefin.client.JellyfinPlaybackPreferences
import app.zelefin.client.LibraryCounts
import app.zelefin.client.LibraryGenre
import app.zelefin.client.LibraryKind
import app.zelefin.client.LibraryRoom
import app.zelefin.client.NetworkTransport
import app.zelefin.client.PlaybackLanguage
import app.zelefin.client.PlaybackPreferences
import app.zelefin.client.SearchHit
import app.zelefin.client.SearchHitKind
import app.zelefin.client.ServerLanguageCode
import app.zelefin.client.ThemeMedia
import app.zelefin.client.isBrowsableGenre
import app.zelefin.client.jellyfin.JellyfinLibrary
import app.zelefin.client.jellyfin.JellyfinScope
import app.zelefin.client.jellyfin.TitleFacts
import app.zelefin.client.jellyfin.withMedia
import app.zelefin.client.network.GatewayCredentials
import app.zelefin.client.plugins.JellyfinTmdbCatalog
import app.zelefin.client.plugins.SkipSegment
import app.zelefin.client.session.SessionVault
import app.zelefin.client.timedBitrateDownload
import app.zelefin.core.CreditPerson
import app.zelefin.core.EmbyAuthResult
import app.zelefin.core.EmbyItem
import app.zelefin.core.EmbyItemCounts
import app.zelefin.core.EmbyItemsResult
import app.zelefin.core.EmbyJson
import app.zelefin.core.EmbyMediaStream
import app.zelefin.core.EmbyPlaybackInfo
import app.zelefin.core.EmbyPublicInfo
import app.zelefin.core.EmbyRecommendation
import app.zelefin.core.EmbyThemeMedia
import app.zelefin.core.HomeFeed
import app.zelefin.core.HomeRowStyle
import app.zelefin.core.HomeSection
import app.zelefin.core.ItemMapper
import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind
import app.zelefin.core.PlaybackMethod
import app.zelefin.core.PlaybackPlan
import app.zelefin.core.PlaybackQueueKind
import app.zelefin.core.PlaybackResumePolicy
import app.zelefin.core.ServerReachability
import app.zelefin.core.TickClock
import app.zelefin.core.TitleCollection
import app.zelefin.core.TitleDetail
import app.zelefin.core.TitleTrailer
import app.zelefin.core.TrailerLinks
import app.zelefin.core.VideoResolution
import app.zelefin.core.ZelefinException
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import org.jellyfin.sdk.model.api.DeviceProfile
import org.jellyfin.sdk.model.api.RecommendationType
import org.jellyfin.sdk.model.api.SubtitlePlaybackMode

/** The Emby counterpart of [JellyfinLibrary] for everything Zelefin shows and plays. */
class EmbyLibrary(
    context: Context,
    baseUrl: String,
    accessToken: String? = null,
    userId: String = "",
    deviceId: String = SessionVault(context.applicationContext).deviceId,
) {
    val api = EmbyApi(
        baseUrl = baseUrl,
        accessToken = accessToken,
        deviceId = deviceId,
        deviceName = JellyfinLibrary.reportedDeviceName(context),
        version = BuildConfig.VERSION_NAME,
    )

    @Volatile
    var userId: String = userId
        private set

    val serverUrl: String get() = api.baseUrl

    private data class StreamPick(val audio: Int?, val subtitle: Int?, val liveStreamId: String?)

    /** What playback started with, keyed by play session: stream indexes for the reports, and the live stream to close. */
    private val streamPicks = ConcurrentHashMap<String, StreamPick>()

    internal val user: String get() = userId.ifBlank { throw ZelefinException.missingUser() }

    suspend fun probe(): ServerReachability = withContext(Dispatchers.IO) {
        try {
            val reply = api.send("GET", "/System/Info/Public")
            if (!reply.ok) return@withContext ServerReachability.fromStatus(reply.status)
            val info = EmbyJson.parser.decodeFromString(EmbyPublicInfo.serializer(), reply.body)
            ServerReachability.Reachable(info.serverName?.trim()?.ifEmpty { null } ?: "Emby", info.version ?: "?")
        } catch (error: Exception) {
            ServerReachability.from(error)
        }
    }

    suspend fun login(username: String, password: String): EmbyAuthResult = withContext(Dispatchers.IO) {
        val body = buildJsonObject {
            put("Username", username)
            put("Pw", password)
        }.toString()
        val reply = api.send("POST", "/Users/AuthenticateByName", json = body)
        if (reply.status == 401) throw ZelefinException.server("Emby did not accept that username or password.")
        if (!reply.ok) throw ZelefinException.server("Emby could not sign in (HTTP ${reply.status}).")
        val result = runCatching { EmbyJson.parser.decodeFromString(EmbyAuthResult.serializer(), reply.body) }.getOrNull()
        val token = result?.accessToken?.takeIf { it.isNotBlank() } ?: throw ZelefinException.server("Emby did not return an access token.")
        val id = result.user?.id?.takeIf { it.isNotBlank() } ?: throw ZelefinException.missingUser()
        api.accessToken = token
        userId = id
        result
    }

    suspend fun logout() {
        api.send("POST", "/Sessions/Logout")
    }

    suspend fun home(hero: JellyfinLibrary.HeroContent = JellyfinLibrary.HeroContent.RecentlyAdded): HomeFeed = withContext(Dispatchers.IO) {
        coroutineScope {
            val resume = async {
                listOrEmpty(PlaybackQueueKind.Resume) {
                    page("/Users/$user/Items/Resume") {
                        this["Limit"] = 20
                        this["MediaTypes"] = "Video"
                        this["Recursive"] = true
                        listDefaults()
                    }
                }
            }
            val nextUp = async {
                listOrEmpty(PlaybackQueueKind.NextUp) {
                    page("/Shows/NextUp") {
                        this["UserId"] = user
                        this["Limit"] = 20
                        listDefaults()
                    }
                }
            }
            val upcoming = async {
                listOrEmpty(PlaybackQueueKind.NextUp) {
                    page("/Shows/Upcoming") {
                        this["UserId"] = user
                        this["Limit"] = 20
                        listDefaults()
                    }
                }
            }
            val movies = async { latest(MediaKind.Movie) }
            val shows = async { latest(MediaKind.Series) }
            val recommendations = async { movieRecommendations() }
            val collections = async { collectionPreview(limit = 24) }
            val genres = async { homeGenres() }
            val watched = async { recentlyWatched() }
            val heroPool = async {
                when (hero) {
                    JellyfinLibrary.HeroContent.Random -> titleSample("Random", favorites = false)
                    JellyfinLibrary.HeroContent.Favorites -> titleSample("DateCreated", favorites = true)
                    else -> emptyList()
                }
            }
            val feed = HomeFeed(
                continueWatching = resume.await(),
                nextUp = nextUp.await(),
                recentMovies = movies.await(),
                recentShows = shows.await(),
                upcoming = upcoming.await(),
                recommendations = recommendations.await(),
                collections = collections.await(),
                genres = genres.await(),
                recentlyWatched = watched.await(),
            )
            feed.copy(featured = JellyfinLibrary.heroItems(feed, hero, heroPool.await()))
        }
    }

    /**
     * `Items/Latest` orders shows by their newest episode, so recently added seasons surface too.
     * Emby still mixes movies into a `Series` request, so results are filtered to the asked-for kind.
     */
    private suspend fun latest(kind: MediaKind): List<MediaItem> = runCatching {
        api.get(
            "/Users/$user/Items/Latest",
            ListSerializer(EmbyItem.serializer()),
            embyQuery {
                this["IncludeItemTypes"] = kind.name
                this["Limit"] = 36
                listDefaults()
            },
        ).media().filter { it.kind == kind }.take(24)
    }.getOrDefault(emptyList())

    private suspend fun movieRecommendations(): List<HomeSection> = runCatching {
        api.get(
            "/Movies/Recommendations",
            ListSerializer(EmbyRecommendation.serializer()),
            embyQuery {
                this["UserId"] = user
                this["CategoryLimit"] = 5
                this["ItemLimit"] = 16
                this["EnableUserData"] = true
                this["EnableImageTypes"] = ImageTypes
            },
        ).mapIndexedNotNull { index, row ->
            val items = row.items.media()
            if (items.isEmpty()) return@mapIndexedNotNull null
            val type = RecommendationType.entries.firstOrNull { it.serialName.equals(row.recommendationType, ignoreCase = true) }
                ?: RecommendationType.SIMILAR_TO_RECENTLY_PLAYED
            HomeSection(
                id = "recommend-${row.categoryId ?: index}",
                title = JellyfinLibrary.recommendationTitle(type, row.baselineItemName),
                style = HomeRowStyle.Portrait,
                items = items,
            )
        }
    }.getOrDefault(emptyList())

    private suspend fun homeGenres(): List<MediaItem> = runCatching {
        genres(limit = 48)
            .filter { isBrowsableGenre(it.name) }
            .distinctBy { genre -> genre.name.lowercase().filter { it.isLetterOrDigit() } }
            .take(24)
            .map { MediaItem(id = it.id, name = it.name, kind = MediaKind.Genre) }
    }.getOrDefault(emptyList())

    /** Played movies and episodes, newest first, one card per show. */
    private suspend fun recentlyWatched(): List<MediaItem> = runCatching {
        val items = page("/Users/$user/Items") {
            this["Recursive"] = true
            this["IncludeItemTypes"] = "Movie,Episode"
            this["Filters"] = "IsPlayed"
            this["IsPlayed"] = true
            this["MediaTypes"] = "Video"
            this["SortBy"] = "DatePlayed"
            this["SortOrder"] = "Descending"
            this["Limit"] = 40
            listDefaults()
        }.items.media()
        val seenSeries = mutableSetOf<String>()
        items.filter { item ->
            val series = item.seriesId?.takeIf { item.kind == MediaKind.Episode }
            series == null || seenSeries.add(series)
        }.take(20)
    }.getOrDefault(emptyList())

    private suspend fun titleSample(sort: String, favorites: Boolean): List<MediaItem> = runCatching {
        page("/Users/$user/Items") {
            this["Recursive"] = true
            this["IncludeItemTypes"] = "Movie,Series"
            if (favorites) this["Filters"] = "IsFavorite"
            this["SortBy"] = sort
            this["SortOrder"] = "Descending"
            this["Limit"] = if (favorites) 48 else 24
            listDefaults()
        }.items.media()
    }.getOrDefault(emptyList())

    /** Emby's mixed libraries carry no `CollectionType`; their name decides, else they list movies and shows. */
    suspend fun libraries(): List<LibraryRoom> = withContext(Dispatchers.IO) {
        val rooms = page("/Users/$user/Views").items.mapNotNull { view ->
            val id = view.id?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            val name = view.name?.trim().orEmpty()
            if (name.isEmpty()) return@mapNotNull null
            LibraryRoom(id = id, name = name, kind = JellyfinLibrary.libraryKind(view.collectionType, name))
        }
        if (rooms.none { it.kind == LibraryKind.LiveTV } || liveTvEnabled()) rooms else rooms.filterNot { it.kind == LibraryKind.LiveTV }
    }

    suspend fun serverCounts(): LibraryCounts = withContext(Dispatchers.IO) {
        runCatching {
            val counts = api.get("/Items/Counts", EmbyItemCounts.serializer(), embyQuery { this["UserId"] = user })
            LibraryCounts(counts.movieCount, counts.seriesCount, counts.episodeCount)
        }.getOrElse {
            LibraryCounts(countItems("Movie", null), countItems("Series", null), countItems("Episode", null))
        }
    }

    suspend fun roomCounts(room: LibraryRoom): LibraryCounts = withContext(Dispatchers.IO) {
        when (room.kind) {
            LibraryKind.Movies -> LibraryCounts(movies = countItems("Movie", room.id))
            LibraryKind.Shows -> LibraryCounts(shows = countItems("Series", room.id), episodes = countItems("Episode", room.id))
            LibraryKind.LiveTV -> LibraryCounts()
            else -> LibraryCounts(countItems("Movie", room.id), countItems("Series", room.id), countItems("Episode", room.id))
        }
    }

    private suspend fun countItems(type: String, parentId: String?): Int = runCatching {
        page("/Users/$user/Items") {
            this["ParentId"] = parentId
            this["Recursive"] = true
            this["IncludeItemTypes"] = type
            this["Limit"] = 0
        }.totalRecordCount
    }.getOrDefault(0)

    suspend fun previewItems(room: LibraryRoom, limit: Int = 8): List<MediaItem> = withContext(Dispatchers.IO) {
        runCatching {
            page("/Users/$user/Items") {
                this["ParentId"] = room.id
                this["Recursive"] = true
                this["IncludeItemTypes"] = JellyfinLibrary.scope(room).kinds.map { it.serialName }
                this["SortBy"] = "DateCreated"
                this["SortOrder"] = "Descending"
                this["Limit"] = limit
                listDefaults()
            }.items.media()
        }.getOrDefault(emptyList())
    }

    suspend fun genres(limit: Int? = null): List<LibraryGenre> = withContext(Dispatchers.IO) {
        page("/Genres") {
            this["UserId"] = user
            this["IncludeItemTypes"] = "Movie,Series"
            this["Recursive"] = true
            this["SortBy"] = "SortName"
            this["Limit"] = limit
            this["EnableImages"] = false
        }.items.mapNotNull { dto ->
            val id = dto.id ?: return@mapNotNull null
            val name = dto.name?.trim().orEmpty()
            if (name.isEmpty()) null else LibraryGenre(id, name)
        }
    }

    suspend fun tmdbCatalog(): JellyfinTmdbCatalog = withContext(Dispatchers.IO) {
        val items = page("/Users/$user/Items") {
            this["Recursive"] = true
            this["IncludeItemTypes"] = "Movie,Series"
            this["Fields"] = "ProviderIds"
            this["Limit"] = MaxItems
            this["EnableImages"] = false
            this["EnableUserData"] = false
        }.items
        val movies = mutableSetOf<Int>()
        val series = mutableSetOf<Int>()
        items.forEach { dto ->
            val tmdb = JellyfinTmdbCatalog.tmdbId(dto.providerIds) ?: return@forEach
            if (dto.type.equals("Series", ignoreCase = true)) series += tmdb else movies += tmdb
        }
        JellyfinTmdbCatalog(movies, series)
    }

    /** Emby has no search hints, so titles, people, genres, and studios are searched side by side. */
    suspend fun searchHints(term: String): List<SearchHit> = withContext(Dispatchers.IO) {
        val trimmed = term.trim()
        if (trimmed.isEmpty()) return@withContext emptyList()
        coroutineScope {
            val titles = async {
                runCatching {
                    page("/Users/$user/Items") {
                        this["SearchTerm"] = trimmed
                        this["Recursive"] = true
                        this["IncludeItemTypes"] = "Movie,Series,Episode,BoxSet"
                        this["Limit"] = 24
                        this["Fields"] = "ProductionYear"
                        this["EnableUserData"] = true
                        this["EnableImageTypes"] = ImageTypes
                    }.items
                }.getOrDefault(emptyList()).mapNotNull(::titleHit)
            }
            fun named(path: String, kind: SearchHitKind, limit: Int) = async {
                runCatching {
                    page(path) {
                        this["SearchTerm"] = trimmed
                        this["UserId"] = user
                        this["Recursive"] = true
                        this["Limit"] = limit
                    }.items
                }.getOrDefault(emptyList()).mapNotNull { namedHit(it, kind) }
            }
            val people = named("/Persons", SearchHitKind.Person, 8)
            val genres = named("/Genres", SearchHitKind.Genre, 6)
            val studios = named("/Studios", SearchHitKind.Studio, 6)
            val seen = mutableSetOf<String>()
            (titles.await() + people.await() + genres.await() + studios.await()).filter { seen.add(it.id) }
        }
    }

    private fun titleHit(dto: EmbyItem): SearchHit? {
        val item = ItemMapper.mediaItem(dto.toSnapshot()) ?: return null
        val label = when (item.kind) {
            MediaKind.Movie -> "Movie"
            MediaKind.Series -> "Show"
            MediaKind.Episode -> item.seriesName ?: "Episode"
            MediaKind.Collection -> "Collection"
            else -> return null
        }
        return SearchHit(
            id = item.id,
            name = item.name,
            subtitle = listOfNotNull(label, item.year?.toString()).joinToString(" · "),
            kind = SearchHitKind.Title,
            item = item,
        )
    }

    private fun namedHit(dto: EmbyItem, kind: SearchHitKind): SearchHit? {
        val id = dto.id ?: return null
        val name = dto.name?.takeIf { it.isNotBlank() } ?: return null
        if (kind == SearchHitKind.Genre && !isBrowsableGenre(name)) return null
        val label = when (kind) {
            SearchHitKind.Person -> "Person"
            SearchHitKind.Genre -> "Genre"
            else -> "Studio"
        }
        val item = MediaItem(
            id = id,
            name = name,
            kind = if (kind == SearchHitKind.Genre) MediaKind.Genre else MediaKind.Unknown,
            primaryImageTag = dto.imageTags["Primary"],
        )
        return SearchHit(id = id, name = name, subtitle = label, kind = kind, item = item)
    }

    suspend fun collectionPreview(limit: Int = 12): List<MediaItem> = withContext(Dispatchers.IO) {
        runCatching { boxSets(limit) }.getOrDefault(emptyList())
    }

    internal suspend fun boxSets(limit: Int): List<MediaItem> = page("/Users/$user/Items") {
        this["Recursive"] = true
        this["IncludeItemTypes"] = "BoxSet"
        this["SortBy"] = "SortName"
        this["SortOrder"] = "Ascending"
        this["Limit"] = limit
        listDefaults()
    }.items.media()

    suspend fun catalog(
        type: String,
        query: CatalogBrowseQuery = CatalogBrowseQuery(),
        onPage: (List<MediaItem>) -> Unit = {},
    ): List<MediaItem> = browse(JellyfinScope(emptyList()), query, onPage, types = listOf(type))

    suspend fun browse(
        scope: JellyfinScope,
        query: CatalogBrowseQuery = CatalogBrowseQuery(),
        onPage: (List<MediaItem>) -> Unit = {},
        types: List<String> = scope.kinds.map { it.serialName },
    ): List<MediaItem> = withContext(Dispatchers.IO) {
        if (types == listOf("TvChannel")) return@withContext liveChannels(onPage)
        val passes = query.resolutionPasses()
        if (passes.size == 1) {
            val (isHd, is4k) = passes.first()
            val items = catalogPass(scope, types, query, isHd, is4k, onPage)
            return@withContext if (query.sort == CatalogSortField.Random) items.shuffled() else items
        }
        val merged = LinkedHashMap<String, MediaItem>()
        for ((isHd, is4k) in passes) {
            for (item in catalogPass(scope, types, query, isHd, is4k) {}) merged.putIfAbsent(item.id, item)
            onPage(merged.values.toList())
        }
        merged.values.toList()
    }

    /** A Live TV room lists Emby's channels in guide order; catalog filters do not apply to them. */
    private suspend fun liveChannels(onPage: (List<MediaItem>) -> Unit): List<MediaItem> {
        val collected = mutableListOf<MediaItem>()
        var start = 0
        while (start < MaxItems) {
            val request = EmbyRequests.liveChannels(user, start, PageSize, ListFields)
            val page = api.get(request.path, EmbyItemsResult.serializer(), request.query)
            if (page.items.isEmpty()) break
            collected += page.items.media()
            onPage(collected.toList())
            start += page.items.size
            if (page.totalRecordCount in 1..start) break
        }
        return collected
    }

    /** Emby has no 4K filter, so a 4K pass asks for HD and keeps the 4K results. */
    private suspend fun catalogPass(
        scope: JellyfinScope,
        types: List<String>,
        query: CatalogBrowseQuery,
        isHd: Boolean?,
        is4k: Boolean?,
        onPage: (List<MediaItem>) -> Unit,
    ): List<MediaItem> {
        val collected = LinkedHashMap<String, MediaItem>()
        var start = 0
        while (start < MaxItems) {
            val page = try {
                page("/Users/$user/Items") { catalogParameters(scope, types, query, if (is4k == true) true else isHd, start) }
            } catch (error: Exception) {
                if (collected.isEmpty()) throw error
                break
            }
            if (page.items.isEmpty()) break
            page.items.media()
                .filter { is4k != true || it.videoResolution == VideoResolution.FourK }
                .forEach { collected.putIfAbsent(it.id, it) }
            onPage(collected.values.toList())
            val next = start + page.items.size
            val finished = if (page.totalRecordCount > 0) next >= page.totalRecordCount else page.items.size < PageSize
            if (finished || next == start) break
            start = next
        }
        return collected.values.toList()
    }

    private fun EmbyQuery.catalogParameters(scope: JellyfinScope, types: List<String>, query: CatalogBrowseQuery, isHd: Boolean?, start: Int) {
        val played = CatalogStatusFilter.Played in query.statuses
        val unplayed = CatalogStatusFilter.Unplayed in query.statuses
        this["ParentId"] = scope.parentId
        this["Recursive"] = true
        this["IncludeItemTypes"] = types
        pipe("GenreIds", scope.genreIds)
        pipe("PersonIds", scope.personIds)
        pipe("StudioIds", scope.studioIds)
        this["SortBy"] = query.sort.embySort()
        if (query.sort.allowsDirection) this["SortOrder"] = if (query.sortAscending) "Ascending" else "Descending"
        this["StartIndex"] = start
        this["Limit"] = PageSize
        this["Filters"] = buildList {
            if (played && !unplayed) add("IsPlayed")
            if (unplayed && !played) add("IsUnplayed")
            if (CatalogStatusFilter.Favorite in query.statuses) add("IsFavorite")
            if (CatalogStatusFilter.ContinueWatching in query.statuses) add("IsResumable")
        }
        this["HasSubtitles"] = true.takeIf { CatalogFeatureFilter.Subtitles in query.features }
        this["HasTrailer"] = true.takeIf { CatalogFeatureFilter.Trailers in query.features }
        this["HasSpecialFeature"] = true.takeIf { CatalogFeatureFilter.Extras in query.features }
        this["HasThemeSong"] = true.takeIf { CatalogFeatureFilter.ThemeSongs in query.features }
        this["HasThemeVideo"] = true.takeIf { CatalogFeatureFilter.ThemeVideos in query.features }
        this["IsHD"] = isHd
        this["Is3D"] = true.takeIf { CatalogVideoKind.ThreeD in query.videoKinds }
        this["VideoTypes"] = query.videoKinds.mapNotNull { kind ->
            when (kind) {
                CatalogVideoKind.Dvd -> "Dvd"
                CatalogVideoKind.BluRay -> "BluRay"
                CatalogVideoKind.Iso -> "Iso"
                else -> null
            }
        }
        pipe("Genres", query.genres.sorted())
        pipe("OfficialRatings", query.officialRatings.sorted())
        pipe("Tags", query.tags.sorted())
        this["Years"] = query.years.sorted()
        pipe("Studios", query.studios.sorted())
        listDefaults(CatalogFields)
    }

    suspend fun catalogFilters(scope: JellyfinScope, types: List<String> = scope.kinds.map { it.serialName }): CatalogFilterOptions =
        withContext(Dispatchers.IO) {
            coroutineScope {
                fun names(path: String) = async {
                    runCatching {
                        page(path) {
                            this["UserId"] = user
                            this["ParentId"] = scope.parentId
                            this["IncludeItemTypes"] = types
                            this["Recursive"] = true
                            this["EnableImages"] = false
                        }.items.mapNotNull { it.name?.trim()?.takeIf { name -> name.isNotEmpty() } }
                    }.getOrDefault(emptyList())
                }
                val genres = names("/Genres")
                val ratings = names("/OfficialRatings")
                val tags = names("/Tags")
                val years = names("/Years")
                val studios = names("/Studios")
                CatalogFilterOptions(
                    genres = genres.await().toChoices(),
                    officialRatings = ratings.await().toChoices(),
                    tags = tags.await().toChoices(),
                    years = years.await().mapNotNull { it.toIntOrNull() }.distinct().sortedDescending()
                        .map { CatalogFilterChoice(it.toString(), it.toString()) },
                    studios = studios.await().toChoices(),
                )
            }
        }

    internal suspend fun item(id: String): EmbyItem = api.get("/Users/$user/Items/$id", EmbyItem.serializer())

    suspend fun mediaItem(id: String): MediaItem? = withContext(Dispatchers.IO) {
        runCatching { item(id) }.getOrNull()?.let { ItemMapper.mediaItem(it.toSnapshot()) }
    }

    /** Movies and episodes play as-is. A series or season resolves to the resume / next episode. */
    suspend fun playableItem(item: MediaItem): MediaItem = withContext(Dispatchers.IO) {
        if (item.kind != MediaKind.Series && item.kind != MediaKind.Season) return@withContext item
        val seriesId = if (item.kind == MediaKind.Season) item.seriesId ?: item.id else item.id
        val episodes = MediaItem.orderedEpisodes(episodes(seriesId).media())
        val hero = MediaItem.heroPlaybackItem(item, episodes)
        if (hero.kind != MediaKind.Episode) throw ZelefinException.server("This show has no playable episodes.")
        hero
    }

    private suspend fun episodes(seriesId: String): List<EmbyItem> = page("/Shows/$seriesId/Episodes") {
        this["UserId"] = user
        listDefaults()
    }.items

    suspend fun detail(id: String): TitleDetail = withContext(Dispatchers.IO) {
        val dto = item(id)
        val item = ItemMapper.mediaItem(dto.toSnapshot()) ?: throw ZelefinException.server("This title could not be read.")
        if (item.kind == MediaKind.Collection) return@withContext collectionDetail(dto, item)
        coroutineScope {
            val episodeDtos = async { if (item.kind == MediaKind.Series) episodes(id) else emptyList() }
            val seasons = async {
                if (item.kind != MediaKind.Series) return@async emptyList()
                page("/Shows/$id/Seasons") {
                    this["UserId"] = user
                    listDefaults()
                }.items.media()
            }
            val related = async {
                runCatching {
                    page("/Items/$id/Similar") {
                        this["UserId"] = user
                        this["Limit"] = 12
                        listDefaults()
                    }.items.media()
                }.getOrDefault(emptyList())
            }
            val trailers = async { if (item.kind == MediaKind.Movie || item.kind == MediaKind.Series) trailers(id, dto) else emptyList() }
            val parts = async { if (item.kind == MediaKind.Movie) additionalParts(id) else emptyList() }
            val orderedEpisodes = MediaItem.orderedEpisodes(episodeDtos.await().media())
            var facts = TitleFacts.from(dto, item)
            if (facts.languages.isEmpty() && facts.file.isEmpty()) {
                val hero = MediaItem.heroPlaybackItem(item, orderedEpisodes)
                episodeDtos.await().firstOrNull { it.id == hero.id }?.let { facts = facts.withMedia(TitleFacts.from(it, hero)) }
            }
            TitleDetail(
                item = item,
                seasons = seasons.await(),
                episodes = orderedEpisodes,
                related = related.await(),
                trailers = trailers.await(),
                moreInfo = facts,
                additionalParts = parts.await(),
            )
        }
    }

    /** A BoxSet page: the collection's own artwork and overview, then its titles in release order. */
    private suspend fun collectionDetail(dto: EmbyItem, item: MediaItem): TitleDetail {
        val members = runCatching {
            page("/Users/$user/Items") {
                this["ParentId"] = item.id
                this["SortBy"] = "PremiereDate"
                this["SortOrder"] = "Ascending"
                this["Limit"] = MaxItems
                listDefaults()
            }.items.media()
        }.getOrDefault(emptyList())
        return TitleDetail(item = item, moreInfo = TitleFacts.from(dto, item), collectionItems = members)
    }

    private suspend fun trailers(id: String, dto: EmbyItem): List<TitleTrailer> {
        val local = runCatching {
            api.get("/Users/$user/Items/$id/LocalTrailers", ListSerializer(EmbyItem.serializer())).media()
        }.getOrDefault(emptyList())
        if (local.isNotEmpty()) {
            return local.map { trailer ->
                TitleTrailer(id = "emby-${trailer.id}", title = trailer.name, caption = "From your server", localItem = trailer)
            }
        }
        val seen = linkedSetOf<String>()
        return dto.remoteTrailers.mapNotNull { remote ->
            val trailer = TrailerLinks.remote(remote.url, remote.name) ?: return@mapNotNull null
            if (!seen.add(trailer.id)) null else trailer
        }
    }

    private suspend fun additionalParts(id: String): List<MediaItem> = runCatching {
        page("/Videos/$id/AdditionalParts") { this["UserId"] = user }.items.media()
    }.getOrDefault(emptyList())

    /** Like Jellyfin: reading each person without a portrait reports what the server has for them. */
    suspend fun peopleWithPhotos(people: List<CreditPerson>, onBatch: suspend (List<CreditPerson>) -> Unit) {
        val missing = people.filter { it.imageTag.isNullOrBlank() && it.imageUrl.isNullOrBlank() && it.id.isNotBlank() }
        if (missing.isEmpty()) return
        val found = mutableMapOf<String, CreditPerson>()
        for (batch in missing.chunked(6)) {
            val rows = coroutineScope {
                batch.map { person -> async { person.id to runCatching { person(person.id) }.getOrNull() } }.awaitAll()
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

    suspend fun person(id: String): CreditPerson? = withContext(Dispatchers.IO) {
        val dto = runCatching { item(id) }.getOrNull() ?: return@withContext null
        val name = dto.name?.trim().orEmpty()
        if (name.isEmpty()) return@withContext null
        CreditPerson(
            id = dto.id ?: id,
            name = name,
            roleLabel = "Cast & Crew",
            imageTag = dto.imageTags["Primary"],
            overview = dto.overview?.trim()?.ifEmpty { null },
            birthYear = dto.productionYear,
        )
    }

    /** `ListItemIds` asks Emby for the box sets that hold the title. */
    suspend fun collectionsContaining(itemId: String): List<TitleCollection> = withContext(Dispatchers.IO) {
        val sets = runCatching {
            page("/Users/$user/Items") {
                this["Recursive"] = true
                this["IncludeItemTypes"] = "BoxSet"
                this["ListItemIds"] = itemId
                this["SortBy"] = "SortName"
                listDefaults()
            }.items.media()
        }.getOrDefault(emptyList())
        coroutineScope {
            sets.map { collection ->
                async { collectionMembers(collection.id).takeIf { it.isNotEmpty() }?.let { TitleCollection(collection, it) } }
            }.awaitAll().filterNotNull().sortedBy { it.collection.name.lowercase() }
        }
    }

    private suspend fun collectionMembers(parentId: String): List<MediaItem> {
        val direct = memberItems(parentId, recursive = false)
        if (direct.isNotEmpty()) return direct
        return memberItems(parentId, recursive = true)
    }

    suspend fun collectionPosterMembers(parentId: String): List<MediaItem> =
        collectionMembers(parentId).filter { !it.primaryImageTag.isNullOrBlank() }.take(4)

    private suspend fun memberItems(parentId: String, recursive: Boolean): List<MediaItem> = runCatching {
        page("/Users/$user/Items") {
            this["ParentId"] = parentId
            this["Recursive"] = recursive
            this["IncludeItemTypes"] = "Movie,Series,Video"
            this["SortBy"] = "SortName"
            this["SortOrder"] = "Ascending"
            this["Limit"] = 40
            listDefaults()
        }.items.media()
    }.getOrDefault(emptyList())

    suspend fun randomTitle(): MediaItem? = withContext(Dispatchers.IO) {
        page("/Users/$user/Items") {
            this["Recursive"] = true
            this["IncludeItemTypes"] = "Movie,Series"
            this["SortBy"] = "Random"
            this["Limit"] = 1
            this["Fields"] = "Overview,Genres"
        }.items.firstOrNull()?.let { ItemMapper.mediaItem(it.toSnapshot()) }
    }

    suspend fun markPlayed(itemId: String) = expectOk(api.send("POST", "/Users/$user/PlayedItems/$itemId"))

    suspend fun markUnplayed(itemId: String) = expectOk(api.send("DELETE", "/Users/$user/PlayedItems/$itemId"))

    suspend fun setFavorite(itemId: String, favorite: Boolean) =
        expectOk(api.send(if (favorite) "POST" else "DELETE", "/Users/$user/FavoriteItems/$itemId"))

    /** Intro and credit markers from Emby's chapter list. */
    suspend fun skipSegments(itemId: String): List<SkipSegment> = withContext(Dispatchers.IO) {
        val dto = runCatching { item(itemId) }.getOrNull() ?: return@withContext emptyList()
        EmbyPlayback.skipSegments(dto.allChapters, dto.runTimeTicks?.let(TickClock::seconds))
    }

    /**
     * Mirrors [JellyfinLibrary.playback]: the user's Emby settings and the language picks choose the
     * starting streams, and [bitrate] turns the file bitrate into the stream cap for adaptive bitrate.
     */
    suspend fun playback(
        item: MediaItem,
        audioLanguage: String = PlaybackPreferences.AUTOMATIC,
        subtitleLanguage: String = PlaybackPreferences.AUTOMATIC,
        preferSdh: Boolean = false,
        bitrate: suspend (sourceBitrate: Int?) -> Int = { JellyfinLibrary.MAX_BITRATE },
    ): PlaybackPlan = withContext(Dispatchers.IO) {
        val target = item
        val resume = if (target.playbackPosition > PlaybackResumePolicy.THRESHOLD) target.playbackPosition else 0.0
        val itemDto = runCatching { item(target.id) }.getOrNull()
        val firstSource = itemDto?.mediaSources?.let { sources ->
            sources.firstOrNull { it.id != null && it.id == target.mediaSourceId } ?: sources.firstOrNull()
        }
        val streams = firstSource?.mediaStreams ?: itemDto?.mediaStreams.orEmpty()
        val scoped = firstSource != null
        val sourceBitrate = firstSource?.bitrate?.takeIf { it > 0 }
            ?: streams.filter { it.isVideo || it.isAudio }.sumOf { it.bitRate ?: 0 }.takeIf { it > 0 }
        val audioTracks = EmbyPlayback.languageTracks(streams, subtitles = false, firstSource?.defaultAudioStreamIndex, scoped)
        val itemSubtitleTracks = EmbyPlayback.languageTracks(streams, subtitles = true, firstSource?.defaultSubtitleStreamIndex, scoped)
        val audioIndex = PlaybackLanguage.audioIndex(audioTracks, audioLanguage)
        val subtitleIndex = PlaybackLanguage.subtitleIndex(itemSubtitleTracks, subtitleLanguage)
        val maxBitrate = bitrate(sourceBitrate).coerceIn(1, JellyfinLibrary.MAX_BITRATE)
        val off = subtitleLanguage == PlaybackPreferences.OFF
        val explicitSubtitle = subtitleLanguage != PlaybackPreferences.AUTOMATIC && subtitleLanguage.isNotEmpty()
        val preferences = runCatching { playbackPreferences() }.getOrNull()
        val plannedSubtitle = when {
            off -> -1
            explicitSubtitle -> subtitleIndex
            else -> PlaybackLanguage.startingSubtitleIndex(
                tracks = itemSubtitleTracks,
                serverIndex = firstSource?.defaultSubtitleStreamIndex,
                mode = preferences?.subtitleMode ?: SubtitlePlaybackMode.DEFAULT,
                preferredLanguage = preferences?.subtitleLanguage.orEmpty(),
                audioLanguage = audioTracks.firstOrNull { it.index == audioIndex }?.language,
                preferSdh = preferSdh,
                deviceLanguage = Locale.getDefault().language,
            )
        }
        val requestedSubtitle = when {
            off -> -1
            explicitSubtitle -> subtitleIndex
            else -> plannedSubtitle
        }
        val response = api.post(
            "/Items/${target.id}/PlaybackInfo",
            EmbyPlaybackInfo.serializer(),
            embyQuery {
                this["UserId"] = user
                this["StartTimeTicks"] = TickClock.ticks(resume)
                this["IsPlayback"] = true
                this["AutoOpenLiveStream"] = true
                this["MaxStreamingBitrate"] = maxBitrate
                this["AudioStreamIndex"] = audioIndex
                this["SubtitleStreamIndex"] = requestedSubtitle
                this["MediaSourceId"] = firstSource?.id
            },
            json = playbackInfoBody(maxBitrate),
        )
        if (!response.errorCode.isNullOrBlank()) {
            throw ZelefinException.server("Emby could not play this title (${response.errorCode}).")
        }
        val source = EmbyPlayback.source(response, firstSource?.id)
            ?: throw ZelefinException.server("The server did not return a playable stream.")
        val method = EmbyPlayback.method(source)
        val token = api.accessToken
        val url = EmbyPlayback.streamUrl(api.baseUrl, token, target.id, source, method, api.deviceId, response.playSessionId)
            ?: throw ZelefinException.missingStreamUrl()
        val externalSubtitles = EmbyPlayback.externalSubtitles(api.baseUrl, token, target.id, source, method)
        val sideloaded = EmbyPlayback.sideloadedIndexes(externalSubtitles)
        val playbackStreams = source.mediaStreams
        val sourceStreams = if (playbackStreams.any { it.isSubtitle } || streams.none { it.isSubtitle }) {
            playbackStreams.ifEmpty { streams }
        } else {
            val merged = playbackStreams.associateBy { it.index }.toMutableMap()
            streams.forEach { stream -> if (stream.index !in merged) merged[stream.index] = stream }
            merged.values.sortedBy { it.index }
        }
        val chosenAudio = source.defaultAudioStreamIndex ?: audioIndex
        val subtitleTracks = EmbyPlayback.languageTracks(sourceStreams, subtitles = true, source.defaultSubtitleStreamIndex, scoped = true)
            .ifEmpty { itemSubtitleTracks }
        val serverSubtitle = when {
            off -> null
            explicitSubtitle -> subtitleIndex?.takeIf { it >= 0 }
            else -> source.defaultSubtitleStreamIndex?.takeIf { it >= 0 } ?: plannedSubtitle?.takeIf { it >= 0 }
        }
        val chosenSubtitle = if (off) {
            -1
        } else {
            PlaybackLanguage.startingSubtitleIndex(
                tracks = subtitleTracks,
                serverIndex = serverSubtitle,
                mode = preferences?.subtitleMode ?: SubtitlePlaybackMode.DEFAULT,
                preferredLanguage = preferences?.subtitleLanguage.orEmpty(),
                audioLanguage = sourceStreams.firstOrNull { it.isAudio && it.index == chosenAudio }?.language,
                preferSdh = preferSdh,
                deviceLanguage = Locale.getDefault().language,
                forcedByUser = explicitSubtitle,
            )
        }
        response.playSessionId?.let { streamPicks[it] = StreamPick(chosenAudio, chosenSubtitle, source.liveStreamId) }
        PlaybackPlan(
            item = target,
            streamUrl = url,
            playSessionId = response.playSessionId,
            mediaSourceId = source.id,
            method = method,
            container = source.container,
            videoCodec = source.mediaStreams.firstOrNull(EmbyMediaStream::isVideo)?.codec,
            startTimeSeconds = resume,
            headers = GatewayCredentials.headers(),
            clientOwnsPlayhead = true,
            chapters = EmbyPlayback.chapters(itemDto?.allChapters.orEmpty().ifEmpty { source.chapters }),
            externalSubtitles = externalSubtitles,
            appliedBitrate = maxBitrate,
            sourceBitrate = source.bitrate?.takeIf { it > 0 } ?: sourceBitrate,
            audioChoice = if (method == PlaybackMethod.DirectPlay) EmbyPlayback.trackChoice(sourceStreams, subtitles = false, chosenAudio) else null,
            subtitleChoice = if (chosenSubtitle == -1) {
                null
            } else {
                EmbyPlayback.trackChoice(sourceStreams, subtitles = true, chosenSubtitle, sideloaded)
                    ?.takeIf { method == PlaybackMethod.DirectPlay || it.externalId != null }
            },
            subtitlesOff = chosenSubtitle == -1 || chosenSubtitle == null,
            bifUrl = api.url("/Videos/${target.id}/index.bif", embyQuery { this["Width"] = 320 }),
        )
    }

    /** Emby reads Jellyfin's DeviceProfile JSON: the same PascalCase keys and enum spellings. */
    private fun playbackInfoBody(maxBitrate: Int): String = buildJsonObject {
        put("DeviceProfile", ProfileJson.encodeToJsonElement(DeviceProfile.serializer(), JellyfinLibrary.deviceProfile(maxBitrate)))
    }.toString()

    suspend fun reportStart(plan: PlaybackPlan, position: Double) = report("/Sessions/Playing", plan, position, paused = false)

    suspend fun reportProgress(plan: PlaybackPlan, position: Double, paused: Boolean) =
        report("/Sessions/Playing/Progress", plan, position, paused)

    /** Stopping also ends a transcode and closes a live stream, which Emby otherwise keeps open for a while. */
    suspend fun reportStop(plan: PlaybackPlan, position: Double) {
        report("/Sessions/Playing/Stopped", plan, position, paused = true)
        val session = plan.playSessionId ?: return
        streamPicks.remove(session)?.liveStreamId?.let { live -> runCatching { closeLiveStream(live) } }
        if (plan.method != PlaybackMethod.DirectPlay) {
            runCatching {
                api.send("DELETE", "/Videos/ActiveEncodings", embyQuery {
                    this["DeviceId"] = api.deviceId
                    this["PlaySessionId"] = session
                })
            }
        }
    }

    private suspend fun report(path: String, plan: PlaybackPlan, position: Double, paused: Boolean) {
        val pick = plan.playSessionId?.let(streamPicks::get)
        val audio = pick?.audio
        val subtitle = pick?.subtitle
        val body = buildJsonObject {
            put("ItemId", plan.item.id)
            plan.mediaSourceId?.let { put("MediaSourceId", it) }
            plan.playSessionId?.let { put("PlaySessionId", it) }
            put("PositionTicks", TickClock.ticks(position))
            put("IsPaused", paused)
            put("CanSeek", true)
            put(
                "PlayMethod",
                when (plan.method) {
                    PlaybackMethod.DirectPlay -> "DirectPlay"
                    PlaybackMethod.Remux -> "DirectStream"
                    PlaybackMethod.Transcode -> "Transcode"
                },
            )
            audio?.let { put("AudioStreamIndex", it) }
            subtitle?.let { put("SubtitleStreamIndex", it) }
        }.toString()
        expectOk(api.send("POST", path, json = body))
    }

    /** The first theme song and theme video, inherited from the series for seasons and episodes. */
    suspend fun themeMedia(itemId: String): ThemeMedia = withContext(Dispatchers.IO) {
        val result = runCatching {
            api.get("/Items/$itemId/ThemeMedia", EmbyThemeMedia.serializer(), embyQuery {
                this["UserId"] = user
                this["InheritFromParent"] = true
                this["Fields"] = "MediaSources,Container"
            })
        }.getOrNull()
        val song = result?.themeSongs?.items?.firstOrNull()?.id
        val video = result?.themeVideos?.items?.firstOrNull()
        ThemeMedia(
            songUrl = song?.let { themeSongUrl(it) },
            videoUrl = video?.id?.let { themeVideoUrl(it, video.mediaSources.firstOrNull()?.id, video.container) },
        )
    }

    private fun themeSongUrl(id: String): String = api.url(
        "/Audio/$id/universal",
        embyQuery {
            this["UserId"] = user
            this["DeviceId"] = api.deviceId
            this["MaxStreamingBitrate"] = 320_000
            this["Container"] = "mp3,aac,m4a,m4b,flac,alac,wav,ogg,opus"
            this["TranscodingContainer"] = "mp3"
            this["TranscodingProtocol"] = "http"
            this["AudioCodec"] = "mp3"
        },
    )

    /** Containers ExoPlayer opens stream as they are; anything else comes back as H.264 HLS. */
    private fun themeVideoUrl(id: String, mediaSourceId: String?, container: String?): String {
        val sourceId = mediaSourceId?.takeIf { it.isNotBlank() }
        val containers = container.orEmpty().lowercase().split(",")
        if (containers.any { it in setOf("mp4", "m4v", "mov", "mkv", "webm") }) {
            return api.url("/Videos/$id/stream", embyQuery {
                this["Static"] = true
                this["MediaSourceId"] = sourceId
            })
        }
        return api.url("/Videos/$id/master.m3u8", embyQuery {
            this["MediaSourceId"] = sourceId
            this["DeviceId"] = api.deviceId
            this["VideoCodec"] = "h264"
            this["AudioCodec"] = "aac"
            this["MaxStreamingBitrate"] = 8_000_000
            this["SegmentContainer"] = "ts"
            this["TranscodingMaxAudioChannels"] = 2
        })
    }

    /** Times a `/Playback/BitrateTest` download for adaptive bitrate and Settings → Test Connection. */
    suspend fun measureBitrate(size: Int, timeoutMillis: Long, transport: NetworkTransport): BitrateProbeResult? =
        withContext(Dispatchers.IO) {
            val request = api.request("/Playback/BitrateTest", embyQuery { this["Size"] = size }).get().build()
            timedBitrateDownload(request, timeoutMillis, transport, "Emby")
        }

    /** The user's Emby audio and subtitle settings, in the shape Settings → Playback edits. */
    suspend fun playbackPreferences(): JellyfinPlaybackPreferences = withContext(Dispatchers.IO) {
        val configuration = configuration()
        fun text(key: String) = (configuration[key] as? JsonPrimitive)?.contentOrNull
        JellyfinPlaybackPreferences(
            audioLanguage = ServerLanguageCode.fromServer(text("AudioLanguagePreference")),
            playDefaultAudioTrack = text("PlayDefaultAudioTrack")?.toBooleanStrictOrNull() ?: false,
            subtitleLanguage = ServerLanguageCode.fromServer(text("SubtitleLanguagePreference")),
            subtitleMode = SubtitlePlaybackMode.entries.firstOrNull { it.serialName.equals(text("SubtitleMode"), ignoreCase = true) }
                ?: SubtitlePlaybackMode.DEFAULT,
        )
    }

    suspend fun savePlaybackPreferences(preferences: JellyfinPlaybackPreferences) = withContext(Dispatchers.IO) {
        updateConfiguration(
            audio = ServerLanguageCode.toServer(preferences.audioLanguage),
            playDefaultAudio = preferences.playDefaultAudioTrack,
            subtitle = ServerLanguageCode.toServer(preferences.subtitleLanguage),
            mode = preferences.subtitleMode,
        )
    }

    /** Mirrors [JellyfinLibrary.applyPlaybackLanguages] for the signed-in Emby user. */
    suspend fun applyPlaybackLanguages(audioCode: String, subtitleCode: String) = withContext(Dispatchers.IO) {
        val automatic = PlaybackPreferences.AUTOMATIC
        val off = PlaybackPreferences.OFF
        val audio = if (audioCode == automatic) "" else ServerLanguageCode.toServer(audioCode)
        val subtitle = if (subtitleCode == automatic || subtitleCode == off) "" else ServerLanguageCode.toServer(subtitleCode)
        val mode = when {
            subtitleCode == off -> SubtitlePlaybackMode.NONE
            subtitle.isEmpty() -> SubtitlePlaybackMode.DEFAULT
            else -> SubtitlePlaybackMode.SMART
        }
        runCatching { updateConfiguration(audio, audio.isEmpty(), subtitle, mode) }
        Unit
    }

    internal suspend fun configuration(): JsonObject {
        val reply = api.send("GET", "/Users/$user")
        expectOk(reply)
        val root = runCatching { EmbyJson.parser.parseToJsonElement(reply.body).jsonObject }.getOrNull()
        return root?.get("Configuration") as? JsonObject ?: throw ZelefinException.server("Emby did not return this user's settings.")
    }

    /** Emby replaces the whole configuration, so the rest of it is sent back untouched. */
    private suspend fun updateConfiguration(audio: String, playDefaultAudio: Boolean, subtitle: String, mode: SubtitlePlaybackMode) {
        val current = configuration()
        val updated = JsonObject(
            current + mapOf(
                "AudioLanguagePreference" to JsonPrimitive(audio),
                "PlayDefaultAudioTrack" to JsonPrimitive(playDefaultAudio),
                "SubtitleLanguagePreference" to JsonPrimitive(subtitle),
                "SubtitleMode" to JsonPrimitive(mode.serialName),
            ),
        )
        expectOk(api.send("POST", "/Users/$user/Configuration", json = updated.toString()))
    }

    internal suspend fun page(path: String, build: EmbyQuery.() -> Unit = {}): EmbyItemsResult =
        api.get(path, EmbyItemsResult.serializer(), embyQuery(build))

    private suspend fun listOrEmpty(queue: PlaybackQueueKind, load: suspend () -> EmbyItemsResult): List<MediaItem> =
        runCatching { load().items.media(queue) }.getOrDefault(emptyList())

    internal fun EmbyQuery.listDefaults(fields: List<String> = ListFields) {
        this["Fields"] = fields
        this["EnableUserData"] = true
        this["EnableImageTypes"] = ImageTypes
    }

    internal fun expectOk(reply: EmbyApi.Reply) {
        if (reply.ok) return
        throw ZelefinException.server(if (reply.status == 401) "Emby did not accept this sign-in. Sign in again." else "Emby answered HTTP ${reply.status}.")
    }

    companion object {
        private const val PageSize = 200
        private const val MaxItems = 20_000
        private const val ImageTypes = "Primary,Thumb,Backdrop,Logo"

        /** Emby leaves these out of list items unless they are asked for. */
        internal val ListFields = listOf(
            "Overview", "Genres", "MediaStreams", "ProviderIds", "People", "ProductionYear", "PremiereDate",
            "OfficialRating", "CommunityRating", "CriticRating", "Width", "Height",
        )
        private val CatalogFields = listOf(
            "Genres", "MediaStreams", "ProviderIds", "ProductionYear", "PremiereDate",
            "OfficialRating", "CommunityRating", "CriticRating", "Width", "Height",
        )

        private val ProfileJson = Json {
            encodeDefaults = true
            explicitNulls = false
        }

        internal fun List<EmbyItem>.media(queue: PlaybackQueueKind = PlaybackQueueKind.Resume): List<MediaItem> =
            mapNotNull { ItemMapper.mediaItem(it.toSnapshot(), queue) }

        private fun List<String>.toChoices(): List<CatalogFilterChoice> = map { it.trim() }
            .filter { it.isNotEmpty() }
            .distinct()
            .sortedBy { it.lowercase() }
            .map { CatalogFilterChoice(it, it) }

        private fun CatalogSortField.embySort(): String = when (this) {
            CatalogSortField.Name -> "SortName"
            CatalogSortField.Random -> "Random"
            CatalogSortField.CommunityRating -> "CommunityRating"
            CatalogSortField.CriticRating -> "CriticRating"
            CatalogSortField.DateAdded -> "DateCreated"
            CatalogSortField.DatePlayed -> "DatePlayed"
            CatalogSortField.ParentalRating -> "OfficialRating"
            CatalogSortField.PlayCount -> "PlayCount"
            CatalogSortField.ReleaseDate -> "PremiereDate"
            CatalogSortField.Runtime -> "Runtime"
        }
    }
}
