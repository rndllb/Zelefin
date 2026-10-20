package app.zelefin.client.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Photo
import androidx.compose.material.icons.filled.PlaylistAdd
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.filled.Subscriptions
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.ViewModule
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.vectorResource
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.text.style.Hyphens
import androidx.compose.ui.text.style.LineBreak
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import app.zelefin.client.R
import app.zelefin.client.CatalogBrowseQuery
import app.zelefin.client.LibraryCounts
import app.zelefin.client.LibraryGenre
import app.zelefin.client.LibraryKind
import app.zelefin.client.LibraryLayout
import app.zelefin.client.LibraryPageBlock
import app.zelefin.client.LibraryRoom
import app.zelefin.client.LibraryRoute
import app.zelefin.client.ZelefinUiState
import app.zelefin.client.formatCount
import app.zelefin.client.libraryTabRooms
import app.zelefin.core.ArtworkUrls
import app.zelefin.core.MediaItem
import app.zelefin.core.SavedSession
import kotlin.math.max
import kotlin.math.roundToInt

private val HeaderRowHeight = 59.dp
private val RoomStride = 84.dp

@Composable
fun LibraryTabPage(
    state: ZelefinUiState,
    bottomInset: Dp,
    onOpen: (MediaItem) -> Unit,
    onRoute: (LibraryRoute) -> Unit,
    onBack: () -> Unit,
    onQuery: (LibraryRoute, CatalogBrowseQuery) -> Unit,
    onRefresh: (LibraryRoute) -> Unit,
    onOverviewRefresh: () -> Unit,
    refreshing: Boolean,
    onFilters: (LibraryRoute) -> Unit,
    onLayout: (LibraryLayout) -> Unit,
    onResetLayout: () -> Unit,
    onCoversDock: (Boolean) -> Unit,
    onProfile: () -> Unit,
    onSessions: () -> Unit,
    onSettings: () -> Unit,
    onSignOut: () -> Unit,
    onRandom: () -> Unit = {},
) {
    val motion = rememberZelefinPush(state.libraryPath) { from, to ->
        when {
            to.size > from.size -> ZelefinPushRelation.Push
            to.size < from.size -> ZelefinPushRelation.Pop
            else -> ZelefinPushRelation.None
        }
    }
    ZelefinPush(motion) { path ->
        when (val route = path.lastOrNull()) {
            null -> LibraryHome(
                state, bottomInset, refreshing, onOverviewRefresh, onRoute, onLayout, onResetLayout, onCoversDock, onProfile, onSessions, onSettings, onSignOut, onRandom,
            )
            LibraryRoute.Genres -> GenresPage(state.libraryOverview.genres, state.libraryOverview.genresLoading, bottomInset, onBack) {
                onRoute(LibraryRoute.Genre(it))
            }
            LibraryRoute.Downloaded -> DownloadedPage(state.session, bottomInset, onBack, onOpen)
            else -> {
                val grid = state.libraryGrids[route] ?: app.zelefin.client.LibraryGridState()
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
                    emptyMessage = when (route) {
                        LibraryRoute.Favorites -> "Titles you favorite will show up here."
                        LibraryRoute.Watchlist -> "Titles you add to Watchlist will show up here."
                        else -> "Titles from this library will show up here."
                    },
                )
            }
        }
    }
}

