package app.zelefin.client.ui

import androidx.annotation.DrawableRes
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.CollectionsBookmark
import androidx.compose.material.icons.outlined.Colorize
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Movie
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material.icons.outlined.SkipNext
import androidx.compose.material.icons.outlined.TheaterComedy
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material.icons.outlined.Tv
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material.icons.rounded.DragHandle
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.zIndex
import androidx.lifecycle.viewmodel.compose.viewModel
import app.zelefin.client.CatalogBrowseQuery
import app.zelefin.client.CatalogSortField
import app.zelefin.client.CatalogStatusFilter
import app.zelefin.client.CustomHomeRow
import app.zelefin.client.CustomHomeRowScope
import app.zelefin.client.CustomHomeRows
import app.zelefin.client.HomeRowSlot
import app.zelefin.client.ZelefinModel
import app.zelefin.client.ZelefinUiState
import app.zelefin.client.LibraryRoom
import kotlin.math.roundToInt

const val CustomHomeTopicPrefix = "custom-home:"

private val InterfaceCaption = IOSColors.tertiaryLabel

/** Accent color. Interface leads with [AccentSection]; this remains for a caller that only wants the swatches. */
@Composable
fun AppearanceSettings() {
    AccentSection()
}

/** Mirrors iOS `TabCustomizationView`: accent, merge, hero, Home rows, tabs, libraries, reset. */
@Composable
fun InterfaceSettings(state: ZelefinUiState, editing: Boolean = false) {
    val model: ZelefinModel = viewModel()
    val context = LocalContext.current
    val noLiveTv = state.isSiloServer
    LaunchedEffect(Unit) { model.pullDisplayPreferences() }

    AccentSection()

    val merged = HomeLayoutPreferences.mergeContinueAndNextUp
    SettingsCard {
        SettingsToggleRow("Combine Continue Watching and Next Up", merged, onChange = { on ->
            HomeLayoutPreferences.setMergeContinueAndNextUp(context, on)
            model.pushDisplayPreferences()
            model.refreshLibrary()
        })
    }
    SettingsFooter(
        if (merged) {
            "In-progress titles and the next episode after you finish one appear in a single Continue Watching row. Each title is still labeled CONTINUE or NEXT."
        } else {
            "Keep in-progress titles in Continue Watching and the next episode after you finish one in Next Up."
        },
    )

    SettingsHeader("Featured Hero")
    SettingsCard {
        SettingsMenuPicker(
            label = "Content",
            choices = FeaturedHeroContent.entries.map { SettingsChoice(it, it.title) },
            selected = HomeLayoutPreferences.heroContent,
            onSelect = { content ->
                if (content == HomeLayoutPreferences.heroContent) return@SettingsMenuPicker
                HomeLayoutPreferences.setHeroContent(context, content)
                model.pushDisplayPreferences()
                model.refreshLibrary()
            },
        )
        SettingsMenuPicker(
            label = "Size",
            choices = HeroSizePreference.entries.map { SettingsChoice(it, it.title) },
            selected = HeroSizePreferences.size,
            onSelect = { size ->
                if (size == HeroSizePreferences.size) return@SettingsMenuPicker
                HeroSizePreferences.setSize(context, size)
            },
        )
    }
    SettingsFooter("What the Home hero cycles through, and how tall the Featured and title-page backdrops run. Compact shows more of a landscape image; Tall is the previous full-bleed height. Recently Added is the default content.")

    SettingsHeader("Poster Badges")
    SettingsCard {
        SettingsToggleRow("Community Rating", PosterBadgePreferences.showsRating, onChange = { on ->
            PosterBadgePreferences.setShowsRating(context, on)
        })
        SettingsToggleRow("Quality Badges", PosterBadgePreferences.showsQuality, onChange = { on ->
            PosterBadgePreferences.setShowsQuality(context, on)
        })
        SettingsToggleRow("Watched Mark", PosterBadgePreferences.showsWatched, onChange = { on ->
            PosterBadgePreferences.setShowsWatched(context, on)
        })
    }
    SettingsFooter("Rating stars, 4K/HDR/Atmos marks, and the watched check on posters. Turn any of them off to quiet the covers.")

    SettingsHeader("Home")
    ReorderableCards(
        items = HomeLayoutPreferences.slots,
        key = { it.raw },
        enabled = editing,
        onCommit = { next ->
            HomeLayoutPreferences.setSlots(context, next)
            model.pushDisplayPreferences()
        },
    ) { slot, handle ->
        when (slot) {
            is HomeRowSlot.BuiltIn -> {
                val row = slot.kind
                ReorderRow(
                    icon = { Icon(homeRowIcon(row), contentDescription = null, tint = ZelefinCyan, modifier = Modifier.size(22.dp)) },
                    title = row.title,
                    checked = if (editing) null else row !in HomeLayoutPreferences.hidden,
                    onCheckedChange = { on ->
                        HomeLayoutPreferences.setVisible(context, row, on)
                        model.pushDisplayPreferences()
                    },
                    handle = if (editing) handle else null,
                )
            }
            is HomeRowSlot.Custom -> {
                val row = CustomHomeRows.row(slot.id) ?: return@ReorderableCards
                ReorderRow(
                    icon = {
                        Icon(Icons.Outlined.Tune, contentDescription = null, tint = ZelefinCyan, modifier = Modifier.size(22.dp))
                    },
                    title = row.title,
                    subtitle = CustomHomeRows.filterSummary(row),
                    checked = if (editing) null else row.enabled,
                    onCheckedChange = { on ->
                        CustomHomeRows.update(context, row.copy(enabled = on))
                        model.pushDisplayPreferences()
                        model.refreshLibrary()
                    },
                    handle = if (editing) handle else null,
                    onTitleClick = if (editing) {
                        null
                    } else {
                        { model.openSettingsTopic("$CustomHomeTopicPrefix${row.id}") }
                    },
                    onDelete = {
                        HomeLayoutPreferences.removeCustomSlot(context, row.id)
                        CustomHomeRows.remove(context, row.id)
                        model.pushDisplayPreferences()
                        model.refreshLibrary()
                    },
                )
            }
        }
    }
    if (!editing) {
        Spacer(Modifier.height(8.dp))
        SettingsCard {
            SettingsActionRow("Add Custom Row") {
                val row = CustomHomeRows.add(context)
                HomeLayoutPreferences.insertCustomSlot(context, row.id)
                model.pushDisplayPreferences()
                model.refreshLibrary()
                model.openSettingsTopic("$CustomHomeTopicPrefix${row.id}")
            }
        }
    }
    SettingsFooter(
        buildString {
            append("Custom rows use catalog filters and can sit between built-in rows. ")
            append("Turn off a row to hide it from Home. Tap Edit to drag rows into a new order.")
            if (merged) append(" Next Up only appears when Combine Continue Watching and Next Up is off.")
        },
    )

    val pinnable = TabPreferences.pinnable(state.libraries)
    val canEnableAnother = PhoneDockLimit.canEnableAnother(
        TabPreferences.enabledTabCount(noLiveTv),
        TabPreferences.enabledLibraryCount(state.libraries),
    )

    SettingsHeader("Start Page")
    SettingsCard {
        SettingsMenuPicker(
            label = "Page",
            choices = StartPagePreferences.choices.map { SettingsChoice(it, it.title) },
            selected = StartPagePreferences.tab,
            onSelect = { page -> StartPagePreferences.setTab(context, page) },
        )
    }
    SettingsFooter("The page Zelefin opens to when you launch it. Home is the default.")

    SettingsHeader("Tabs")
    SettingsCard {
        SettingsToggleRow("Show Tab Names", TabPreferences.showsNames, onChange = { on ->
            TabPreferences.setShowsNames(context, on)
        })
    }
    Spacer(Modifier.height(8.dp))
    val visibleTabs = TabPreferences.order.filter { it.availableOnAndroid }
    ReorderableCards(
        items = visibleTabs,
        key = { it.raw },
        enabled = editing,
        onCommit = { next ->
            TabPreferences.setShownOrder(context, next)
            model.pushDisplayPreferences()
        },
    ) { tab, handle ->
        val appTab = tab.appTab ?: return@ReorderableCards
        ReorderRow(
            icon = { DockTabIcon(appTab, selected = false, description = null, tint = ZelefinCyan, modifier = Modifier.size(22.dp)) },
            title = tab.title,
            checked = if (editing || !tab.canHide) null else TabPreferences.isShown(tab),
            onCheckedChange = { on ->
                if (!on || canEnableAnother) {
                    TabPreferences.setShown(context, tab, on)
                    model.pushDisplayPreferences()
                }
            },
            handle = if (editing) handle else null,
        )
    }
    val tablet = LocalConfiguration.current.isLargeScreen()
    val tabNames = if (tablet) {
        ""
    } else if (TabPreferences.showsNames) {
        "Each dock icon shows its name. The phone dock holds 5 tabs, including Search. "
    } else {
        "The dock shows icons only. Turn Show Tab Names on to put a name under each icon. The phone dock holds 5 tabs, including Search. "
    }
    val sidebarEdit = if (tablet) " On tablets, you can also use Edit at the top of the sidebar." else ""
    SettingsFooter(tabNames + "Turn off a tab to hide it from the tab bar. Tap Edit to drag rows into a new order." + sidebarEdit)

    if (pinnable.isNotEmpty()) {
        SettingsHeader("Libraries")
        SettingsCard {
            pinnable.forEachIndexed { index, room ->
                if (index > 0) SettingsCardDivider()
                ReorderRow(
                    icon = { DockTabIcon(app.zelefin.client.AppTab.Room, selected = false, description = null, tint = ZelefinCyan, modifier = Modifier.size(22.dp), room = room) },
                    title = room.name,
                    checked = room.id in TabPreferences.dockLibraryIds,
                    onCheckedChange = { on ->
                        if (!on || canEnableAnother) TabPreferences.setLibraryPinned(context, room.id, on)
                    },
                    handle = null,
                )
            }
        }
        SettingsFooter(
            if (tablet) {
                "Turn on a custom library, such as Anime, to put it in the dock."
            } else {
                "Turn on a custom library, such as Anime, to put it in the dock. It uses one of the 5 phone spots."
            },
        )
    }

    val animeRooms = pinnable.filter(LibraryIcons::canChoose)
    if (animeRooms.isNotEmpty()) {
        SettingsHeader("Anime Icons")
        SettingsCard {
            animeRooms.forEachIndexed { index, room ->
                if (index > 0) SettingsCardDivider()
                LibraryIconRow(room) { model.openSettingsTopic("$LibraryIconTopicPrefix${room.id}") }
            }
        }
        SettingsFooter("Pick the icon a library with Anime in its name shows when it's in the dock.")
    }

    Spacer(Modifier.height(22.dp))
    SettingsCard {
        SettingsSecondaryButton("Reset Home Rows") {
            HomeLayoutPreferences.reset(context)
            model.pushDisplayPreferences()
            model.refreshLibrary()
        }
        SettingsCardDivider()
        SettingsSecondaryButton("Reset Tabs") {
            TabPreferences.reset(context)
            model.pushDisplayPreferences()
        }
    }
}

