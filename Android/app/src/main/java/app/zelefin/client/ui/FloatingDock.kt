package app.zelefin.client.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.layout.layoutId
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.IntOffset
import kotlin.math.roundToInt
import androidx.compose.ui.unit.dp
import app.zelefin.client.AppTab
import app.zelefin.client.R
import dev.chrisbanes.haze.ExperimentalHazeApi
import dev.chrisbanes.haze.HazeInputScale
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeStyle
import dev.chrisbanes.haze.hazeEffect
import dev.chrisbanes.haze.hazeSource
import dev.chrisbanes.haze.materials.ExperimentalHazeMaterialsApi
import dev.chrisbanes.haze.materials.HazeMaterials

/** Full tab pill + detached search button. Stays expanded while the page scrolls. */
val DockTabBarHeight = 54.dp

/** Matches iOS `TabBarIconMetrics.side`. */
private val DockIconSize = 28.dp

/** Space scrolling content keeps clear of the dock. Bottom inset matches the 16 dp side inset. */
val DockContentReserve = 86.dp

private val DockGap = 8.dp
private val DockShape = RoundedCornerShape(percent = 50)
internal val DockFill = Color(0x6628282A)
internal val DockBorder = Color.White.copy(alpha = 0.16f)
internal val DockSelectedFill = Color.White.copy(alpha = 0.14f)
internal val DockInactive = Color.White.copy(alpha = 0.92f)

private val DockTabs = listOf(AppTab.Home, AppTab.Movies, AppTab.Shows, AppTab.Library)

private enum class DockSlot { Tab, Search }

class ZelefinHazeState internal constructor(internal val state: HazeState) {
    var scrollLocks by mutableIntStateOf(0)
        private set

    fun acquireScroll() {
        scrollLocks += 1
    }

    fun releaseScroll() {
        scrollLocks = (scrollLocks - 1).coerceAtLeast(0)
    }
}

/** Turns the live frost off while a list is moving, then restores it when the list rests. */
@Composable
fun TrackHazeScroll(scrolling: Boolean) {
    val haze = LocalZelefinHaze.current ?: return
    DisposableEffect(haze, scrolling) {
        if (scrolling) haze.acquireScroll()
        onDispose { if (scrolling) haze.releaseScroll() }
    }
}

/** Draws floating glass above the page so it can frost the same way the dock does. */
class ZelefinGlassHost {
    var content by mutableStateOf<(@Composable () -> Unit)?>(null)
    var foreground by mutableStateOf<(@Composable () -> Unit)?>(null)
    var discs by mutableStateOf(emptyList<GlassDisc>())
}

class GlassDisc(
    val key: Any,
    val description: String,
    val icon: ImageVector,
    onClick: () -> Unit,
    val secondaryIcon: ImageVector? = null,
    val secondaryDescription: String = "",
    onSecondaryClick: () -> Unit = {},
    val shape: Shape = CircleShape,
) {
    var bounds by mutableStateOf(Rect.Zero)
    var onClick: () -> Unit = onClick
    var onSecondaryClick: () -> Unit = onSecondaryClick
    var badge by mutableIntStateOf(0)
}

val LocalZelefinHaze = staticCompositionLocalOf<ZelefinHazeState?> { null }
val LocalZelefinGlassHost = staticCompositionLocalOf<ZelefinGlassHost?> { null }

/** Corner radius shared with the dock pill. Overlay menus use this shape. */
val ZelefinOverlayShape = RoundedCornerShape(28.dp)

/**
 * Shows one overlay in the same window as the dock, so [zelefinGlassChrome] frosts the page.
 * Only one overlay can be up at a time.
 */
@Composable
fun PresentZelefinOverlay(visible: Boolean, content: @Composable () -> Unit) {
    val host = LocalZelefinGlassHost.current
    val current = rememberUpdatedState(content)
    DisposableEffect(host) {
        onDispose { host?.content = null }
    }
    LaunchedEffect(visible, host) {
        host?.content = if (visible) {
            { current.value.invoke() }
        } else {
            null
        }
    }
}

@Composable
fun rememberZelefinHazeState(): ZelefinHazeState = remember { ZelefinHazeState(HazeState()) }

/**
 * Keeps a circular control in the layout, and draws its frosted face above the page
 * so it blurs the same way the dock does.
 */
