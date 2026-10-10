package app.zelefin.client.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.interaction.MutableInteractionSource
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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.CollectionsBookmark
import androidx.compose.material.icons.outlined.Colorize
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Movie
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material.icons.outlined.SkipNext
import androidx.compose.material.icons.outlined.TheaterComedy
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material.icons.outlined.Tv
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.DragHandle
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.zIndex
import androidx.lifecycle.viewmodel.compose.viewModel
import app.zelefin.client.ZelefinModel
import app.zelefin.client.ZelefinUiState
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

private val InterfaceCaption = ZelefinMuted
private val SwatchShape = RoundedCornerShape(9.7.dp)
private const val DockFullNote = "The dock is full. Turn off a tab or library first."

/** Accent color. Used by the Appearance topic. */
@Composable
fun AppearanceSettings() {
    AccentSection()
}

/** Mirrors iOS `TabCustomizationView`: merge, hero, Home rows, tabs, libraries, reset. */
@Composable
fun InterfaceSettings(state: ZelefinUiState) {
    val model: ZelefinModel = viewModel()
    val context = LocalContext.current
    val silo = state.session?.usesSilo == true
    LaunchedEffect(Unit) { model.pullDisplayPreferences() }

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
    }
    SettingsFooter("What the Home hero cycles through. Recently Added is the default. Random picks a new set when Home refreshes.")

    SettingsHeader("Home")
    ReorderableCards(
        items = HomeLayoutPreferences.order,
        key = { it.raw },
        enabled = true,
        onCommit = { next ->
            HomeLayoutPreferences.setOrder(context, next)
            model.pushDisplayPreferences()
        },
    ) { row, handle ->
        ReorderRow(
            icon = { Icon(homeRowIcon(row), contentDescription = null, tint = MaterialTheme.colorScheme.onSurface, modifier = Modifier.size(22.dp)) },
            title = row.title,
            checked = row !in HomeLayoutPreferences.hidden,
            onCheckedChange = { on ->
                HomeLayoutPreferences.setVisible(context, row, on)
                model.pushDisplayPreferences()
            },
            handle = handle,
        )
    }
    SettingsFooter(
        if (merged) {
            "Drag to reorder. Turn off a row to hide it from Home. Next Up only appears when Combine Continue Watching and Next Up is off."
        } else {
            "Drag to reorder. Turn off a row to hide it from Home."
        },
    )

    var dockNote by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(dockNote) {
        if (dockNote != null) {
            delay(3_000)
            dockNote = null
        }
    }
    val pinnable = TabPreferences.pinnable(state.libraries)
    val canEnableAnother = PhoneDockLimit.canEnableAnother(
        TabPreferences.enabledTabCount(silo),
        TabPreferences.enabledLibraryCount(state.libraries),
    )

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
        enabled = true,
        onCommit = { next ->
            val full = TabPreferences.order
            val result = next.toMutableList()
            full.filterNot { it.availableOnAndroid }.forEach { missing ->
                result.add(full.indexOf(missing).coerceAtMost(result.size), missing)
            }
            TabPreferences.setOrder(context, result)
            model.pushDisplayPreferences()
        },
    ) { tab, handle ->
        val appTab = tab.appTab ?: return@ReorderableCards
        ReorderRow(
            icon = { DockTabIcon(appTab, selected = false, description = null, tint = MaterialTheme.colorScheme.onSurface, modifier = Modifier.size(22.dp)) },
            title = tab.title,
            checked = if (tab.canHide) TabPreferences.isShown(tab) else null,
            onCheckedChange = { on ->
                if (on && !canEnableAnother) {
                    dockNote = DockFullNote
                } else {
                    TabPreferences.setShown(context, tab, on)
                    model.pushDisplayPreferences()
                }
            },
            handle = handle,
        )
    }
    SettingsFooter(
        if (TabPreferences.showsNames) {
            "Each dock icon shows its name. The phone dock holds 5 tabs, including Search. Drag to reorder. Turn off a tab to hide it from the tab bar."
        } else {
            "The dock shows icons only. Turn Show Tab Names on to put a name under each icon. The phone dock holds 5 tabs, including Search. Drag to reorder. Turn off a tab to hide it from the tab bar."
        },
    )
    dockNote?.let { DockNote(it) }

    if (pinnable.isNotEmpty()) {
        SettingsHeader("Libraries")
        pinnable.forEachIndexed { index, room ->
            if (index > 0) Spacer(Modifier.height(8.dp))
            SettingsCard {
                ReorderRow(
                    icon = { DockTabIcon(app.zelefin.client.AppTab.Room, selected = false, description = null, tint = MaterialTheme.colorScheme.onSurface, modifier = Modifier.size(22.dp)) },
                    title = room.name,
                    checked = room.id in TabPreferences.dockLibraryIds,
                    onCheckedChange = { on ->
                        if (on && !canEnableAnother) dockNote = DockFullNote else TabPreferences.setLibraryPinned(context, room.id, on)
                    },
                    handle = null,
                )
            }
        }
        SettingsFooter("Turn on a custom library, such as Anime, to put it in the dock. It uses one of the 5 phone spots.")
    }

    Spacer(Modifier.height(22.dp))
    SettingsCard {
        SettingsSecondaryButton("Reset Home Rows") {
            HomeLayoutPreferences.reset(context)
            model.pushDisplayPreferences()
            model.refreshLibrary()
        }
        Spacer(Modifier.height(10.dp))
        SettingsSecondaryButton("Reset Tabs") {
            TabPreferences.reset(context)
            model.pushDisplayPreferences()
        }
    }
}