internal const val LibraryIconTopicPrefix = "library-icon:"

@Composable
private fun LibraryIconRow(room: LibraryRoom, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = SettingsRowHeight).clickable(onClick = onClick).padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(painterResource(LibraryIcons.icon(room, selected = false)), contentDescription = null, tint = ZelefinCyan, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(14.dp))
        Text(room.name, style = SettingsRowText, maxLines = 1, modifier = Modifier.weight(1f))
        Text(
            if (LibraryIcons.chosen(room) == null) "Default" else "Custom",
            color = InterfaceCaption,
            fontFamily = ZelefinFont,
            fontSize = 17.sp,
        )
        Spacer(Modifier.width(6.dp))
        Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = InterfaceCaption)
    }
}

/** Mirrors iOS `LibraryIconPickerView`: Default, then the anime characters. */
@Composable
internal fun LibraryIconPicker(roomId: String, state: ZelefinUiState) {
    val context = LocalContext.current
    val room = state.libraries.firstOrNull { it.id == roomId } ?: return
    val chosen = LibraryIcons.chosen(room)
    val tiles = listOf(null) + LibraryIcons.animeChoices
    SettingsCard {
        BoxWithConstraints(Modifier.fillMaxWidth().padding(vertical = 12.dp)) {
            val columns = (maxWidth / 80.dp).toInt().coerceAtLeast(3)
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                tiles.chunked(columns).forEach { row ->
                    Row(Modifier.fillMaxWidth()) {
                        row.forEach { choice ->
                            LibraryIconTile(
                                res = choice?.res ?: LibraryIcons.defaultIcon(room, selected = false),
                                title = choice?.title ?: "Default",
                                selected = choice?.key == chosen?.key,
                                modifier = Modifier.weight(1f),
                            ) { LibraryIcons.setChoice(context, room.id, choice?.key) }
                        }
                        repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }
        }
    }
    SettingsFooter("Icons by PlainIcon (Anime characters), licensed under CC BY 4.0.")
}

@Composable
private fun LibraryIconTile(@DrawableRes res: Int, title: String, selected: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val shape = RoundedCornerShape(14.dp)
    Column(
        modifier.clickable(onClickLabel = title, onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier
                .size(60.dp)
                .background(Color.White.copy(alpha = if (selected) 0.14f else 0.06f), shape)
                .then(if (selected) Modifier.border(2.dp, ZelefinCyan, shape) else Modifier),
            contentAlignment = Alignment.Center,
        ) {
            Icon(painterResource(res), contentDescription = null, tint = if (selected) ZelefinCyan else Color.White, modifier = Modifier.size(40.dp))
        }
        Spacer(Modifier.height(6.dp))
        Text(
            title,
            color = if (selected) Color.White else InterfaceCaption,
            fontFamily = ZelefinFont,
            fontSize = 11.sp,
            textAlign = TextAlign.Center,
            maxLines = 2,
            modifier = Modifier.heightIn(min = 28.dp).padding(horizontal = 2.dp),
        )
    }
}

private fun homeRowIcon(row: HomeRowKind): ImageVector = when (row) {
    HomeRowKind.Featured -> Icons.Outlined.AutoAwesome
    HomeRowKind.ContinueWatching -> Icons.Outlined.PlayCircle
    HomeRowKind.NextUp -> Icons.Outlined.SkipNext
    HomeRowKind.Upcoming -> Icons.Outlined.CalendarMonth
    HomeRowKind.Recommendations -> Icons.Outlined.ThumbUp
    HomeRowKind.RecentlyAddedMovies -> Icons.Outlined.Movie
    HomeRowKind.RecentlyAddedShows -> Icons.Outlined.Tv
    HomeRowKind.Collections -> Icons.Outlined.CollectionsBookmark
    HomeRowKind.Genres -> Icons.Outlined.TheaterComedy
    HomeRowKind.RecentlyWatched -> Icons.Outlined.History
}

/** Icon, semibold title, optional toggle, optional drag handle. A null [checked] means the row can't be turned off. */
@Composable
private fun ReorderRow(
    icon: @Composable () -> Unit,
    title: String,
    checked: Boolean?,
    onCheckedChange: (Boolean) -> Unit,
    handle: Modifier?,
    subtitle: String? = null,
    onTitleClick: (() -> Unit)? = null,
    onDelete: (() -> Unit)? = null,
) {
    Row(Modifier.fillMaxWidth().heightIn(min = SettingsRowHeight).padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        icon()
        Spacer(Modifier.width(14.dp))
        Column(
            Modifier
                .weight(1f)
                .then(if (onTitleClick != null) Modifier.clickable(onClick = onTitleClick) else Modifier),
        ) {
            Text(title, style = SettingsRowText, maxLines = 1)
            if (subtitle != null) {
                Text(subtitle, color = InterfaceCaption, fontFamily = FontFamily.SansSerif, fontSize = 13.sp, maxLines = 1)
            }
        }
        if (onDelete != null) {
            Text(
                "Delete",
                color = Color(0xFFFF453A),
                fontFamily = FontFamily.SansSerif,
                fontSize = 15.sp,
                modifier = Modifier
                    .clickable(onClick = onDelete)
                    .padding(horizontal = 8.dp),
            )
        }
        if (checked != null) {
            Box(Modifier.toggleable(value = checked, role = Role.Switch, onValueChange = onCheckedChange)) {
                IOSSwitch(checked)
            }
        }
        if (handle != null) {
            Spacer(Modifier.width(10.dp))
            Box(handle.size(32.dp), contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.DragHandle, contentDescription = "Reorder $title", tint = InterfaceCaption, modifier = Modifier.size(22.dp))
            }
        }
    }
}

