package app.zelefin.client.ui

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.offset
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.unit.IntOffset
import kotlin.math.roundToInt
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.runtime.rememberCoroutineScope
import app.zelefin.client.plugins.JellyfinEnhancedHomeSurface
import app.zelefin.core.ArtworkUrls
import app.zelefin.core.HomeFeed
import kotlinx.coroutines.launch
import app.zelefin.core.MediaItem
import app.zelefin.core.SavedSession
import kotlinx.coroutines.delay

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeFeedPage(
    feed: HomeFeed,
    session: SavedSession?,
    bottomInset: Dp,
    onOpen: (MediaItem) -> Unit,
    onPlay: (MediaItem) -> Unit,
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    onProfile: () -> Unit,
    onSessions: () -> Unit,
    onSettings: () -> Unit,
    onSignOut: () -> Unit,
    onToggleWatched: (MediaItem) -> Unit,
    onToggleFavorite: (MediaItem) -> Unit,
    onHideFromHome: (suspend (MediaItem, JellyfinEnhancedHomeSurface) -> String?)? = null,
) {
    var more by remember { mutableStateOf<TitleMoreRequest?>(null) }
    var note by remember { mutableStateOf<MenuNotice?>(null) }
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    val refreshState = rememberPullToRefreshState()
    var headerVisible by remember { mutableStateOf(true) }
    var previousOffset by remember { mutableIntStateOf(0) }
    TrackHazeScroll(listState.isScrollInProgress)
    LaunchedEffect(listState) {
        snapshotFlow {
            listState.firstVisibleItemIndex * 100_000 + listState.firstVisibleItemScrollOffset
        }.collect { offset ->
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
    val statusTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    Box(Modifier.fillMaxSize()) {
    PullToRefreshBox(
        isRefreshing = isRefreshing,
        onRefresh = onRefresh,
        state = refreshState,
        modifier = Modifier.fillMaxSize(),
        indicator = {
            PullToRefreshDefaults.Indicator(
                modifier = Modifier.align(Alignment.TopCenter).statusBarsPadding(),
                isRefreshing = isRefreshing,
                state = refreshState,
                containerColor = Color(0xFF1C1C1E),
                color = ZelefinCyan,
            )
        },
    ) {
    LazyColumn(
        state = listState,
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            top = if (feed.featured.isEmpty()) statusTop + HomeHeaderHeight else 0.dp,
            bottom = bottomInset,
        ),
        verticalArrangement = Arrangement.spacedBy(28.dp),
    ) {
        if (feed.featured.isNotEmpty()) {
            item {
                FeaturedHero(feed.featured, session, onOpen, onPlay, paused = more != null) { item, anchor ->
                    more = TitleMoreRequest(item, TitleMenuContext.Featured, anchor)
                }
            }
        }
        if (feed.continueWatching.isNotEmpty()) {
            item {
                HomeRow("Continue Watching", feed.continueWatching, session, landscape = true, onOpen) { item, anchor ->
                    more = TitleMoreRequest(item, TitleMenuContext.ContinueWatching, anchor)
                }
            }
        }
        if (feed.nextUp.isNotEmpty()) {
            item {
                HomeRow("Next Up", feed.nextUp, session, landscape = true, onOpen) { item, anchor ->
                    more = TitleMoreRequest(item, TitleMenuContext.NextUp, anchor)
                }
            }
        }
        if (feed.recentMovies.isNotEmpty()) {
            item { HomeRow("Recently Added Movies", feed.recentMovies, session, landscape = false, onOpen) }
        }
        if (feed.recentShows.isNotEmpty()) {
            item { HomeRow("Recently Added Shows", feed.recentShows, session, landscape = false, onOpen) }
        }
    }
    }
    HomeTitleBar(headerVisible, session, onProfile, onSessions, onSettings, onSignOut)
    }
    TitleMoreOverlay(
        request = more,
        onDismiss = { more = null },
        onPlay = onPlay,
        onOpen = onOpen,
        onToggleWatched = onToggleWatched,
        onToggleFavorite = onToggleFavorite,
        note = note,
        onDismissNote = { note = null },
        onHideFromHome = onHideFromHome?.let { hide ->
            { item, context ->
                val surface = if (context == TitleMenuContext.NextUp) {
                    JellyfinEnhancedHomeSurface.NextUp
                } else {
                    JellyfinEnhancedHomeSurface.ContinueWatching
                }
                scope.launch {
                    hide(item, surface)?.let { note = MenuNotice("Jellyfin Enhanced", it) }
                }
            }
        },
    )
}

private val HomeHeaderHeight = 59.dp

@Composable
private fun HomeTitleBar(
    visible: Boolean,
    session: SavedSession?,
    onProfile: () -> Unit,
    onSessions: () -> Unit,
    onSettings: () -> Unit,
    onSignOut: () -> Unit,
) {
    val alpha by animateFloatAsState(if (visible) 1f else 0f, tween(180), label = "homeHeader")
    val shift by animateDpAsState(if (visible) 0.dp else (-120).dp, tween(180), label = "homeHeaderShift")
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
            "Home",
            color = Color.White,
            fontFamily = ZelefinFont,
            fontWeight = FontWeight.Bold,
            fontSize = 34.sp,
            modifier = Modifier.weight(1f),
        )
        AccountAvatarMenu(session, onProfile, onSessions, onSettings, onSignOut)
    }
}

