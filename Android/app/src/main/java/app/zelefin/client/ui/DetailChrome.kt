package app.zelefin.client.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.offset
import androidx.compose.runtime.snapshotFlow
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.foundation.layout.aspectRatio
import app.zelefin.client.BrowsePage
import app.zelefin.client.EnhancedExtras
import app.zelefin.client.LibraryRoute
import app.zelefin.client.PluginsController
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import android.content.Intent
import android.net.Uri
import app.zelefin.client.ZelefinUiState
import app.zelefin.core.ArtworkUrls
import app.zelefin.core.AudioFormat
import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind
import app.zelefin.core.SavedSession
import app.zelefin.core.TitleDetail
import app.zelefin.core.TitleTrailer
import app.zelefin.core.VideoRange
import app.zelefin.core.VideoResolution

private sealed interface DetailSheet {
    data class More(val item: MediaItem, val anchor: Rect, val context: TitleMenuContext) : DetailSheet
    data object MoreInfo : DetailSheet
    data class Collections(val item: MediaItem) : DetailSheet
    data object Seasons : DetailSheet
    data class DownloadSeasons(val anchor: Rect) : DetailSheet
    data class DownloadVideos(val anchor: Rect) : DetailSheet
    data class Subtitles(val item: MediaItem) : DetailSheet
    data class Review(val existing: app.zelefin.client.plugins.JellyfinEnhancedReview?) : DetailSheet
    data class RemotePlay(val item: MediaItem) : DetailSheet
    data class SyncPlay(val item: MediaItem) : DetailSheet
    data class Images(val item: MediaItem) : DetailSheet
    data class Identify(val item: MediaItem) : DetailSheet
    data class Metadata(val item: MediaItem) : DetailSheet
}

