package app.zelefin.client.cast

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Cast
import androidx.compose.material.icons.rounded.CastConnected
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Forward10
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Replay10
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.client.ui.ZelefinFont
import app.zelefin.core.PlaybackPlan
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.SessionManagerListener
import kotlinx.coroutines.delay

@Composable
fun CastRouteButton(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val connected = rememberCastConnected()
    Icon(
        if (connected) Icons.Rounded.CastConnected else Icons.Rounded.Cast,
        contentDescription = "Cast",
        tint = Color.White,
        modifier = modifier
            .size(40.dp)
            .clip(CircleShape)
            .clickable { ZelefinCast.showChooser(context) }
            .padding(8.dp),
    )
}

@Composable
fun rememberCastConnected(): Boolean {
    val context = LocalContext.current
    var connected by remember { mutableStateOf(ZelefinCast.isConnected(context)) }
    DisposableEffect(context) {
        val manager = ZelefinCast.context(context)?.sessionManager
        val listener = object : SessionManagerListener<CastSession> {
            override fun onSessionStarted(session: CastSession, sessionId: String) { connected = true }
            override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) { connected = true }
            override fun onSessionEnded(session: CastSession, error: Int) { connected = false }
            override fun onSessionSuspended(session: CastSession, reason: Int) { connected = false }
            override fun onSessionStarting(session: CastSession) = Unit
            override fun onSessionStartFailed(session: CastSession, error: Int) { connected = false }
            override fun onSessionEnding(session: CastSession) = Unit
            override fun onSessionResumeFailed(session: CastSession, error: Int) { connected = false }
            override fun onSessionResuming(session: CastSession, sessionId: String) = Unit
        }
        manager?.addSessionManagerListener(listener, CastSession::class.java)
        connected = ZelefinCast.isConnected(context)
        onDispose { manager?.removeSessionManagerListener(listener, CastSession::class.java) }
    }
    return connected
}

@Composable
fun CastRemoteSurface(
    plan: PlaybackPlan,
    artworkUrl: String?,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    var playing by remember { mutableStateOf(true) }
    var position by remember { mutableDoubleStateOf(plan.startTimeSeconds) }
    var duration by remember { mutableDoubleStateOf(plan.item.runtime ?: 0.0) }
    var volume by remember { mutableDoubleStateOf(ZelefinCast.session(context)?.volume ?: 0.5) }
    LaunchedEffect(plan.streamUrl) {
        ZelefinCast.load(context, plan, artworkUrl)
    }
    LaunchedEffect(Unit) {
        while (true) {
            val client = ZelefinCast.remote(context)
            val status = client?.mediaStatus
            if (status != null) {
                playing = status.playerState == com.google.android.gms.cast.MediaStatus.PLAYER_STATE_PLAYING
                position = status.streamPosition / 1000.0
                val length = status.mediaInfo?.streamDuration ?: 0L
                if (length > 0) duration = length / 1000.0
                volume = ZelefinCast.session(context)?.volume ?: volume
            }
            delay(400)
        }
    }
    Box(modifier.fillMaxSize().background(Color(0xFF111111))) {
        Column(
            Modifier
                .align(Alignment.Center)
                .padding(28.dp)
                .fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Icon(Icons.Rounded.CastConnected, contentDescription = null, tint = Color.White, modifier = Modifier.size(36.dp))
            Spacer(Modifier.height(16.dp))
            Text(
                ZelefinCast.titleFor(plan.item),
                color = Color.White,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.SemiBold,
                fontSize = 20.sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(8.dp))
            Text("Playing on TV", color = Color.White.copy(alpha = 0.62f), fontFamily = ZelefinFont, fontSize = 14.sp)
            Spacer(Modifier.height(28.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(28.dp), verticalAlignment = Alignment.CenterVertically) {
                CastIcon(Icons.Rounded.Replay10) { ZelefinCast.seek(context, (position - 10).coerceAtLeast(0.0)) }
                Box(
                    Modifier
                        .size(72.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.12f))
                        .clickable {
                            if (playing) ZelefinCast.pause(context) else ZelefinCast.play(context)
                            playing = !playing
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        if (playing) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                        contentDescription = if (playing) "Pause" else "Play",
                        tint = Color.White,
                        modifier = Modifier.size(36.dp),
                    )
                }
                CastIcon(Icons.Rounded.Forward10) { ZelefinCast.seek(context, position + 10) }
            }
            Spacer(Modifier.height(24.dp))
            Slider(
                value = if (duration > 0) (position / duration).toFloat().coerceIn(0f, 1f) else 0f,
                onValueChange = { fraction ->
                    val time = fraction * duration
                    position = time
                    ZelefinCast.seek(context, time)
                },
                colors = SliderDefaults.colors(thumbColor = Color.White, activeTrackColor = Color.White, inactiveTrackColor = Color.White.copy(0.24f)),
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(8.dp))
            Text("Volume", color = Color.White.copy(alpha = 0.62f), fontFamily = ZelefinFont, fontSize = 13.sp)
            Slider(
                value = volume.toFloat().coerceIn(0f, 1f),
                onValueChange = {
                    volume = it.toDouble()
                    ZelefinCast.setVolume(context, volume)
                },
                colors = SliderDefaults.colors(thumbColor = Color.White, activeTrackColor = Color.White, inactiveTrackColor = Color.White.copy(0.24f)),
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(16.dp))
            Row(
                Modifier
                    .clip(RoundedCornerShape(50))
                    .background(Color.White.copy(alpha = 0.12f))
                    .clickable {
                        ZelefinCast.stop(context)
                        onClose()
                    }
                    .padding(horizontal = 18.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(Icons.Rounded.Stop, contentDescription = null, tint = Color.White, modifier = Modifier.size(18.dp))
                Text("Stop Casting", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold)
            }
        }
        Row(
            Modifier
                .align(Alignment.TopStart)
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Rounded.Close,
                contentDescription = "Close",
                tint = Color.White,
                modifier = Modifier
                    .size(44.dp)
                    .clip(CircleShape)
                    .clickable(onClick = onClose)
                    .padding(10.dp),
            )
            Spacer(Modifier.weight(1f))
            CastRouteButton()
        }
    }
}

@Composable
private fun CastIcon(icon: androidx.compose.ui.graphics.vector.ImageVector, onClick: () -> Unit) {
    Icon(
        icon,
        contentDescription = null,
        tint = Color.White,
        modifier = Modifier
            .size(44.dp)
            .clip(CircleShape)
            .clickable(onClick = onClick)
            .padding(8.dp),
    )
}

fun Context.castArtwork(plan: PlaybackPlan): String? = plan.item.backdropUrl ?: plan.item.posterUrl
