package app.zelefin.client.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.client.AppTab
import app.zelefin.client.LibraryRoom
import app.zelefin.client.PlayerDirective
import app.zelefin.client.Screen
import app.zelefin.client.ZelefinUiState
import kotlinx.coroutines.flow.SharedFlow
import app.zelefin.core.MediaItem
import app.zelefin.core.PlaybackPlan
import app.zelefin.core.TitleDetail

@Composable
fun LibraryScreen(
    state: ZelefinUiState,
    onTab: (AppTab) -> Unit,
    onOpen: (MediaItem) -> Unit,
    onPlay: (MediaItem) -> Unit,
    onLibraryRoute: (app.zelefin.client.LibraryRoute) -> Unit,
    onLibraryBack: () -> Unit,
    onLibraryQuery: (app.zelefin.client.LibraryRoute, app.zelefin.client.CatalogBrowseQuery) -> Unit,
    onLibraryRefresh: (app.zelefin.client.LibraryRoute) -> Unit,
    onOverviewRefresh: () -> Unit,
    onLibraryFilters: (app.zelefin.client.LibraryRoute) -> Unit,
    onLibraryLayout: (app.zelefin.client.LibraryLayout) -> Unit,
    onResetLibraryLayout: () -> Unit,
    onRefresh: () -> Unit,
    onSignOut: () -> Unit,
    onProfile: () -> Unit,
    onSettings: () -> Unit,
    onSessions: () -> Unit,
    onToggleWatched: (MediaItem) -> Unit,
    onToggleFavorite: (MediaItem) -> Unit,
    onToggleWatchlist: (MediaItem) -> Unit = {},
    onRandom: () -> Unit,
    onCatalogQuery: (AppTab, app.zelefin.client.CatalogBrowseQuery) -> Unit,
    onCatalogRefresh: (AppTab) -> Unit,
    onCatalogFilters: (AppTab) -> Unit,
    onCoversDock: (Boolean) -> Unit,
    onSearchTerm: (String) -> Unit,
    onSearchHit: (app.zelefin.client.SearchHit) -> Unit,
    onSearchOpen: (MediaItem) -> Unit,
    onRemoveRecentSearch: (String) -> Unit,
    onClearRecentSearches: () -> Unit,
    plugins: app.zelefin.client.PluginsController,
    onHideFromHome: suspend (MediaItem, app.zelefin.client.plugins.JellyfinEnhancedHomeSurface) -> String? = { _, _ -> null },
    onSeeAll: (app.zelefin.client.HomeShelf) -> Unit = {},
    onBrowse: (app.zelefin.client.BrowsePage) -> Unit = {},
    onEnsureGrid: (app.zelefin.client.LibraryRoute) -> Unit = {},
) {
    val contentBottom = dockContentReserve()
    val pluginState by plugins.state.collectAsState()
    Box(Modifier.fillMaxSize().background(ZelefinBlack)) {
        Column(Modifier.fillMaxSize()) {
            if (state.tab != AppTab.Library && state.tab != AppTab.Search) {
                state.message?.let { Text(it, color = ZelefinMuted, modifier = Modifier.padding(horizontal = 20.dp)) }
            }
            when (state.tab) {
                AppTab.Home -> HomeFeedPage(
                    state.home,
                    state.session,
                    contentBottom,
                    onOpen,
                    onPlay,
                    state.homeRefreshing,
                    onRefresh,
                    onProfile,
                    onSessions,
                    onSettings,
                    onSignOut,
                    onToggleWatched,
                    onToggleFavorite,
                    onToggleWatchlist = if (state.isSiloServer) null else onToggleWatchlist,
                    onHideFromHome = if (pluginState.hidesFromHome) onHideFromHome else null,
                    onSeeAll = onSeeAll,
                    onBrowse = onBrowse,
                )
                AppTab.Collections, AppTab.Favorites, AppTab.Room -> DockRoutePage(
                    state = state,
                    bottomInset = contentBottom,
                    onOpen = onOpen,
                    onBrowse = onBrowse,
                    onEnsureGrid = onEnsureGrid,
                    onQuery = onLibraryQuery,
                    onRefresh = onLibraryRefresh,
                    onFilters = onLibraryFilters,
                    onCoversDock = onCoversDock,
                    onProfile = onProfile,
                    onSessions = onSessions,
                    onSettings = onSettings,
                    onSignOut = onSignOut,
                )
                AppTab.Movies -> CatalogBrowsePage(
                    title = "Movies",
                    items = state.movies,
                    query = state.movieQuery,
                    options = state.movieFilters,
                    session = state.session,
                    refreshing = state.moviesRefreshing,
                    loading = state.moviesLoading,
                    bottomInset = contentBottom,
                    onOpen = onOpen,
                    onRefresh = { onCatalogRefresh(AppTab.Movies) },
                    onQuery = { onCatalogQuery(AppTab.Movies, it) },
                    onLoadFilters = { onCatalogFilters(AppTab.Movies) },
                    onCoversDock = onCoversDock,
                    onProfile = onProfile,
                    onSessions = onSessions,
                    onSettings = onSettings,
                    onSignOut = onSignOut,
                )
                AppTab.Shows -> CatalogBrowsePage(
                    title = "Shows",
                    items = state.shows,
                    query = state.showQuery,
                    options = state.showFilters,
                    session = state.session,
                    refreshing = state.showsRefreshing,
                    loading = state.showsLoading,
                    bottomInset = contentBottom,
                    onOpen = onOpen,
                    onRefresh = { onCatalogRefresh(AppTab.Shows) },
                    onQuery = { onCatalogQuery(AppTab.Shows, it) },
                    onLoadFilters = { onCatalogFilters(AppTab.Shows) },
                    onCoversDock = onCoversDock,
                    onProfile = onProfile,
                    onSessions = onSessions,
                    onSettings = onSettings,
                    onSignOut = onSignOut,
                )
                AppTab.Library -> LibraryTabPage(
                    state = state,
                    bottomInset = contentBottom,
                    onOpen = onOpen,
                    onRoute = onLibraryRoute,
                    onBack = onLibraryBack,
                    onQuery = onLibraryQuery,
                    onRefresh = onLibraryRefresh,
                    onOverviewRefresh = onOverviewRefresh,
                    refreshing = state.libraryRefreshing,
                    onFilters = onLibraryFilters,
                    onLayout = onLibraryLayout,
                    onResetLayout = onResetLibraryLayout,
                    onCoversDock = onCoversDock,
                    onProfile = onProfile,
                    onSessions = onSessions,
                    onSettings = onSettings,
                    onSignOut = onSignOut,
                    onRandom = onRandom,
                )
                AppTab.Search -> SearchTabPage(
                    state = state,
                    bottomInset = contentBottom,
                    onTerm = onSearchTerm,
                    onHit = onSearchHit,
                    onOpenItem = onSearchOpen,
                    onOpen = onOpen,
                    onPlay = onPlay,
                    onRemoveRecent = onRemoveRecentSearch,
                    onClearRecents = onClearRecentSearches,
                    onRoute = onLibraryRoute,
                    onBack = onLibraryBack,
                    onQuery = onLibraryQuery,
                    onRefresh = onLibraryRefresh,
                    onFilters = onLibraryFilters,
                    onCoversDock = onCoversDock,
                    onProfile = onProfile,
                    onSessions = onSessions,
                    onSettings = onSettings,
                    onSignOut = onSignOut,
                    plugins = plugins,
                )
            }
        }
    }
}

