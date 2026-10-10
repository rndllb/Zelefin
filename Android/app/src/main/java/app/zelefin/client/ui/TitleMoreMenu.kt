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
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.heightIn
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
import androidx.compose.material.icons.outlined.PlaylistAdd
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.LiveTv
import androidx.compose.material.icons.outlined.Movie
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.text.style.TextOverflow
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
    onToggleWatchlist: ((MediaItem) -> Unit)? = null,
    onIdentify: ((MediaItem) -> Unit)? = null,
    onEditMetadata: ((MediaItem) -> Unit)? = null,
    onDownloadSeason: ((MediaItem) -> Unit)? = null,
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
                            if (target != null) startDownload(target)
                            onDismiss()
                        }
                        is app.zelefin.client.downloads.DownloadControlState.Downloading -> {
                            app.zelefin.client.downloads.ZelefinDownloads.pause(current.item)
                            onDismiss()
                        }
                        is app.zelefin.client.downloads.DownloadControlState.Paused -> {
                            app.zelefin.client.downloads.ZelefinDownloads.resume(current.item)
                            onDismiss()
                        }
                        app.zelefin.client.downloads.DownloadControlState.Downloaded -> downloadRemoval = target
                        app.zelefin.client.downloads.DownloadControlState.Unavailable -> Unit
                    }
                },
                onDownloadSeason = if (
                    onDownloadSeason != null &&
                    (current.item.kind == MediaKind.Series || current.item.kind == MediaKind.Season)
                ) {
                    {
                        onDismiss()
                        onDownloadSeason.invoke(current.item)
                    }
                } else {
                    null
                },
                onToggleFavorite = {
                    onDismiss()
                    onToggleFavorite(current.item)
                },
                onToggleWatchlist = onToggleWatchlist?.let { toggle ->
                    {
                        onDismiss()
                        toggle(current.item)
                    }
                },
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
                onIdentify = onIdentify?.let { open ->
                    {
                        onDismiss()
                        open(current.item)
                    }
                },
                onEditMetadata = onEditMetadata?.let { open ->
                    {
                        onDismiss()
                        open(current.item)
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
    onDownloadSeason: (() -> Unit)? = null,
    onToggleFavorite: () -> Unit,
    onToggleWatchlist: (() -> Unit)? = null,
    onToggleSkipCinema: () -> Unit,
    onCollections: (() -> Unit)?,
    onAddSubtitles: (() -> Unit)?,
    onHideFromHome: (() -> Unit)?,
    isAdmin: Boolean = false,
    onPlayElsewhere: (() -> Unit)? = null,
    onSyncPlay: (() -> Unit)? = null,
    onRefreshMetadata: (() -> Unit)? = null,
    onIdentify: (() -> Unit)? = null,
    onEditMetadata: (() -> Unit)? = null,
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
    AnchoredMenuFrame(
        request.anchor,
        alignTrailing = true,
        onDismiss = onDismiss,
        clearBottom = dockContentReserve(),
    ) {
        Column(
            Modifier
                .zelefinGlassChrome(hazeState, ZelefinMenuShape)
                .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) {}
                .heightIn(max = screenHeight - 24.dp)
                .verticalScroll(rememberScrollState())
                .zelefinMenuWidth()
                .padding(vertical = 4.dp),
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
                        is app.zelefin.client.downloads.DownloadControlState.Paused -> Icons.Outlined.Download
                        app.zelefin.client.downloads.DownloadControlState.Downloaded -> Icons.Filled.CheckCircle
                        else -> Icons.Outlined.Download
                    },
                    onDownload,
                )
            }
            if (onDownloadSeason != null) {
                MoreRow(
                    if (item.kind == MediaKind.Season) "Download Season" else "Download Series",
                    Icons.Outlined.Download,
                    onDownloadSeason,
                )
            }
            MoreRow(
                if (item.isFavorite) "Remove from Favorites" else "Add to Favorites",
                if (item.isFavorite) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder,
                onToggleFavorite,
            )
            if (onToggleWatchlist != null && !usesSilo) {
                MoreRow(
                    if (item.isWatchlisted) "Remove from Watchlist" else "Add to Watchlist",
                    Icons.Outlined.PlaylistAdd,
                    onToggleWatchlist,
                )
            }
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
                    MoreRow("Play on Another Device…", Icons.Outlined.ConnectedTv, onClick = { onPlayElsewhere?.invoke() })
                }
                if (showSync) {
                    MoreRow("Play in SyncPlay…", Icons.Outlined.Groups, onClick = { onSyncPlay?.invoke() })
                }
                if (showAdmin) {
                    MenuHairline()
                    if (showRefresh) {
                        MoreRow("Refresh Metadata", Icons.Outlined.Refresh, dismissOnClick = false, onClick = { onRefreshMetadata?.invoke() })
                    }
                    if (showAdminRemote) {
                        if (onIdentify != null) {
                            MoreRow("Identify…", Icons.Outlined.Search, onClick = onIdentify)
                        }
                        if (onEditMetadata != null) {
                            MoreRow("Edit Metadata…", Icons.Outlined.Image, onClick = onEditMetadata)
                        }
                        MoreRow("Edit Images…", Icons.Outlined.Image, onClick = { onEditImages?.invoke() })
                        MoreRow(
                            "Delete from Library…",
                            Icons.Outlined.Delete,
                            onClick = { onDeleteFromLibrary?.invoke() },
                            destructive = true,
                        )
                    }
                }
                if (showRemote) {
                    MenuHairline()
                    MoreRow(
                        "Skip Cinema Intros",
                        if (skipCinemaIntros) Icons.Outlined.Check else null,
                        {
                            onToggleSkipCinema()
                            onDismiss()
                        },
                    )
                }
            }
        }
    }
}

@Composable
internal fun MenuHairline() {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .height(0.5.dp)
            .background(MaterialTheme.colorScheme.outline),
    )
}

@Composable
internal fun MoreRow(
    title: String,
    icon: ImageVector?,
    onClick: () -> Unit,
    destructive: Boolean = false,
    dismissOnClick: Boolean = true,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val run = LocalMenuAction.current
    val textTint = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface
    val iconTint = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface
    Row(
        Modifier
            .fillMaxWidth()
            .height(44.dp)
            .padding(horizontal = 4.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(if (pressed) MaterialTheme.colorScheme.surfaceContainerHighest else Color.Transparent)
            .clickable(interactionSource = interaction, indication = null) {
                if (dismissOnClick) run(onClick) else onClick()
            }
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(20.dp), contentAlignment = Alignment.Center) {
            if (icon != null) {
                Icon(icon, contentDescription = null, tint = iconTint, modifier = Modifier.size(20.dp))
            }
        }
        Spacer(Modifier.width(12.dp))
        Text(
            title,
            color = textTint,
            fontFamily = ZelefinFont,
            fontSize = 17.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
    }
}