@Composable
fun DetailPage(
    detail: TitleDetail?,
    busy: Boolean,
    state: ZelefinUiState,
    onBack: () -> Unit,
    onPlay: (MediaItem) -> Unit,
    onOpen: (MediaItem) -> Unit,
    onToggleWatched: (MediaItem) -> Unit,
    onToggleFavorite: (MediaItem) -> Unit,
    onCoversDock: (Boolean) -> Unit = {},
    onLoadCollections: suspend (String) -> app.zelefin.client.jellyfin.CollectionEditor = { app.zelefin.client.jellyfin.CollectionEditor(emptyList(), emptySet()) },
    onSetCollectionMember: suspend (String, String, Boolean) -> Unit = { _, _, _ -> },
    onCreateCollection: suspend (String, String) -> Unit = { _, _ -> },
    plugins: PluginsController? = null,
    actions: DetailTitleActions = DetailTitleActions(),
) {
    var sheet by remember { mutableStateOf<DetailSheet?>(null) }
    var note by remember { mutableStateOf<MenuNotice?>(null) }
    var downloadRemoval by remember { mutableStateOf<MediaItem?>(null) }
    DownloadRemovalOverlay(downloadRemoval) { downloadRemoval = null }
    val pageSheet: DetailSheet? = when (val current = sheet) {
        DetailSheet.MoreInfo, is DetailSheet.Collections, is DetailSheet.Subtitles, is DetailSheet.Review -> current
        is DetailSheet.RemotePlay, is DetailSheet.SyncPlay, is DetailSheet.Images, is DetailSheet.Identify, is DetailSheet.Metadata -> current
        else -> null
    }
    val pluginState = plugins?.state?.collectAsState()?.value
    val scope = rememberCoroutineScope()
    val pageItem = detail?.item
    // Owned by the page, not the hero row, so the song keeps playing when the hero scrolls away.
    val theme = rememberThemeMedia(pageItem?.id)
    var extrasRevision by remember(pageItem?.id) { mutableIntStateOf(0) }
    var extras by remember(pageItem?.id) { mutableStateOf<EnhancedExtras?>(null) }
    var reviewBusy by remember { mutableStateOf(false) }
    var reviewError by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(pageItem?.id, pageItem?.tmdbId, pluginState?.jellyfin?.enhanced, extrasRevision) {
        val target = pageItem ?: return@LaunchedEffect
        extras = plugins?.enhancedExtras(target.kind, target.tmdbId)
    }
    fun saveReview(content: String, rating: Double?) {
        val target = pageItem ?: return
        val controller = plugins ?: return
        reviewBusy = true
        reviewError = null
        scope.launch {
            try {
                controller.saveReview(target.kind, target.tmdbId, content, rating)
                sheet = null
                extrasRevision++
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (error: Throwable) {
                reviewError = error.message ?: "The review didn’t save."
            }
            reviewBusy = false
        }
    }
    fun deleteReview(review: app.zelefin.client.plugins.JellyfinEnhancedReview) {
        val target = pageItem ?: return
        val controller = plugins ?: return
        reviewBusy = true
        scope.launch {
            try {
                controller.deleteReview(target.kind, target.tmdbId, review)
                if (sheet is DetailSheet.Review) sheet = null
                extrasRevision++
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (error: Throwable) {
                note = MenuNotice("Reviews", error.message ?: "The review didn’t delete.")
            }
            reviewBusy = false
        }
    }
    val sheetMotion = rememberZelefinSheet(pageSheet)
    BackHandler(enabled = sheet != null || note != null || sheetMotion.displayed != null) {
        if (note != null) note = null else sheet = null
    }
    val coversChrome = sheetMotion.displayed != null
    val coversDock = coversChrome
    androidx.compose.runtime.DisposableEffect(coversDock) {
        onCoversDock(coversDock)
        onDispose { onCoversDock(false) }
    }
    val session = state.session
    val context = LocalContext.current
    val titleId = detail?.item?.id
    var skipCinema by remember(titleId) {
        mutableStateOf(
            titleId != null && context.getSharedPreferences("zelefin.playback", android.content.Context.MODE_PRIVATE)
                .getBoolean("skipCinema.$titleId", false),
        )
    }
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        Box(Modifier.fillMaxSize().zelefinSheetBackdrop(sheetMotion.progress)) {
        if (detail == null) {
            Box(Modifier.fillMaxSize()) {
                GlassBack(onBack)
                Column(
                    Modifier.align(Alignment.Center).padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    if (busy) CircularProgressIndicator(color = ZelefinCyan)
                    state.message?.let { Text(it, color = ZelefinMuted, modifier = Modifier.padding(top = if (busy) 16.dp else 0.dp)) }
                }
            }
        } else {
            val item = detail.item
            var seasonId by remember(item.id, detail.seasons) { mutableStateOf(detail.seasons.firstOrNull()?.id) }
            var seasonJump by remember(item.id) { mutableStateOf<String?>(null) }
            val season = detail.seasons.firstOrNull { it.id == seasonId } ?: detail.seasons.firstOrNull()
            var videoSort by remember(item.id) { mutableStateOf(YouTubeVideoSort.Latest) }
            val pageState = rememberLazyListState()
            LazyColumn(
                state = pageState,
                modifier = Modifier.fillMaxSize(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = dockContentReserve()),
            ) {
                if (item.isYouTube) {
                    val onVideoMore = { video: MediaItem, anchor: Rect ->
                        sheet = DetailSheet.More(video, anchor, TitleMenuContext.Episode)
                    }
                    if (item.kind == MediaKind.Series) {
                        youTubeChannelItems(
                            detail = detail,
                            session = session,
                            sort = videoSort,
                            onSort = { videoSort = it },
                            onPlay = onPlay,
                            onOpenVideo = onOpen,
                            onToggleFavorite = onToggleFavorite,
                            onMore = onVideoMore,
                        )
                    } else {
                        youTubeVideoItems(
                            detail = detail,
                            session = session,
                            onPlay = onPlay,
                            onOpenVideo = onOpen,
                            onOpenChannel = onOpen,
                            onToggleWatched = onToggleWatched,
                            onToggleFavorite = onToggleFavorite,
                            onMore = onVideoMore,
                        )
                    }
                    return@LazyColumn
                }
                item(key = "hero") {
                    DetailHero(
                        item = item,
                        episodes = detail.episodes,
                        session = session,
                        onPlay = onPlay,
                        onMore = { sheet = DetailSheet.MoreInfo },
                        moreInfo = detail.moreInfo,
                        theme = theme,
                        collectionItems = detail.collectionItems,
                    )
                }
                item(key = "download-status") {
                    DetailDownloadStatus(item, Modifier.padding(bottom = 20.dp))
                }
                if (item.kind == MediaKind.Collection) {
                    collectionGroups(detail.collectionItems).forEach { (title, members) ->
                        item(key = "collection-$title") {
                            SectionTitle(title) { actions.onBrowse(BrowsePage.Library(LibraryRoute.Collection(item.id, item.name))) }
                            LazyRow(
                                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp),
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                items(members, key = { it.id }) { member ->
                                    PortraitHomeCard(member, session) { onOpen(member) }
                                }
                            }
                            Spacer(Modifier.height(20.dp))
                        }
                    }
                }
                if (detail.seasons.isNotEmpty()) {
                    item(key = "episodes") {
                        EpisodeStripSection(
                            seasons = detail.seasons,
                            episodes = detail.episodes,
                            season = season,
                            seasonId = seasonId,
                            seasonJump = seasonJump,
                            session = session,
                            onSeason = { seasonId = it },
                            onJumpConsumed = { seasonJump = null },
                            onOpenSeasons = { sheet = DetailSheet.Seasons },
                            onPlay = onPlay,
                            onMore = { episode, anchor ->
                                sheet = DetailSheet.More(episode, anchor, TitleMenuContext.Episode)
                            },
                        )
                    }
                }
                if (detail.additionalParts.isNotEmpty()) {
                    item(key = "parts") {
                        SectionTitle("Additional Parts")
                        LazyRow(
                            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            items(detail.additionalParts, key = { it.id }) { part ->
                                PortraitHomeCard(part, session) { onPlay(part) }
                            }
                        }
                        Spacer(Modifier.height(20.dp))
                    }
                }
                if (detail.trailers.isNotEmpty()) {
                    item(key = "trailers") {
                        SectionTitle("Trailers") { actions.onBrowse(BrowsePage.Trailers(detail.trailers, item)) }
                        LazyRow(
                            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            items(detail.trailers, key = { it.id }) { trailer ->
                                TrailerCard(trailer, item, session) {
                                    val local = trailer.localItem
                                    if (local != null) {
                                        onPlay(local)
                                    } else {
                                        val url = trailer.watchUrl ?: return@TrailerCard
                                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                                    }
                                }
                            }
                        }
                        Spacer(Modifier.height(20.dp))
                    }
                }
                if (detail.related.isNotEmpty()) {
                    item(key = "related") {
                        SectionTitle("Related") { actions.onBrowse(BrowsePage.Shelf("Related", detail.related)) }
                        LazyRow(
                            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            items(detail.related, key = { it.id }) { related ->
                                PortraitHomeCard(related, session) { onOpen(related) }
                            }
                        }
                        Spacer(Modifier.height(20.dp))
                    }
                }
                if (item.people.isNotEmpty()) {
                    item(key = "cast") {
                        SectionTitle("Cast & Crew") { actions.onBrowse(BrowsePage.Cast(item.people)) }
                        LazyRow(
                            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            items(item.people.take(24), key = { it.id + it.roleLabel }) { person ->
                                CastCard(
                                    person,
                                    session,
                                    onClick = personRoute(person, session)?.let { route -> { actions.onBrowse(BrowsePage.Library(route)) } },
                                )
                            }
                        }
                        Spacer(Modifier.height(20.dp))
                    }
                }
                items(detail.collections, key = { it.collection.id }) { membership ->
                    val title = if (detail.collections.size > 1) membership.collection.name else "Collection"
                    SectionTitle(title) { onOpen(membership.collection) }
                    LazyRow(
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        items(membership.items, key = { member -> membership.collection.id + member.id }) { member ->
                            PortraitHomeCard(member, session) { onOpen(member) }
                        }
                    }
                    Spacer(Modifier.height(20.dp))
                }
                item(key = "about") { AboutRow(item) { sheet = DetailSheet.MoreInfo } }
                extras?.let { loaded ->
                    item(key = "enhanced") {
                        TitleEnhancedExtras(
                            extras = loaded,
                            isAdministrator = pluginState?.isAdmin == true,
                            isOwn = { plugins?.isOwnReview(it) == true },
                            onWrite = {
                                reviewError = null
                                sheet = DetailSheet.Review(loaded.reviews.firstOrNull { plugins?.isOwnReview(it) == true })
                            },
                            onDelete = ::deleteReview,
                        )
                    }
                }
                item(key = "information") { FactsBlock("Information", detail.moreInfo.information) }
                item(key = "languages") { FactsBlock("Languages", detail.moreInfo.languages) }
                item(key = "file") { FactsBlock("File", detail.moreInfo.file) }
            }
            var chromeShown by remember(item.id) { mutableStateOf(true) }
            if (item.isYouTube) {
                LaunchedEffect(pageState) {
                    var previous = 0
                    var travel = 0
                    snapshotFlow { pageState.firstVisibleItemIndex * 100_000 + pageState.firstVisibleItemScrollOffset }
                        .collect { offset ->
                            val delta = offset - previous
                            previous = offset
                            travel = if (delta != 0 && (delta > 0) != (travel > 0)) delta else travel + delta
                            chromeShown = when {
                                offset <= 40 -> true
                                travel > 24 -> false
                                travel < -24 -> true
                                else -> chromeShown
                            }
                        }
                }
            }
            val chromeShift by animateDpAsState(if (chromeShown) 0.dp else (-120).dp, tween(180), label = "detailChrome")
            if (!coversChrome) {
                GlassBack(onBack, Modifier.align(Alignment.TopStart).offset(y = chromeShift))
                Row(
                    Modifier
                        .align(Alignment.TopEnd)
                        .offset(y = chromeShift)
                        .statusBarsPadding()
                        .padding(end = 12.dp, top = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    GlassMore { anchor ->
                        sheet = DetailSheet.More(
                            if (item.isYouTube) item else MediaItem.heroPlaybackItem(item, detail.episodes),
                            anchor,
                            TitleMenuContext.Detail,
                        )
                    }
                    DownloadSharePill(
                        item = item,
                        episodes = detail.episodes,
                        seasons = detail.seasons,
                        onShare = { shareTitle(context, item, session) },
                        onRemove = { downloadRemoval = it },
                        onChooseSeasons = {
                            sheet = if (item.isYouTube) DetailSheet.DownloadVideos(it) else DetailSheet.DownloadSeasons(it)
                        },
                    )
                }
            }
            if (sheet is DetailSheet.Seasons) {
                SeasonMenu(
                    seasons = detail.seasons,
                    selectedId = seasonId,
                    onSelect = {
                        seasonId = it
                        seasonJump = it
                        sheet = null
                    },
                    onDismiss = { sheet = null },
                )
            }
        }
        if (sheetMotion.displayed != null) ZelefinSheetScrim(sheetMotion.progress)
        }
        if (detail != null) {
            when (val shown = sheetMotion.displayed) {
                DetailSheet.MoreInfo -> Box(Modifier.fillMaxSize().zelefinSheetRise(sheetMotion.progress)) {
                    MoreInfoSheet(detail.item, detail.moreInfo) { sheet = null }
                }
                is DetailSheet.Collections -> Box(Modifier.fillMaxSize().zelefinSheetRise(sheetMotion.progress)) {
                    CollectionSheet(
                        item = shown.item,
                        onLoad = onLoadCollections,
                        onSetMember = onSetCollectionMember,
                        onCreate = onCreateCollection,
                        onDismiss = { sheet = null },
                    )
                }
                is DetailSheet.Subtitles -> if (plugins != null) {
                    ZelefinSheetSurface(sheetMotion.progress) {
                        OpenSubtitlesSheet(
                            item = shown.item,
                            plugins = plugins,
                            onClose = { sheet = null },
                            onSaved = actions.onRefreshDetail,
                        )
                    }
                }
                is DetailSheet.RemotePlay -> ZelefinSheetSurface(sheetMotion.progress) {
                    RemotePlaySheet(
                        item = shown.item,
                        onLoad = actions.remoteTargets ?: { emptyList() },
                        onPlay = actions.playOnRemote,
                        onClose = { sheet = null },
                    )
                }
                is DetailSheet.SyncPlay -> ZelefinSheetSurface(sheetMotion.progress) {
                    SyncPlaySheet(
                        item = shown.item,
                        defaultGroupName = session?.userName?.let { "$it’s group" } ?: "Watch Together",
                        onLoad = actions.syncPlayGroups ?: { emptyList() },
                        onStart = actions.playInSyncPlay,
                        onClose = { sheet = null },
                    )
                }
                is DetailSheet.Images -> ZelefinSheetSurface(sheetMotion.progress) {
                    ImagePickerSheet(
                        item = shown.item,
                        onLoad = actions.remoteArtwork ?: { _, _ -> emptyList() },
                        onChoose = actions.applyArtwork,
                        onClose = { sheet = null },
                    )
                }
                is DetailSheet.Identify -> ZelefinSheetSurface(sheetMotion.progress) {
                    IdentifySheet(
                        item = shown.item,
                        onSearch = actions.identifyHits ?: { emptyList() },
                        onApply = actions.applyIdentify ?: { _, _ -> },
                        onClose = { sheet = null },
                    )
                }
                is DetailSheet.Metadata -> ZelefinSheetSurface(sheetMotion.progress) {
                    EditMetadataSheet(
                        item = shown.item,
                        onSave = actions.saveMetadata ?: { _, _ -> },
                        onClose = { sheet = null },
                    )
                }
                is DetailSheet.Review -> ZelefinSheetSurface(sheetMotion.progress) {
                    TitleReviewEditor(
                        existing = shown.existing,
                        busy = reviewBusy,
                        error = reviewError,
                        onSave = ::saveReview,
                        onDelete = shown.existing?.let { review -> { deleteReview(review) } },
                        onClose = { sheet = null },
                    )
                }
                else -> Unit
            }
        }
    }
    val more = sheet as? DetailSheet.More
    TitleMoreOverlay(
        request = more?.let { TitleMoreRequest(it.item, it.context, it.anchor) },
        onDismiss = { sheet = null },
        onPlay = { target ->
            if (target.isYouTube && target.kind == MediaKind.Series) {
                detail?.channelVideos?.firstOrNull()?.let(onPlay)
            } else {
                onPlay(target)
            }
        },
        onOpen = onOpen,
        onToggleWatched = onToggleWatched,
        onToggleFavorite = onToggleFavorite,
        onToggleWatchlist = actions.onToggleWatchlist,
        onIdentify = actions.identifyHits?.let { { target -> sheet = DetailSheet.Identify(pageItem ?: target) } },
        onEditMetadata = actions.saveMetadata?.let { { target -> sheet = DetailSheet.Metadata(pageItem ?: target) } },
        onDownloadSeason = actions.downloadRelated,
        usesSilo = session?.usesSilo == true,
        skipCinemaIntros = skipCinema,
        onCollections = detail?.item?.let { pageItem ->
            if (session?.usesSilo == true || pageItem.kind == MediaKind.Collection) null else {
                { sheet = DetailSheet.Collections(pageItem) }
            }
        },
        onToggleSkipCinema = {
            val id = titleId ?: return@TitleMoreOverlay
            val next = !skipCinema
            skipCinema = next
            context.getSharedPreferences("zelefin.playback", android.content.Context.MODE_PRIVATE)
                .edit()
                .putBoolean("skipCinema.$id", next)
                .apply()
        },
        note = note,
        onDismissNote = { note = null },
        onAddSubtitles = more?.item?.takeIf { pluginState?.showsAddSubtitles(it.kind) == true }?.let {
            { target -> sheet = DetailSheet.Subtitles(target) }
        },
        isAdmin = pluginState?.isAdmin == true,
        onPlayElsewhere = actions.remoteTargets?.let { { target -> sheet = DetailSheet.RemotePlay(target) } },
        onSyncPlay = actions.syncPlayGroups?.let { { target -> sheet = DetailSheet.SyncPlay(target) } },
        onRefreshMetadata = actions.refreshMetadata?.let { refresh -> { target -> refresh(pageItem ?: target) } },
        onEditImages = actions.remoteArtwork?.let { { target -> sheet = DetailSheet.Images(pageItem ?: target) } },
        onDeleteFromLibrary = actions.deleteFromLibrary
            ?.takeIf { pageItem?.kind != MediaKind.Collection }
            ?.let { delete -> { target -> delete(pageItem ?: target) } },
    )
    val downloadVideos = sheet as? DetailSheet.DownloadVideos
    YouTubeDownloadMenu(
        videos = detail?.channelVideos.orEmpty(),
        anchor = downloadVideos?.anchor ?: Rect.Zero,
        visible = downloadVideos != null && detail != null,
        onDismiss = { sheet = null },
    )
    val downloadSeasons = sheet as? DetailSheet.DownloadSeasons
    DownloadSeasonsSheet(
        seasons = detail?.seasons.orEmpty(),
        episodes = detail?.episodes.orEmpty(),
        anchor = downloadSeasons?.anchor ?: Rect.Zero,
        visible = downloadSeasons != null && detail != null,
        onConfirm = { indexes ->
            val page = detail ?: return@DownloadSeasonsSheet
            sheet = null
            startSeasonDownload(
                indexes,
                page.episodes,
                app.zelefin.client.downloads.DownloadEligibility.playableItem(page.item, page.episodes) ?: page.item,
            )
        },
        onDismiss = { sheet = null },
    )
}

private fun personRoute(person: app.zelefin.core.CreditPerson, session: SavedSession?): LibraryRoute.Person? =
    if (session?.usesSilo == true || person.id.isBlank()) null else LibraryRoute.Person(person.id, person.name)

@Composable
private fun DetailHero(
    item: MediaItem,
    episodes: List<MediaItem>,
    session: app.zelefin.core.SavedSession?,
    onPlay: (MediaItem) -> Unit,
    onMore: () -> Unit,
    moreInfo: app.zelefin.core.TitleMoreInfo,
    theme: ThemeMediaPlayers? = null,
    collectionItems: List<MediaItem> = emptyList(),
) {
    val screenHeight = LocalConfiguration.current.screenHeightDp.dp
    val heroHeight = (screenHeight * 0.82f).coerceAtLeast(560.dp).coerceAtMost(screenHeight)
    val isCollection = item.kind == MediaKind.Collection
    val playback = if (isCollection) collectionPlaybackItem(item, collectionItems) else MediaItem.heroPlaybackItem(item, episodes)
    Box(Modifier.fillMaxWidth().height(heroHeight)) {
        CachedArtwork(
            urls = heroArtworkCandidates(item, session),
            contentDescription = item.name,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        theme?.let { ThemeVideoBackdrop(it, Modifier.fillMaxSize()) }
        Box(
            Modifier
                .fillMaxWidth()
                .height(heroHeight / 2)
                .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.5f), Color.Transparent))),
        )
        Box(
            Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        0.28f to Color.Transparent,
                        0.58f to Color.Black.copy(alpha = 0.55f),
                        0.86f to Color.Black.copy(alpha = 0.94f),
                        1f to Color.Black,
                    ),
                ),
        )
        Column(
            Modifier
                .align(Alignment.BottomCenter)
                .padding(horizontal = 32.dp)
                .padding(bottom = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            HeroLogo(item, session, maxHeight = 72.dp, maxWidth = 320.dp, titleSize = 34.sp)
            Text(
                if (isCollection) collectionMetadataLine(item, collectionItems) else item.heroMetadataLine,
                color = Color.White.copy(alpha = 0.92f),
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.SemiBold,
                fontSize = 15.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center,
            )
            if (playback.kind != MediaKind.Collection) {
                DetailPlayButton(playback) { onPlay(playback) }
            }
            val overview = item.overview?.takeIf { it.isNotBlank() }
            val showMore = (overview?.length ?: 0) > 90 || moreInfo.hasDetails
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (overview != null) {
                    Box(Modifier.fillMaxWidth()) {
                        Text(
                            overview,
                            color = Color.White.copy(alpha = 0.88f),
                            fontFamily = ZelefinFont,
                            fontSize = 15.sp,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.padding(end = if (showMore) 72.dp else 0.dp),
                        )
                        if (showMore) {
                            MoreCapsule(Modifier.align(Alignment.BottomEnd), onMore)
                        }
                    }
                }
                SpecsRow(item)
                if (overview == null && showMore) {
                    MoreCapsule(Modifier, onMore)
                }
            }
        }
    }
}