@Composable
fun DetailScreen(
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
    plugins: app.zelefin.client.PluginsController? = null,
    actions: DetailTitleActions = DetailTitleActions(),
) {
    DetailPage(
        detail,
        busy,
        state,
        onBack,
        onPlay,
        onOpen,
        onToggleWatched,
        onToggleFavorite,
        onCoversDock,
        onLoadCollections,
        onSetCollectionMember,
        onCreateCollection,
        plugins,
        actions = actions,
    )
}

@Composable
fun PlayerScreen(
    plan: PlaybackPlan,
    plugins: app.zelefin.client.PluginsController,
    onProgress: (Double, Boolean) -> Unit,
    onStopped: (Double) -> Unit,
    onClose: () -> Unit,
    onPlaybackReady: () -> Unit = {},
    onUserTransport: (PlayerDirective) -> Unit = {},
    directives: SharedFlow<PlayerDirective>? = null,
    session: app.zelefin.core.SavedSession? = null,
    onLoadNext: suspend (MediaItem) -> MediaItem? = { null },
    onPlayNext: (MediaItem, Double) -> Unit = { _, _ -> },
    onReload: (Double) -> Unit = {},
    onRecover: (Double) -> Unit = {},
    onAdaptiveBitrate: ((Int, Double) -> Unit)? = null,
) {
    val pluginState by plugins.state.collectAsState()
    var subtitleSearchAt by remember(plan.streamUrl) { mutableStateOf<Double?>(null) }
    var subtitleSaved by remember(plan.streamUrl) { mutableStateOf(false) }
    val subtitleSheet = rememberZelefinSheet(subtitleSearchAt)
    androidx.activity.compose.BackHandler(enabled = subtitleSearchAt != null) { subtitleSearchAt = null }
    val canAddSubtitles = !plan.streamUrl.startsWith("file:")
    val addSubtitles: ((Double) -> Unit)? = if (canAddSubtitles && pluginState.showsAddSubtitles(plan.item.kind)) {
        { position -> subtitleSearchAt = position }
    } else {
        null
    }
    var segments by remember(plan.item.id) { mutableStateOf(emptyList<app.zelefin.client.plugins.SkipSegment>()) }
    LaunchedEffect(plan.item.id) { segments = plugins.skipSegments(plan.item.id) }
    var nextEpisode by remember(plan.item.id) { mutableStateOf<MediaItem?>(null) }
    LaunchedEffect(plan.item.id) {
        if (plan.item.kind == app.zelefin.core.MediaKind.Episode) nextEpisode = runCatching { onLoadNext(plan.item) }.getOrNull()
    }
    val nextArtwork = remember(nextEpisode, session) { nextEpisode?.let { artworkCandidates(it, session, landscape = true) }.orEmpty() }
    var sourceRetries by remember(plan.item.id) { mutableIntStateOf(0) }
    val remote = !plan.streamUrl.startsWith("file:")
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        PlayerSurface(
            plan = plan,
            session = session,
            onProgress = onProgress,
            onStopped = onStopped,
            onClose = onClose,
            skipSegments = segments,
            autoSkip = { kind ->
                when (kind) {
                    app.zelefin.client.plugins.SkipSegment.Kind.Intro -> pluginState.autoSkipIntro
                    app.zelefin.client.plugins.SkipSegment.Kind.Outro -> pluginState.autoSkipCredits
                }
            },
            nextEpisode = nextEpisode,
            nextArtwork = nextArtwork,
            onPlayNext = onPlayNext,
            onAddSubtitles = addSubtitles,
            suspended = subtitleSearchAt != null,
            onAdaptiveBitrate = onAdaptiveBitrate,
            onRecover = if (remote && sourceRetries < 1) {
                { position ->
                    sourceRetries += 1
                    onRecover(position)
                }
            } else {
                null
            },
            onRetryStream = if (remote) onRecover else null,
            onPlaybackReady = onPlaybackReady,
            onUserTransport = onUserTransport,
            directives = directives,
        )
        if (subtitleSheet.displayed != null) {
            ZelefinSheetScrim(subtitleSheet.progress)
            ZelefinSheetSurface(subtitleSheet.progress) {
                OpenSubtitlesSheet(
                    item = plan.item,
                    plugins = plugins,
                    onClose = {
                        val position = subtitleSearchAt
                        subtitleSearchAt = null
                        if (subtitleSaved && position != null) onReload(position)
                    },
                    onSaved = { subtitleSaved = true },
                )
            }
        }
    }
}
