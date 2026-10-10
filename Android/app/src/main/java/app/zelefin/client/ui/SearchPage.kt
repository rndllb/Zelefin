package app.zelefin.client.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.shrinkHorizontally
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Business
import androidx.compose.material.icons.outlined.Category
import androidx.compose.material.icons.outlined.Movie
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.runtime.collectAsState
import app.zelefin.client.CatalogBrowseQuery
import app.zelefin.client.DiscoverGridState
import app.zelefin.client.PluginsController
import app.zelefin.client.plugins.SeerrTitle
import app.zelefin.client.LibraryGenre
import app.zelefin.client.LibraryGridState
import app.zelefin.client.LibraryRoute
import app.zelefin.client.SearchHit
import app.zelefin.client.SearchHitKind
import app.zelefin.client.SearchMinimumLength
import app.zelefin.client.SearchScope
import app.zelefin.client.ZelefinUiState
import app.zelefin.client.searchSubtitle
import app.zelefin.core.MediaItem
import app.zelefin.core.SavedSession

private val RowHairline = Color.White.copy(alpha = 0.08f)
private val FieldPrompt = ZelefinMuted
private val FieldIcon = ZelefinMuted
private val HitSubtitle = Color.White.copy(alpha = 0.45f)

/** The Discover scope's content. Null when no request service is set up. */
private class SearchDiscover(
    val content: @Composable (term: String, topInset: Dp, bottomInset: Dp, onDrag: () -> Unit, onScrollOffset: (Int, Int) -> Unit) -> Unit,
)