/** A collection's titles split into rows by kind, like iOS `CollectionMemberGroup`. */
private fun collectionGroups(members: List<MediaItem>): List<Pair<String, List<MediaItem>>> {
    val grouped = setOf(MediaKind.Movie, MediaKind.Series, MediaKind.Season, MediaKind.Episode)
    val other = members.filter { it.kind !in grouped }
    return listOf(
        "Movies" to members.filter { it.kind == MediaKind.Movie },
        "Shows" to members.filter { it.kind == MediaKind.Series || it.kind == MediaKind.Season },
        "Episodes" to members.filter { it.kind == MediaKind.Episode },
        (if (other.size == members.size) "Titles" else "More") to other,
    ).filter { it.second.isNotEmpty() }
}

/** Play on a collection starts its next unwatched title. */
private fun collectionPlaybackItem(collection: MediaItem, members: List<MediaItem>): MediaItem =
    MediaItem.preferredEpisode(members.filter { it.kind == MediaKind.Movie || it.kind == MediaKind.Episode || it.kind == MediaKind.Unknown })
        ?: collection

/** "Collection · 3 Movies · 1985–1990" */
private fun collectionMetadataLine(collection: MediaItem, members: List<MediaItem>): String {
    val parts = mutableListOf(collection.kindLabel)
    if (members.isNotEmpty()) {
        val noun = if (members.all { it.kind == MediaKind.Movie }) {
            if (members.size == 1) "Movie" else "Movies"
        } else {
            if (members.size == 1) "Title" else "Titles"
        }
        parts += "${members.size} $noun"
    }
    val years = members.mapNotNull { it.year }
    val first = years.minOrNull()
    val last = years.maxOrNull()
    if (first != null && last != null) {
        parts += if (first == last) "$first" else "$first–$last"
    } else {
        parts += collection.genres.take(2)
    }
    return parts.joinToString("  ·  ")
}