@Composable
@OptIn(ExperimentalMaterial3Api::class)
private fun LibraryHome(
    state: ZelefinUiState,
    bottomInset: Dp,
    refreshing: Boolean,
    onRefresh: () -> Unit,
    onRoute: (LibraryRoute) -> Unit,
    onLayout: (LibraryLayout) -> Unit,
    onResetLayout: () -> Unit,
    onCoversDock: (Boolean) -> Unit,
    onProfile: () -> Unit,
    onSessions: () -> Unit,
    onSettings: () -> Unit,
    onSignOut: () -> Unit,
    onRandom: () -> Unit,
) {
    var arranging by remember { mutableStateOf(false) }
    val sheet = rememberZelefinSheet(if (arranging) Unit else null)
    val silo = state.session?.usesSilo == true
    val eligible = state.libraries.libraryTabRooms(silo)
    val layout = state.libraryLayout
    val rooms = layout.displayed(eligible)
    val overview = state.libraryOverview
    val jumps = listOf(LibraryPageBlock.Favorites, LibraryPageBlock.Watchlist, LibraryPageBlock.Genres)
        .filter { it !in layout.hiddenBlocks }
    val collections = if (LibraryPageBlock.Collections in layout.hiddenBlocks) emptyList() else overview.collections.take(12)
    val statusTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    val headerHeight = statusTop + HeaderRowHeight
    var headerVisible by remember { mutableStateOf(true) }

    DisposableEffect(Unit) {
        onDispose { onCoversDock(false) }
    }
    LaunchedEffect(sheet.displayed) { onCoversDock(sheet.displayed != null) }
    BackHandler(enabled = sheet.displayed != null) { arranging = false }

    Box(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().zelefinSheetBackdrop(sheet.progress)) {
            when {
                state.libraries.isEmpty() && state.librariesLoading -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = ZelefinCyan)
                    }
                }
                state.libraries.isEmpty() && state.message != null -> {
                    Column(
                        Modifier.fillMaxSize().padding(top = headerHeight + 40.dp, start = 32.dp, end = 32.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text("Couldn’t Load Library", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 22.sp)
                        Spacer(Modifier.height(8.dp))
                        Text(state.message, color = ZelefinMuted, fontSize = 16.sp)
                    }
                }
                else -> {
                    val listState = rememberLazyListState()
                    val refreshState = rememberPullToRefreshState()
                    var previousOffset by remember { mutableIntStateOf(0) }
                    val hasStats = overview.counts?.let { it.total > 0 } == true
                    LaunchedEffect(hasStats) {
                        if (hasStats && listState.firstVisibleItemIndex == 1 && listState.firstVisibleItemScrollOffset == 0) {
                            listState.scrollToItem(0)
                        }
                    }
                    LaunchedEffect(listState) {
                        snapshotFlow { listState.firstVisibleItemIndex * 100_000 + listState.firstVisibleItemScrollOffset }
                            .collect { offset ->
                                val delta = offset - previousOffset
                                previousOffset = offset
                                headerVisible = when {
                                    offset <= 40 -> true
                                    delta > 12 -> false
                                    delta < -12 -> true
                                    else -> headerVisible
                                }
                            }
                    }
                    PullToRefreshBox(
                        isRefreshing = refreshing,
                        onRefresh = onRefresh,
                        state = refreshState,
                        modifier = Modifier.fillMaxSize(),
                        indicator = {
                            PullToRefreshDefaults.Indicator(
                                modifier = Modifier.align(Alignment.TopCenter).padding(top = headerHeight - 36.dp),
                                isRefreshing = refreshing,
                                state = refreshState,
                                containerColor = Color(0xFF1C1C1E),
                                color = ZelefinCyan,
                            )
                        },
                    ) {
                    LazyColumn(
                        state = listState,
                        contentPadding = PaddingValues(top = headerHeight, bottom = bottomInset + 32.dp),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        overview.counts?.takeIf { it.total > 0 }?.let { counts ->
                            item(key = "stats") {
                                ServerStats(counts)
                                Spacer(Modifier.height(16.dp))
                            }
                        }
                        items(rooms, key = { "room-${it.id}" }) { room ->
                            RoomBand(
                                room = room,
                                covers = overview.covers[room.id].orEmpty(),
                                caption = overview.roomCounts[room.id]?.caption,
                                session = state.session,
                                modifier = Modifier.padding(horizontal = 16.dp).padding(bottom = 12.dp),
                            ) { onRoute(LibraryRoute.Room(room)) }
                        }
                        item(key = "jumps") {
                            val tiles = jumps + null
                            val columns = if (tiles.size >= 4) 2 else tiles.size.coerceAtLeast(1)
                            Column(
                                Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 20.dp),
                                verticalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                tiles.chunked(columns).forEach { row ->
                                    Row(
                                        Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                                    ) {
                                        row.forEach { block ->
                                            val tile = Modifier.weight(1f)
                                            if (block == null) {
                                                DownloadedJumpTile(tile) { onRoute(LibraryRoute.Downloaded) }
                                            } else {
                                                JumpTile(block, tile) {
                                                    onRoute(
                                                        when (block) {
                                                            LibraryPageBlock.Favorites -> LibraryRoute.Favorites
                                                            LibraryPageBlock.Watchlist -> LibraryRoute.Watchlist
                                                            else -> LibraryRoute.Genres
                                                        },
                                                    )
                                                }
                                            }
                                        }
                                        repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                                    }
                                }
                            }
                        }
                        if (collections.isNotEmpty()) {
                            item(key = "collections-title") {
                                Text(
                                    "Collections",
                                    color = Color.White,
                                    fontFamily = ZelefinFont,
                                    fontWeight = FontWeight.SemiBold,
                                    fontSize = 20.sp,
                                    modifier = Modifier.padding(start = 16.dp, top = 32.dp, bottom = 12.dp),
                                )
                            }
                            item(key = "collections") {
                                CollectionGrid(collections, state.session) { item ->
                                    onRoute(LibraryRoute.Collection(item.id, item.name))
                                }
                            }
                        }
                    }
                    }
                }
            }
            LibraryHeader(
                visible = headerVisible,
                arrangeShown = sheet.displayed == null && state.libraryPath.isEmpty(),
                session = state.session,
                onArrange = { arranging = true },
                onRandom = onRandom,
                onProfile = onProfile,
                onSessions = onSessions,
                onSettings = onSettings,
                onSignOut = onSignOut,
            )
            if (sheet.displayed != null) ZelefinSheetScrim(sheet.progress)
        }
        if (sheet.displayed != null) {
            ZelefinSheetSurface(sheet.progress, canvas = MaterialTheme.colorScheme.surface) {
                ArrangeSheet(
                    rooms = layout.arranged(eligible),
                    layout = layout,
                    onLayout = onLayout,
                    onReset = onResetLayout,
                    onDone = { arranging = false },
                )
            }
        }
    }
}