@Composable
fun SearchTabPage(
    state: ZelefinUiState,
    bottomInset: Dp,
    onTerm: (String) -> Unit,
    onHit: (SearchHit) -> Unit,
    onOpenItem: (MediaItem) -> Unit,
    onOpen: (MediaItem) -> Unit,
    onPlay: (MediaItem) -> Unit,
    onRemoveRecent: (String) -> Unit,
    onClearRecents: () -> Unit,
    onRoute: (LibraryRoute) -> Unit,
    onBack: () -> Unit,
    onQuery: (LibraryRoute, CatalogBrowseQuery) -> Unit,
    onRefresh: (LibraryRoute) -> Unit,
    onFilters: (LibraryRoute) -> Unit,
    onCoversDock: (Boolean) -> Unit,
    onProfile: () -> Unit,
    onSessions: () -> Unit,
    onSettings: () -> Unit,
    onSignOut: () -> Unit,
    plugins: PluginsController,
) {
    val pluginState by plugins.state.collectAsState()
    val discoverState by plugins.discover.collectAsState()
    var requestTitle by remember { mutableStateOf<SeerrTitle?>(null) }
    val sheet = rememberZelefinSheet(requestTitle)
    val selectTitle: (SeerrTitle) -> Unit = { title ->
        val resolved = discoverState.resolved(title)
        when {
            resolved.availability == SeerrTitle.Availability.Available -> Unit
            pluginState.oneTapRequests -> if (resolved.canRequest) plugins.requestOneTap(title)
            else -> requestTitle = title
        }
    }
    val discover = if (pluginState.discoverAvailable) {
        SearchDiscover { term, top, bottom, onDrag, onScrollOffset ->
            DiscoverPane(
                onScrollOffset = onScrollOffset,
                discover = discoverState,
                plugins = pluginState,
                term = term,
                topInset = top,
                bottomInset = bottom,
                onSearch = plugins::searchDiscover,
                onLoadHome = { plugins.loadDiscoverHome() },
                onOpenQuery = { onRoute(LibraryRoute.Discover(it)) },
                onSelect = selectTitle,
                onDrag = onDrag,
            )
        }
    } else {
        null
    }
    LaunchedEffect(sheet.displayed) { onCoversDock(sheet.displayed != null) }
    val haze = LocalZelefinHaze.current
    PresentZelefinOverlay(visible = discoverState.notice != null && haze != null) {
        val hazeState = haze ?: return@PresentZelefinOverlay
        ZelefinGlassAlert(
            hazeState = hazeState,
            title = "Request",
            message = discoverState.notice.orEmpty(),
            onDismiss = plugins::clearNotice,
        )
    }

    val motion = rememberZelefinPush(state.searchPath) { from, to ->
        when {
            to.size > from.size -> ZelefinPushRelation.Push
            to.size < from.size -> ZelefinPushRelation.Pop
            else -> ZelefinPushRelation.None
        }
    }
    Box(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().zelefinSheetBackdrop(sheet.progress)) {
            ZelefinPush(motion) { path ->
                when (val route = path.lastOrNull()) {
                    null -> SearchHome(
                        state = state,
                        bottomInset = bottomInset,
                        onTerm = onTerm,
                        onHit = onHit,
                        onOpenItem = onOpenItem,
                        onPlay = onPlay,
                        onRemoveRecent = onRemoveRecent,
                        onClearRecents = onClearRecents,
                        onGenre = { onRoute(LibraryRoute.Genre(it)) },
                        onProfile = onProfile,
                        onSessions = onSessions,
                        onSettings = onSettings,
                        onSignOut = onSignOut,
                        discover = discover,
                    )
                    is LibraryRoute.Discover -> DiscoverGridPage(
                        query = route.query,
                        grid = discoverState.grids[route.query.key] ?: DiscoverGridState(),
                        discover = discoverState,
                        bottomInset = bottomInset,
                        onBack = onBack,
                        onLoadMore = { plugins.loadDiscoverGrid(route.query, more = true) },
                        onSelect = selectTitle,
                    )
                    else -> {
                        val grid = state.libraryGrids[route] ?: LibraryGridState()
                        CatalogBrowsePage(
                            title = route.title,
                            items = grid.items,
                            query = grid.query,
                            options = grid.filters,
                            session = state.session,
                            refreshing = grid.refreshing,
                            loading = grid.loading,
                            bottomInset = bottomInset,
                            onOpen = onOpen,
                            onRefresh = { onRefresh(route) },
                            onQuery = { onQuery(route, it) },
                            onLoadFilters = { onFilters(route) },
                            onCoversDock = onCoversDock,
                            onProfile = onProfile,
                            onSessions = onSessions,
                            onSettings = onSettings,
                            onSignOut = onSignOut,
                            onBack = onBack,
                            emptyMessage = "Titles from your library will show up here.",
                        )
                    }
                }
            }
            if (sheet.displayed != null) ZelefinSheetScrim(sheet.progress)
        }
        sheet.displayed?.let { title ->
            ZelefinSheetSurface(sheet.progress, canvas = ZelefinBlack) {
                SeerrRequestSheet(
                    title = title,
                    plugins = plugins,
                    canManage = pluginState.canManageRequests,
                    onClose = { requestTitle = null },
                )
            }
        }
    }
    BackHandler(enabled = sheet.displayed != null) { requestTitle = null }
}