@Composable
private fun DetailPlayButton(item: MediaItem, onClick: () -> Unit) {
    Row(
        Modifier
            .width(175.dp)
            .height(45.dp)
            .clip(RoundedCornerShape(50))
            .background(Color.White)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
    ) {
        Icon(Icons.Filled.PlayArrow, contentDescription = null, tint = Color.Black, modifier = Modifier.size(16.dp))
        if (item.progress > 0.02) {
            Box(
                Modifier
                    .width(55.dp)
                    .height(7.dp)
                    .clip(RoundedCornerShape(50))
                    .background(Color.Black.copy(alpha = 0.18f)),
            ) {
                Box(
                    Modifier
                        .fillMaxWidth(item.progress.toFloat().coerceIn(0f, 1f))
                        .height(7.dp)
                        .background(Color.Black.copy(alpha = 0.72f)),
                )
            }
        }
        Text(
            item.playActionDurationLabel ?: "Play",
            color = Color.Black,
            fontFamily = ZelefinFont,
            fontWeight = FontWeight.SemiBold,
            fontSize = 15.sp,
            maxLines = 1,
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SpecsRow(item: MediaItem) {
    val yearRuntime = listOfNotNull(item.year?.toString(), item.runtimeLabel).joinToString(" · ")
    FlowRow(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (yearRuntime.isNotBlank()) {
            Text(yearRuntime, color = Color.White.copy(alpha = 0.88f), fontFamily = ZelefinFont, fontSize = 15.sp, maxLines = 1)
        }
        item.criticRating?.takeIf { it > 0 }?.let { score ->
            Text(
                "${kotlin.math.round(score).toInt()}%",
                color = Color.White.copy(alpha = 0.88f),
                fontFamily = ZelefinFont,
                fontSize = 15.sp,
            )
        }
        item.communityRating?.takeIf { it > 0 }?.let { score ->
            Icon(Icons.Filled.Star, contentDescription = null, tint = Color(0xFFFFD60A), modifier = Modifier.size(12.dp))
            Text(
                if (score <= 10) String.format("%.1f", score) else "${score.toInt()}%",
                color = Color.White.copy(alpha = 0.88f),
                fontFamily = ZelefinFont,
                fontSize = 15.sp,
            )
        }
        item.ageGateLabel?.let { age ->
            Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = Color(0xFF34C759), modifier = Modifier.size(14.dp))
            Text(age, color = Color.White.copy(alpha = 0.88f), fontFamily = ZelefinFont, fontSize = 15.sp)
        }
        item.officialRating?.takeIf { it.isNotBlank() }?.let { SpecBadge(it) }
        resolutionLabel(item.videoResolution)?.let { SpecBadge(it) }
        rangeLabel(item.videoRange)?.let { SpecBadge(it) }
        if (item.audioFormat == AudioFormat.Atmos) SpecBadge("Atmos")
        if (item.hasClosedCaptions) SpecBadge("CC")
        if (item.hasAudioDescription) SpecBadge("AD")
    }
}

@Composable
private fun SpecBadge(value: String) {
    Text(
        value,
        color = Color.White.copy(alpha = 0.9f),
        fontFamily = ZelefinFont,
        fontSize = 12.sp,
        modifier = Modifier.border(1.dp, Color.White.copy(alpha = 0.85f), RoundedCornerShape(3.dp)).padding(horizontal = 4.dp, vertical = 2.dp),
    )
}

@Composable
private fun SeasonHeader(title: String, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(title, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 20.sp)
        Text("↕", color = Color.White.copy(alpha = 0.55f), fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 16.sp)
    }
}

@Composable
private fun SeasonMenu(
    seasons: List<MediaItem>,
    selectedId: String?,
    onSelect: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val haze = LocalZelefinHaze.current ?: return
    CenteredMenuFrame(onDismiss) {
        val run = LocalMenuAction.current
        Column(
            Modifier
                .widthIn(max = 250.dp)
                .zelefinGlassChrome(haze, ZelefinMenuShape)
                .zelefinMenuWidth()
                .padding(vertical = 4.dp),
        ) {
            seasons.forEach { season ->
                val selected = season.id == selectedId
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clickable { run { onSelect(season.id) } }
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.width(22.dp)) {
                        if (selected) {
                            Icon(Icons.Rounded.Check, contentDescription = "Selected", tint = ZelefinCyan, modifier = Modifier.size(16.dp))
                        }
                    }
                    Text(
                        season.seasonMenuTitle,
                        style = MaterialTheme.typography.bodyLarge,
                    )
                }
            }
        }
    }
}

