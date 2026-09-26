package app.zelefin.client.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.client.AppTab
import app.zelefin.client.LibraryRoom
import app.zelefin.client.Screen
import app.zelefin.client.ZelefinUiState
import app.zelefin.core.HouseholdProfile
import app.zelefin.core.MediaBackend
import app.zelefin.core.MediaItem
import app.zelefin.core.PlaybackPlan
import app.zelefin.core.SiloPendingSignIn
import app.zelefin.core.TitleDetail

@Composable
fun ProfilesScreen(pending: SiloPendingSignIn, onChoose: (HouseholdProfile) -> Unit) {
    Column(Modifier.fillMaxSize().background(ZelefinBlack).padding(24.dp)) {
        Text("Who’s watching?", style = androidx.compose.material3.MaterialTheme.typography.headlineLarge)
        Spacer(Modifier.height(24.dp))
        LazyVerticalGrid(columns = GridCells.Adaptive(140.dp), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            items(pending.profiles.size) { index ->
                val profile = pending.profiles[index]
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.clickableNoRipple { onChoose(profile) }) {
                    CachedArtwork(
                        url = profile.avatarUrl,
                        contentDescription = profile.name,
                        modifier = Modifier.height(120.dp).fillMaxWidth().clip(RoundedCornerShape(16.dp)),
                        contentScale = ContentScale.Crop,
                    )
                    Text(profile.name, modifier = Modifier.padding(top = 8.dp), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (profile.hasPin) Text("PIN", color = ZelefinMuted, style = androidx.compose.material3.MaterialTheme.typography.bodyMedium)
                }
            }
        }
    }
}

@Composable
fun PinScreen(profile: HouseholdProfile, busy: Boolean, message: String?, onSubmit: (String) -> Unit, onBack: () -> Unit) {
    var pin by rememberSaveable { mutableStateOf("") }
    Column(Modifier.fillMaxSize().background(ZelefinBlack).padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        TextButton(onClick = onBack) { Text("Back") }
        Text(profile.name, style = androidx.compose.material3.MaterialTheme.typography.headlineLarge)
        Text("Enter the profile PIN.", color = ZelefinMuted)
        Field("PIN", pin, password = true) { pin = it.filter { char -> char.isDigit() } }
        Button(onClick = { onSubmit(pin) }, enabled = pin.length >= 4 && !busy, colors = ButtonDefaults.buttonColors(containerColor = ZelefinCyan, contentColor = Color.Black)) {
            Text("Continue")
        }
        message?.let { Text(it, color = ZelefinMuted) }
    }
}

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
) {
    val contentBottom = DockContentReserve
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
                    onHideFromHome = if (pluginState.hidesFromHome) onHideFromHome else null,
                    onSeeAll = onSeeAll,
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
                    onFilters = onLibraryFilters,
                    onLayout = onLibraryLayout,
                    onResetLayout = onResetLibraryLayout,
                    onCoversDock = onCoversDock,
                    onProfile = onProfile,
                    onSessions = onSessions,
                    onSettings = onSettings,
                    onSignOut = onSignOut,
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
    session: app.zelefin.core.SavedSession? = null,
    onLoadNext: suspend (MediaItem) -> MediaItem? = { null },
    onPlayNext: (MediaItem, Double) -> Unit = { _, _ -> },
) {
    val pluginState by plugins.state.collectAsState()
    var segments by remember(plan.item.id) { mutableStateOf(emptyList<app.zelefin.client.plugins.SkipSegment>()) }
    LaunchedEffect(plan.item.id) { segments = plugins.skipSegments(plan.item.id) }
    var nextEpisode by remember(plan.item.id) { mutableStateOf<MediaItem?>(null) }
    LaunchedEffect(plan.item.id) {
        if (plan.item.kind == app.zelefin.core.MediaKind.Episode) nextEpisode = runCatching { onLoadNext(plan.item) }.getOrNull()
    }
    val nextArtwork = remember(nextEpisode, session) { nextEpisode?.let { artworkCandidates(it, session, landscape = true) }.orEmpty() }
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        PlayerSurface(
            plan = plan,
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
        )
    }
}

@Composable
private fun Field(label: String, value: String, password: Boolean = false, onChange: (String) -> Unit) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        label = { Text(label) },
        singleLine = true,
        visualTransformation = if (password) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
        keyboardOptions = KeyboardOptions(keyboardType = if (password && label == "PIN") KeyboardType.NumberPassword else KeyboardType.Text),
        modifier = Modifier.fillMaxWidth(),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = ZelefinCyan,
            cursorColor = ZelefinCyan,
            focusedLabelColor = ZelefinCyan,
        ),
    )
}

private fun Modifier.clickableNoRipple(onClick: () -> Unit): Modifier = this.clickable(onClick = onClick)
