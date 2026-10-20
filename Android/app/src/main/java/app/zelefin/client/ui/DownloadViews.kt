package app.zelefin.client.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowCircleDown
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathData
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.client.downloads.DownloadControlState
import app.zelefin.client.downloads.DownloadEligibility
import app.zelefin.client.downloads.DownloadMark
import app.zelefin.client.downloads.DownloadNotice
import app.zelefin.client.downloads.DownloadProgress
import app.zelefin.client.downloads.DownloadPrompts
import app.zelefin.client.downloads.DownloadRow
import app.zelefin.client.downloads.ZelefinDownloads
import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind
import app.zelefin.core.SavedSession
import app.zelefin.core.SeasonDownloadChoice
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sin

private val DestructiveRed = Color(0xFFFF453A)

/** Two-button confirm: Cancel on the leading side, the action on the trailing side. */
@Composable
private fun DownloadGlassConfirm(
    hazeState: ZelefinHazeState,
    title: String,
    message: String,
    confirmLabel: String,
    destructive: Boolean = false,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    SettingsAlertDialog(
        title = title,
        message = message,
        confirmLabel = confirmLabel,
        onConfirm = onConfirm,
        onDismiss = onDismiss,
        destructive = destructive,
    )
}

@Composable
internal fun DownloadRemovalConfirm(hazeState: ZelefinHazeState, prompt: DownloadNotice, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    DownloadGlassConfirm(
        hazeState = hazeState,
        title = prompt.title,
        message = prompt.message,
        confirmLabel = "Delete",
        destructive = true,
        onConfirm = onConfirm,
        onDismiss = onDismiss,
    )
}

/** Asks before deleting [target]'s downloaded file. */
@Composable
fun DownloadRemovalOverlay(target: MediaItem?, onDismiss: () -> Unit) {
    val haze = LocalZelefinHaze.current
    PresentZelefinOverlay(visible = target != null && haze != null) {
        val hazeState = haze ?: return@PresentZelefinOverlay
        val item = target ?: return@PresentZelefinOverlay
        DownloadRemovalConfirm(
            hazeState = hazeState,
            prompt = DownloadPrompts.removal(item),
            onConfirm = {
                ZelefinDownloads.remove(item.id)
                onDismiss()
            },
            onDismiss = onDismiss,
        )
    }
}

/** Download failures surface here, wherever the user is when the transfer ends. */
@Composable
fun DownloadNoticeAlert() {
    val notice by ZelefinDownloads.state.collectAsState()
    val haze = LocalZelefinHaze.current
    val current = notice.notice
    PresentZelefinOverlay(visible = current != null && haze != null) {
        val hazeState = haze ?: return@PresentZelefinOverlay
        val shown = current ?: return@PresentZelefinOverlay
        ZelefinGlassAlert(hazeState = hazeState, title = shown.title, message = shown.message, onDismiss = ZelefinDownloads::dismissNotice)
    }
}

/** Jellyfin DisplayMessage while the app is open. Closed-app delivery is the Zelefin plugin push. */
@Composable
fun SessionMessageAlert() {
    val inbound by app.zelefin.client.session.SessionMessageCenter.message.collectAsState()
    val haze = LocalZelefinHaze.current
    val current = inbound
    LaunchedEffect(current?.id) {
        val timeout = current?.timeoutMs ?: return@LaunchedEffect
        if (timeout <= 0) return@LaunchedEffect
        kotlinx.coroutines.delay(timeout.toLong())
        if (app.zelefin.client.session.SessionMessageCenter.message.value?.id == current.id) {
            app.zelefin.client.session.SessionMessageCenter.dismiss()
        }
    }
    PresentZelefinOverlay(visible = current != null && haze != null) {
        val hazeState = haze ?: return@PresentZelefinOverlay
        val shown = current ?: return@PresentZelefinOverlay
        ZelefinGlassAlert(
            hazeState = hazeState,
            title = shown.alertTitle,
            message = shown.alertBody ?: shown.text,
            onDismiss = app.zelefin.client.session.SessionMessageCenter::dismiss,
        )
    }
}

internal fun startDownload(target: MediaItem) {
    ZelefinDownloads.start(target)
}

