package app.zelefin.client.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.ConnectedTv
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.LiveTv
import androidx.compose.material.icons.outlined.Movie
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.StopCircle
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import kotlinx.coroutines.launch
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material.icons.outlined.ClosedCaption
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import app.zelefin.client.plugins.JellyfinEnhancedHomeHide
import app.zelefin.client.plugins.JellyfinEnhancedHomeSurface
import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind

enum class TitleMenuContext { Featured, ContinueWatching, NextUp, Episode, Detail }

internal data class MenuNotice(val title: String, val message: String)

internal fun plusNotice(feature: app.zelefin.client.ZelefinPlus.Feature): MenuNotice =
    app.zelefin.client.ZelefinPlus.notice(feature).let { (title, message) -> MenuNotice(title, message) }

data class TitleMoreRequest(
    val item: MediaItem,
    val context: TitleMenuContext,
    val anchor: Rect,
)

@Composable
internal fun TitleMoreOverlay(
    request: TitleMoreRequest?,
    onDismiss: () -> Unit,
    onPlay: (MediaItem) -> Unit,
    onOpen: (MediaItem) -> Unit,
    onToggleWatched: (MediaItem) -> Unit,
    onToggleFavorite: (MediaItem) -> Unit,
    usesSilo: Boolean = false,
    skipCinemaIntros: Boolean = false,
    onToggleSkipCinema: () -> Unit = {},
    onCollections: (() -> Unit)? = null,
    note: MenuNotice? = null,
    onDismissNote: () -> Unit = {},
    onAddSubtitles: ((MediaItem) -> Unit)? = null,
    onHideFromHome: ((MediaItem, TitleMenuContext) -> Unit)? = null,
    isAdmin: Boolean = false,
    onPlayElsewhere: ((MediaItem) -> Unit)? = null,
    onSyncPlay: ((MediaItem) -> Unit)? = null,
    onRefreshMetadata: (suspend (MediaItem) -> Unit)? = null,
    onEditImages: ((MediaItem) -> Unit)? = null,
    onDeleteFromLibrary: (suspend (MediaItem) -> Unit)? = null,
) {
    val haze = LocalZelefinHaze.current
    PresentZelefinOverlay(visible = (request != null || note != null) && haze != null) {
        val hazeState = haze ?: return@PresentZelefinOverlay
        val current = request
        var menuNote by remember(current?.item?.id, current?.anchor) { mutableStateOf<MenuNotice?>(null) }
        var actionNote by remember(current?.item?.id, current?.anchor) { mutableStateOf<MenuNotice?>(null) }
        var confirmDelete by remember(current?.item?.id, current?.anchor) { mutableStateOf(false) }
        var working by remember(current?.item?.id, current?.anchor) { mutableStateOf(false) }
        var downloadRemoval by remember(current?.item?.id, current?.anchor) { mutableStateOf<MediaItem?>(null) }
        val scope = rememberCoroutineScope()
        val showing = note ?: menuNote
        val finished = actionNote
        if (finished != null && note == null) {
            ZelefinGlassAlert(
                hazeState = hazeState,
                title = finished.title,
                message = finished.message,
                onDismiss = {
                    actionNote = null
                    onDismiss()
                },
            )
        } else if (confirmDelete && current != null && onDeleteFromLibrary != null && note == null) {
            ZelefinGlassConfirm(
                hazeState = hazeState,
                title = "Delete this title from the library?",
                message = "Jellyfin will remove this item and its files from the server. This cannot be undone.",
                confirmLabel = if (working) "Deleting…" else "Delete Files",
                destructive = true,
                enabled = !working,
                onCancel = { confirmDelete = false },
                onConfirm = {
                    working = true
                    scope.launch {
                        runCatching { onDeleteFromLibrary(current.item) }
                            .onSuccess {
                                working = false
                                confirmDelete = false
                                onDismiss()
                            }
                            .onFailure { error ->
                                if (error is kotlinx.coroutines.CancellationException) throw error
                                working = false
                                confirmDelete = false
                                actionNote = MenuNotice("Couldn’t Delete", error.message ?: "Jellyfin kept this title. Try again in a moment.")
                            }
                    }
                },
            )
        } else if (showing != null) {
            ZelefinGlassAlert(
                hazeState = hazeState,
                title = showing.title,
                message = showing.message,
                onDismiss = {
                    if (note != null) onDismissNote() else menuNote = null
                },
            )
        } else if (downloadRemoval != null) {
            val removing = downloadRemoval!!
            DownloadRemovalConfirm(
                hazeState = hazeState,
                prompt = app.zelefin.client.downloads.DownloadPrompts.removal(removing),
                onConfirm = {
                    app.zelefin.client.downloads.ZelefinDownloads.remove(removing.id)
                    downloadRemoval = null
                    onDismiss()
                },
                onDismiss = { downloadRemoval = null },
            )
        } else if (current != null) {
            TitleMorePanel(
                hazeState = hazeState,
                request = current,
                usesSilo = usesSilo,
                skipCinemaIntros = skipCinemaIntros,
                onDismiss = onDismiss,
                onPlay = {
                    onDismiss()
                    onPlay(current.item)
                },
                onOpen = {
                    onDismiss()
                    onOpen(current.item)
                },
                onToggleWatched = {
                    onDismiss()
                    onToggleWatched(current.item)
                },
                onDownload = {
                    val target = app.zelefin.client.downloads.DownloadEligibility.playableItem(current.item)
                    when (app.zelefin.client.downloads.ZelefinDownloads.state.value.control(current.item)) {
                        app.zelefin.client.downloads.DownloadControlState.Idle -> {
                            val notice = target?.let(::startDownload)
                            if (notice != null) menuNote = notice else onDismiss()
                        }
                        is app.zelefin.client.downloads.DownloadControlState.Downloading -> {
                            app.zelefin.client.downloads.ZelefinDownloads.cancel(current.item)
                            onDismiss()
                        }
                        app.zelefin.client.downloads.DownloadControlState.Downloaded -> downloadRemoval = target
                        app.zelefin.client.downloads.DownloadControlState.Unavailable -> Unit
                    }
                },
                onToggleFavorite = {
                    onDismiss()
                    onToggleFavorite(current.item)
                },
                onNotice = { menuNote = it },
                onToggleSkipCinema = onToggleSkipCinema,
                onCollections = onCollections,
                onAddSubtitles = onAddSubtitles?.let { add ->
                    {
                        onDismiss()
                        add(current.item)
                    }
                },
                onHideFromHome = onHideFromHome?.takeIf {
                    current.context == TitleMenuContext.ContinueWatching || current.context == TitleMenuContext.NextUp
                }?.let { hide ->
                    {
                        onDismiss()
                        hide(current.item, current.context)
                    }
                },
                isAdmin = isAdmin,
                onPlayElsewhere = onPlayElsewhere?.let { open ->
                    {
                        onDismiss()
                        open(current.item)
                    }
                },
                onSyncPlay = onSyncPlay?.let { open ->
                    {
                        onDismiss()
                        open(current.item)
                    }
                },
                onRefreshMetadata = onRefreshMetadata?.let { refresh ->
                    {
                        if (!working) {
                            working = true
                            scope.launch {
                                actionNote = runCatching { refresh(current.item) }.fold(
                                    onSuccess = { MenuNotice("Refreshing Metadata", "Jellyfin is refreshing this title. New details appear in a moment.") },
                                    onFailure = { error ->
                                        if (error is kotlinx.coroutines.CancellationException) throw error
                                        MenuNotice("Couldn’t Refresh", error.message ?: "Jellyfin didn’t accept the refresh. Try again in a moment.")
                                    },
                                )
                                working = false
                            }
                        }
                    }
                },
                onEditImages = onEditImages?.let { open ->
                    {
                        onDismiss()
                        open(current.item)
                    }
                },
                onDeleteFromLibrary = onDeleteFromLibrary?.let { { confirmDelete = true } },
            )
        }
    }
}