@Composable
private fun MoreCapsule(modifier: Modifier, onClick: () -> Unit) {
    Text(
        "MORE",
        color = Color.White,
        fontFamily = ZelefinFont,
        fontWeight = FontWeight.Bold,
        fontSize = 12.sp,
        modifier = modifier
            .clip(RoundedCornerShape(50))
            .background(Color.White.copy(alpha = 0.16f))
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 4.dp),
    )
}

@Composable
private fun CastCard(person: app.zelefin.core.CreditPerson, session: SavedSession?, onClick: (() -> Unit)? = null) {
    val photo = session?.serverUrl?.let { ArtworkUrls.person(it, person, session.accessToken) }
    Column(
        Modifier
            .width(116.dp)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier
                .size(110.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.08f)),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                person.name.firstOrNull()?.uppercaseChar()?.toString() ?: "?",
                color = Color.White,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.Bold,
                fontSize = 28.sp,
            )
            if (photo != null) {
                CachedArtwork(
                    url = photo,
                    contentDescription = person.name,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(person.name, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 12.sp, maxLines = 2, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
        Text(person.roleLabel, color = Color.White.copy(alpha = 0.55f), fontFamily = ZelefinFont, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
    }
}

private val AboutCardColor = Color(0xFF1C1C1E)

@Composable
private fun AboutRow(item: MediaItem, onMore: () -> Unit) {
    val genres = item.genres.filter { it.isNotBlank() }.joinToString(", ") { it.uppercase() }.ifBlank { null }
    val overview = item.overview?.trim()?.ifEmpty { null }
    val critic = item.criticRating?.takeIf { it > 0 }?.let { kotlin.math.round(it).toInt() }
    val audience = item.communityRating?.takeIf { it > 0 }
    val age = item.ageGateLabel
    if (overview == null && genres == null && critic == null && audience == null && age == null) return
    Spacer(Modifier.height(8.dp))
    Text(
        "About",
        color = Color.White,
        fontFamily = ZelefinFont,
        fontWeight = FontWeight.SemiBold,
        fontSize = 20.sp,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
    )
    LazyRow(
        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            AboutSynopsisCard(item.name, genres, overview, onMore)
        }
        critic?.let { score ->
            item {
                AboutRatingCard(
                    value = "$score%",
                    label = "TOMATOMETER",
                    meaning = if (score >= 60) {
                        "$score% of professional critic reviews are positive. Titles at 60% or higher are Fresh."
                    } else {
                        "$score% of professional critic reviews are positive. Titles below 60% are Rotten."
                    },
                    icon = {
                        Box(
                            Modifier
                                .size(26.dp)
                                .background(if (score >= 60) Color(0xFF34C759) else Color(0xFFFF453A), CircleShape),
                        )
                    },
                )
            }
        }
        audience?.let { score ->
            item {
                val value = if (score <= 10) {
                    if (score % 1.0 == 0.0) score.toInt().toString() else String.format("%.1f", score)
                } else {
                    "${score.toInt()}%"
                }
                AboutRatingCard(
                    value = value,
                    label = "AUDIENCE",
                    meaning = if (score <= 10) {
                        "Community score stored on this title, usually from IMDb or TMDB user votes."
                    } else {
                        "Audience score stored on this title."
                    },
                    icon = { Icon(Icons.Filled.Star, contentDescription = null, tint = Color(0xFFFFD60A), modifier = Modifier.size(22.dp)) },
                )
            }
        }
        age?.let { gate ->
            item {
                AboutRatingCard(
                    value = gate,
                    label = "COMMON SENSE",
                    meaning = commonSenseMeaning(item.officialRating, gate),
                    icon = { Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = Color(0xFF34C759), modifier = Modifier.size(24.dp)) },
                )
            }
        }
    }
    Spacer(Modifier.height(20.dp))
}

