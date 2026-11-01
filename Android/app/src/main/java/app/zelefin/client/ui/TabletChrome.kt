package app.zelefin.client.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.ViewSidebar
import androidx.compose.material.icons.rounded.DragHandle
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import app.zelefin.client.AppTab
import app.zelefin.core.MediaItem
import app.zelefin.core.SavedSession
import kotlin.math.roundToInt

/*
 * Android tablets lay out like iPad: the tabs float in a capsule in the page header row, a button
 * in it opens a sidebar with the same tabs and the account, and Now Playing floats at the bottom.
 * Phones keep the bottom dock.
 */

/** The top tab bar shares the page header row: 4dp under the status bar, as tall as its 45dp buttons. */
private val TabletTopBarHeight = 45.dp
private val TabletTopBarTop = 4.dp

/** How far a title page's floating buttons sit under the status bar: in the tab bar's row on tablets. */
@Composable
internal fun floatingButtonsTop(): Dp = if (LocalConfiguration.current.isLargeScreen()) TabletTopBarTop else 8.dp

/** iPad's sidebar width. The page narrows by this much while the sidebar is open. */
internal val TabletSidebarWidth = 280.dp

/** Below this window width (a tablet held upright) the sidebar covers the page instead of narrowing it. */
private const val SidebarPushMinWidthDp = 960

internal fun sidebarNarrowsPage(screenWidthDp: Int): Boolean = screenWidthDp >= SidebarPushMinWidthDp

/**
 * On a page laid out under the sidebar (Home and title pages, as on iPad), how far its content
 * starts from the leading edge: the sidebar's width while it narrows the page, otherwise 0.
 */
internal val LocalSidebarInset = compositionLocalOf { 0.dp }

/** Lays content out beside the sidebar on a page that runs under it. */
@Composable
internal fun Modifier.besideSidebar(): Modifier = padding(start = LocalSidebarInset.current)

/** A shelf's padding: it starts beside the sidebar and scrolls on under it, as on iPad. */
@Composable
internal fun shelfPadding(horizontal: Dp = 16.dp): PaddingValues =
    PaddingValues(start = horizontal + LocalSidebarInset.current, end = horizontal)

/**
 * iPad's background extension for hero art: laid out beside the sidebar, it also draws itself
 * mirrored into the sidebar's width on its leading side, so the art carries on under the glass.
 */
@Composable
internal fun Modifier.extendsUnderSidebar(): Modifier {
    val width = LocalSidebarInset.current
    val layer = rememberGraphicsLayer()
    if (width <= 0.dp) return this
    return drawWithContent {
        layer.record { this@drawWithContent.drawContent() }
        drawLayer(layer)
        clipRect(left = -width.toPx(), top = 0f, right = 0f, bottom = size.height) {
            withTransform({ scale(-1f, 1f, pivot = Offset.Zero) }) { drawLayer(layer) }
        }
    }
}

/** Dims the page under a covering sidebar; a tap closes it. */
@Composable
fun ZelefinTabletSidebarScrim(onDismiss: () -> Unit) {
    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.4f))
            .clickable(interactionSource = null, indication = null, onClickLabel = "Hide sidebar", onClick = onDismiss),
    )
}

private val TabletMiniPlayerWidth = 460.dp

private fun DockEntry.isCurrent(currentTab: AppTab, currentRoomId: String?): Boolean =
    tab == currentTab && (room == null || room.id == currentRoomId)

/**
 * Where the top tab bar sits, in root coordinates, so page header titles can stop short of it.
 * Empty while the bar is hidden.
 */
internal val LocalTabletTopBarBounds = staticCompositionLocalOf<State<Rect>?> { null }

private val TitleClearance = 12.dp

/** True while the tablet sidebar is open. */
internal val LocalTabletSidebarShown = compositionLocalOf { false }

/**
 * A tab page's title steps aside while the sidebar is open, as on iPad: the sidebar's selected
 * row already names the page.
 */
@Composable
internal fun Modifier.tabTitleBesideSidebar(): Modifier {
    val hidden = LocalTabletSidebarShown.current
    val alpha by animateFloatAsState(if (hidden) 0f else 1f, tween(180), label = "tabTitle")
    return graphicsLayer { this.alpha = alpha }.then(if (hidden) Modifier.clearAndSetSemantics {} else Modifier)
}

/**
 * Ends a header title before the top tab bar, which floats in the same row. Apply it after
 * `weight(1f)`, so the measured width is the title's whole slot.
 */