/** The Download half of the detail hero's Download / Share capsule. Share stands alone when downloads are off. */
@Composable
internal fun DownloadSharePill(
    item: MediaItem,
    episodes: List<MediaItem>,
    seasons: List<MediaItem> = emptyList(),
    onShare: () -> Unit,
    onRemove: (MediaItem) -> Unit,
    onChooseSeasons: ((Rect) -> Unit)? = null,
) {
    val downloads by ZelefinDownloads.state.collectAsState()
    val control = downloads.control(item, episodes)
    val target = DownloadEligibility.playableItem(item, episodes)
    if (control == DownloadControlState.Unavailable || target == null) {
        Box(Modifier.size(45.dp).zelefinGlassDisc("detail-share", "Share", Icons.Outlined.Share, onShare))
        return
    }
    val icon = when (control) {
        is DownloadControlState.Downloading -> downloadRingIcon(control.fraction)
        DownloadControlState.Downloaded -> Icons.Filled.CheckCircle
        else -> Icons.Outlined.Download
    }
    val description = when (control) {
        is DownloadControlState.Downloading -> "Cancel Download"
        DownloadControlState.Downloaded -> "Remove Download"
        else -> "Download"
    }
    val key = "detail-download-share"
    val host = LocalZelefinGlassHost.current
    val bounds = remember { arrayOf(Rect.Zero) }
    Box(
        Modifier
            .size(width = 92.dp, height = 45.dp)
            .onGloballyPositioned { bounds[0] = it.boundsInRoot() }
            .zelefinGlassSplit(
                key = key,
                leadingDescription = description,
                leadingIcon = icon,
                trailingDescription = "Share",
                trailingIcon = Icons.Outlined.Share,
                onLeading = {
                    when (ZelefinDownloads.state.value.control(item, episodes)) {
                        DownloadControlState.Idle -> {
                            if (item.kind == MediaKind.Series) {
                                val choices = SeasonDownloadChoice.options(seasons, episodes)
                                if (onChooseSeasons != null && (item.isYouTube || choices.size > 1)) {
                                    onChooseSeasons(bounds[0])
                                } else {
                                    startSeasonDownload(choices.firstOrNull()?.seasonIndex?.let(::setOf), episodes, target)
                                }
                            } else {
                                startDownload(target)
                            }
                        }
                        is DownloadControlState.Downloading -> ZelefinDownloads.pause(target)
                        is DownloadControlState.Paused -> ZelefinDownloads.resume(target)
                        DownloadControlState.Downloaded -> onRemove(target)
                        DownloadControlState.Unavailable -> Unit
                    }
                },
                onTrailing = onShare,
            ),
    )
    // A new icon re-registers the capsule; carry the known bounds over so it does not blink for a frame.
    SideEffect {
        val disc = host?.discs?.lastOrNull { it.key == key } ?: return@SideEffect
        if (disc.bounds == Rect.Zero && bounds[0] != Rect.Zero) disc.bounds = bounds[0]
    }
}

internal fun startSeasonDownload(indexes: Set<Int>?, episodes: List<MediaItem>, fallback: MediaItem) {
    val selected = SeasonDownloadChoice.episodes(indexes, episodes)
    ZelefinDownloads.startAll(selected.ifEmpty { listOf(fallback) })
}

@Composable
internal fun DownloadSeasonsSheet(
    seasons: List<MediaItem>,
    episodes: List<MediaItem>,
    onConfirm: (Set<Int>) -> Unit,
    onDismiss: () -> Unit,
    anchor: Rect = Rect.Zero,
    visible: Boolean = true,
) {
    val haze = LocalZelefinHaze.current
    PresentZelefinOverlay(visible = visible && haze != null) {
        val hazeState = haze ?: return@PresentZelefinOverlay
        val choices = remember(seasons, episodes) { SeasonDownloadChoice.options(seasons, episodes) }
        val indexes = remember(choices) { choices.mapNotNull { it.seasonIndex }.toSet() }
        var selected by remember(choices) { mutableStateOf(emptySet<Int>()) }
        val allOn = indexes.isNotEmpty() && selected.containsAll(indexes)
        DownloadSeasonsMenu(
            hazeState = hazeState,
            choices = choices,
            indexes = indexes,
            selected = selected,
            allOn = allOn,
            screenHeight = LocalConfiguration.current.screenHeightDp.dp,
            anchor = anchor,
            onSelect = { selected = it },
            onConfirm = onConfirm,
            onDismiss = onDismiss,
        )
    }
}