/** Editor for a custom Home filter row (Interface → custom-home:&lt;id&gt;). */
@Composable
fun CustomHomeRowEditorTopic(rowId: String, onDeleted: () -> Unit) {
    val model: ZelefinModel = viewModel()
    val context = LocalContext.current
    val existing = CustomHomeRows.row(rowId)
    if (existing == null) {
        Text("This custom row was removed.", color = InterfaceCaption, fontFamily = FontFamily.SansSerif)
        return
    }
    var draft by remember(rowId) { mutableStateOf(existing) }
    var query by remember(rowId) { mutableStateOf(existing.browseQuery) }

    fun persist(next: CustomHomeRow, nextQuery: CatalogBrowseQuery = query) {
        val saved = next.withQuery(nextQuery)
        draft = saved
        query = nextQuery
        CustomHomeRows.update(context, saved)
        model.pushDisplayPreferences()
        model.refreshLibrary()
    }

    SettingsHeader("Name")
    SettingsCard {
        SettingsTextField(
            label = "Title",
            value = draft.title,
            icon = Icons.Outlined.Tune,
            onChange = { persist(draft.copy(title = it.ifBlank { "Custom Row" })) },
            placeholder = "Custom Row",
        )
    }

    SettingsHeader("Library")
    SettingsCard {
        SettingsMenuPicker(
            label = "Scope",
            choices = CustomHomeRowScope.entries.map { SettingsChoice(it, it.title) },
            selected = draft.resolvedScope,
            onSelect = { scope -> persist(draft.copy(scope = scope.raw)) },
        )
    }
    SettingsFooter("Movies is the default. Shows and Movies & Shows browse those libraries with the same filters.")

    SettingsHeader("Sort")
    SettingsCard {
        SettingsMenuPicker(
            label = "Sort By",
            choices = CatalogSortField.entries.map { SettingsChoice(it, it.title) },
            selected = query.sort,
            onSelect = { field ->
                persist(
                    draft,
                    query.copy(
                        sort = field,
                        sortAscending = if (field.allowsDirection) query.sortAscending else true,
                    ),
                )
            },
        )
        if (query.sort.allowsDirection) {
            SettingsToggleRow("Ascending", query.sortAscending, onChange = { on ->
                persist(draft, query.copy(sortAscending = on))
            })
        }
    }

    SettingsHeader("Filters")
    SettingsCard {
        CatalogStatusFilter.entries.forEach { status ->
            SettingsToggleRow(status.title, status in query.statuses, onChange = { on ->
                val next = if (on) query.statuses + status else query.statuses - status
                persist(draft, query.copy(statuses = next))
            })
        }
    }
    SettingsFooter(
        buildString {
            append("Status filters apply on Home and when you open See All. ")
            if (query.activeFilterCount > 0) append("${query.activeFilterCount} filters active. ")
            append("Genre and other catalog filters can be refined from See All on Home.")
        },
    )

    Spacer(Modifier.height(16.dp))
    SettingsCard {
        SettingsActionRow("Delete Custom Row", destructive = true) {
            HomeLayoutPreferences.removeCustomSlot(context, rowId)
            CustomHomeRows.remove(context, rowId)
            model.pushDisplayPreferences()
            model.refreshLibrary()
            onDeleted()
        }
    }
}