@Composable
private fun FeaturedHero(
    items: List<MediaItem>,
    session: SavedSession?,
    onOpen: (MediaItem) -> Unit,
    onPlay: (MediaItem) -> Unit,
    paused: Boolean,
    onMore: (MediaItem, androidx.compose.ui.geometry.Rect) -> Unit,
) {
    val slides = remember(items) { items.take(8) }
    var index by remember(slides) { mutableIntStateOf(0) }
    val host = LocalZelefinGlassHost.current
    val dotBounds = remember { mutableStateOf(androidx.compose.ui.geometry.Rect.Zero) }
    DisposableEffect(host, slides.size, index, paused) {
        host?.foreground = if (slides.size < 2) {
            null
        } else {
            {
                val bounds = dotBounds.value
                if (bounds.width > 1f) {
                    HeroPagerDots(
                        count = slides.size,
                        index = index,
                        paused = paused,
                        onAdvance = { index = (index + 1) % slides.size },
                        modifier = Modifier.offset { IntOffset(bounds.left.roundToInt(), bounds.top.roundToInt()) },
                    )
                }
            }
        }
        onDispose { host?.foreground = null }
    }
    val screenHeight = LocalConfiguration.current.screenHeightDp.dp
    val heroHeight = (screenHeight * 0.82f).coerceAtLeast(560.dp).coerceAtMost(screenHeight)
    val item = slides[index.coerceIn(slides.indices)]

    Box(
        Modifier
            .fillMaxWidth()
            .height(heroHeight)
            .pointerInput(slides) {
                var drag = 0f
                detectHorizontalDragGestures(
                    onDragEnd = {
                        if (slides.size > 1 && drag < -48f) index = (index + 1) % slides.size
                        if (slides.size > 1 && drag > 48f) index = (index - 1 + slides.size) % slides.size
                        drag = 0f
                    },
                    onHorizontalDrag = { _, amount -> drag += amount },
                )
            },
    ) {
        CachedArtwork(
            urls = heroArtworkCandidates(item, session),
            contentDescription = item.name,
            contentScale = ContentScale.Crop,
            crossfade = true,
            modifier = Modifier.fillMaxSize().clickable { onOpen(item) },
        )
        Box(
            Modifier
                .fillMaxWidth()
                .height(heroHeight / 2)
                .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.55f), Color.Transparent))),
        )
        Box(
            Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        0f to Color.Transparent,
                        0.45f to Color.Transparent,
                        0.72f to Color.Black.copy(alpha = 0.55f),
                        1f to Color.Black.copy(alpha = 0.96f),
                    ),
                ),
        )
        Column(
            Modifier
                .align(Alignment.BottomCenter)
                .padding(horizontal = 24.dp)
                .padding(bottom = 56.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp)) {
                HeroLogo(item, session)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        item.heroMetadataLine,
                        color = Color.White.copy(alpha = 0.86f),
                        fontFamily = ZelefinFont,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 15.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    item.officialRating?.takeIf { it.isNotBlank() }?.let { RatingBadge(it) }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier
                        .clip(RoundedCornerShape(50))
                        .background(Color.White)
                        .clickable { onPlay(item) }
                        .padding(horizontal = 36.dp, vertical = 13.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Icons.Filled.PlayArrow, contentDescription = null, tint = Color.Black, modifier = Modifier.size(18.dp))
                        Text("Play", color = Color.Black, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
                    }
                }
                val moreAnchor = remember { mutableStateOf(androidx.compose.ui.geometry.Rect.Zero) }
                Box(
                    Modifier
                        .size(48.dp)
                        .shadow(
                            elevation = 6.dp,
                            shape = CircleShape,
                            ambientColor = Color.Black.copy(alpha = 0.06f),
                            spotColor = Color.Black.copy(alpha = 0.10f),
                        )
                        .clip(CircleShape)
                        .background(DockFill)
                        .border(0.5.dp, DockBorder, CircleShape)
                        .onGloballyPositioned { coords ->
                            val next = coords.boundsInRoot()
                            if (moreAnchor.value != next) moreAnchor.value = next
                        }
                        .clickable { onMore(item, moreAnchor.value) },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Filled.MoreHoriz, contentDescription = "More", tint = Color.White)
                }
            }
        }
        if (slides.size > 1) {
            Row(
                Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 14.dp)
                    .onGloballyPositioned { coords ->
                        val next = coords.boundsInRoot()
                        if (dotBounds.value != next) dotBounds.value = next
                    },
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                repeat(slides.size) { dot ->
                    Box(Modifier.width(if (dot == index) 24.dp else 7.dp).height(7.dp))
                }
            }
        }
    }
}