@Composable
private fun AboutSynopsisCard(title: String, genres: String?, overview: String?, onMore: () -> Unit) {
    Column(
        Modifier
            .width(304.dp)
            .height(164.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(AboutCardColor)
            .clickable(enabled = !overview.isNullOrBlank(), onClick = onMore)
            .padding(12.dp),
    ) {
        Text(title, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
        genres?.let {
            Text(it, color = Color.White.copy(alpha = 0.45f), fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 11.sp, maxLines = 1, modifier = Modifier.padding(top = 4.dp))
        }
        if (!overview.isNullOrBlank()) {
            Box(Modifier.padding(top = 4.dp).weight(1f)) {
                Text(overview, color = Color.White.copy(alpha = 0.92f), fontFamily = ZelefinFont, fontSize = 12.sp, maxLines = 4, overflow = TextOverflow.Ellipsis)
                Row(Modifier.align(Alignment.BottomEnd), verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier
                            .width(36.dp)
                            .height(18.dp)
                            .background(Brush.horizontalGradient(listOf(Color.Transparent, AboutCardColor))),
                    )
                    Text("MORE", color = Color.White.copy(alpha = 0.55f), fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                }
            }
        }
    }
}

@Composable
private fun AboutRatingCard(value: String, label: String, meaning: String, icon: @Composable () -> Unit) {
    Column(
        Modifier
            .width(152.dp)
            .height(164.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(AboutCardColor)
            .padding(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            icon()
            Text(value, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 22.sp, maxLines = 1)
        }
        Text(label, color = Color.White.copy(alpha = 0.45f), fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 11.sp, letterSpacing = 0.6.sp, maxLines = 1, modifier = Modifier.padding(top = 6.dp))
        Text(meaning, color = Color.White.copy(alpha = 0.92f), fontFamily = ZelefinFont, fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp))
    }
}

@Composable
private fun FactsBlock(title: String, rows: List<app.zelefin.core.TitleMoreRow>) {
    if (rows.isEmpty()) return
    Text(
        title,
        color = Color.White,
        fontFamily = ZelefinFont,
        fontWeight = FontWeight.SemiBold,
        fontSize = 20.sp,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
    )
    Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        rows.forEach { row ->
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(row.label, color = Color.White.copy(alpha = 0.48f), fontFamily = ZelefinFont, fontSize = 13.sp)
                Text(row.value, color = Color.White, fontFamily = ZelefinFont, fontSize = 16.sp)
            }
        }
    }
    Spacer(Modifier.height(20.dp))
}

@Composable
private fun MoreInfoSheet(item: MediaItem, info: app.zelefin.core.TitleMoreInfo, onDismiss: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        Spacer(Modifier.statusBarsPadding().height(12.dp))
        Column(
            Modifier
                .weight(1f)
                .fillMaxWidth()
                .clip(RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp))
                .background(Color(0xFF202022)),
        ) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Spacer(Modifier.size(46.dp))
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(item.name, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 20.sp, maxLines = 2, textAlign = TextAlign.Center)
                item.genres.firstOrNull()?.takeIf { it.isNotBlank() }?.let {
                    Text(it, color = Color.White.copy(alpha = 0.72f), fontFamily = ZelefinFont, fontSize = 15.sp)
                }
            }
            Box(
                Modifier
                    .size(46.dp)
                    .clip(CircleShape)
                    .background(DockFill)
                    .border(0.5.dp, DockBorder, CircleShape)
                    .clickable(onClick = onDismiss),
                contentAlignment = Alignment.Center,
            ) {
                Text("✕", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
            }
        }
        Column(
            Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp)
                .padding(top = 20.dp, bottom = 24.dp)
                .navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(28.dp),
        ) {
            item.overview?.takeIf { it.isNotBlank() }?.let {
                Text(it, color = Color.White, fontFamily = ZelefinFont, fontSize = 16.sp)
            }
            SpecsRow(item)
            MoreInfoBlock("Information", info.information)
            MoreInfoBlock("Languages", info.languages)
            MoreInfoBlock("File", info.file)
            if (info.links.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Links", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 22.sp)
                    info.links.forEach { link ->
                        val context = LocalContext.current
                        Text(
                            link.name,
                            color = Color.White,
                            fontFamily = ZelefinFont,
                            fontSize = 16.sp,
                            textDecoration = androidx.compose.ui.text.style.TextDecoration.Underline,
                            modifier = Modifier.clickable {
                                context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(link.url)))
                            },
                        )
                    }
                }
            }
            info.accessibilityNote?.let { note ->
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Accessibility", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 22.sp)
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        SpecBadge("CC")
                        Text(note, color = Color.White.copy(alpha = 0.72f), fontFamily = ZelefinFont, fontSize = 13.sp, modifier = Modifier.weight(1f))
                    }
                }
            }
        }
        }
    }
}