/**
 * One grouped section, a row per item, reordered by dragging the handle Modifier handed to
 * [content]. Neighbours slide out of the way while dragging; the new order is committed on release.
 */
@Composable
private fun <T> ReorderableCards(
    items: List<T>,
    key: (T) -> Any,
    enabled: Boolean,
    onCommit: (List<T>) -> Unit,
    content: @Composable (T, Modifier) -> Unit,
) {
    val spacing = 0.dp
    val spacingPx = with(LocalDensity.current) { spacing.toPx() }
    val rowFill = MaterialTheme.colorScheme.surfaceContainerHigh
    var cardHeight by remember { mutableFloatStateOf(0f) }
    var dragging by remember(items) { mutableIntStateOf(-1) }
    var dragY by remember(items) { mutableFloatStateOf(0f) }
    val stride = cardHeight + spacingPx
    val target = if (dragging < 0 || stride <= 0f) -1 else (dragging + (dragY / stride).roundToInt()).coerceIn(0, items.lastIndex)
    val latestItems by rememberUpdatedState(items)
    val latestCommit by rememberUpdatedState(onCommit)

    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = SettingsGroupMargin)
            .clip(SettingsGroupShape)
            .background(rowFill),
    ) {
        items.forEachIndexed { index, item ->
            key(key(item)) {
                val shift = when {
                    dragging < 0 || index == dragging -> 0f
                    index in (dragging + 1)..target -> -stride
                    index in target until dragging -> stride
                    else -> 0f
                }
                val animatedShift by animateFloatAsState(shift, label = "reorderShift")
                val isDragging = index == dragging
                val handle = Modifier.pointerInput(index, enabled) {
                    if (!enabled) return@pointerInput
                    detectDragGestures(
                        onDragStart = {
                            dragging = index
                            dragY = 0f
                        },
                        onDragEnd = {
                            val from = dragging
                            val step = cardHeight + spacingPx
                            val to = if (from < 0 || step <= 0f) from else (from + (dragY / step).roundToInt()).coerceIn(0, latestItems.lastIndex)
                            if (from >= 0 && to != from) {
                                val next = latestItems.toMutableList()
                                next.add(to, next.removeAt(from))
                                latestCommit(next)
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
                Box(
                    Modifier
                        .zIndex(if (isDragging) 1f else 0f)
                        .graphicsLayer {
                            translationY = if (isDragging) dragY else animatedShift
                            val scale = if (isDragging) 1.02f else 1f
                            scaleX = scale
                            scaleY = scale
                        }
                        .onSizeChanged { if (index == 0) cardHeight = it.height.toFloat() }
                        .background(rowFill),
                ) {
                    Column(Modifier.padding(horizontal = SettingsContentInset)) {
                        content(item, handle)
                        if (index < items.lastIndex) SettingsCardDivider()
                    }
                }
            }
        }
    }
}

/** Identity strip + horizontal bead rail — mirrors iOS `AccentColorPickerGrid`. */
@Composable
internal fun AccentSection() {
    val context = LocalContext.current
    val focusManager = LocalFocusManager.current
    var pickerOpen by remember { mutableStateOf(false) }
    val selectedId = AccentPreferences.presetId
    val custom = selectedId == AccentPreferences.CUSTOM_ID
    val active = AccentPreferences.preset(selectedId, AccentPreferences.customHex)

    SettingsHeader("Accent Color")
    SettingsCard {
        Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(active.color.copy(alpha = 0.12f))
                    .border(1.dp, active.color.copy(alpha = 0.22f), RoundedCornerShape(16.dp))
                    .padding(horizontal = 14.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.size(54.dp), contentAlignment = Alignment.Center) {
                    Box(
                        Modifier
                            .size(54.dp)
                            .background(active.color.copy(alpha = 0.28f), CircleShape),
                    )
                    Box(
                        Modifier
                            .size(36.dp)
                            .shadow(10.dp, CircleShape, ambientColor = active.color.copy(alpha = 0.45f), spotColor = active.color.copy(alpha = 0.45f))
                            .background(active.color, CircleShape)
                            .border(1.dp, Color.White.copy(alpha = 0.22f), CircleShape),
                    )
                }
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        active.name,
                        fontFamily = ZelefinFont,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 17.sp,
                        color = Color.White,
                    )
                    Text(
                        active.hex.uppercase(),
                        fontFamily = ZelefinFont,
                        fontSize = 12.sp,
                        color = IOSColors.secondaryLabel,
                    )
                }
                if (custom) {
                    Icon(Icons.Outlined.Tune, contentDescription = null, tint = active.color, modifier = Modifier.size(22.dp))
                }
            }

            Row(
                Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                AccentPreferences.presets.forEach { preset ->
                    AccentBead(
                        name = preset.name,
                        color = preset.color,
                        selected = selectedId == preset.id,
                        eyedropper = false,
                    ) { AccentPreferences.select(context, preset.id) }
                }
                AccentBead(
                    name = "Custom",
                    color = AccentPreferences.customColor,
                    selected = custom,
                    eyedropper = true,
                ) { AccentPreferences.selectCustom(context) }
            }

            if (custom) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text("Mix your own", style = SettingsRowText, modifier = Modifier.weight(1f))
                    Box(
                        Modifier
                            .size(30.dp)
                            .clip(CircleShape)
                            .background(Brush.sweepGradient(HueStops))
                            .clickable { pickerOpen = true }
                            .padding(4.dp)
                            .clip(CircleShape)
                            .background(Color.Black)
                            .padding(2.dp)
                            .clip(CircleShape)
                            .background(AccentPreferences.customColor),
                    )
                }
                SettingsCardDivider()
                HexRow(onDone = { focusManager.clearFocus() })
            }
        }
    }
    SettingsFooter("Tints buttons, highlights, and icons throughout the app.")

    if (pickerOpen) {
        AccentColorPickerPanel(onDismiss = { pickerOpen = false })
    }
}