@Composable
internal fun Modifier.clearOfTabletTopBar(): Modifier {
    val bar = LocalTabletTopBarBounds.current ?: return this
    val density = LocalDensity.current
    var slot by remember { mutableStateOf(Rect.Zero) }
    val barRect = bar.value
    val overlap = if (barRect.isEmpty || slot.isEmpty || slot.top > barRect.bottom || slot.bottom < barRect.top) {
        0f
    } else {
        slot.right - (barRect.left - with(density) { TitleClearance.toPx() })
    }
    val trim = with(density) { overlap.coerceIn(0f, slot.width).toDp() }
    return onGloballyPositioned { slot = it.boundsInRoot() }.padding(end = trim)
}

/**
 * iPad's floating tab bar, in the page header row: one capsule with the sidebar button, the tabs
 * by name, and Search.
 */
@Composable
fun ZelefinTabletTopBar(
    entries: List<DockEntry>,
    currentTab: AppTab,
    currentRoomId: String?,
    onShowSidebar: () -> Unit,
    onSelectEntry: (DockEntry) -> Unit,
    onBounds: (Rect) -> Unit,
    modifier: Modifier = Modifier,
) {
    val tabs = entries.filter { it.tab != AppTab.Search }
    val search = entries.firstOrNull { it.tab == AppTab.Search }
    DisposableEffect(Unit) { onDispose { onBounds(Rect.Zero) } }
    Box(modifier.fillMaxWidth().statusBarsPadding().padding(top = TabletTopBarTop), contentAlignment = Alignment.TopCenter) {
        Box(Modifier.height(TabletTopBarHeight).onGloballyPositioned { onBounds(it.boundsInRoot()) }) {
            LiquidGlassPane(TabletTopBarHeight / 2, Modifier.matchParentSize())
            Row(
                Modifier.clip(RoundedCornerShape(percent = 50)).padding(TabletTopBarInset),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TopBarIconButton(description = "Show sidebar", selected = false, onClick = onShowSidebar) {
                    Icon(Icons.Outlined.ViewSidebar, contentDescription = null, tint = DockIdleTint, modifier = Modifier.size(21.dp))
                }
                tabs.forEach { entry ->
                    TopBarTab(entry, entry.isCurrent(currentTab, currentRoomId)) { onSelectEntry(entry) }
                }
                if (search != null) {
                    val selected = currentTab == AppTab.Search
                    TopBarIconButton(description = search.title, selected = selected, onClick = { onSelectEntry(search) }) {
                        DockTabIcon(AppTab.Search, selected = selected, description = null, tint = if (selected) ZelefinCyan else DockIdleTint, modifier = Modifier.size(21.dp))
                    }
                }
            }
        }
    }
}

private val TabletTopBarInset = 3.dp
private val TopBarItemHeight = TabletTopBarHeight - TabletTopBarInset * 2