@Composable
private fun MoreInfoBlock(title: String, rows: List<app.zelefin.core.TitleMoreRow>) {
    if (rows.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(title, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 22.sp)
        rows.forEach { row ->
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(row.label, color = Color.White.copy(alpha = 0.48f), fontFamily = ZelefinFont, fontSize = 13.sp)
                Text(row.value, color = Color.White, fontFamily = ZelefinFont, fontSize = 16.sp)
            }
        }
    }
}

private data class EpisodeStripCard(
    val copy: Int,
    val seasonId: String,
    val episode: MediaItem,
) {
    val key: String = "$copy:${episode.id}"
}

private fun commonSenseMeaning(officialRating: String?, ageGate: String): String {
    val compact = (officialRating ?: ageGate).uppercase().filter { !it.isWhitespace() }
    return when {
        compact.contains("NC-17") || compact == "X" || ageGate == "18+" -> "Adults only. No one 17 and under admitted."
        compact == "R" || compact.contains("TV-MA") || ageGate == "17+" -> "Restricted. Under 17 requires accompanying parent or adult guardian. May contain intense violence, strong language, or sexual content."
        compact.contains("PG-13") || ageGate == "13+" -> "Parents strongly cautioned. Some material may be inappropriate for children under 13."
        compact.contains("TV-14") -> "Parents strongly cautioned. May be unsuitable for children under 14."
        compact == "PG" || compact.contains("TV-PG") || ageGate == "7+" -> "Parental guidance suggested. Some material may not be suitable for children."
        compact.contains("TV-Y7") -> "Directed to older children. May include mild fantasy or comedic violence."
        compact == "G" || compact.contains("TV-G") || compact.startsWith("TV-Y") || ageGate == "All" -> "Suitable for all ages."
        else -> "Age guidance based on the title’s official rating."
    }
}

private fun seasonNumber(season: MediaItem): Int? =
    if (season.kind == MediaKind.Season) season.seasonIndex ?: season.episodeIndex else season.seasonIndex

private fun episodeStrip(seasons: List<MediaItem>, episodes: List<MediaItem>): List<EpisodeStripCard> {
    if (episodes.isEmpty()) return emptyList()
    val rank = seasons.mapIndexedNotNull { index, season ->
        seasonNumber(season)?.let { it to index }
    }.toMap()
    val ordered = episodes.sortedWith(
        compareBy(
            { rank[it.seasonIndex] ?: Int.MAX_VALUE },
            { it.episodeIndex ?: Int.MAX_VALUE },
            { it.name },
        ),
    )
    val base = ordered.map { episode ->
        val seasonId = seasons.firstOrNull { seasonNumber(it) == episode.seasonIndex }?.id
            ?: seasons.firstOrNull()?.id
            ?: ""
        seasonId to episode
    }
    return (0 until 3).flatMap { copy ->
        base.map { (seasonId, episode) -> EpisodeStripCard(copy, seasonId, episode) }
    }
}

private fun episodeStripIndex(strip: List<EpisodeStripCard>, seasonId: String?, copy: Int): Int {
    if (strip.isEmpty()) return -1
    val match = strip.indexOfFirst { card ->
        card.copy == copy && (seasonId == null || card.seasonId == seasonId)
    }
    if (match >= 0) return match
    return strip.indexOfFirst { it.copy == copy }.let { if (it >= 0) it else 0 }
}

@Composable
private fun EpisodeStripSection(
    seasons: List<MediaItem>,
    episodes: List<MediaItem>,
    season: MediaItem?,
    seasonId: String?,
    seasonJump: String?,
    session: app.zelefin.core.SavedSession?,
    onSeason: (String) -> Unit,
    onJumpConsumed: () -> Unit,
    onOpenSeasons: () -> Unit,
    onPlay: (MediaItem) -> Unit,
    onMore: (MediaItem, Rect) -> Unit,
) {
    val strip = remember(seasons, episodes) { episodeStrip(seasons, episodes) }
    val listState = rememberLazyListState(
        initialFirstVisibleItemIndex = episodeStripIndex(strip, seasonId, copy = 1).coerceAtLeast(0),
    )
    LaunchedEffect(seasonJump, strip) {
        val target = seasonJump ?: return@LaunchedEffect
        val index = episodeStripIndex(strip, target, copy = 1)
        if (index >= 0) listState.animateScrollToItem(index)
        onJumpConsumed()
    }
    val leadingSeason = strip.getOrNull(listState.firstVisibleItemIndex)?.seasonId
    LaunchedEffect(leadingSeason) {
        if (!leadingSeason.isNullOrEmpty() && leadingSeason != seasonId) onSeason(leadingSeason)
    }
    LaunchedEffect(listState.isScrollInProgress) {
        if (listState.isScrollInProgress || seasonJump != null) return@LaunchedEffect
        val card = strip.getOrNull(listState.firstVisibleItemIndex) ?: return@LaunchedEffect
        if (card.copy == 1) return@LaunchedEffect
        val home = strip.indexOfFirst { it.copy == 1 && it.episode.id == card.episode.id }
        if (home >= 0 && home != listState.firstVisibleItemIndex) listState.scrollToItem(home)
    }
    SeasonHeader(season?.seasonMenuTitle ?: "Season", onOpenSeasons)
    if (strip.isNotEmpty()) {
        LazyRow(
            state = listState,
            flingBehavior = rememberSnapFlingBehavior(listState),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(strip, key = { it.key }) { card ->
                EpisodeCard(card.episode, session, onPlay) { anchor -> onMore(card.episode, anchor) }
            }
        }
    }
    Spacer(Modifier.height(20.dp))
}

