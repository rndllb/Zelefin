package app.zelefin.client.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.tappableElement
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FastForward
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.lerp
import androidx.compose.ui.unit.sp
import app.zelefin.client.AppTab
import app.zelefin.core.MediaItem
import app.zelefin.core.SavedSession
import coil.compose.AsyncImage
import kotlin.math.roundToInt
import kotlin.math.sign

internal val DockBottomGap = 6.dp
internal val DockGap = 8.dp
/** iOS `tabViewBottomAccessory` height. */
internal val DockMiniPlayerHeight = 48.dp
private val DockSideMargin = 20.dp
private val DockMaxWidth = 520.dp
private val DockLabeledHeight = 56.dp
private val DockIconOnlyHeight = 50.dp
/** Minimized tab bar, and the inline mini player beside it. */
private val DockCompactHeight = 48.dp
/** iOS 26 dark tab bar: the selected tab sits in a darker capsule, not a lighter one. */
private val DockLensFill = Color.Black.copy(alpha = 0.34f)
private val DockLensPressedFill = Color.Black.copy(alpha = 0.46f)
private val DockIdleTint = Color.White.copy(alpha = 0.94f)

/** Scroll travel before the dock collapses or comes back. */
private const val DockMinimizeTravelPx = 36f

internal fun dockBarHeight(showsNames: Boolean = TabPreferences.showsNames): Dp =
    if (showsNames) DockLabeledHeight else DockIconOnlyHeight

/**
 * Space under the dock. Like iOS, the bar dips into the gesture-bar inset (about 20dp up),
 * but stays clear of on-screen navigation buttons, which can be tapped.
 */
@Composable
internal fun dockBottomInset(): Dp {
    val nav = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    val buttons = WindowInsets.tappableElement.asPaddingValues().calculateBottomPadding()
    return if (buttons > 0.dp) buttons + DockBottomGap else (nav - 4.dp).coerceAtLeast(12.dp)
}

/**
 * The dock's collapse state, and where the mini player artwork sits so the player can grow
 * out of it. Mirrors iOS `tabBarMinimizeBehavior(.onScrollDown)`.
 */
@Stable
class DockChromeState {
    var minimized by mutableStateOf(false)
        private set
    var hasMiniPlayer by mutableStateOf(false)
    private var travel = 0f

    /** Scrolling the page down collapses the dock; scrolling up, or pulling at the top, brings it back. */
    val scroll: NestedScrollConnection = object : NestedScrollConnection {
        override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
            val dy = consumed.y
            if (dy == 0f) {
                if (available.y > 0f) expand()
                return Offset.Zero
            }
            if (sign(dy) != sign(travel)) travel = 0f
            travel += dy
            if (travel < -DockMinimizeTravelPx) minimized = true
            if (travel > DockMinimizeTravelPx) minimized = false
            return Offset.Zero
        }
    }

    fun expand() {
        minimized = false
        travel = 0f
    }
}

val LocalDockChrome = staticCompositionLocalOf<DockChromeState?> { null }

/**
 * iOS 26 tab bar on liquid glass: a capsule of tabs with a sliding lens, Search in its own
 * circle, and the mini player above it. Collapsed, the capsule shrinks to the selected tab and
 * the mini player slides in between it and Search.
 */