@Composable
private fun AccentBead(name: String, color: Color, selected: Boolean, eyedropper: Boolean, onClick: () -> Unit) {
    val bead = if (selected) 34.dp else 28.dp
    Box(
        Modifier
            .size(44.dp)
            .clip(CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        if (selected) {
            Box(
                Modifier
                    .size(42.dp)
                    .border(5.dp, color.copy(alpha = 0.35f), CircleShape)
                    .border(2.dp, Color.White.copy(alpha = 0.9f), CircleShape),
            )
        }
        Box(
            Modifier
                .size(bead)
                .then(
                    if (selected) {
                        Modifier.shadow(8.dp, CircleShape, ambientColor = color.copy(alpha = 0.55f), spotColor = color.copy(alpha = 0.55f))
                    } else {
                        Modifier
                    },
                )
                .background(color, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            if (eyedropper) {
                Icon(
                    Icons.Outlined.Colorize,
                    contentDescription = null,
                    tint = Color.White.copy(alpha = 0.95f),
                    modifier = Modifier.size(if (selected) 13.dp else 11.dp),
                )
            }
        }
    }
}

/** Hex entry: a leading #, digits only, saved while typing whenever the text is a valid hex. */
@Composable
private fun HexRow(onDone: () -> Unit) {
    val context = LocalContext.current
    val stored = AccentPreferences.customHex
    var text by remember { mutableStateOf(hexDigits(stored)) }
    LaunchedEffect(stored) {
        val digits = hexDigits(stored)
        if (!text.equals(digits, ignoreCase = true)) text = digits
    }
    val preview = AccentPreferences.colorFromHex(text) ?: AccentPreferences.customColor
    fun revertIfInvalid() {
        if (AccentPreferences.normalizedHex(text) == null) text = hexDigits(AccentPreferences.customHex)
    }
    Row(Modifier.fillMaxWidth().heightIn(min = SettingsRowHeight).padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(
            "#",
            style = SettingsRowText.copy(
                color = IOSColors.secondaryLabel,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.SemiBold,
            ),
        )
        Spacer(Modifier.width(8.dp))
        IOSTextField(
            value = text,
            onChange = { value ->
                val digits = value.filter { it != '#' }.uppercase().take(6)
                text = digits
                AccentPreferences.normalizedHex(digits)?.let { hex ->
                    if (hex != AccentPreferences.customHex) AccentPreferences.setCustomHex(context, hex)
                }
            },
            modifier = Modifier
                .weight(1f)
                .semantics { contentDescription = "Hex code" }
                .onFocusChanged { if (!it.isFocused) revertIfInvalid() },
            placeholder = "RRGGBB",
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.Characters,
                autoCorrectEnabled = false,
                keyboardType = KeyboardType.Ascii,
                imeAction = ImeAction.Done,
            ),
            keyboardActions = KeyboardActions(onDone = {
                revertIfInvalid()
                onDone()
            }),
        )
        Spacer(Modifier.width(12.dp))
        Box(
            Modifier
                .size(28.dp)
                .clip(RoundedCornerShape(7.dp))
                .background(preview)
                .border(0.5.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(7.dp)),
        )
    }
}

private fun hexDigits(hex: String): String {
    val value = hex.trim().uppercase()
    return if (value.startsWith("#")) value.drop(1) else value
}

private val HueStops = listOf(0f, 60f, 120f, 180f, 240f, 300f, 360f).map { Color.hsv(it, 1f, 1f) }

/** In-app color picker: saturation/brightness square and a hue slider, no opacity. Changes apply live. */
@Composable
private fun AccentColorPickerPanel(onDismiss: () -> Unit) {
    val context = LocalContext.current
    val start = remember {
        FloatArray(3).also { android.graphics.Color.colorToHSV(AccentPreferences.customColor.toArgb(), it) }
    }
    var hue by remember { mutableFloatStateOf(start[0]) }
    var saturation by remember { mutableFloatStateOf(start[1]) }
    var brightness by remember { mutableFloatStateOf(start[2]) }
    fun apply() {
        AccentPreferences.setCustomHex(context, AccentPreferences.hexFrom(Color.hsv(hue.coerceIn(0f, 360f), saturation, brightness)))
    }

    Dialog(onDismissRequest = onDismiss) {
        Box(Modifier.clip(RoundedCornerShape(34.dp)).background(IOSColors.alert)) {
        Column(
            Modifier
                .width(320.dp)
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier
                        .size(28.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(Color.hsv(hue.coerceIn(0f, 360f), saturation, brightness))
                        .border(0.5.dp, IOSColors.separator, RoundedCornerShape(8.dp)),
                )
                Spacer(Modifier.width(12.dp))
                Text("Color", style = SettingsRowText.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.weight(1f))
                IOSCapsuleButton("Done", onDismiss, prominent = true, height = 36.dp)
            }
            BoxWithConstraints(
                Modifier
                    .fillMaxWidth()
                    .aspectRatio(1.2f)
                    .clip(RoundedCornerShape(12.dp))
                    .background(Brush.horizontalGradient(listOf(Color.White, Color.hsv(hue.coerceIn(0f, 360f), 1f, 1f))))
                    .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black)))
                    .pointerInput(Unit) {
                        fun update(position: Offset) {
                            saturation = (position.x / size.width).coerceIn(0f, 1f)
                            brightness = 1f - (position.y / size.height).coerceIn(0f, 1f)
                            apply()
                        }
                        awaitEachGesture {
                            val down = awaitFirstDown()
                            update(down.position)
                            drag(down.id) { change ->
                                change.consume()
                                update(change.position)
                            }
                        }
                    },
            ) {
                val density = LocalDensity.current
                val w = with(density) { maxWidth.toPx() }
                val h = with(density) { maxHeight.toPx() }
                val thumb = with(density) { 11.dp.toPx() }
                Box(
                    Modifier
                        .offset { IntOffset((saturation * w - thumb).roundToInt(), ((1f - brightness) * h - thumb).roundToInt()) }
                        .size(22.dp)
                        .border(2.5.dp, Color.White, CircleShape)
                        .padding(2.5.dp)
                        .clip(CircleShape)
                        .background(Color.hsv(hue.coerceIn(0f, 360f), saturation, brightness)),
                )
            }
            BoxWithConstraints(
                Modifier
                    .fillMaxWidth()
                    .height(28.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(Brush.horizontalGradient(HueStops))
                    .pointerInput(Unit) {
                        fun update(position: Offset) {
                            hue = (position.x / size.width).coerceIn(0f, 1f) * 360f
                            apply()
                        }
                        awaitEachGesture {
                            val down = awaitFirstDown()
                            update(down.position)
                            drag(down.id) { change ->
                                change.consume()
                                update(change.position)
                            }
                        }
                    },
                contentAlignment = Alignment.CenterStart,
            ) {
                val density = LocalDensity.current
                val w = with(density) { maxWidth.toPx() }
                val thumb = with(density) { 12.dp.toPx() }
                Box(
                    Modifier
                        .offset { IntOffset(((hue / 360f) * w - thumb).roundToInt().coerceIn(0, (w - thumb * 2).roundToInt()), 0) }
                        .size(24.dp)
                        .border(2.5.dp, Color.White, CircleShape)
                        .padding(2.5.dp)
                        .clip(CircleShape)
                        .background(Color.hsv(hue.coerceIn(0f, 360f), 1f, 1f)),
                )
            }
        }
        }
    }
}

