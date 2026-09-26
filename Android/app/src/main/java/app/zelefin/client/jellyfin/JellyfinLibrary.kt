package app.zelefin.client.jellyfin

import android.content.Context
import app.zelefin.client.network.GatewayHttp
import app.zelefin.core.CreditPerson
import app.zelefin.core.FeaturedHero
import app.zelefin.core.HomeFeed
import app.zelefin.client.LibraryRoom
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
import org.jellyfin.sdk.api.client.extensions.get
import org.jellyfin.sdk.api.client.extensions.itemsApi
import org.jellyfin.sdk.api.client.extensions.libraryApi
import org.jellyfin.sdk.api.client.extensions.mediaInfoApi
import org.jellyfin.sdk.api.client.extensions.playStateApi
import org.jellyfin.sdk.api.client.extensions.quickConnectApi
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
import org.jellyfin.sdk.model.api.ItemFields
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
import org.jellyfin.sdk.model.api.SortOrder
import org.jellyfin.sdk.model.api.SubtitleDeliveryMethod
import org.jellyfin.sdk.model.api.SubtitleProfile
import org.jellyfin.sdk.model.api.TranscodingProfile
import org.jellyfin.sdk.model.api.request.GetEpisodesRequest
import org.jellyfin.sdk.model.api.request.GetItemsRequest
import org.jellyfin.sdk.model.api.request.GetNextUpRequest
import org.jellyfin.sdk.model.api.request.GetResumeItemsRequest
import org.jellyfin.sdk.model.api.request.GetSeasonsRequest
import org.jellyfin.sdk.model.api.request.GetSimilarItemsRequest

class JellyfinLibrary(
    context: Context,
    private val baseUrl: String,
    accessToken: String? = null,
) {
    private val api: ApiClient = jellyfin(context).createApi(
        baseUrl = baseUrl,
        accessToken = accessToken,
        httpClientOptions = HttpClientOptions(requestTimeout = 60.seconds, socketTimeout = 60.seconds),
    )

    val serverUrl: String get() = api.baseUrl ?: baseUrl

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

    suspend fun home(userId: UUID): HomeFeed = withContext(Dispatchers.IO) {
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
            ).content.items
        }
        val movies = latest(userId, BaseItemKind.MOVIE)
        val shows = latest(userId, BaseItemKind.SERIES)
        HomeFeed(
            featured = FeaturedHero.interleave(
                movies.filter { it.hasHeroBackdrop && !it.isWatched },
                shows.filter { it.hasHeroBackdrop && !it.isWatched },
            ).ifEmpty { FeaturedHero.interleave(movies, shows) },
            continueWatching = resume,
            nextUp = nextUp,
            recentMovies = movies,
            recentShows = shows,
        )
    }

    suspend fun libraries(userId: UUID): List<LibraryRoom> = withContext(Dispatchers.IO) {
        api.userViewsApi.getUserViews(userId = userId, includeHidden = true).content.items.mapNotNull { dto ->
            val name = dto.name?.trim().orEmpty()
            if (name.isEmpty()) return@mapNotNull null
            LibraryRoom(id = dto.id.toString(), name = name)
        }
    }

    suspend fun itemsInLibrary(userId: UUID, parentId: String): List<MediaItem> = withContext(Dispatchers.IO) {
        api.itemsApi.getItems(
            GetItemsRequest(
                userId = userId,
                parentId = UUID.fromString(parentId),
                recursive = true,
                includeItemTypes = listOf(BaseItemKind.MOVIE, BaseItemKind.SERIES),
                sortBy = listOf(ItemSortBy.SORT_NAME),
                sortOrder = listOf(SortOrder.ASCENDING),
                limit = 80,
                fields = listFields,
                enableUserData = true,
                enableImageTypes = imageTypes,
            ),
        ).content.items.mapNotNull { ItemMapper.mediaItem(it.toSnapshot()) }
    }

    suspend fun catalog(userId: UUID, kind: BaseItemKind): List<MediaItem> = withContext(Dispatchers.IO) {
        val result = api.itemsApi.getItems(
            GetItemsRequest(
                userId = userId,
                recursive = true,
                includeItemTypes = listOf(kind),
                sortBy = listOf(ItemSortBy.DATE_CREATED),
                sortOrder = listOf(SortOrder.DESCENDING),
                limit = 80,
                fields = listFields,
                enableUserData = true,
                enableImageTypes = imageTypes,
            ),
        ).content
        result.items.mapNotNull { ItemMapper.mediaItem(it.toSnapshot()) }
    }

    suspend fun detail(userId: UUID, id: String): TitleDetail = withContext(Dispatchers.IO) {
        val itemId = UUID.fromString(id)
        val dto = api.userLibraryApi.getItem(itemId, userId).content
        val item = ItemMapper.mediaItem(dto.toSnapshot()) ?: throw ZelefinException.server("This title could not be read.")
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
        TitleDetail(
            item = item,
            seasons = seasons,
            episodes = orderedEpisodes,
            related = related,
            trailers = trailers,
            moreInfo = facts,
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

    suspend fun playback(userId: UUID, item: MediaItem): PlaybackPlan = withContext(Dispatchers.IO) {
        val target = item
        val resume = if (target.playbackPosition > PlaybackResumePolicy.THRESHOLD) target.playbackPosition else 0.0
        val response = api.mediaInfoApi.getPostedPlaybackInfo(
            itemId = UUID.fromString(target.id),
            data = PlaybackInfoDto(
                userId = userId,
                maxStreamingBitrate = MAX_BITRATE,
                startTimeTicks = app.zelefin.core.TickClock.ticks(resume),
                deviceProfile = deviceProfile(),
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
        val url = StreamResumeUrl.ensuringStartTimeTicks(rawUrl, method, resume)
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
            clientOwnsPlayhead = method == PlaybackMethod.DirectPlay,
        )
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
        ).content.items.mapNotNull { ItemMapper.mediaItem(it.toSnapshot()) }
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

        fun jellyfin(context: Context) = createJellyfin {
            this.context = context.applicationContext
            clientInfo = ClientInfo(name = "Zelefin", version = "0.1.0")
            val factory = OkHttpFactory(GatewayHttp.client)
            apiClientFactory = factory
            socketConnectionFactory = factory
        }

        fun deviceProfile(): DeviceProfile {
            val videoCodecs = "h264,hevc,av1,vp9,vp8,mpeg4,mpeg2video"
            val audioCodecs = "aac,aac_latm,ac3,eac3,mp3,flac,opus,vorbis,truehd,dts"
            val containers = "mp4,m4v,mov,mkv,matroska,webm,ts,mpegts,avi"
            return DeviceProfile(
                name = "Zelefin",
                maxStreamingBitrate = MAX_BITRATE,
                maxStaticBitrate = MAX_BITRATE,
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
                    SubtitleProfile(format = "srt", method = SubtitleDeliveryMethod.EXTERNAL),
                    SubtitleProfile(format = "ass", method = SubtitleDeliveryMethod.EXTERNAL),
                    SubtitleProfile(format = "pgssub", method = SubtitleDeliveryMethod.EXTERNAL),
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

private fun BaseItemDto.toSnapshot(): JellyfinItemSnapshot {
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