@Composable
fun ZelefinGlassDock(
    chrome: DockChromeState,
    currentTab: AppTab,
    currentRoomId: String?,
    entries: List<DockEntry>,
    showsNames: Boolean,
    nowPlaying: MediaItem?,
    session: SavedSession?,
    onSelectEntry: (DockEntry) -> Unit,
    onOpenNowPlaying: () -> Unit,
    onStopNowPlaying: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val tabs = entries.filter { it.tab != AppTab.Search }
    val search = entries.firstOrNull { it.tab == AppTab.Search }
    val selectedIndex = tabs.indexOfFirst { currentTab == it.tab && (it.room == null || it.room.id == currentRoomId) }
    val progress by animateFloatAsState(
        targetValue = if (chrome.minimized) 1f else 0f,
        animationSpec = spring(dampingRatio = 0.82f, stiffness = 360f),
        label = "dockMinimize",
    )
    val barExpanded = dockBarHeight(showsNames)
    val bottom = dockBottomInset()
    val hasMini = nowPlaying != null
    val height = bottom + barExpanded + if (hasMini) DockGap + DockMiniPlayerHeight else 0.dp

    BoxWithConstraints(modifier.fillMaxWidth().height(height)) {
        val full = (maxWidth - DockSideMargin * 2).coerceAtMost(DockMaxWidth)
        val start = (maxWidth - full) / 2
        val bar = lerp(barExpanded, DockCompactHeight, progress)
        val tabsExpandedWidth = full - barExpanded - DockGap
        val tabsWidth = lerp(tabsExpandedWidth, DockCompactHeight, progress)
        val selected = tabs.getOrNull(selectedIndex)

        Box(
            Modifier
                .align(Alignment.BottomStart)
                .padding(start = start, bottom = bottom)
                .size(tabsWidth, bar),
        ) {
            LiquidGlassPane(bar / 2, Modifier.matchParentSize())
            Box(Modifier.matchParentSize().clip(RoundedCornerShape(bar / 2))) {
                if (progress < 0.98f) {
                    DockTabRow(
                        tabs = tabs,
                        selectedIndex = selectedIndex,
                        showsNames = showsNames,
                        onSelect = { index -> tabs.getOrNull(index)?.let(onSelectEntry) },
                        modifier = Modifier
                            .wrapContentSize(Alignment.CenterStart, unbounded = true)
                            .requiredSize(tabsExpandedWidth, barExpanded)
                            .graphicsLayer { alpha = (1f - progress * 1.6f).coerceIn(0f, 1f) },
                    )
                }
                if (progress > 0.02f) {
                    val entry = selected ?: tabs.firstOrNull()
                    Box(
                        Modifier
                            .matchParentSize()
                            .graphicsLayer { alpha = ((progress - 0.35f) / 0.65f).coerceIn(0f, 1f) }
                            .clickable(onClickLabel = "Show tabs") { chrome.expand() },
                        contentAlignment = Alignment.Center,
                    ) {
                        if (entry != null) {
                            DockTabIcon(entry.tab, selected = true, description = entry.title, tint = ZelefinCyan, modifier = Modifier.size(22.dp), room = entry.room)
                        }
                    }
                }
            }
        }

        if (search != null) {
            val searchSelected = currentTab == AppTab.Search
            Box(
                Modifier
                    .align(Alignment.BottomStart)
                    .padding(start = start + full - bar, bottom = bottom)
                    .size(bar),
            ) {
                LiquidGlassPane(bar / 2, Modifier.matchParentSize())
                Box(
                    Modifier
                        .matchParentSize()
                        .clip(CircleShape)
                        .clickable(onClickLabel = search.title) { onSelectEntry(search) },
                    contentAlignment = Alignment.Center,
                ) {
                    DockTabIcon(
                        AppTab.Search,
                        selected = searchSelected,
                        description = search.title,
                        tint = if (searchSelected) ZelefinCyan else DockIdleTint,
                        modifier = Modifier.size(22.dp),
                    )
                }
            }
        }

        if (nowPlaying != null) {
            val inlineStart = start + DockCompactHeight + DockGap
            val miniStart = lerp(start, inlineStart, progress)
            val miniWidth = lerp(full, full - (DockCompactHeight + DockGap) * 2, progress)
            val miniHeight = lerp(DockMiniPlayerHeight, DockCompactHeight, progress)
            val miniBottom = lerp(bottom + barExpanded + DockGap, bottom, progress)
            Box(
                Modifier
                    .align(Alignment.BottomStart)
                    .padding(start = miniStart, bottom = miniBottom)
                    .size(miniWidth, miniHeight),
            ) {
                LiquidGlassPane(miniHeight / 2, Modifier.matchParentSize())
                DockMiniPlayer(
                    item = nowPlaying,
                    session = session,
                    collapse = progress,
                    onOpen = onOpenNowPlaying,
                    onStop = onStopNowPlaying,
                    modifier = Modifier.matchParentSize().clip(RoundedCornerShape(miniHeight / 2)),
                )
            }
        }
    }
}