@Composable
fun Modifier.zelefinGlassDisc(
    key: Any,
    description: String,
    icon: ImageVector,
    onClick: () -> Unit,
): Modifier {
    val host = LocalZelefinGlassHost.current ?: return this.clickable(onClick = onClick)
    val click = rememberUpdatedState(onClick)
    DisposableEffect(host, key, description, icon) {
        val disc = GlassDisc(key, description, icon, onClick = { click.value() })
        host.discs = host.discs.filter { it.key != key } + disc
        onDispose { host.discs = host.discs.filter { it.key != key } }
    }
    SideEffect {
        host.discs.firstOrNull { it.key == key }?.onClick = { click.value() }
    }
    return this.onGloballyPositioned { coords ->
        val disc = host.discs.firstOrNull { it.key == key } ?: return@onGloballyPositioned
        val next = coords.boundsInRoot()
        if (disc.bounds != next) disc.bounds = next
    }
}

/**
 * A two-part frosted capsule, drawn above the page the same way a glass disc is.
 */
@Composable
fun Modifier.zelefinGlassSplit(
    key: Any,
    leadingDescription: String,
    leadingIcon: ImageVector,
    trailingDescription: String,
    trailingIcon: ImageVector,
    onLeading: () -> Unit,
    onTrailing: () -> Unit,
    badge: Int = 0,
): Modifier {
    val host = LocalZelefinGlassHost.current ?: return this
    val leading = rememberUpdatedState(onLeading)
    val trailing = rememberUpdatedState(onTrailing)
    DisposableEffect(host, key, leadingIcon, trailingIcon) {
        val disc = GlassDisc(
            key = key,
            description = leadingDescription,
            icon = leadingIcon,
            onClick = { leading.value() },
            secondaryIcon = trailingIcon,
            secondaryDescription = trailingDescription,
            onSecondaryClick = { trailing.value() },
            shape = RoundedCornerShape(percent = 50),
        )
        host.discs = host.discs.filter { it.key != key } + disc
        onDispose { host.discs = host.discs.filter { it.key != key } }
    }
    SideEffect {
        host.discs.firstOrNull { it.key == key }?.let { disc ->
            disc.onClick = { leading.value() }
            disc.onSecondaryClick = { trailing.value() }
            disc.badge = badge
        }
    }
    return this.onGloballyPositioned { coords ->
        val disc = host.discs.firstOrNull { it.key == key } ?: return@onGloballyPositioned
        val next = coords.boundsInRoot()
        if (disc.bounds != next) disc.bounds = next
    }
}

@Composable
fun ZelefinForeground(host: ZelefinGlassHost) {
    Box(Modifier.fillMaxSize()) {
        host.foreground?.invoke()
    }
}