@Composable
private fun HeroPagerDots(
    count: Int,
    index: Int,
    paused: Boolean,
    onAdvance: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var progress by remember(index) { mutableFloatStateOf(0f) }
    LaunchedEffect(index, count, paused) {
        if (paused || count < 2) return@LaunchedEffect
        val started = System.nanoTime()
        while (true) {
            val elapsed = (System.nanoTime() - started) / 1_000_000_000f / 6f
            if (elapsed >= 1f) {
                onAdvance()
                return@LaunchedEffect
            }
            progress = elapsed
            delay(32)
        }
    }
    Row(
        modifier,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        repeat(count) { dot ->
            val active = dot == index
            Box(
                Modifier
                    .width(if (active) 24.dp else 7.dp)
                    .height(7.dp)
                    .clip(RoundedCornerShape(50))
                    .background(Color.White.copy(alpha = 0.38f)),
            ) {
                if (active) {
                    Box(
                        Modifier
                            .fillMaxWidth(progress.coerceIn(0f, 1f))
                            .height(7.dp)
                            .background(Color.White),
                    )
                }
            }
        }
    }
}

@Composable
internal fun HeroLogo(
    item: MediaItem,
    session: SavedSession?,
    maxHeight: Dp = 92.dp,
    maxWidth: Dp = 300.dp,
    titleSize: androidx.compose.ui.unit.TextUnit = 28.sp,
) {
    val logo = session?.serverUrl?.let { ArtworkUrls.logo(it, item, session.accessToken) }
    if (logo != null) {
        CachedArtwork(
            url = logo,
            contentDescription = item.name,
            contentScale = ContentScale.Fit,
            modifier = Modifier.widthIn(max = maxWidth).height(maxHeight),
        )
    } else {
        Text(
            item.name,
            color = Color.White,
            fontFamily = ZelefinFont,
            fontWeight = FontWeight.Bold,
            fontSize = titleSize,
            textAlign = TextAlign.Center,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.widthIn(max = maxWidth),
        )
    }
}

