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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
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
import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind

enum class TitleMenuContext { Featured, ContinueWatching, NextUp, Episode, Detail }

internal data class MenuNotice(val title: String, val message: String)

private fun plusNotice(feature: String) = MenuNotice(
    "Zelefin Plus",
    "Zelefin Plus includes $feature. Sign in, browse, and Play stay free.",
)

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
) {
    val haze = LocalZelefinHaze.current
    PresentZelefinOverlay(visible = (request != null || note != null) && haze != null) {
        val hazeState = haze ?: return@PresentZelefinOverlay
        val current = request
        var menuNote by remember(current?.item?.id, current?.anchor) { mutableStateOf<MenuNotice?>(null) }
        val showing = note ?: menuNote
        if (showing != null) {
            ZelefinGlassAlert(
                hazeState = hazeState,
                title = showing.title,
                message = showing.message,
                onDismiss = {
                    if (note != null) onDismissNote() else menuNote = null
                },
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
                onDownload = { menuNote = plusNotice("Downloads") },
                onToggleFavorite = {
                    onDismiss()
                    onToggleFavorite(current.item)
                },
                onNotice = { menuNote = it },
                onToggleSkipCinema = onToggleSkipCinema,
                onCollections = onCollections,
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
) {
    val item = request.item
    val showGoTo = request.context != TitleMenuContext.Episode
    val library = request.context == TitleMenuContext.Detail
    val showRemote = library && !usesSilo
    val showSync = showRemote && item.kind.usesVideoPlayer
    val screenHeight = LocalConfiguration.current.screenHeightDp.dp
    val menuWidth = if (library) 292.dp else 250.dp
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
                    var rules = 0
                    if (library) {
                        rows += 1
                        if (showRemote) rows += 1
                        if (showSync) rows += 1
                        rows += 1
                        rules += 1
                        if (showRemote) {
                            rows += 3
                            rules += 1
                        }
                    }
                    val natural = rows * 44.dp.roundToPx() + rules * 9.dp.roundToPx() + 12.dp.roundToPx()
                    val menuHeight = natural.coerceAtMost((screenHeight - 24.dp).roundToPx())
                    val below = request.anchor.bottom + gap
                    val y = if (below + menuHeight > screenHeight.roundToPx()) {
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
            MoreRow("Download", Icons.Outlined.Download, onDownload)
            MoreRow(
                if (item.isFavorite) "Remove from Favorites" else "Add to Favorites",
                if (item.isFavorite) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder,
                onToggleFavorite,
            )
            if (library && onCollections != null) {
                MoreRow("Add to Collection…", Icons.Outlined.Folder, onClick = onCollections)
                if (showRemote) {
                    MoreRow("Play on Another Device…", Icons.Outlined.ConnectedTv, onClick = { onNotice(plusNotice("Sessions")) })
                }
                if (showSync) {
                    MoreRow("Play in SyncPlay…", Icons.Outlined.Groups, onClick = { onNotice(plusNotice("SyncPlay")) })
                }
                MenuHairline()
                MoreRow("Refresh Metadata", Icons.Outlined.Refresh, onClick = { onNotice(plusNotice("Admin Tools")) })
                if (showRemote) {
                    MoreRow("Edit Images…", Icons.Outlined.Image, onClick = { onNotice(plusNotice("Admin Tools")) })
                    MoreRow(
                        "Delete from Library…",
                        Icons.Outlined.Delete,
                        onClick = { onNotice(plusNotice("Admin Tools")) },
                        destructive = true,
                    )
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

@Composable
private fun MenuHairline() {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .height(0.5.dp)
            .background(Color.White.copy(alpha = 0.16f)),
    )
}

@Composable
private fun MoreRow(
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
        Text(title, color = tint, fontFamily = Outfit, fontSize = 17.sp, maxLines = 1, modifier = Modifier.weight(1f))
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(20.dp))
        } else {
            Box(Modifier.size(20.dp))
        }
    }
}