@Composable
private fun TitleMorePanel(
    hazeState: ZelefinHazeState,
    request: TitleMoreRequest,
    usesSilo: Boolean,
    skipCinemaIntros: Boolean,
    onDismiss: () -> Unit,
    onPlay: () -> Unit,
    onOpen: () -> Unit,
    onToggleWatched: () -> Unit,
    onDownload: () -> Unit,
    onToggleFavorite: () -> Unit,
    onNotice: (MenuNotice) -> Unit,
    onToggleSkipCinema: () -> Unit,
    onCollections: (() -> Unit)?,
    onAddSubtitles: (() -> Unit)?,
    onHideFromHome: (() -> Unit)?,
    isAdmin: Boolean = false,
    onPlayElsewhere: (() -> Unit)? = null,
    onSyncPlay: (() -> Unit)? = null,
    onRefreshMetadata: (() -> Unit)? = null,
    onEditImages: (() -> Unit)? = null,
    onDeleteFromLibrary: (() -> Unit)? = null,
) {
    val item = request.item
    val showGoTo = request.context != TitleMenuContext.Episode
    val library = request.context == TitleMenuContext.Detail
    val showRemote = library && !usesSilo
    val showSync = showRemote && item.kind.usesVideoPlayer
    val showRefresh = isAdmin && onRefreshMetadata != null
    val showAdminRemote = isAdmin && showRemote
    val showAdmin = showRefresh || showAdminRemote
    val screenHeight = LocalConfiguration.current.screenHeightDp.dp
    val menuWidth = when {
        onHideFromHome != null -> 320.dp
        library -> 292.dp
        else -> 250.dp
    }
    Box(Modifier.fillMaxSize()) {
        Box(
            Modifier
                .fillMaxSize()
                .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }, onClick = onDismiss),
        )
        Column(
            Modifier
                .offset {
                    val width = menuWidth.roundToPx()
                    val gap = 8.dp.roundToPx()
                    var rows = 4 + if (showGoTo) 1 else 0
                    if (onAddSubtitles != null) rows += 1
                    if (onHideFromHome != null) rows += 1
                    var rules = 0
                    if (library) {
                        rows += 1
                        if (showRemote) rows += 1
                        if (showSync) rows += 1
                        if (showAdmin) {
                            rules += 1
                            if (showRefresh) rows += 1
                            if (showAdminRemote) rows += 2
                        }
                        if (showRemote) {
                            rows += 1
                            rules += 1
                        }
                    }
                    val natural = rows * 44.dp.roundToPx() + rules * 9.dp.roundToPx() + 12.dp.roundToPx()
                    val menuHeight = natural.coerceAtMost((screenHeight - 24.dp).roundToPx())
                    val below = request.anchor.bottom + gap
                    val dockClear = (screenHeight - DockContentReserve).roundToPx()
                    val y = if (below + menuHeight > dockClear) {
                        (request.anchor.top - gap - menuHeight).toInt()
                    } else {
                        below.toInt()
                    }
                    IntOffset(
                        x = (request.anchor.right - width).toInt().coerceAtLeast(16.dp.roundToPx()),
                        y = y.coerceAtLeast(8.dp.roundToPx()),
                    )
                }
                .width(menuWidth)
                .heightIn(max = screenHeight - 24.dp)
                .zelefinGlassChrome(hazeState, ZelefinOverlayShape)
                .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) {}
                .verticalScroll(rememberScrollState())
                .padding(vertical = 6.dp),
        ) {
            MoreRow(if (item.kind == MediaKind.Episode) "Play Episode" else "Play", Icons.Filled.PlayArrow, onPlay)
            if (showGoTo) {
                val show = item.kind == MediaKind.Episode || item.kind == MediaKind.Season || item.kind == MediaKind.Series
                MoreRow(if (show) "Go to Show" else "Go to Movie", if (show) Icons.Outlined.LiveTv else Icons.Outlined.Movie, onOpen)
            }
            MoreRow(
                if (item.isWatched) "Mark as Unwatched" else "Mark as Watched",
                if (item.isWatched) Icons.Outlined.VisibilityOff else Icons.Outlined.CheckCircle,
                onToggleWatched,
            )
            val downloadControl = app.zelefin.client.downloads.ZelefinDownloads.state.collectAsState().value.control(item)
            if (downloadControl != app.zelefin.client.downloads.DownloadControlState.Unavailable) {
                MoreRow(
                    downloadControl.menuTitle,
                    when (downloadControl) {
                        is app.zelefin.client.downloads.DownloadControlState.Downloading -> Icons.Outlined.StopCircle
                        app.zelefin.client.downloads.DownloadControlState.Downloaded -> Icons.Filled.CheckCircle
                        else -> Icons.Outlined.Download
                    },
                    onDownload,
                )
            }
            MoreRow(
                if (item.isFavorite) "Remove from Favorites" else "Add to Favorites",
                if (item.isFavorite) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder,
                onToggleFavorite,
            )
            if (onHideFromHome != null) {
                val surface = if (request.context == TitleMenuContext.NextUp) {
                    JellyfinEnhancedHomeSurface.NextUp
                } else {
                    JellyfinEnhancedHomeSurface.ContinueWatching
                }
                MoreRow(JellyfinEnhancedHomeHide.menuTitle(surface), Icons.Outlined.RemoveCircleOutline, onHideFromHome)
            }
            if (onAddSubtitles != null) {
                MoreRow("Add Subtitles", Icons.Outlined.ClosedCaption, onAddSubtitles)
            }
            if (library && onCollections != null) {
                MoreRow("Add to Collection…", Icons.Outlined.Folder, onClick = onCollections)
                if (showRemote) {
                    MoreRow("Play on Another Device…", Icons.Outlined.ConnectedTv, onClick = {
                        plusGated(app.zelefin.client.ZelefinPlus.Feature.Sessions, onNotice, onPlayElsewhere)
                    })
                }
                if (showSync) {
                    MoreRow("Play in SyncPlay…", Icons.Outlined.Groups, onClick = {
                        plusGated(app.zelefin.client.ZelefinPlus.Feature.SyncPlay, onNotice, onSyncPlay)
                    })
                }
                if (showAdmin) {
                    MenuHairline()
                    if (showRefresh) {
                        MoreRow("Refresh Metadata", Icons.Outlined.Refresh, onClick = {
                            plusGated(app.zelefin.client.ZelefinPlus.Feature.AdminTools, onNotice, onRefreshMetadata)
                        })
                    }
                    if (showAdminRemote) {
                        MoreRow("Edit Images…", Icons.Outlined.Image, onClick = {
                            plusGated(app.zelefin.client.ZelefinPlus.Feature.AdminTools, onNotice, onEditImages)
                        })
                        MoreRow(
                            "Delete from Library…",
                            Icons.Outlined.Delete,
                            onClick = { plusGated(app.zelefin.client.ZelefinPlus.Feature.AdminTools, onNotice, onDeleteFromLibrary) },
                            destructive = true,
                        )
                    }
                }
                if (showRemote) {
                    MenuHairline()
                    MoreRow(
                        "Skip Cinema Intros",
                        if (skipCinemaIntros) Icons.Outlined.Check else null,
                        onToggleSkipCinema,
                    )
                }
            }
        }
    }
}

private fun plusGated(feature: app.zelefin.client.ZelefinPlus.Feature, onNotice: (MenuNotice) -> Unit, action: (() -> Unit)?) {
    if (!app.zelefin.client.ZelefinPlus.allows(feature)) onNotice(plusNotice(feature)) else action?.invoke()
}

@Composable
internal fun MenuHairline() {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .height(0.5.dp)
            .background(Color.White.copy(alpha = 0.16f)),
    )
}

@Composable
internal fun MoreRow(
    title: String,
    icon: ImageVector?,
    onClick: () -> Unit,
    destructive: Boolean = false,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val tint = if (destructive) Color(0xFFFF453A) else DockInactive
    Row(
        Modifier
            .fillMaxWidth()
            .height(44.dp)
            .padding(horizontal = 6.dp)
            .clip(RoundedCornerShape(22.dp))
            .background(if (pressed) DockSelectedFill else Color.Transparent)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, color = tint, fontFamily = ZelefinFont, fontSize = 17.sp, maxLines = 1, modifier = Modifier.weight(1f))
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(20.dp))
        } else {
            Box(Modifier.size(20.dp))
        }
    }
}