@Composable
private fun SearchHome(
    state: ZelefinUiState,
    bottomInset: Dp,
    onTerm: (String) -> Unit,
    onHit: (SearchHit) -> Unit,
    onOpenItem: (MediaItem) -> Unit,
    onPlay: (MediaItem) -> Unit,
    onRemoveRecent: (String) -> Unit,
    onClearRecents: () -> Unit,
    onGenre: (LibraryGenre) -> Unit,
    onProfile: () -> Unit,
    onSessions: () -> Unit,
    onSettings: () -> Unit,
    onSignOut: () -> Unit,
    discover: SearchDiscover?,
) {
    val search = state.search
    val focus = LocalFocusManager.current
    val focusRequester = remember { FocusRequester() }
    var focused by remember { mutableStateOf(false) }
    var scope by rememberSaveable { mutableStateOf(SearchScope.Library) }
    var discoverTerm by rememberSaveable { mutableStateOf("") }
    val term = if (scope == SearchScope.Discover) discoverTerm else search.term
    val active = focused || term.isNotEmpty()
    var headerVisible by remember { mutableStateOf(true) }
    var headerPx by remember { mutableIntStateOf(0) }
    val headerHeight = with(LocalDensity.current) { headerPx.toDp() }
    var menu by remember { mutableStateOf<RecentMenuRequest?>(null) }

    fun setTerm(value: String) {
        if (scope == SearchScope.Discover) discoverTerm = value else onTerm(value)
    }
    fun cancel() {
        setTerm("")
        headerVisible = true
        focus.clearFocus()
    }

    BackHandler(enabled = active) { cancel() }
    LaunchedEffect(active) { if (active) headerVisible = true }

    val onScrollOffset: (Int, Int) -> Unit = { offset, delta ->
        if (!active) {
            headerVisible = when {
                offset <= 40 -> true
                delta > 12 -> false
                delta < -12 -> true
                else -> headerVisible
            }
        }
    }
    val dismissKeyboard = { focus.clearFocus() }

    // The chrome sits inside the app's blur source, so it frosts this page's own layer instead.
    val pageGlass = rememberZelefinHazeState()
    val appGlass = LocalZelefinHaze.current
    Box(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().zelefinHazeSource(pageGlass)) {
        when {
            scope == SearchScope.Discover && discover != null -> discover.content(discoverTerm.trim(), headerHeight, bottomInset, dismissKeyboard, onScrollOffset)
            scope == SearchScope.Discover -> DiscoverUnavailable(
                usesSilo = state.session?.usesSilo == true,
                topInset = headerHeight,
            )
            !active -> GenreGrid(search.genres, search.genresLoading, headerHeight, bottomInset, onScrollOffset, onGenre)
            term.isEmpty() -> RecentList(
                recents = search.recents,
                session = state.session,
                topInset = headerHeight,
                bottomInset = bottomInset,
                onDrag = dismissKeyboard,
                onOpen = {
                    dismissKeyboard()
                    onOpenItem(it)
                },
                onMenu = { item, anchor -> menu = RecentMenuRequest(item, anchor) },
                onClear = onClearRecents,
            )
            term.trim().length < SearchMinimumLength -> NoResults(term, headerHeight)
            search.hits.isEmpty() && search.loading -> Box(
                Modifier.fillMaxWidth().padding(top = headerHeight + 40.dp),
                contentAlignment = Alignment.TopCenter,
            ) {
                CircularProgressIndicator(color = ZelefinCyan)
            }
            search.hits.isEmpty() -> NoResults(term, headerHeight)
            else -> HitList(
                hits = search.hits,
                session = state.session,
                topInset = headerHeight,
                bottomInset = bottomInset,
                onDrag = dismissKeyboard,
                onHit = {
                    dismissKeyboard()
                    onHit(it)
                },
            )
        }
        }
        SearchChrome(
            glass = SearchGlass(pageGlass),
            visible = headerVisible,
            active = active,
            focused = focused,
            scope = scope,
            term = term,
            session = state.session,
            focusRequester = focusRequester,
            modifier = Modifier.onSizeChanged { headerPx = it.height },
            onFocus = { focused = it },
            onTerm = ::setTerm,
            onScope = { scope = it },
            onCancel = ::cancel,
            onSubmit = dismissKeyboard,
            onProfile = onProfile,
            onSessions = onSessions,
            onSettings = onSettings,
            onSignOut = onSignOut,
        )
    }
    RecentMenu(
        request = menu,
        onDismiss = { menu = null },
        onPlay = onPlay,
        onOpen = onOpenItem,
        onRemove = onRemoveRecent,
    )
}

private class SearchGlass(val haze: ZelefinHazeState)

@Composable
private fun Modifier.searchGlass(glass: SearchGlass, shape: androidx.compose.ui.graphics.Shape): Modifier =
    zelefinGlassChrome(glass.haze, shape)