@Composable
private fun DownloadSeasonsMenu(
    hazeState: ZelefinHazeState,
    choices: List<SeasonDownloadChoice>,
    indexes: Set<Int>,
    selected: Set<Int>,
    allOn: Boolean,
    screenHeight: Dp,
    anchor: Rect,
    onSelect: (Set<Int>) -> Unit,
    onConfirm: (Set<Int>) -> Unit,
    onDismiss: () -> Unit,
) {
    AnchoredMenuFrame(anchor, alignTrailing = true, onDismiss) {
        val run = LocalMenuAction.current
        Column(
            Modifier
                .widthIn(max = 250.dp)
                .zelefinGlassChrome(hazeState, ZelefinMenuShape)
                .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) {}
                .zelefinMenuWidth()
                .padding(vertical = 4.dp),
        ) {
            Column(Modifier.heightIn(max = screenHeight * 0.45f).verticalScroll(rememberScrollState())) {
                DownloadSeasonRow("Select All", selected = allOn) {
                    onSelect(if (allOn) emptySet() else indexes)
                }
                choices.forEach { choice ->
                    val number = choice.seasonIndex ?: return@forEach
                    DownloadSeasonRow(choice.title, selected = number in selected) {
                        onSelect(if (number in selected) selected - number else selected + number)
                    }
                }
            }
            Box(
                Modifier
                    .padding(horizontal = 16.dp)
                    .fillMaxWidth()
                    .height(0.5.dp)
                    .background(DockBorder),
            )
            DownloadMenuRow("Cancel", Icons.Outlined.Close, DestructiveRed) { run(onDismiss) }
            DownloadMenuRow(
                title = "Download",
                icon = Icons.Outlined.Download,
                color = Color.White,
                enabled = selected.isNotEmpty(),
            ) {
                val picked = selected
                run { onConfirm(picked) }
            }
        }
    }
}

@Composable
private fun DownloadSeasonRow(title: String, selected: Boolean, onClick: () -> Unit) {
    DownloadMenuRow(
        title = title,
        icon = Icons.Rounded.Check,
        color = Color.White,
        showsLeading = selected,
        onClick = onClick,
    )
}

@Composable
private fun DownloadMenuRow(
    title: String,
    icon: ImageVector,
    color: Color,
    enabled: Boolean = true,
    showsLeading: Boolean = true,
    onClick: () -> Unit,
) {
    val tint = color.copy(alpha = if (enabled) 1f else 0.4f)
    Row(
        Modifier
            .fillMaxWidth()
            .height(44.dp)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(20.dp), contentAlignment = Alignment.Center) {
            if (showsLeading) {
                Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(20.dp))
            }
        }
        Text(title, color = tint, fontFamily = ZelefinFont, fontSize = 17.sp)
    }
}

/** Download choices for a TubeArchivist channel: newest videos, unwatched, or everything. [videos] is newest first. */
@Composable
internal fun YouTubeDownloadMenu(
    videos: List<MediaItem>,
    anchor: Rect,
    visible: Boolean,
    onDismiss: () -> Unit,
) {
    val haze = LocalZelefinHaze.current
    PresentZelefinOverlay(visible = visible && haze != null) {
        val hazeState = haze ?: return@PresentZelefinOverlay
        val unwatched = remember(videos) { videos.filter { !it.isWatched } }
        AnchoredMenuFrame(anchor, alignTrailing = true, onDismiss) {
            val run = LocalMenuAction.current
            fun download(picked: List<MediaItem>) = run {
                ZelefinDownloads.startAll(picked)
                onDismiss()
            }
            Column(
                Modifier
                    .widthIn(max = 280.dp)
                    .zelefinGlassChrome(hazeState, ZelefinMenuShape)
                    .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) {}
                    .zelefinMenuWidth()
                    .padding(vertical = 4.dp),
            ) {
                listOf(5, 10).filter { videos.size > it }.forEach { count ->
                    DownloadMenuRow("Latest $count Videos", Icons.Outlined.Download, Color.White) { download(videos.take(count)) }
                }
                if (unwatched.isNotEmpty() && unwatched.size < videos.size) {
                    DownloadMenuRow("Unwatched (${unwatched.size})", Icons.Outlined.Download, Color.White) { download(unwatched) }
                }
                if (videos.isNotEmpty()) {
                    DownloadMenuRow(
                        if (videos.size == 1) "Download Video" else "All ${videos.size} Videos",
                        Icons.Outlined.Download,
                        Color.White,
                    ) { download(videos) }
                }
                Box(
                    Modifier
                        .padding(horizontal = 16.dp)
                        .fillMaxWidth()
                        .height(0.5.dp)
                        .background(DockBorder),
                )
                DownloadMenuRow("Cancel", Icons.Outlined.Close, DestructiveRed) { run(onDismiss) }
            }
        }
    }
}