@Composable
fun ZelefinGlassDiscs(hazeState: ZelefinHazeState, host: ZelefinGlassHost) {
    val discs = host.discs
    val blur = hazeState.scrollLocks == 0
    val density = LocalDensity.current
    if (discs.isEmpty()) return
    Box(Modifier.fillMaxSize()) {
        discs.forEach { disc ->
            val bounds = disc.bounds
            if (bounds.width <= 1f || bounds.height <= 1f) return@forEach
            val width = with(density) { bounds.width.toDp() }
            val height = with(density) { bounds.height.toDp() }
            val split = disc.secondaryIcon
            Box(
                Modifier
                    .offset { IntOffset(bounds.left.roundToInt(), bounds.top.roundToInt()) }
                    .size(width, height)
                    .zelefinGlassChrome(hazeState, disc.shape, blur)
                    .then(if (split == null) Modifier.clickable { disc.onClick() } else Modifier),
                contentAlignment = Alignment.Center,
            ) {
                if (split == null) {
                    Icon(disc.icon, contentDescription = disc.description, tint = Color.White)
                } else {
                    Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            Modifier
                                .weight(1f)
                                .fillMaxHeight()
                                .clickable { disc.onClick() },
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(disc.icon, contentDescription = disc.description, tint = Color.White, modifier = Modifier.size(22.dp))
                        }
                        Box(
                            Modifier
                                .size(width = 1.dp, height = 20.dp)
                                .background(Color.White.copy(alpha = 0.28f)),
                        )
                        Box(
                            Modifier
                                .weight(1f)
                                .fillMaxHeight()
                                .clickable { disc.onSecondaryClick() },
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(split, contentDescription = disc.secondaryDescription, tint = Color.White, modifier = Modifier.size(22.dp))
                            if (disc.badge > 0) {
                                Text(
                                    disc.badge.toString(),
                                    color = Color.Black,
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Bold,
                                    modifier = Modifier
                                        .align(Alignment.TopEnd)
                                        .padding(top = 4.dp, end = 2.dp)
                                        .clip(CircleShape)
                                        .background(Color.White)
                                        .padding(horizontal = 5.dp, vertical = 1.dp),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun Modifier.zelefinHazeSource(state: ZelefinHazeState): Modifier = hazeSource(state = state.state)

@Composable
fun ZelefinFloatingDock(
    currentTab: AppTab,
    hazeState: ZelefinHazeState,
    onSelect: (AppTab) -> Unit,
    modifier: Modifier = Modifier,
) {
    val blur = hazeState.scrollLocks == 0
    val chrome = Modifier.zelefinGlassChrome(hazeState, DockShape, blur)
    Layout(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .padding(bottom = 16.dp),
        content = {
            Box(
                modifier = Modifier
                    .layoutId(DockSlot.Tab)
                    .then(chrome),
                contentAlignment = Alignment.Center,
            ) {
                DockTabBar(currentTab = currentTab, onSelect = onSelect, modifier = Modifier.fillMaxSize())
            }
            DockSearchButton(
                selected = currentTab == AppTab.Search,
                onClick = { onSelect(AppTab.Search) },
                modifier = Modifier
                    .layoutId(DockSlot.Search)
                    .then(chrome),
            )
        },
    ) { measurables, constraints ->
        val gap = DockGap.roundToPx()
        val total = constraints.maxWidth
        val rowHeight = DockTabBarHeight.roundToPx()
        val side = rowHeight
        val tabWidth = (total - side - gap).coerceAtLeast(0)
        val placed = measurables.map { measurable ->
            val width = if (measurable.layoutId == DockSlot.Tab) tabWidth else side
            measurable.layoutId to measurable.measure(Constraints.fixed(width, rowHeight))
        }
        layout(total, rowHeight) {
            placed.forEach { (slot, placeable) ->
                if (slot == DockSlot.Search) {
                    placeable.place(total - side, 0)
                } else {
                    placeable.place(0, 0)
                }
            }
        }
    }
}

@Composable
private fun DockTabBar(
    currentTab: AppTab,
    onSelect: (AppTab) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.padding(horizontal = 4.dp, vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        DockTabs.forEach { tab ->
            val selected = currentTab == tab
            val tint = if (selected) ZelefinCyan else DockInactive
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .clip(DockShape)
                    .background(if (selected) DockSelectedFill else Color.Transparent)
                    .clickable { onSelect(tab) },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    painter = painterResource(dockIcon(tab, selected)),
                    contentDescription = tab.name,
                    tint = tint,
                    modifier = Modifier.size(DockIconSize),
                )
            }
        }
    }
}

@Composable
private fun DockSearchButton(
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(modifier = modifier.clickable(onClick = onClick), contentAlignment = Alignment.Center) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(4.dp)
                .clip(CircleShape)
                .background(if (selected) DockSelectedFill else Color.Transparent),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                painter = painterResource(dockIcon(AppTab.Search, selected)),
                contentDescription = "Search",
                tint = if (selected) ZelefinCyan else DockInactive,
                modifier = Modifier.size(DockIconSize),
            )
        }
    }
}

@OptIn(ExperimentalHazeMaterialsApi::class, ExperimentalHazeApi::class)
@Composable
fun Modifier.zelefinGlassChrome(hazeState: ZelefinHazeState, shape: Shape, blur: Boolean = true): Modifier {
    val style = dockHazeStyle()
    return this
        .shadow(
            elevation = 6.dp,
            shape = shape,
            clip = false,
            ambientColor = Color.Black.copy(alpha = 0.06f),
            spotColor = Color.Black.copy(alpha = 0.10f),
        )
        .clip(shape)
        .hazeEffect(state = hazeState.state, style = style) {
            inputScale = HazeInputScale.Fixed(0.33f)
            blurEnabled = blur
        }
        .border(width = 0.5.dp, color = DockBorder, shape = shape)
}

@OptIn(ExperimentalHazeMaterialsApi::class)
@Composable
private fun dockHazeStyle(): HazeStyle = HazeMaterials.thin(containerColor = DockFill)

private fun dockIcon(tab: AppTab, selected: Boolean): Int = when (tab) {
    AppTab.Home -> if (selected) R.drawable.iconsax_home_filled else R.drawable.iconsax_home
    AppTab.Movies -> if (selected) R.drawable.iconsax_movies_filled else R.drawable.iconsax_movies
    AppTab.Shows -> if (selected) R.drawable.iconsax_shows_filled else R.drawable.iconsax_shows
    AppTab.Library -> if (selected) R.drawable.iconsax_library_filled else R.drawable.iconsax_library
    AppTab.Search -> if (selected) R.drawable.iconsax_search_filled else R.drawable.iconsax_search
}