@Composable
private fun RatingBadge(rating: String) {
    Text(
        rating,
        color = Color.White,
        fontFamily = ZelefinFont,
        fontWeight = FontWeight.SemiBold,
        fontSize = 11.sp,
        modifier = Modifier
            .border(1.dp, Color.White, RoundedCornerShape(3.dp))
            .padding(horizontal = 5.dp, vertical = 2.dp),
    )
}

@Composable
private fun HomeRow(
    title: String,
    items: List<MediaItem>,
    session: SavedSession?,
    landscape: Boolean,
    onOpen: (MediaItem) -> Unit,
    onMore: ((MediaItem, androidx.compose.ui.geometry.Rect) -> Unit)? = null,
) {
    if (items.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(
            Modifier.padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(title, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 20.sp)
            Icon(
                Icons.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = Color.White.copy(alpha = 0.45f),
                modifier = Modifier.size(16.dp),
            )
        }
        val rowState = rememberLazyListState()
        TrackHazeScroll(rowState.isScrollInProgress)
        LazyRow(
            state = rowState,
            contentPadding = PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(items, key = { title + it.id }) { item ->
                if (landscape) LandscapeHomeCard(item, session, { onOpen(item) }, onMore)
                else PortraitHomeCard(item, session) { onOpen(item) }
            }
        }
    }
}

@Composable
private fun LandscapeHomeCard(
    item: MediaItem,
    session: SavedSession?,
    onClick: () -> Unit,
    onMore: ((MediaItem, androidx.compose.ui.geometry.Rect) -> Unit)? = null,
) {
    val moreAnchor = remember { mutableStateOf(androidx.compose.ui.geometry.Rect.Zero) }
    Box(
        Modifier
            .width(280.dp)
            .height(158.dp)
            .posterChrome()
            .clickable(onClick = onClick),
    ) {
        CachedArtwork(
            urls = artworkCandidates(item, session, landscape = true),
            contentDescription = item.continueWatchingTitle,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize().background(Color.White.copy(alpha = 0.08f)),
        )
        ItemPosterMarks(item, portrait = false)
        Box(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .height(44.dp)
                .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.72f)))),
        )
        Row(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .padding(horizontal = 10.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            if (item.showsResumeProgress) {
                Icon(Icons.Filled.PlayArrow, contentDescription = null, tint = Color.White.copy(alpha = 0.75f), modifier = Modifier.size(9.dp))
                Box(
                    Modifier
                        .width(22.dp)
                        .height(3.5.dp)
                        .clip(RoundedCornerShape(50))
                        .background(Color.White.copy(alpha = 0.32f)),
                ) {
                    Box(
                        Modifier
                            .fillMaxWidth(item.progress.toFloat().coerceIn(0f, 1f))
                            .height(3.5.dp)
                            .background(Color.White.copy(alpha = 0.75f)),
                    )
                }
            }
            item.continueWatchingCaption?.let { caption ->
                Text(
                    caption,
                    color = Color.White.copy(alpha = 0.75f),
                    fontFamily = ZelefinFont,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 11.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
            } ?: Spacer(Modifier.weight(1f))
            Icon(
                Icons.Filled.MoreHoriz,
                contentDescription = "More",
                tint = Color.White.copy(alpha = 0.75f),
                modifier = Modifier
                    .size(28.dp)
                    .onGloballyPositioned { moreAnchor.value = it.boundsInRoot() }
                    .clickable(enabled = onMore != null) { onMore?.invoke(item, moreAnchor.value) },
            )
        }
    }
}

@Composable
internal fun PortraitHomeCard(item: MediaItem, session: SavedSession?, onClick: () -> Unit) {
    Box(
        Modifier
            .width(124.dp)
            .height(186.dp)
            .posterChrome()
            .clickable(onClick = onClick),
    ) {
        CachedArtwork(
            urls = artworkCandidates(item, session, landscape = false),
            contentDescription = item.name,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize().background(Color.White.copy(alpha = 0.08f)),
        )
        ItemPosterMarks(item, portrait = true)
    }
}