/**
 * Tabs with the iOS lens: it springs to the selected tab, and while a finger is down it
 * follows the finger across the bar, picking the tab under it on release.
 */
@Composable
private fun DockTabRow(
    tabs: List<DockEntry>,
    selectedIndex: Int,
    showsNames: Boolean,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val haptics = LocalHapticFeedback.current
    val density = LocalDensity.current
    var pressing by remember { mutableStateOf(false) }
    var touchX by remember { mutableFloatStateOf(0f) }
    var restingX by remember { mutableFloatStateOf(0f) }
    BoxWithConstraints(modifier) {
        val inset = 4.dp
        val insetPx = with(density) { inset.toPx() }
        val count = tabs.size.coerceAtLeast(1)
        val tabPx = (constraints.maxWidth - insetPx * 2) / count
        val tabWidth = with(density) { tabPx.toDp() }
        fun indexAt(x: Float) = ((x - insetPx) / tabPx).toInt().coerceIn(0, count - 1)
        val hover = if (pressing) indexAt(touchX) else selectedIndex
        val target = when {
            pressing -> (touchX - insetPx - tabPx / 2).coerceIn(0f, tabPx * (count - 1))
            selectedIndex >= 0 -> selectedIndex * tabPx
            else -> null
        }
        if (target != null && !pressing) restingX = target
        val lensX by animateFloatAsState(
            targetValue = target ?: restingX,
            animationSpec = if (pressing) spring(dampingRatio = 1f, stiffness = 2400f) else spring(dampingRatio = 0.72f, stiffness = 520f),
            label = "dockLensX",
        )
        val lensScale by animateFloatAsState(
            targetValue = if (pressing) 1.12f else 1f,
            animationSpec = spring(dampingRatio = 0.6f, stiffness = 500f),
            label = "dockLensScale",
        )
        val lensAlpha by animateFloatAsState(if (target == null) 0f else 1f, label = "dockLensAlpha")
        LaunchedEffect(hover, pressing) {
            if (pressing) haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        }
        Box(
            Modifier
                .offset { IntOffset((insetPx + lensX).roundToInt(), insetPx.roundToInt()) }
                .size(tabWidth, maxHeight - inset * 2)
                .graphicsLayer {
                    scaleX = lensScale
                    scaleY = lensScale
                    alpha = lensAlpha
                }
                .clip(RoundedCornerShape(percent = 50))
                .background(if (pressing) DockLensPressedFill else DockLensFill),
        )
        Row(
            Modifier
                .fillMaxSize()
                .padding(horizontal = inset)
                .pointerInput(count, tabPx) {
                    awaitEachGesture {
                        val down = awaitFirstDown(requireUnconsumed = false)
                        pressing = true
                        touchX = down.position.x + insetPx
                        do {
                            val event = awaitPointerEvent()
                            event.changes.forEach { change ->
                                if (change.pressed) touchX = change.position.x + insetPx
                                change.consume()
                            }
                        } while (event.changes.any { it.pressed })
                        val index = indexAt(touchX)
                        pressing = false
                        onSelect(index)
                    }
                },
        ) {
            tabs.forEachIndexed { index, entry ->
                DockTabItem(
                    entry = entry,
                    highlighted = index == hover,
                    selected = index == selectedIndex,
                    showsNames = showsNames,
                    onSelect = { onSelect(index) },
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                )
            }
        }
    }
}