@Composable
private fun SearchChrome(
    glass: SearchGlass,
    visible: Boolean,
    active: Boolean,
    focused: Boolean,
    scope: SearchScope,
    term: String,
    session: SavedSession?,
    focusRequester: FocusRequester,
    modifier: Modifier,
    onFocus: (Boolean) -> Unit,
    onTerm: (String) -> Unit,
    onScope: (SearchScope) -> Unit,
    onCancel: () -> Unit,
    onSubmit: () -> Unit,
    onProfile: () -> Unit,
    onSessions: () -> Unit,
    onSettings: () -> Unit,
    onSignOut: () -> Unit,
) {
    val alpha by animateFloatAsState(if (visible) 1f else 0f, tween(180), label = "searchChrome")
    val shift by animateDpAsState(if (visible) 0.dp else (-160).dp, tween(180), label = "searchChromeShift")
    val tablet = LocalConfiguration.current.smallestScreenWidthDp >= 600
    val showsScope = focused || tablet
    val topPad by animateDpAsState(if (active) 8.dp else 4.dp, SearchSessionMotion(), label = "searchTopPad")
    val bottomPad by animateDpAsState(if (showsScope) 4.dp else 12.dp, SearchFocusMotion(), label = "searchBottomPad")
    Column(
        modifier
            .fillMaxWidth()
            .offset(y = shift)
            .graphicsLayer { this.alpha = alpha }
            .statusBarsPadding()
            .padding(horizontal = 16.dp)
            .padding(top = topPad, bottom = bottomPad),
    ) {
        AnimatedVisibility(
            visible = !active,
            enter = fadeIn(SearchSessionMotion()) + expandVertically(SearchSessionMotion(), expandFrom = Alignment.Top),
            exit = fadeOut(SearchSessionMotion()) + shrinkVertically(SearchSessionMotion(), shrinkTowards = Alignment.Top),
        ) {
            Row(Modifier.padding(bottom = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "Search",
                    color = Color.White,
                    fontFamily = ZelefinFont,
                    fontWeight = FontWeight.Bold,
                    fontSize = 34.sp,
                    maxLines = 1,
                    modifier = Modifier.weight(1f),
                )
                AccountAvatarMenu(session, onProfile, onSessions, onSettings, onSignOut)
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            SearchField(
                glass = glass,
                term = term,
                prompt = scope.prompt,
                focusRequester = focusRequester,
                modifier = Modifier.weight(1f),
                onFocus = onFocus,
                onTerm = onTerm,
                onSubmit = onSubmit,
            )
            AnimatedVisibility(
                visible = active,
                enter = fadeIn(SearchSessionMotion()) + scaleIn(SearchSessionMotion(), initialScale = 0.6f) + expandHorizontally(SearchSessionMotion()),
                exit = fadeOut(SearchSessionMotion()) + scaleOut(SearchSessionMotion(), targetScale = 0.6f) + shrinkHorizontally(SearchSessionMotion()),
            ) {
                Box(Modifier.size(46.dp).then(if (visible) Modifier.zelefinGlassDisc("search-cancel", "Cancel", Icons.Filled.Close, onCancel) else Modifier))
            }
        }
        AnimatedVisibility(
            visible = showsScope,
            enter = fadeIn(SearchFocusMotion()) + expandVertically(SearchFocusMotion(), expandFrom = Alignment.Top),
            exit = fadeOut(SearchFocusMotion()) + shrinkVertically(SearchFocusMotion(), shrinkTowards = Alignment.Top),
        ) {
            Box(Modifier.padding(top = 10.dp)) { ScopeBar(glass, scope, onScope) }
        }
    }
}

/** iOS `.smooth(duration: 0.25)` for the search session, `.easeInOut(0.22)` for focus. */
private fun <T> SearchSessionMotion() = tween<T>(250, easing = FastOutSlowInEasing)
private fun <T> SearchFocusMotion() = tween<T>(220, easing = FastOutSlowInEasing)

@Composable
private fun SearchField(
    glass: SearchGlass,
    term: String,
    prompt: String,
    focusRequester: FocusRequester,
    modifier: Modifier,
    onFocus: (Boolean) -> Unit,
    onTerm: (String) -> Unit,
    onSubmit: () -> Unit,
) {
    val shape = RoundedCornerShape(50)
    Row(
        modifier
            .searchGlass(glass, shape)
            .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) { focusRequester.requestFocus() }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.Search, contentDescription = null, tint = FieldIcon, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(8.dp))
        BasicTextField(
            value = term,
            onValueChange = onTerm,
            singleLine = true,
            textStyle = MaterialTheme.typography.bodyLarge,
            cursorBrush = SolidColor(ZelefinCyan),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(onSearch = { onSubmit() }),
            modifier = Modifier
                .weight(1f)
                .focusRequester(focusRequester)
                .onFocusChanged { onFocus(it.isFocused) },
            decorationBox = { inner ->
                Box(contentAlignment = Alignment.CenterStart) {
                    if (term.isEmpty()) Text(prompt, color = FieldPrompt, fontFamily = ZelefinFont, fontSize = 17.sp, maxLines = 1)
                    inner()
                }
            },
        )
        if (term.isNotEmpty()) {
            Spacer(Modifier.width(8.dp))
            Icon(
                Icons.Filled.Cancel,
                contentDescription = "Clear",
                tint = FieldIcon,
                modifier = Modifier
                    .size(20.dp)
                    .clip(CircleShape)
                    .clickable { onTerm("") },
            )
        }
    }
}