/** Status card under the detail hero while this title (or one of its episodes) downloads. */
@Composable
internal fun DetailDownloadStatus(item: MediaItem, modifier: Modifier = Modifier) {
    val downloads by ZelefinDownloads.state.collectAsState()
    val transfer = downloads.transfer(item) ?: return
    DownloadStatusBanner(transfer, onCancel = { ZelefinDownloads.cancel(transfer.item) }, modifier = modifier)
}

@Composable
fun DownloadStatusBanner(progress: DownloadProgress, onCancel: () -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    Row(
        modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .posterChrome(16.dp)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .padding(start = 14.dp, end = 6.dp, top = 10.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        DownloadRing(progress.fraction, size = 26.dp, stroke = 2.5.dp, indeterminate = progress.bytesExpected <= 0)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(progress.bannerTitle, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(progress.sizeLabel(context), color = ZelefinMuted, fontFamily = ZelefinFont, fontSize = 13.sp, maxLines = 1)
        }
        Text(
            "Cancel",
            color = ZelefinCyan,
            fontFamily = ZelefinFont,
            fontWeight = FontWeight.SemiBold,
            fontSize = 15.sp,
            modifier = Modifier
                .clickable(onClick = onCancel)
                .padding(horizontal = 10.dp, vertical = 8.dp),
        )
    }
}

@Composable
fun DownloadRing(fraction: Double, size: Dp, stroke: Dp, modifier: Modifier = Modifier, indeterminate: Boolean = false) {
    Canvas(modifier.size(size)) {
        val width = stroke.toPx()
        val inset = width / 2
        val arcSize = Size(this.size.width - width, this.size.height - width)
        drawArc(Color.White.copy(alpha = 0.25f), 0f, 360f, useCenter = false, topLeft = Offset(inset, inset), size = arcSize, style = Stroke(width))
        val sweep = if (indeterminate) 0f else (fraction.coerceIn(0.0, 1.0) * 360).toFloat()
        if (sweep > 0f) {
            drawArc(Color.White, -90f, sweep, useCenter = false, topLeft = Offset(inset, inset), size = arcSize, style = Stroke(width, cap = StrokeCap.Round))
        }
    }
}

private val ringIcons = HashMap<Int, ImageVector>()

/** A progress ring with a stop square, as an icon so it can sit in the glass capsule. Quantized to 2%. */
fun downloadRingIcon(fraction: Double): ImageVector {
    val step = (fraction.coerceIn(0.0, 1.0) * 50).roundToInt()
    return synchronized(ringIcons) { ringIcons.getOrPut(step) { buildRingIcon(step / 50f) } }
}

private fun buildRingIcon(fraction: Float): ImageVector {
    val radius = 10f
    val circle = PathData {
        moveTo(12f, 2f)
        arcTo(radius, radius, 0f, false, true, 12f, 22f)
        arcTo(radius, radius, 0f, false, true, 12f, 2f)
    }
    val builder = ImageVector.Builder("DownloadRing$fraction", 24.dp, 24.dp, 24f, 24f)
        .addPath(circle, stroke = SolidColor(Color.White), strokeAlpha = 0.3f, strokeLineWidth = 2.2f)
    if (fraction >= 0.999f) {
        builder.addPath(circle, stroke = SolidColor(Color.White), strokeLineWidth = 2.2f)
    } else if (fraction > 0f) {
        val angle = 2 * PI * fraction - PI / 2
        val x = (12 + radius * cos(angle)).toFloat()
        val y = (12 + radius * sin(angle)).toFloat()
        val arc = PathData {
            moveTo(12f, 2f)
            arcTo(radius, radius, 0f, fraction > 0.5f, true, x, y)
        }
        builder.addPath(arc, stroke = SolidColor(Color.White), strokeLineWidth = 2.2f, strokeLineCap = StrokeCap.Round)
    }
    val stop = PathData {
        moveTo(9.5f, 9.5f)
        lineTo(14.5f, 9.5f)
        lineTo(14.5f, 14.5f)
        lineTo(9.5f, 14.5f)
        close()
    }
    return builder.addPath(stop, fill = SolidColor(Color.White)).build()
}

/** Downloading: dimmed poster with a small ring. Downloaded: a small glyph in the top-trailing corner. */
@Composable
fun BoxScope.DownloadPosterMark(item: MediaItem, portrait: Boolean) {
    val downloads = ZelefinDownloads.state.collectAsState()
    val mark by remember(item.id, item.kind) { derivedStateOf { downloads.value.mark(item) } }
    when (val current = mark) {
        DownloadMark.None -> Unit
        is DownloadMark.Downloading -> {
            val percent = (current.fraction * 100).roundToInt()
            Box(
                Modifier
                    .matchParentSize()
                    .background(Color.Black.copy(alpha = 0.45f))
                    .semantics { contentDescription = if (percent > 0) "Downloading $percent percent" else "Downloading" },
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    DownloadRing(current.fraction, size = 24.dp, stroke = 2.5.dp, indeterminate = current.fraction <= 0)
                    if (percent > 0) {
                        Spacer(Modifier.height(4.dp))
                        Text("$percent%", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 12.sp)
                    }
                }
            }
        }
        DownloadMark.Downloaded -> {
            val trailing = if (portrait && item.isWatched) 32.dp else 6.dp
            Box(
                Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 6.dp, end = trailing)
                    .size(20.dp),
                contentAlignment = Alignment.Center,
            ) {
                Box(Modifier.size(14.dp).background(Color.Black.copy(alpha = 0.78f), CircleShape))
                Icon(Icons.Filled.ArrowCircleDown, contentDescription = "Downloaded", tint = Color.White, modifier = Modifier.size(20.dp))
            }
        }
    }
}