/** Liquid Glass look for the dock, mini player, and floating buttons, with a live preview. */
@Composable
private fun LiquidGlassSettings(state: ZelefinUiState) {
    val context = LocalContext.current
    val mode = GlassPreferences.mode
    val style = GlassPreferences.style
    val backdrop = state.home.featured.firstOrNull() ?: state.home.continueWatching.firstOrNull()
    SettingsHeader("Liquid Glass")
    LiquidGlassPreview(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .height(170.dp),
    ) {
        if (backdrop != null) {
            CachedArtwork(
                urls = artworkCandidates(backdrop, state.session, landscape = true),
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
    Spacer(Modifier.height(12.dp))
    SettingsCard {
        SettingsMenuPicker(
            label = "Look",
            choices = GlassMode.entries.map { SettingsChoice(it, it.title) },
            selected = mode,
            onSelect = { next -> GlassPreferences.setMode(context, next) },
        )
        GlassKnob.entries.forEach { knob ->
            SettingsCardDivider()
            val value = knob.read(if (mode == GlassMode.Off) GlassMode.Clear.preset!! else style)
            SettingsSliderRow(
                label = knob.title,
                value = value,
                valueText = knob.label(value),
                range = knob.range,
                onChange = { next -> GlassPreferences.adjust(context, knob, next) },
            )
        }
    }
    SettingsFooter(
        when (mode) {
            GlassMode.Clear -> "Clear lets more of the page show through the dock and mini player. Move a slider to make your own look."
            GlassMode.Tinted -> "Tinted darkens and frosts the glass so labels stand out over bright artwork. Move a slider to make your own look."
            GlassMode.Custom -> "Your own look. Frost blurs what shows through, Darkness tints it, Refraction and Edge Width shape the bent rim, Color Fringe adds rainbow edges, and Vibrance boosts color. Pick Clear or Tinted to start over."
            GlassMode.Off -> "Off shows a plain frosted bar with no live refraction. It is the smoothest option on older phones. Move a slider to turn the glass back on."
        },
    )
    Spacer(Modifier.height(8.dp))
    SettingsCard {
        SettingsSecondaryButton("Reset Custom Glass") {
            GlassPreferences.resetCustom(context)
        }
    }
    SettingsFooter("Clears your slider changes and goes back to Clear.")
}