@Composable
private fun LibraryHeader(
    visible: Boolean,
    arrangeShown: Boolean,
    session: SavedSession?,
    onArrange: () -> Unit,
    onRandom: () -> Unit,
    onProfile: () -> Unit,
    onSessions: () -> Unit,
    onSettings: () -> Unit,
    onSignOut: () -> Unit,
) {
    val alpha by animateFloatAsState(if (visible) 1f else 0f, tween(180), label = "libraryHeader")
    val shift by animateDpAsState(if (visible) 0.dp else (-120).dp, tween(180), label = "libraryHeaderShift")
    val diceFive = ImageVector.vectorResource(R.drawable.iconsax_dice_five)
    Row(
        Modifier
            .fillMaxWidth()
            .offset(y = shift)
            .graphicsLayer { this.alpha = alpha }
            .statusBarsPadding()
            .padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            "Library",
            color = Color.White,
            fontFamily = ZelefinFont,
            fontWeight = FontWeight.Bold,
            fontSize = 34.sp,
            maxLines = 1,
            modifier = Modifier.weight(1f),
        )
        Box(
            Modifier
                .size(45.dp)
                .then(
                    if (visible && arrangeShown) {
                        Modifier.zelefinGlassDisc("library-random", "Pick something", diceFive, onRandom)
                    } else {
                        Modifier
                    },
                ),
        )
        Spacer(Modifier.width(12.dp))
        Box(
            Modifier
                .size(45.dp)
                .then(
                    if (visible && arrangeShown) {
                        Modifier.zelefinGlassDisc("library-arrange", "Arrange Library", Icons.Filled.Menu, onArrange)
                    } else {
                        Modifier
                    },
                ),
        )
        Spacer(Modifier.width(12.dp))
        AccountAvatarMenu(session, onProfile, onSessions, onSettings, onSignOut)
    }
}

