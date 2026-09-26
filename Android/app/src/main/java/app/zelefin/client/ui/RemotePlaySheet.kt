package app.zelefin.client.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ConnectedTv
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.client.jellyfin.RemoteSession
import app.zelefin.client.jellyfin.clockLabel
import app.zelefin.core.MediaItem
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

private val RemoteCaption = Color.White.copy(alpha = 0.55f)

/** iOS `PlayOnDeviceSheet`: sends this title to another signed-in Jellyfin client. */
@Composable
internal fun RemotePlaySheet(
    item: MediaItem,
    onLoad: suspend () -> List<RemoteSession>,
    onPlay: suspend (RemoteSession, MediaItem) -> Unit,
    onClose: () -> Unit,
) {
    var targets by remember(item.id) { mutableStateOf(emptyList<RemoteSession>()) }
    var loading by remember(item.id) { mutableStateOf(true) }
    var reload by remember(item.id) { mutableIntStateOf(0) }
    var sendingId by remember(item.id) { mutableStateOf<String?>(null) }
    var error by remember(item.id) { mutableStateOf<String?>(null) }
    var sentTo by remember(item.id) { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(item.id, reload) {
        loading = true
        try {
            targets = onLoad()
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (failure: Throwable) {
            error = failure.message ?: "Jellyfin didn’t list connected devices."
        }
        loading = false
    }

    fun send(target: RemoteSession) {
        if (sendingId != null) return
        sendingId = target.id
        scope.launch {
            try {
                onPlay(target, item)
                sentTo = target.deviceName.ifBlank { target.client.ifBlank { "the other device" } }
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (failure: Throwable) {
                error = failure.message ?: "That device didn’t accept the title."
            }
            sendingId = null
        }
    }

    Column(Modifier.fillMaxSize()) {
        SheetBar(title = "Play On", leading = "Cancel", onLeading = onClose, trailing = "Refresh", onTrailing = { reload++ })
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            val resume = item.playbackPosition.takeIf { it > 5 }
            Text(
                if (resume != null) "${item.name} starts at ${clockLabel(resume)} on the device you pick." else "${item.name} starts on the device you pick.",
                color = RemoteCaption,
                fontFamily = ZelefinFont,
                fontSize = 13.sp,
                modifier = Modifier.padding(horizontal = 8.dp),
            )
            Column(Modifier.fillMaxWidth().clip(SheetGroupShape).background(SheetGroupFill)) {
                when {
                    loading && targets.isEmpty() -> Box(Modifier.fillMaxWidth().padding(18.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(22.dp))
                    }
                    targets.isEmpty() -> Text(
                        "No other devices are connected right now.",
                        color = RemoteCaption,
                        fontFamily = ZelefinFont,
                        fontSize = 16.sp,
                        modifier = Modifier.padding(16.dp),
                    )
                    else -> targets.forEachIndexed { index, target ->
                        if (index > 0) SheetGroupDivider()
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .clickable(enabled = sendingId == null) { send(target) }
                                .padding(horizontal = 16.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(Icons.Outlined.ConnectedTv, contentDescription = null, tint = ZelefinCyan, modifier = Modifier.size(22.dp))
                            Box(Modifier.width(12.dp))
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(target.deviceLabel.ifBlank { "Jellyfin client" }, color = Color.White, fontFamily = ZelefinFont, fontSize = 16.sp)
                                Text(
                                    if (target.isPlaying) "${target.userLabel} · ${target.title}" else target.userLabel,
                                    color = RemoteCaption,
                                    fontFamily = ZelefinFont,
                                    fontSize = 12.sp,
                                    maxLines = 1,
                                )
                            }
                            if (sendingId == target.id) {
                                Box(Modifier.width(8.dp))
                                CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
                            }
                        }
                    }
                }
            }
        }
    }

    val haze = LocalZelefinHaze.current
    PresentZelefinOverlay(visible = (error != null || sentTo != null) && haze != null) {
        val hazeState = haze ?: return@PresentZelefinOverlay
        if (error != null) {
            ZelefinGlassAlert(hazeState = hazeState, title = "Play On", message = error.orEmpty(), onDismiss = { error = null })
        } else {
            ZelefinGlassAlert(
                hazeState = hazeState,
                title = "Playing on ${sentTo.orEmpty()}",
                message = "${item.name} is starting there now.",
                onDismiss = {
                    sentTo = null
                    onClose()
                },
            )
        }
    }
}