@Composable
private fun DockNote(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp),
    )
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
) {
    Row(Modifier.fillMaxWidth().height(32.dp), verticalAlignment = Alignment.CenterVertically) {
        icon()
        Spacer(Modifier.width(14.dp))
        Text(
            title,
            style = MaterialTheme.typography.titleMedium,
            maxLines = 1,
            modifier = Modifier.weight(1f),
        )
        if (checked != null) {
            Switch(
                checked = checked,
                onCheckedChange = onCheckedChange,
            )
        }
        if (handle != null) {
            Spacer(Modifier.width(10.dp))
            Box(handle.size(32.dp), contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.DragHandle, contentDescription = "Reorder $title", tint = InterfaceCaption, modifier = Modifier.size(22.dp))
            }
        }
    }
}

/**
 * One settings card per item, reordered by dragging the handle Modifier handed to [content].
 * Neighbours slide out of the way while dragging; the new order is committed on release.
 */
@Composable
private fun <T> ReorderableCards(
    items: List<T>,
    key: (T) -> Any,
    enabled: Boolean,
    onCommit: (List<T>) -> Unit,
    content: @Composable (T, Modifier) -> Unit,
) {
    val spacing = 8.dp
    val spacingPx = with(LocalDensity.current) { spacing.toPx() }
    var cardHeight by remember { mutableFloatStateOf(0f) }
    var dragging by remember(items) { mutableIntStateOf(-1) }
    var dragY by remember(items) { mutableFloatStateOf(0f) }
    val stride = cardHeight + spacingPx
    val target = if (dragging < 0 || stride <= 0f) -1 else (dragging + (dragY / stride).roundToInt()).coerceIn(0, items.lastIndex)
    val latestItems by rememberUpdatedState(items)
    val latestCommit by rememberUpdatedState(onCommit)

    Column(verticalArrangement = Arrangement.spacedBy(spacing)) {
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
                        .onSizeChanged { if (index == 0) cardHeight = it.height.toFloat() },
                ) {
                    SettingsCard { content(item, handle) }
                }
            }
        }
    }
}

@Composable
internal fun AccentSection() {
    val context = LocalContext.current
    val focusManager = LocalFocusManager.current
    var pickerOpen by remember { mutableStateOf(false) }
    val selectedId = AccentPreferences.presetId
    val custom = selectedId == AccentPreferences.CUSTOM_ID

    SettingsHeader("Accent Color")
    SettingsCard {
        val cells: List<AccentPreset?> = AccentPreferences.presets + null
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            cells.chunked(5).forEach { row ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    row.forEach { preset ->
                        Box(Modifier.weight(1f), contentAlignment = Alignment.TopCenter) {
                            if (preset != null) {
                                AccentSwatch(preset.name, preset.color, selected = selectedId == preset.id, eyedropper = false) {
                                    AccentPreferences.select(context, preset.id)
                                }
                            } else {
                                AccentSwatch("Custom", AccentPreferences.customColor, selected = custom, eyedropper = true) {
                                    AccentPreferences.selectCustom(context)
                                }
                            }
                        }
                    }
                    repeat(5 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
        if (custom) {
            Spacer(Modifier.height(16.dp))
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("Color", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
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
    SettingsFooter("Accent color tints buttons, highlights, and icons throughout the app.")

    if (pickerOpen) {
        AccentColorPickerPanel(onDismiss = { pickerOpen = false })
    }
}

@Composable
private fun AccentSwatch(name: String, color: Color, selected: Boolean, eyedropper: Boolean, onClick: () -> Unit) {
    Column(
        Modifier.clip(RoundedCornerShape(10.dp)).clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier
                .size(44.dp)
                .background(color, SwatchShape)
                .then(if (selected) Modifier.border(2.5.dp, Color.White, SwatchShape) else Modifier),
            contentAlignment = Alignment.Center,
        ) {
            when {
                selected -> Icon(Icons.Rounded.Check, contentDescription = "Selected", tint = Color.White, modifier = Modifier.size(20.dp))
                eyedropper -> Icon(Icons.Outlined.Colorize, contentDescription = null, tint = Color.White, modifier = Modifier.size(20.dp))
            }
        }
        Spacer(Modifier.height(6.dp))
        Text(
            name,
            style = MaterialTheme.typography.labelSmall,
            color = if (selected) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
        )
    }
}

/** Hex entry: saves while typing whenever the text is a valid hex; invalid text reverts when editing ends. */
@Composable
private fun HexRow(onDone: () -> Unit) {
    val context = LocalContext.current
    val stored = AccentPreferences.customHex
    var text by remember { mutableStateOf(stored) }
    LaunchedEffect(stored) {
        if (AccentPreferences.normalizedHex(text) != stored) text = stored
    }
    val preview = AccentPreferences.colorFromHex(text) ?: AccentPreferences.customColor
    fun revertIfInvalid() {
        if (AccentPreferences.normalizedHex(text) == null) text = AccentPreferences.customHex
    }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier
                .size(36.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(preview)
                .border(0.5.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(8.dp)),
        )
        Spacer(Modifier.width(12.dp))
        OutlinedTextField(
            value = text,
            onValueChange = { value ->
                text = value.take(7)
                AccentPreferences.normalizedHex(text)?.let { hex ->
                    if (hex != AccentPreferences.customHex) AccentPreferences.setCustomHex(context, hex)
                }
            },
            modifier = Modifier
                .weight(1f)
                .onFocusChanged { if (!it.isFocused) revertIfInvalid() },
            placeholder = { Text("Hex code") },
            singleLine = true,
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
    }
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
        Surface(
            shape = RoundedCornerShape(28.dp),
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            tonalElevation = 6.dp,
        ) {
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
                        .border(0.5.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(8.dp)),
                )
                Spacer(Modifier.width(12.dp))
                Text("Color", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                TextButton(onClick = onDismiss) { Text("Done") }
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