@Composable
private fun ScopeBar(glass: SearchGlass, scope: SearchScope, onScope: (SearchScope) -> Unit) {
    val shape = RoundedCornerShape(50)
    val options = SearchScope.entries
    val index by animateFloatAsState(options.indexOf(scope).toFloat(), SearchFocusMotion(), label = "scopePill")
    BoxWithConstraints(
        Modifier
            .fillMaxWidth()
            .searchGlass(glass, shape)
            .padding(3.dp),
    ) {
        val segment = maxWidth / options.size
        Box(
            Modifier
                .offset(x = segment * index)
                .width(segment)
                .height(34.dp)
                .clip(shape)
                .background(Color.White.copy(alpha = 0.22f))
                .border(0.5.dp, Color.White.copy(alpha = 0.28f), shape),
        )
        Row {
            options.forEach { option ->
                val selected = option == scope
                val tint by animateColorAsState(
                    if (selected) Color.White else Color.White.copy(alpha = 0.55f),
                    SearchFocusMotion(),
                    label = "scopeTint",
                )
                Box(
                    Modifier
                        .weight(1f)
                        .height(34.dp)
                        .clip(shape)
                        .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) { onScope(option) }
                        .semantics { this.selected = selected },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        option.title,
                        color = tint,
                        fontFamily = ZelefinFont,
                        fontWeight = if (selected) FontWeight.Bold else FontWeight.SemiBold,
                        fontSize = 15.sp,
                    )
                }
            }
        }
    }
}

@Composable
internal fun TrackOffset(offset: () -> Int, onScrollOffset: (Int, Int) -> Unit) {
    var previous by remember { mutableIntStateOf(0) }
    val latestOffset by rememberUpdatedState(offset)
    val latestOnScroll by rememberUpdatedState(onScrollOffset)
    LaunchedEffect(Unit) {
        snapshotFlow { latestOffset() }.collect { value ->
            val delta = value - previous
            previous = value
            latestOnScroll(value, delta)
        }
    }
}

@Composable
private fun GenreGrid(
    genres: List<LibraryGenre>,
    loading: Boolean,
    topInset: Dp,
    bottomInset: Dp,
    onScrollOffset: (Int, Int) -> Unit,
    onGenre: (LibraryGenre) -> Unit,
) {
    if (genres.isEmpty()) {
        if (loading) {
            Box(Modifier.fillMaxWidth().padding(top = topInset + 40.dp), contentAlignment = Alignment.TopCenter) {
                CircularProgressIndicator(color = ZelefinCyan)
            }
        }
        return
    }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val columns = when {
            maxWidth >= 900.dp -> 7
            maxWidth >= 600.dp -> 5
            else -> 3
        }
        val gridState = rememberLazyGridState()
        TrackOffset({ gridState.firstVisibleItemIndex * 100_000 + gridState.firstVisibleItemScrollOffset }, onScrollOffset)
        LazyVerticalGrid(
            state = gridState,
            columns = GridCells.Fixed(columns),
            contentPadding = PaddingValues(start = 18.dp, end = 18.dp, top = topInset + 8.dp, bottom = bottomInset + 32.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.fillMaxSize(),
        ) {
            items(genres, key = { it.id }) { genre ->
                GenreCard(genre.name, aspect = 1f / 1.52f, corner = if (columns == 3) 8.dp else 10.dp) { onGenre(genre) }
            }
        }
    }
}