@Composable
private fun ServerStats(counts: LibraryCounts) {
    Row(
        Modifier
            .padding(horizontal = 16.dp)
            .fillMaxWidth()
            .height(64.dp)
            .posterChrome(16.dp)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StatFact(counts.movies, "Movies", Modifier.weight(1f))
        StatDivider()
        StatFact(counts.shows, "Shows", Modifier.weight(1f))
        StatDivider()
        StatFact(counts.episodes, "Episodes", Modifier.weight(1f))
        if (counts.videos > 0) {
            StatDivider()
            StatFact(counts.videos, "Videos", Modifier.weight(1f))
        }
    }
}

@Composable
private fun StatFact(value: Int, label: String, modifier: Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(formatCount(value), color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 20.sp, maxLines = 1)
        Text(label, color = Color.White.copy(alpha = 0.72f), fontWeight = FontWeight.Medium, fontSize = 12.sp, maxLines = 1)
    }
}

@Composable
private fun StatDivider() {
    Box(Modifier.width(1.dp).height(28.dp).background(Color.White.copy(alpha = 0.16f)))
}

@Composable
private fun RoomBand(
    room: LibraryRoom,
    covers: List<MediaItem>,
    caption: String?,
    session: SavedSession?,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val showsArtwork = room.kind != LibraryKind.LiveTV
    val label = caption ?: room.kind.takeIf { it != LibraryKind.Other }?.browseLabel?.takeIf { !it.equals(room.name, ignoreCase = true) }
    Box(
        modifier
            .fillMaxWidth()
            .height(168.dp)
            .posterChrome(18.dp)
            .clickable(onClick = onClick),
    ) {
        val lead = covers.firstOrNull()
        if (showsArtwork && lead != null) {
            CachedArtwork(
                urls = washCandidates(lead, session),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceContainerHigh))
        }
        Box(
            Modifier.fillMaxSize().background(
                Brush.horizontalGradient(
                    listOf(Color.Black.copy(alpha = 0.82f), Color.Black.copy(alpha = 0.38f), Color.Black.copy(alpha = 0.12f)),
                ),
            ),
        )
        Row(
            Modifier.fillMaxSize().padding(start = 20.dp, end = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                FitText(room.name, style = RoomNameStyle, maxLines = 2, minScale = RoomNameMinScale)
                if (label != null) {
                    FitText(label, style = RoomCaptionStyle, maxLines = 4, minScale = RoomNameMinScale)
                }
            }
            if (showsArtwork) PosterFan(room.kind, fanCovers(covers), session)
        }
    }
}

private val RoomNameStyle = TextStyle(
    color = Color.White,
    fontFamily = ZelefinFont,
    fontWeight = FontWeight.SemiBold,
    fontSize = 28.sp,
    lineHeight = 32.sp,
)
private val RoomCaptionStyle = TextStyle(
    color = Color.White.copy(alpha = 0.62f),
    fontFamily = ZelefinFont,
    fontWeight = FontWeight.Medium,
    fontSize = 15.sp,
    lineHeight = 19.sp,
)
private const val RoomNameMinScale = 0.75f
private val FanPoster = 76.dp
private val FanStep = 52.dp

private fun scaled(style: TextStyle, scale: Float) =
    style.copy(fontSize = style.fontSize * scale, lineHeight = style.lineHeight * scale)