@Composable
private fun DockTabItem(
    entry: DockEntry,
    highlighted: Boolean,
    selected: Boolean,
    showsNames: Boolean,
    onSelect: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val tint = if (highlighted) ZelefinCyan else DockIdleTint
    Column(
        modifier.semantics(mergeDescendants = true) {
            role = Role.Tab
            this.selected = selected
            contentDescription = entry.title
            onClick(label = entry.title) {
                onSelect()
                true
            }
        },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center,
    ) {
        DockTabIcon(entry.tab, selected = highlighted, description = null, tint = tint, modifier = Modifier.size(if (showsNames) 22.dp else 24.dp), room = entry.room)
        if (showsNames) {
            Spacer(Modifier.height(1.dp))
            Text(
                entry.title,
                color = tint,
                fontFamily = ZelefinFont,
                fontSize = 10.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/** iOS mini player row: artwork, title, transport. Long-press for Play / Stop like the iOS context menu. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DockMiniPlayer(
    item: MediaItem,
    session: SavedSession?,
    collapse: Float,
    onOpen: () -> Unit,
    onStop: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var menuOpen by remember { mutableStateOf(false) }
    var bounds by remember { mutableStateOf(Rect.Zero) }
    MiniPlayerRow(
        item = item,
        session = session,
        collapse = collapse,
        onOpen = onOpen,
        modifier = modifier
            .onGloballyPositioned { bounds = it.boundsInRoot() }
            .combinedClickable(
                onClickLabel = "Open player",
                onLongClick = { menuOpen = true },
                onClick = onOpen,
            ),
    )
    PresentZelefinOverlay(visible = menuOpen) {
        AnchoredMenuFrame(
            anchor = bounds,
            alignTrailing = false,
            onDismiss = { menuOpen = false },
            clearBottom = dockContentReserve(),
        ) {
            Column(
                Modifier
                    .zelefinGlassChrome(ZelefinMenuShape)
                    .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) {}
                    .zelefinMenuWidth()
                    .padding(vertical = 4.dp),
            ) {
                MoreRow("Play", Icons.Filled.PlayArrow, onClick = {
                    menuOpen = false
                    onOpen()
                })
                MoreRow("Stop", Icons.Filled.Stop, destructive = true, onClick = {
                    menuOpen = false
                    onStop()
                })
            }
        }
    }
}

/** The mini player's contents: artwork, title, and transport buttons. */
@Composable
internal fun MiniPlayerRow(
    item: MediaItem,
    session: SavedSession?,
    collapse: Float,
    onOpen: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val compact = collapse > 0.5f
    // iOS MiniPlayerView spacing: 16pt leading, 10pt trailing; inline 12pt, 8pt. The art reads
    // smaller on iOS inside the system accessory, so it is a touch under its 34pt / 26pt here.
    val art = lerp(30.dp, 24.dp, collapse)
    val leading = lerp(16.dp, 12.dp, collapse)
    val trailing = lerp(10.dp, 8.dp, collapse)
    val spacing = lerp(10.dp, 8.dp, collapse)
    val subtitle = item.episodeLabel ?: item.continueWatchingCaption
    val secondaryAlpha = (1f - collapse * 2f).coerceIn(0f, 1f)
    Row(
        modifier.padding(start = leading, end = trailing),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AsyncImage(
            model = artwork(item, session, landscape = false),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .size(art)
                .clip(RoundedCornerShape(6.dp))
                .background(Color.White.copy(alpha = 0.08f)),
        )
        Spacer(Modifier.width(spacing))
        Column(Modifier.weight(1f)) {
            Text(
                item.continueWatchingTitle,
                color = Color.White,
                fontFamily = ZelefinFont,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (!compact && !subtitle.isNullOrBlank()) {
                Text(
                    subtitle,
                    color = Color.White.copy(alpha = 0.6f),
                    fontFamily = ZelefinFont,
                    fontSize = 11.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.graphicsLayer { alpha = secondaryAlpha },
                )
            }
        }
        Spacer(Modifier.width(spacing))
        MiniTransportButton(Icons.Filled.PlayArrow, "Play", onOpen)
        if (!compact) {
            MiniTransportButton(Icons.Filled.FastForward, "Next", onOpen, Modifier.graphicsLayer { alpha = secondaryAlpha })
        }
    }
}

/** iOS: a 16pt semibold SF symbol in a 30pt frame. */
@Composable
private fun MiniTransportButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    onClick: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier
            .size(30.dp)
            .clip(CircleShape)
            .then(if (onClick != null) Modifier.clickable(onClickLabel = label, onClick = onClick) else Modifier),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = label, tint = Color.White, modifier = Modifier.size(20.dp))
    }
}