@Composable
private fun EpisodeCard(
    item: MediaItem,
    session: app.zelefin.core.SavedSession?,
    onPlay: (MediaItem) -> Unit,
    onMore: (Rect) -> Unit,
) {
    val anchor = remember { mutableStateOf(Rect.Zero) }
    val ordinal = if (item.seasonIndex != null && item.episodeIndex != null) "S${item.seasonIndex}  E${item.episodeIndex}" else null
    val shape = RoundedCornerShape(10.dp)
    Column(
        Modifier
            .width(252.dp)
            .clip(shape)
            .background(Color.White.copy(alpha = 0.08f))
            .border(PosterOutlineWidth, Color.White.copy(alpha = 0.10f), shape)
            .clickable { onPlay(item) },
    ) {
        Box(Modifier.fillMaxWidth().height(142.dp)) {
            CachedArtwork(
                urls = artworkCandidates(item, session, landscape = true),
                contentDescription = item.name,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
            if (item.isWatched) WatchedMark(Modifier.align(Alignment.TopEnd).padding(8.dp))
        }
        Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
            ordinal?.let {
                Text(it, color = Color.White.copy(alpha = 0.55f), fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 11.sp, letterSpacing = 0.7.sp)
            }
            Text(item.name, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                item.overview.orEmpty(),
                color = Color.White.copy(alpha = 0.62f),
                fontFamily = ZelefinFont,
                fontSize = 12.sp,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(top = 4.dp).height(48.dp),
            )
            Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.PlayArrow, contentDescription = null, tint = Color.White.copy(alpha = 0.84f), modifier = Modifier.size(9.dp))
                item.runtimeLabel?.let {
                    Text(it, color = Color.White.copy(alpha = 0.84f), fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 12.sp, modifier = Modifier.padding(start = 6.dp))
                }
                Spacer(Modifier.weight(1f))
                Icon(
                    Icons.Filled.MoreHoriz,
                    contentDescription = "More",
                    tint = Color.White.copy(alpha = 0.72f),
                    modifier = Modifier
                        .size(28.dp)
                        .onGloballyPositioned { anchor.value = it.boundsInRoot() }
                        .clickable { onMore(anchor.value) },
                )
            }
        }
    }
}

@Composable
internal fun TrailerCard(
    trailer: TitleTrailer,
    title: MediaItem,
    session: app.zelefin.core.SavedSession?,
    fillWidth: Boolean = false,
    onClick: () -> Unit,
) {
    val art = trailer.thumbnailUrl?.let { listOf(it) }
        ?: trailer.localItem?.let { artworkCandidates(it, session, landscape = true) }
        ?: heroArtworkCandidates(title, session)
    Box(
        Modifier
            .then(if (fillWidth) Modifier.fillMaxWidth().aspectRatio(16f / 9f) else Modifier.width(280.dp).height(158.dp))
            .posterChrome()
            .clickable(onClick = onClick),
    ) {
        CachedArtwork(
            urls = art,
            contentDescription = trailer.title,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize().background(Color.White.copy(alpha = 0.08f)),
        )
        Box(
            Modifier
                .align(Alignment.Center)
                .size(44.dp)
                .background(Color.Black.copy(alpha = 0.48f), CircleShape)
                .border(0.8.dp, Color.White.copy(alpha = 0.55f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.PlayArrow, contentDescription = null, tint = Color.White, modifier = Modifier.size(22.dp))
        }
        Box(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .height(62.dp)
                .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.78f)))),
        )
        Column(Modifier.align(Alignment.BottomStart).padding(horizontal = 12.dp, vertical = 10.dp)) {
            Text(trailer.title, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(trailer.caption, color = Color.White.copy(alpha = 0.78f), fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 11.sp, maxLines = 1)
        }
    }
}

@Composable
private fun SectionTitle(title: String, onClick: (() -> Unit)? = null) {
    Row(
        Modifier
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(title, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 20.sp)
        Icon(Icons.Outlined.KeyboardArrowRight, contentDescription = null, tint = Color.White.copy(alpha = 0.45f))
    }
}

@Composable
private fun GlassMore(modifier: Modifier = Modifier, onMore: (Rect) -> Unit) {
    val anchor = remember { mutableStateOf(Rect.Zero) }
    Box(
        modifier
            .size(45.dp)
            .onGloballyPositioned { anchor.value = it.boundsInRoot() }
            .zelefinGlassDisc("detail-more", "More", Icons.Filled.MoreHoriz) { onMore(anchor.value) },
    )
}

private fun shareTitle(context: android.content.Context, item: MediaItem, session: SavedSession?) {
    item.youTubeUrl?.let { url ->
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_SUBJECT, item.name)
            putExtra(Intent.EXTRA_TEXT, "${item.name}\n$url")
        }
        context.startActivity(Intent.createChooser(send, "Share"))
        return
    }
    val serverUrl = session?.serverUrl ?: return
    val itemId = item.seriesDetailItemId ?: item.id
    val title = if (item.seriesDetailItemId == null) item.name else (item.seriesName ?: item.name)
    val headline = item.year?.let { "$title ($it)" } ?: title
    val base = serverUrl.trimEnd('/')
    val web = "$base/web/index.html#!/details?id=$itemId"
    val zelefin = "zelefin://item?id=${Uri.encode(itemId)}&server=${Uri.encode(serverUrl)}"
    val lines = mutableListOf(headline)
    val serverName = session.serverName?.trim().orEmpty().ifEmpty { session.displayServer }
    if (serverName.isNotEmpty()) lines += serverName
    lines += ""
    lines += "Open in Zelefin:"
    lines += zelefin
    lines += ""
    lines += "Or in a browser on this server:"
    lines += web
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, headline)
        putExtra(Intent.EXTRA_TEXT, lines.joinToString("\n"))
    }
    context.startActivity(Intent.createChooser(send, "Share"))
}

@Composable
private fun GlassBack(onBack: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier
            .statusBarsPadding()
            .padding(start = 12.dp, top = 8.dp)
            .size(44.dp)
            .zelefinGlassDisc("detail-back", "Back", Icons.AutoMirrored.Outlined.ArrowBack, onBack),
    )
}

private fun resolutionLabel(resolution: VideoResolution): String? = when (resolution) {
    VideoResolution.Sd -> "SD"
    VideoResolution.Hd -> "HD"
    VideoResolution.FourK -> "4K"
    VideoResolution.Unknown -> null
}

private fun rangeLabel(range: VideoRange): String? = when (range) {
    VideoRange.Sdr -> null
    VideoRange.Hdr10 -> "HDR"
    VideoRange.Hdr10Plus -> "HDR10+"
    VideoRange.DolbyVision -> "Dolby Vision"
    VideoRange.Hlg -> "HLG"
}