private fun textFits(measurer: TextMeasurer, text: String, style: TextStyle, maxLines: Int, width: Int, scale: Float): Boolean {
    if (width <= 0) return false
    val layout = measurer.measure(text, scaled(style, scale), maxLines = maxLines, constraints = Constraints(maxWidth = width))
    if (layout.hasVisualOverflow) return false
    return (0 until layout.lineCount - 1).none { line ->
        val end = layout.getLineEnd(line)
        end in 1 until text.length && !text[end - 1].isWhitespace() && !text[end].isWhitespace()
    }
}

/**
 * Shrinks the text until it fits in [maxLines] without splitting a word. Short words may shrink
 * past [minScale] to [floorScale]; longer words are hyphenated at [minScale], the way iOS wraps them.
 */
@Composable
private fun FitText(text: String, style: TextStyle, maxLines: Int, minScale: Float = 0.75f, floorScale: Float = 0.6f) {
    val measurer = rememberTextMeasurer()
    BoxWithConstraints {
        val width = constraints.maxWidth
        val scale = remember(text, style, width) {
            generateSequence(1f) { it - 0.05f }
                .takeWhile { it > floorScale - 0.001f }
                .firstOrNull { textFits(measurer, text, style, maxLines, width, it) }
                ?.takeIf { it >= minScale - 0.001f || text.split(' ').all { word -> word.length <= 7 } }
        }
        Text(
            text,
            style = if (scale != null) {
                scaled(style, scale)
            } else {
                scaled(style, minScale).copy(hyphens = Hyphens.Auto, lineBreak = LineBreak.Paragraph)
            },
            maxLines = maxLines,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

private fun fanCovers(covers: List<MediaItem>): List<MediaItem> {
    val usable = covers.filter { cover ->
        !cover.usesGeneratedCollage() && (cover.primaryImageTag != null || !cover.posterUrl.isNullOrBlank())
    }
    return (if (usable.isNotEmpty()) usable else covers).take(4)
}

@Composable
private fun PosterFan(kind: LibraryKind, art: List<MediaItem>, session: SavedSession?) {
    val poster = FanPoster
    val step = FanStep
    if (art.isEmpty()) {
        Box(Modifier.size(width = poster, height = 114.dp), contentAlignment = Alignment.Center) {
            Icon(kindIcon(kind), contentDescription = null, tint = Color.White.copy(alpha = 0.34f), modifier = Modifier.size(34.dp))
        }
        return
    }
    Box(Modifier.size(width = poster + step * (art.size - 1), height = 114.dp)) {
        art.forEachIndexed { index, item ->
            Box(
                Modifier
                    .offset(x = step * index)
                    .zIndex(index.toFloat())
                    .size(width = poster, height = 114.dp)
                    .shadow(8.dp, RoundedCornerShape(8.dp))
                    .posterChrome(8.dp),
            ) {
                CachedArtwork(
                    urls = artworkCandidates(item, session, landscape = false),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize().background(Color(0xFF1C1C1E)),
                )
            }
        }
    }
}

@Composable
private fun JumpTile(block: LibraryPageBlock, modifier: Modifier, onClick: () -> Unit) {
    Column(
        modifier
            .height(88.dp)
            .posterChrome(14.dp)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(blockIcon(block), contentDescription = null, tint = Color.White, modifier = Modifier.size(26.dp))
        Spacer(Modifier.height(8.dp))
        Text(
            block.title,
            color = Color.White,
            fontWeight = FontWeight.SemiBold,
            fontSize = 15.sp,
            maxLines = 1,
            modifier = Modifier.padding(horizontal = 8.dp),
        )
    }
}

@Composable
private fun CollectionGrid(items: List<MediaItem>, session: SavedSession?, onOpen: (MediaItem) -> Unit) {
    BoxWithConstraints(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        val count = columnCount(maxWidth)
        Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
            items.chunked(count).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    row.forEach { item ->
                        LabeledPortrait(item.name, artworkCandidates(item, session, landscape = false), Modifier.weight(1f), item, session) { onOpen(item) }
                    }
                    repeat(count - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

@Composable
internal fun LabeledPortrait(
    title: String,
    urls: List<String>,
    modifier: Modifier,
    item: MediaItem? = null,
    session: SavedSession? = null,
    onClick: () -> Unit,
) {
    Box(
        modifier
            .aspectRatio(2f / 3f)
            .posterChrome()
            .clickable(onClick = onClick),
    ) {
        if (item != null && item.usesGeneratedCollage()) {
            CollectionArtwork(item, session, title, Modifier.fillMaxSize())
        } else {
            CachedArtwork(
                urls = urls,
                contentDescription = title,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceContainerHigh),
            )
        }
        Box(
            Modifier.fillMaxSize().background(
                Brush.verticalGradient(0.5f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.82f)),
            ),
        )
        Text(
            title,
            color = Color.White,
            fontWeight = FontWeight.Bold,
            fontSize = 15.sp,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.align(Alignment.BottomStart).padding(10.dp),
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun GenresPage(
    genres: List<LibraryGenre>,
    loading: Boolean,
    bottomInset: Dp,
    onBack: () -> Unit,
    onGenre: (LibraryGenre) -> Unit,
) {
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface)) {
        TopAppBar(
            title = { Text("Genres") },
            navigationIcon = {
                IconButton(onClick = onBack) {
                    Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
                }
            },
            colors = TopAppBarDefaults.topAppBarColors(
                containerColor = MaterialTheme.colorScheme.surface,
                titleContentColor = MaterialTheme.colorScheme.onSurface,
                navigationIconContentColor = MaterialTheme.colorScheme.onSurface,
            ),
        )
        when {
            genres.isEmpty() && loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
            genres.isEmpty() -> Column(
                Modifier.fillMaxSize().padding(top = 40.dp, start = 32.dp, end = 32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text("No Genres", color = MaterialTheme.colorScheme.onSurface, fontWeight = FontWeight.Bold, fontSize = 22.sp)
                Spacer(Modifier.height(8.dp))
                Text("Genres from your libraries will show up here.", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 16.sp)
            }
            else -> BoxWithConstraints(Modifier.fillMaxSize()) {
                val gridState = rememberLazyGridState()
                LazyVerticalGrid(
                    state = gridState,
                    columns = GridCells.Fixed(columnCount(maxWidth - 32.dp)),
                    contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = bottomInset),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalArrangement = Arrangement.spacedBy(20.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    items(genres, key = { it.id }) { genre ->
                        GenreCard(genre.name) { onGenre(genre) }
                    }
                }
            }
        }
    }
}

@Composable
internal fun GenreCard(title: String, aspect: Float = 2f / 3f, corner: Dp = 12.dp, onClick: () -> Unit) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth().aspectRatio(aspect),
        shape = RoundedCornerShape(corner),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            GenreIcon(
                title,
                side = maxWidth * 0.42f,
                tint = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.align(Alignment.Center).padding(bottom = maxHeight * 0.12f),
            )
            val cardWidth = maxWidth
            Box(Modifier.align(Alignment.BottomStart).padding(cardWidth * 0.08f)) {
                FitText(
                    title,
                    style = TextStyle(
                        color = MaterialTheme.colorScheme.onSurface,
                        fontFamily = ZelefinFont,
                        fontWeight = FontWeight.Bold,
                        fontSize = (cardWidth.value * 0.16f).sp,
                        lineHeight = (cardWidth.value * 0.19f).sp,
                    ),
                    maxLines = 3,
                    minScale = 0.5f,
                    floorScale = 0.5f,
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ArrangeSheet(
    rooms: List<LibraryRoom>,
    layout: LibraryLayout,
    onLayout: (LibraryLayout) -> Unit,
    onReset: () -> Unit,
    onDone: () -> Unit,
) {
    var order by remember(rooms.map { it.id }) { mutableStateOf(rooms) }
    var dragging by remember { mutableStateOf<String?>(null) }
    var dragY by remember { mutableFloatStateOf(0f) }
    val stride = with(LocalDensity.current) { RoomStride.toPx() }
    fun target(from: Int): Int = (from + (dragY / stride).roundToInt()).coerceIn(0, max(order.size - 1, 0))

    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface)) {
        TopAppBar(
            title = { Text("Arrange") },
            windowInsets = WindowInsets(0, 0, 0, 0),
            actions = {
                TextButton(onClick = onDone) {
                    Text("Done", fontWeight = FontWeight.SemiBold)
                }
            },
            colors = TopAppBarDefaults.topAppBarColors(
                containerColor = MaterialTheme.colorScheme.surface,
                titleContentColor = MaterialTheme.colorScheme.onSurface,
                actionIconContentColor = MaterialTheme.colorScheme.primary,
            ),
        )
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 28.dp),
        ) {
            Text(
                "Hold a room and drag it up or down. The eye hides it from Library.",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 15.sp,
            )
            Spacer(Modifier.height(28.dp))
            val from = order.indexOfFirst { it.id == dragging }
            order.forEachIndexed { index, room -> key(room.id) {
                val shown = room.id !in layout.resolvedHidden(rooms)
                val isDragging = room.id == dragging
                val neighbor = when {
                    from < 0 || isDragging -> 0f
                    from < target(from) && index in (from + 1)..target(from) -> -stride
                    from > target(from) && index in target(from) until from -> stride
                    else -> 0f
                }
                val animated by animateFloatAsState(neighbor, tween(220), label = "roomShift")
                val dragModifier = Modifier.pointerInput(room.id) {
                    detectDragGestures(
                        onDragStart = {
                            dragging = room.id
                            dragY = 0f
                        },
                        onDrag = { change, amount ->
                            change.consume()
                            dragY += amount.y
                        },
                        onDragEnd = {
                            val start = order.indexOfFirst { it.id == room.id }
                            if (start >= 0) {
                                val end = target(start)
                                if (end != start) {
                                    val next = order.toMutableList().apply { add(end, removeAt(start)) }
                                    order = next
                                    onLayout(layout.copy(order = next.map { it.id }))
                                }
                            }
                            dragging = null
                            dragY = 0f
                        },
                        onDragCancel = {
                            dragging = null
                            dragY = 0f
                        },
                    )
                }
                Card(
                    modifier = Modifier
                        .padding(bottom = 10.dp)
                        .zIndex(if (isDragging) 1f else 0f)
                        .graphicsLayer {
                            translationY = if (isDragging) dragY else animated
                            val scale = if (isDragging) 1.03f else 1f
                            scaleX = scale
                            scaleY = scale
                        }
                        .fillMaxWidth()
                        .heightIn(min = 74.dp),
                    shape = RoundedCornerShape(12.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = if (shown) {
                            MaterialTheme.colorScheme.surfaceContainerHigh
                        } else {
                            MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.55f)
                        },
                    ),
                    elevation = CardDefaults.cardElevation(defaultElevation = if (isDragging) 3.dp else 0.dp),
                ) {
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 74.dp).padding(start = 6.dp, end = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                    Box(Modifier.size(44.dp).then(dragModifier), contentAlignment = Alignment.Center) {
                        Icon(Icons.Filled.DragHandle, contentDescription = "Reorder ${room.name}", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Column(Modifier.weight(1f).fillMaxHeight().then(dragModifier), verticalArrangement = Arrangement.Center) {
                        Text(room.name, color = MaterialTheme.colorScheme.onSurface, fontWeight = FontWeight.SemiBold, fontSize = 20.sp, maxLines = 1)
                        if (!shown) Text("Hidden", color = MaterialTheme.colorScheme.onSurfaceVariant, fontWeight = FontWeight.Medium, fontSize = 15.sp)
                    }
                    EyeButton(shown) {
                        val hidden = layout.resolvedHidden(rooms).toMutableSet()
                        if (shown) hidden += room.id else hidden -= room.id
                        onLayout(layout.copy(hidden = hidden, usesDefaultHidden = false))
                    }
                    }
                }
            } }
            Spacer(Modifier.height(18.dp))
            Text("Also on Library", color = MaterialTheme.colorScheme.onSurface, fontWeight = FontWeight.SemiBold, fontSize = 20.sp)
            Spacer(Modifier.height(12.dp))
            Text("These stay under your rooms. Hide any you don’t need.", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 15.sp)
            Spacer(Modifier.height(16.dp))
            LibraryPageBlock.entries.forEach { block ->
                val shown = block !in layout.hiddenBlocks
                Card(
                    modifier = Modifier.padding(bottom = 10.dp).fillMaxWidth().heightIn(min = 64.dp),
                    shape = RoundedCornerShape(12.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = if (shown) {
                            MaterialTheme.colorScheme.surfaceContainerHigh
                        } else {
                            MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.55f)
                        },
                    ),
                    elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
                ) {
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(start = 16.dp, end = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                    Icon(blockIcon(block), contentDescription = null, tint = MaterialTheme.colorScheme.onSurface, modifier = Modifier.size(22.dp))
                    Spacer(Modifier.width(12.dp))
                    Text(block.title, color = MaterialTheme.colorScheme.onSurface, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, modifier = Modifier.weight(1f))
                    EyeButton(shown) {
                        val hidden = if (shown) layout.hiddenBlocks + block else layout.hiddenBlocks - block
                        onLayout(layout.copy(hiddenBlocks = hidden))
                    }
                    }
                }
            }
            Spacer(Modifier.height(18.dp))
            TextButton(
                onClick = onReset,
                modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp),
            ) {
                Text("Reset arrangement", fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            }
        }
    }
}

@Composable
private fun EyeButton(shown: Boolean, onClick: () -> Unit) {
    IconButton(onClick = onClick, modifier = Modifier.size(44.dp)) {
        Icon(
            if (shown) Icons.Outlined.Visibility else Icons.Outlined.VisibilityOff,
            contentDescription = if (shown) "Hide" else "Show",
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

private fun columnCount(width: Dp): Int = max(3, ((width + 10.dp) / (124.dp + 10.dp)).toInt())

private fun washCandidates(item: MediaItem, session: SavedSession?): List<String> {
    val base = session?.serverUrl
    val backdrop = base?.let { ArtworkUrls.backdrop(it, item, session.accessToken, 960) }
    return (listOfNotNull(backdrop) + artworkCandidates(item, session, landscape = true)).distinct()
}

private fun kindIcon(kind: LibraryKind): ImageVector = when (kind) {
    LibraryKind.Movies -> Icons.Filled.Movie
    LibraryKind.Shows -> Icons.Filled.Tv
    LibraryKind.Music -> Icons.Filled.MusicNote
    LibraryKind.Photos -> Icons.Filled.Photo
    LibraryKind.LiveTV -> Icons.Filled.LiveTv
    LibraryKind.HomeVideos -> Icons.Filled.Videocam
    LibraryKind.Collections -> Icons.Filled.GridView
    LibraryKind.YouTube -> Icons.Filled.Subscriptions
    else -> Icons.Filled.VideoLibrary
}

private fun blockIcon(block: LibraryPageBlock): ImageVector = when (block) {
    LibraryPageBlock.Favorites -> Icons.Filled.Favorite
    LibraryPageBlock.Watchlist -> Icons.Filled.PlaylistAdd
    LibraryPageBlock.Genres -> Icons.Filled.GridView
    LibraryPageBlock.Collections -> Icons.Filled.ViewModule
}