@Composable
internal fun DownloadedJumpTile(modifier: Modifier, onClick: () -> Unit) {
    Column(
        modifier
            .height(88.dp)
            .posterChrome(14.dp)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(Icons.Filled.ArrowCircleDown, contentDescription = null, tint = Color.White, modifier = Modifier.size(26.dp))
        Spacer(Modifier.height(8.dp))
        Text(
            "Downloaded",
            color = Color.White,
            fontWeight = FontWeight.SemiBold,
            fontSize = 15.sp,
            maxLines = 1,
            modifier = Modifier.padding(horizontal = 8.dp),
        )
    }
}

private sealed interface DownloadedEntry {
    val key: String
    val title: MediaItem

    data class Active(val progress: DownloadProgress, override val title: MediaItem) : DownloadedEntry {
        override val key get() = "active-${progress.item.id}"
    }

    data class Stored(val row: DownloadRow) : DownloadedEntry {
        override val key get() = "row-${row.id}"
        override val title get() = row.title
    }
}

/** Library → Downloaded. Reads only local records, so it works without a connection. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun DownloadedPage(
    session: SavedSession?,
    bottomInset: Dp,
    onBack: () -> Unit,
    onOpen: (MediaItem) -> Unit,
) {
    val downloads by ZelefinDownloads.state.collectAsState()
    val active = downloads.activeTransfers
    val rows = downloads.rows
    val entries = active.map { progress ->
        val title = if (progress.item.kind == MediaKind.Episode && !progress.item.seriesId.isNullOrEmpty()) {
            DownloadEligibility.showItem(progress.item)
        } else {
            progress.item
        }
        DownloadedEntry.Active(progress, title)
    }.distinctBy { it.title.id } + rows.filter { row -> active.none { it.item.id == row.id || it.item.seriesId == row.id } }
        .map { DownloadedEntry.Stored(it) }
    val statusTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    val headerHeight = statusTop + 59.dp
    var menu by remember { mutableStateOf<Pair<DownloadRow, Rect>?>(null) }
    var removal by remember { mutableStateOf<DownloadRow?>(null) }
    val haze = LocalZelefinHaze.current

    PresentZelefinOverlay(visible = haze != null && (menu != null || removal != null)) {
        val hazeState = haze ?: return@PresentZelefinOverlay
        val confirm = removal
        val open = menu
        if (confirm != null) {
            DownloadRemovalConfirm(
                hazeState = hazeState,
                prompt = DownloadPrompts.removal(confirm),
                onConfirm = {
                    ZelefinDownloads.remove(confirm)
                    removal = null
                },
                onDismiss = { removal = null },
            )
        } else if (open != null) {
            DownloadedRowMenu(
                hazeState = hazeState,
                anchor = open.second,
                onDismiss = { menu = null },
                onRemove = {
                    menu = null
                    removal = open.first
                },
            )
        }
    }

    Box(Modifier.fillMaxSize()) {
        if (entries.isEmpty()) {
            Column(
                Modifier.fillMaxSize().padding(top = headerHeight + 40.dp, start = 32.dp, end = 32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Icon(Icons.Filled.ArrowCircleDown, contentDescription = null, tint = ZelefinMuted, modifier = Modifier.size(44.dp))
                Spacer(Modifier.height(14.dp))
                Text("No Downloads", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 22.sp)
                Spacer(Modifier.height(8.dp))
                Text(
                    "Movies and episodes you download will show up here for offline playback.",
                    color = ZelefinMuted,
                    fontSize = 16.sp,
                    textAlign = TextAlign.Center,
                )
            }
        } else {
            BoxWithConstraints(Modifier.fillMaxSize()) {
                val gridState = rememberLazyGridState()
                val columns = max(3, ((maxWidth - 32.dp + 10.dp) / (124.dp + 10.dp)).toInt())
                LazyVerticalGrid(
                    state = gridState,
                    columns = GridCells.Fixed(columns),
                    contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = headerHeight, bottom = bottomInset),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalArrangement = Arrangement.spacedBy(20.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    items(entries, key = { it.key }) { entry ->
                        val anchor = remember { arrayOf(Rect.Zero) }
                        val title = entry.title
                        val description = when (entry) {
                            is DownloadedEntry.Stored -> if (entry.row.isSeries) "${title.name}, ${entry.row.episodeCount} episodes" else title.name
                            is DownloadedEntry.Active -> title.name
                        }
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .aspectRatio(2f / 3f)
                                .onGloballyPositioned { anchor[0] = it.boundsInRoot() }
                                .posterChrome()
                                .combinedClickable(
                                    onClick = { onOpen(title) },
                                    onLongClick = (entry as? DownloadedEntry.Stored)?.let { stored -> { menu = stored.row to anchor[0] } },
                                )
                                .semantics(mergeDescendants = true) { contentDescription = description },
                        ) {
                            CachedArtwork(
                                urls = listOfNotNull(ZelefinDownloads.localArtwork(title)) + artworkCandidates(title, session, landscape = false),
                                contentDescription = null,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceContainerHigh),
                            )
                            ItemPosterMarks(title, portrait = true)
                        }
                    }
                }
            }
        }
        Row(
            Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            GlassBackDisc("downloaded-back", shown = true, onBack = onBack)
            Spacer(Modifier.width(12.dp))
            Text("Downloaded", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 22.sp)
        }
    }
}

@Composable
private fun DownloadedRowMenu(hazeState: ZelefinHazeState, anchor: Rect, onDismiss: () -> Unit, onRemove: () -> Unit) {
    AnchoredMenuFrame(anchor, alignTrailing = true, onDismiss = onDismiss, clearBottom = dockContentReserve()) {
            Column(
                Modifier
                    .zelefinGlassChrome(hazeState, ZelefinMenuShape)
                    .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) {}
                    .zelefinMenuWidth()
                    .padding(vertical = 4.dp),
            ) {
                MoreRow("Remove Download", Icons.Outlined.Delete, onRemove, destructive = true)
            }
    }
}