@Composable
private fun DragDismiss(scrolling: Boolean, onDrag: () -> Unit) {
    LaunchedEffect(scrolling) { if (scrolling) onDrag() }
}

@Composable
private fun HitList(
    hits: List<SearchHit>,
    session: SavedSession?,
    topInset: Dp,
    bottomInset: Dp,
    onDrag: () -> Unit,
    onHit: (SearchHit) -> Unit,
) {
    val listState = rememberLazyListState()
    DragDismiss(listState.isScrollInProgress, onDrag)
    LazyColumn(
        state = listState,
        contentPadding = PaddingValues(top = topInset, bottom = bottomInset + 32.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        items(hits, key = { it.id }) { hit ->
            SearchRow(
                title = hit.name,
                subtitle = hit.subtitle,
                item = hit.item,
                placeholder = hitIcon(hit.kind),
                session = session,
                onClick = { onHit(hit) },
            )
        }
    }
}

@Composable
private fun RecentList(
    recents: List<MediaItem>,
    session: SavedSession?,
    topInset: Dp,
    bottomInset: Dp,
    onDrag: () -> Unit,
    onOpen: (MediaItem) -> Unit,
    onMenu: (MediaItem, Rect) -> Unit,
    onClear: () -> Unit,
) {
    val listState = rememberLazyListState()
    DragDismiss(listState.isScrollInProgress, onDrag)
    LazyColumn(
        state = listState,
        contentPadding = PaddingValues(top = topInset + 8.dp, bottom = bottomInset + 32.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        item(key = "recent-header") {
            Row(
                Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Recently Searched",
                    color = Color.White,
                    fontFamily = ZelefinFont,
                    fontWeight = FontWeight.Bold,
                    fontSize = 20.sp,
                    modifier = Modifier.weight(1f),
                )
                if (recents.isNotEmpty()) {
                    Text(
                        "Clear",
                        color = ZelefinCyan,
                        fontFamily = ZelefinFont,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 17.sp,
                        modifier = Modifier
                            .clip(RoundedCornerShape(8.dp))
                            .clickable(onClick = onClear)
                            .padding(horizontal = 4.dp, vertical = 4.dp),
                    )
                }
            }
        }
        if (recents.isEmpty()) {
            item(key = "recent-empty") {
                Text(
                    "Titles you open from Search show up here.",
                    color = ZelefinMuted,
                    fontFamily = ZelefinFont,
                    fontSize = 15.sp,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }
        }
        items(recents, key = { "recent-${it.id}" }) { item ->
            SearchRow(
                title = item.name,
                subtitle = item.searchSubtitle(),
                item = item,
                placeholder = Icons.Outlined.Movie,
                session = session,
                onClick = { onOpen(item) },
                trailing = { MoreButton { anchor -> onMenu(item, anchor) } },
            )
        }
    }
}

@Composable
private fun MoreButton(onClick: (Rect) -> Unit) {
    var bounds by remember { mutableStateOf(Rect.Zero) }
    Box(
        Modifier
            .size(36.dp)
            .onGloballyPositioned { bounds = it.boundsInRoot() }
            .clip(CircleShape)
            .clickable { onClick(bounds) },
        contentAlignment = Alignment.Center,
    ) {
        Icon(Icons.Filled.MoreHoriz, contentDescription = "More", tint = Color.White.copy(alpha = 0.72f))
    }
}

@Composable
private fun SearchRow(
    title: String,
    subtitle: String?,
    item: MediaItem,
    placeholder: ImageVector,
    session: SavedSession?,
    onClick: () -> Unit,
    trailing: (@Composable () -> Unit)? = null,
) {
    Column(Modifier.fillMaxWidth().clickable(onClick = onClick)) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Box(
                Modifier
                    .size(width = 52.dp, height = 78.dp)
                    .posterChrome(6.dp)
                    .background(Color.White.copy(alpha = 0.08f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(placeholder, contentDescription = null, tint = Color.White.copy(alpha = 0.34f), modifier = Modifier.size(22.dp))
                CachedArtwork(
                    urls = artworkCandidates(item, session, landscape = false),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    title,
                    color = Color.White,
                    fontFamily = ZelefinFont,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 17.sp,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                if (!subtitle.isNullOrEmpty()) {
                    Text(subtitle, color = HitSubtitle, fontFamily = ZelefinFont, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            trailing?.invoke()
        }
        Box(Modifier.fillMaxWidth().padding(start = 82.dp).height(0.5.dp).background(RowHairline))
    }
}

@Composable
private fun DiscoverUnavailable(usesSilo: Boolean, topInset: Dp) {
    Column(
        Modifier.fillMaxWidth().padding(top = topInset + 40.dp, start = 32.dp, end = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            if (usesSilo) "Requests Are Off" else "Sign In to Seerr",
            color = MaterialTheme.colorScheme.onSurface,
            fontWeight = FontWeight.Bold,
            fontSize = 22.sp,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(8.dp))
        Text(
            if (usesSilo) {
                "Install the Seerr plugin or Sonarr & Radarr requests on this Silo server, then open Plugins in Settings."
            } else {
                "Add Seerr in Settings to request movies and shows."
            },
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontSize = 16.sp,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun NoResults(term: String, topInset: Dp) {
    Column(
        Modifier.fillMaxWidth().padding(top = topInset + 24.dp, start = 32.dp, end = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(Icons.Filled.Search, contentDescription = null, tint = ZelefinMuted, modifier = Modifier.size(44.dp))
        Spacer(Modifier.height(12.dp))
        Text(
            "No Results for “${term.trim()}”",
            color = Color.White,
            fontFamily = ZelefinFont,
            fontWeight = FontWeight.Bold,
            fontSize = 22.sp,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(6.dp))
        Text(
            "Check the spelling or try a new search.",
            color = ZelefinMuted,
            fontFamily = ZelefinFont,
            fontSize = 15.sp,
            textAlign = TextAlign.Center,
        )
    }
}

private data class RecentMenuRequest(val item: MediaItem, val anchor: Rect)

@Composable
private fun RecentMenu(
    request: RecentMenuRequest?,
    onDismiss: () -> Unit,
    onPlay: (MediaItem) -> Unit,
    onOpen: (MediaItem) -> Unit,
    onRemove: (String) -> Unit,
) {
    val haze = LocalZelefinHaze.current
    DisposableEffect(Unit) { onDispose { onDismiss() } }
    PresentZelefinOverlay(visible = request != null && haze != null) {
        val hazeState = haze ?: return@PresentZelefinOverlay
        val current = request ?: return@PresentZelefinOverlay
        AnchoredMenuFrame(
            current.anchor,
            alignTrailing = true,
            onDismiss = onDismiss,
            clearBottom = dockContentReserve(),
        ) {
            Column(
                Modifier
                    .zelefinGlassChrome(hazeState, ZelefinMenuShape)
                    .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) {}
                    .zelefinMenuWidth()
                    .padding(vertical = 4.dp),
            ) {
                MoreRow("Play", Icons.Filled.PlayArrow, {
                    onDismiss()
                    onPlay(current.item)
                })
                MoreRow("View Details", Icons.Outlined.Info, {
                    onDismiss()
                    onOpen(current.item)
                })
                MoreRow("Remove", Icons.Outlined.Delete, {
                    onDismiss()
                    onRemove(current.item.id)
                }, destructive = true)
            }
        }
    }
}

private fun hitIcon(kind: SearchHitKind): ImageVector = when (kind) {
    SearchHitKind.Title -> Icons.Outlined.Movie
    SearchHitKind.Person -> Icons.Outlined.Person
    SearchHitKind.Genre -> Icons.Outlined.Category
    SearchHitKind.Studio -> Icons.Outlined.Business
}