@Composable
private fun TopBarTab(entry: DockEntry, selected: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .height(TopBarItemHeight)
            .clip(RoundedCornerShape(percent = 50))
            .background(if (selected) DockLensFill else Color.Transparent)
            .semantics(mergeDescendants = true) {
                role = Role.Tab
                this.selected = selected
            }
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            entry.title,
            color = if (selected) ZelefinCyan else Color.White,
            fontFamily = ZelefinFont,
            fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun TopBarIconButton(description: String, selected: Boolean, onClick: () -> Unit, icon: @Composable () -> Unit) {
    Box(
        Modifier
            .size(TopBarItemHeight)
            .clip(CircleShape)
            .background(if (selected) DockLensFill else Color.Transparent)
            .semantics { contentDescription = description }
            .clickable(onClickLabel = description, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { icon() }
}

private val SidebarInset = 8.dp
private val SidebarShape = RoundedCornerShape(26.dp)

/** iPad's dark sidebar glass carries its own frost, so it reads as glass even over black. */
private val SidebarFrost = Color.White.copy(alpha = 0.08f)

/** The sidebar frosts what's behind it far more than menus do, as iPad's does. */
private val SidebarFrostBlur = 34.dp

/**
 * iPad's sidebar: a liquid glass panel floating inside the screen's edges, with the dock's tabs as
 * rows and the account at the bottom. Drawn above the page it's live glass; under a sheet it
 * falls back to the frosted fill.
 */
@Composable
fun ZelefinTabletSidebar(
    entries: List<DockEntry>,
    currentTab: AppTab,
    currentRoomId: String?,
    session: SavedSession?,
    onSelectEntry: (DockEntry) -> Unit,
    onClose: () -> Unit,
    onProfile: () -> Unit,
    onSessions: () -> Unit,
    onSettings: () -> Unit,
    onSignOut: () -> Unit,
    onReorder: (List<DockTab>) -> Unit,
    onSetShown: (DockTab, Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val top = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    // The panel starts under the status bar where the page headers' buttons do, so its header
    // row lines up with theirs; the account lines up with Now Playing.
    val innerBottom = (dockBottomInset() - SidebarInset).coerceAtLeast(SidebarInset)
    Column(
        modifier
            .width(TabletSidebarWidth)
            .fillMaxHeight()
            .padding(start = SidebarInset, top = top + TabletTopBarTop, bottom = SidebarInset, end = SidebarInset)
            .shadow(6.dp, SidebarShape, clip = false, ambientColor = Color.Black.copy(alpha = 0.18f), spotColor = Color.Black.copy(alpha = 0.24f))
            .clip(SidebarShape)
            .zelefinLiquidGlassBackground(
                SidebarShape,
                fallback = MaterialTheme.colorScheme.surfaceContainerHigh,
                style = GlassPreferences.style.let { it.copy(blur = maxOf(it.blur, SidebarFrostBlur), tintAlpha = maxOf(it.tintAlpha, 0.55f)) },
            )
            .background(SidebarFrost)
            .border(0.75.dp, GlassRim, SidebarShape)
            .padding(top = TabletTopBarInset, bottom = innerBottom),
    ) {
        var editing by rememberSaveable { mutableStateOf(false) }
        Row(Modifier.fillMaxWidth().padding(start = 12.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                if (editing) "Done" else "Edit",
                color = Color.White,
                fontFamily = ZelefinFont,
                fontWeight = if (editing) FontWeight.SemiBold else FontWeight.Normal,
                fontSize = 16.sp,
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .clickable(role = Role.Button) { editing = !editing }
                    .padding(horizontal = 8.dp, vertical = 6.dp),
            )
            Spacer(Modifier.weight(1f))
            TopBarIconButton(description = "Hide sidebar", selected = false, onClick = onClose) {
                Icon(Icons.Outlined.ViewSidebar, contentDescription = null, tint = Color.White, modifier = Modifier.size(21.dp))
            }
        }
        Spacer(Modifier.height(12.dp))
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 8.dp),
            verticalArrangement = Arrangement.spacedBy(SidebarRowGap),
        ) {
            if (editing) {
                SidebarEditList(onReorder = onReorder, onSetShown = onSetShown)
            } else {
                entries.forEach { entry ->
                    SidebarRow(entry, entry.isCurrent(currentTab, currentRoomId)) { onSelectEntry(entry) }
                }
            }
        }
        // iPad's sidebar account: a 36pt photo 20pt in from the edge, then the name.
        Row(
            Modifier.fillMaxWidth().padding(start = 20.dp, end = 16.dp, top = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            AccountAvatarMenu(
                session,
                onProfile = onProfile,
                onSessions = onSessions,
                onSettings = onSettings,
                onSignOut = onSignOut,
                floating = false,
                diameter = 36.dp,
            )
            Text(
                session?.userName.orEmpty(),
                color = Color.White,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.SemiBold,
                fontSize = 15.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

private val SidebarRowHeight = 44.dp
private val SidebarRowGap = 2.dp

/**
 * iPad's sidebar Edit: every tab Android has, hidden ones included, shown or hidden with the
 * circle and reordered by the handle. Home can't be hidden. Neighbours slide aside while
 * dragging; the order is saved on release.
 */
@Composable
private fun SidebarEditList(onReorder: (List<DockTab>) -> Unit, onSetShown: (DockTab, Boolean) -> Unit) {
    val tabs = TabPreferences.order.filter { it.availableOnAndroid }
    val pitch = with(LocalDensity.current) { (SidebarRowHeight + SidebarRowGap).toPx() }
    var dragging by remember(tabs) { mutableIntStateOf(-1) }
    var dragY by remember(tabs) { mutableFloatStateOf(0f) }
    val latestTabs by rememberUpdatedState(tabs)
    val latestReorder by rememberUpdatedState(onReorder)
    fun targetOf(from: Int): Int = (from + (dragY / pitch).roundToInt()).coerceIn(0, latestTabs.lastIndex)
    val target = if (dragging < 0) -1 else targetOf(dragging)
    tabs.forEachIndexed { index, tab ->
        key(tab.raw) {
            val shift = when {
                dragging < 0 || index == dragging -> 0f
                index in (dragging + 1)..target -> -pitch
                index in target until dragging -> pitch
                else -> 0f
            }
            val animatedShift by animateFloatAsState(shift, label = "sidebarReorder")
            val lifted = index == dragging
            val handle = Modifier.pointerInput(index) {
                detectDragGestures(
                    onDragStart = {
                        dragging = index
                        dragY = 0f
                    },
                    onDragEnd = {
                        val from = dragging
                        val to = if (from < 0) from else targetOf(from)
                        if (from >= 0 && to != from) {
                            latestReorder(latestTabs.toMutableList().apply { add(to, removeAt(from)) })
                        }
                        dragging = -1
                        dragY = 0f
                    },
                    onDragCancel = {
                        dragging = -1
                        dragY = 0f
                    },
                    onDrag = { change, amount ->
                        change.consume()
                        dragY += amount.y
                    },
                )
            }
            SidebarEditRow(
                tab = tab,
                shown = TabPreferences.isShown(tab),
                onShown = { onSetShown(tab, it) },
                handle = handle,
                modifier = Modifier
                    .zIndex(if (lifted) 1f else 0f)
                    .graphicsLayer {
                        translationY = if (lifted) dragY else animatedShift
                        val scale = if (lifted) 1.03f else 1f
                        scaleX = scale
                        scaleY = scale
                    },
            )
        }
    }
}

@Composable
private fun SidebarEditRow(tab: DockTab, shown: Boolean, onShown: (Boolean) -> Unit, handle: Modifier, modifier: Modifier) {
    val appTab = tab.appTab ?: return
    val tint = if (shown) Color.White else ZelefinMuted
    Row(
        modifier
            .fillMaxWidth()
            .height(SidebarRowHeight)
            .clip(RoundedCornerShape(10.dp))
            .background(Color.White.copy(alpha = 0.06f))
            .padding(start = 10.dp, end = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(28.dp), contentAlignment = Alignment.Center) {
            if (tab.canHide) {
                Icon(
                    if (shown) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                    contentDescription = null,
                    tint = if (shown) ZelefinCyan else ZelefinMuted,
                    modifier = Modifier
                        .size(22.dp)
                        .clip(CircleShape)
                        .toggleable(value = shown, role = Role.Checkbox, onValueChange = onShown)
                        .semantics { contentDescription = if (shown) "Hide ${tab.title}" else "Show ${tab.title}" },
                )
            }
        }
        DockTabIcon(appTab, selected = false, description = null, tint = tint, modifier = Modifier.size(22.dp))
        Text(tab.title, color = tint, fontFamily = ZelefinFont, fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        Box(handle.size(36.dp), contentAlignment = Alignment.Center) {
            Icon(Icons.Rounded.DragHandle, contentDescription = "Reorder ${tab.title}", tint = ZelefinMuted, modifier = Modifier.size(22.dp))
        }
    }
}

@Composable
private fun SidebarRow(entry: DockEntry, selected: Boolean, onClick: () -> Unit) {
    val tint = if (selected) ZelefinCyan else Color.White
    Row(
        Modifier
            .fillMaxWidth()
            .height(SidebarRowHeight)
            .clip(RoundedCornerShape(10.dp))
            .background(if (selected) Color.White.copy(alpha = 0.1f) else Color.Transparent)
            .semantics(mergeDescendants = true) {
                role = Role.Tab
                this.selected = selected
            }
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        DockTabIcon(entry.tab, selected = selected, description = null, tint = tint, modifier = Modifier.size(22.dp), room = entry.room)
        Text(entry.title, color = tint, fontFamily = ZelefinFont, fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** Now Playing on a tablet: the dock's mini player, floating on its own at the bottom. */
@Composable
fun ZelefinTabletMiniPlayer(
    nowPlaying: MediaItem,
    session: SavedSession?,
    onOpen: () -> Unit,
    onStop: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier
            .padding(bottom = dockBottomInset())
            .widthIn(max = TabletMiniPlayerWidth)
            .fillMaxWidth()
            .padding(horizontal = 20.dp)
            .height(DockMiniPlayerHeight),
    ) {
        LiquidGlassPane(DockMiniPlayerHeight / 2, Modifier.matchParentSize())
        DockMiniPlayer(
            item = nowPlaying,
            session = session,
            collapse = 0f,
            onOpen = onOpen,
            onStop = onStop,
            modifier = Modifier.matchParentSize().clip(RoundedCornerShape(DockMiniPlayerHeight / 2)),
        )
    }
}
