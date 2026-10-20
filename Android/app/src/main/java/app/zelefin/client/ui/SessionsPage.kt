package app.zelefin.client.ui

import androidx.activity.compose.BackHandler
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.VolumeDown
import androidx.compose.material.icons.automirrored.outlined.VolumeOff
import androidx.compose.material.icons.automirrored.outlined.VolumeUp
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.outlined.Forward10
import androidx.compose.material.icons.outlined.Replay10
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.client.jellyfin.JellyfinLibrary
import app.zelefin.client.jellyfin.RemoteSession
import app.zelefin.client.jellyfin.SessionControl
import app.zelefin.client.jellyfin.playbackSessions
import app.zelefin.client.jellyfin.reportedDeviceId
import app.zelefin.client.jellyfin.sendSessionControl
import app.zelefin.client.jellyfin.sendSessionMessage
import app.zelefin.core.SavedSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Live Jellyfin sessions with remote control (iOS `SessionsView` / `SessionDetailView`).
 * Renders inside the settings page sheet, where floating glass overlays and discs are not drawn, so everything is inline.
 */
@Composable
internal fun SessionsPanel(session: SavedSession?) {
    val saved = session ?: return
    val context = LocalContext.current
    val client = remember(saved.accountId, saved.serverUrl, saved.accessToken) {
        JellyfinLibrary(context.applicationContext, saved.serverUrl, saved.accessToken)
    }
    val localDevice = remember(client) { runCatching { client.reportedDeviceId }.getOrNull() }
    var sessions by remember(client) { mutableStateOf<List<RemoteSession>?>(null) }
    var loadError by remember(client) { mutableStateOf<String?>(null) }
    var selectedId by remember(client) { mutableStateOf<String?>(null) }
    var refreshTick by remember(client) { mutableIntStateOf(0) }

    LaunchedEffect(client, refreshTick, selectedId) {
        while (true) {
            try {
                sessions = client.playbackSessions()
                loadError = null
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (failure: Throwable) {
                loadError = failure.message ?: "Jellyfin didn’t list sessions."
            }
            delay(if (selectedId != null) 3_000 else 4_000)
        }
    }
    BackHandler(enabled = selectedId != null) { selectedId = null }

    val selected = selectedId?.let { id -> sessions?.firstOrNull { it.id == id } }
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        if (selectedId != null) {
            SessionBackRow { selectedId = null }
            if (selected == null) {
                SessionCard {
                    Text("This session has ended.", color = IOSColors.secondaryLabel, fontSize = 15.sp)
                }
            } else {
                SessionDetail(
                    session = selected,
                    saved = saved,
                    isThisDevice = selected.isThisDevice(localDevice),
                    client = client,
                    onChanged = { refreshTick++ },
                )
            }
            return@Column
        }
        val list = sessions
        when {
            list == null && loadError == null -> Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
                IOSSpinner(Modifier.size(24.dp))
            }
            list.isNullOrEmpty() -> SessionCard {
                Text(
                    loadError ?: "No one is connected to this server right now.",
                    color = IOSColors.secondaryLabel,
                    fontSize = 15.sp,
                )
            }
            else -> {
                val playing = list.filter { it.isPlaying }
                val connected = list.filterNot { it.isPlaying }
                if (playing.isNotEmpty()) {
                    SessionSectionLabel("Now Playing")
                    SessionCard(contentPadding = 6.dp) {
                        playing.forEachIndexed { index, item ->
                            if (index > 0) SessionDivider()
                            SessionRow(item, saved, item.isThisDevice(localDevice)) { selectedId = item.id }
                        }
                    }
                }
                if (connected.isNotEmpty()) {
                    SessionSectionLabel("Connected")
                    SessionCard(contentPadding = 6.dp) {
                        connected.forEachIndexed { index, item ->
                            if (index > 0) SessionDivider()
                            SessionRow(item, saved, item.isThisDevice(localDevice)) { selectedId = item.id }
                        }
                    }
                }
                Text(
                    "Updates every few seconds. Tap a session for details and remote control.",
                    color = IOSColors.secondaryLabel,
                    fontSize = 13.sp,
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
            }
        }
    }
}

@Composable
private fun SessionRow(session: RemoteSession, saved: SavedSession, isThisDevice: Boolean, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SessionArtwork(session, saved, 44.dp)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(session.title, style = SettingsRowText, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(session.userLabel, color = IOSColors.secondaryLabel, fontSize = 13.sp, maxLines = 1)
            Text(
                if (isThisDevice) "This device" else session.deviceLabel.ifBlank { session.deviceType ?: "Jellyfin client" },
                color = IOSColors.secondaryLabel,
                fontSize = 12.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (session.isPlaying) {
                Text(
                    "${if (session.isPaused) "Paused" else session.playMethod} · ${session.positionLabel}",
                    color = IOSColors.secondaryLabel,
                    fontSize = 12.sp,
                    maxLines = 1,
                )
                SessionProgress(session.progressFraction)
            }
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = IOSColors.secondaryLabel)
    }
}

@Composable
private fun SessionDetail(
    session: RemoteSession,
    saved: SavedSession,
    isThisDevice: Boolean,
    client: JellyfinLibrary,
    onChanged: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var busy by remember(session.id) { mutableStateOf<SessionControl?>(null) }
    var status by remember(session.id) { mutableStateOf<String?>(null) }
    var composing by remember(session.id) { mutableStateOf(false) }
    var message by remember(session.id) { mutableStateOf("") }
    var sending by remember(session.id) { mutableStateOf(false) }

    fun control(command: SessionControl) {
        if (busy != null) return
        busy = command
        scope.launch {
            try {
                client.sendSessionControl(session, command, saved.userId)
                status = null
                delay(400)
                onChanged()
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (failure: Throwable) {
                status = failure.message ?: "That client didn’t accept the command."
            }
            busy = null
        }
    }

    fun send() {
        if (sending || message.isBlank()) return
        sending = true
        scope.launch {
            try {
                client.sendSessionMessage(session.id, message)
                status = "Message sent to ${session.deviceName.ifBlank { session.userLabel }}."
                message = ""
                composing = false
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (failure: Throwable) {
                status = failure.message ?: "The message didn’t send."
            }
            sending = false
        }
    }

    SessionCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            SessionArtwork(session, saved, 64.dp)
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(session.title, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 20.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(
                    listOf(session.userLabel, if (isThisDevice) "This device" else session.deviceLabel).filter { it.isNotBlank() }.joinToString(" · "),
                    color = IOSColors.secondaryLabel,
                    fontSize = 13.sp,
                    maxLines = 2,
                )
                StatusChip(
                    when {
                        !session.isPlaying -> "Connected"
                        session.isPaused -> "Paused"
                        else -> "Playing"
                    },
                )
            }
        }
        if (session.isPlaying) {
            Spacer(Modifier.height(14.dp))
            SessionProgress(session.progressFraction)
            Spacer(Modifier.height(6.dp))
            Text(session.positionLabel, color = IOSColors.secondaryLabel, fontSize = 12.sp)
        }
        Spacer(Modifier.height(16.dp))
        if (session.canControl) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
                if (session.canSeek) ControlButton(Icons.Outlined.Replay10, "Back 10 seconds", busy == SessionControl.Back10) { control(SessionControl.Back10) }
                ControlButton(Icons.Filled.SkipPrevious, "Previous", busy == SessionControl.Previous) { control(SessionControl.Previous) }
                ControlButton(
                    if (session.isPaused || !session.isPlaying) Icons.Filled.PlayArrow else Icons.Filled.Pause,
                    if (session.isPaused) "Play" else "Pause",
                    busy == SessionControl.PlayPause,
                    large = true,
                ) { control(SessionControl.PlayPause) }
                ControlButton(Icons.Filled.SkipNext, "Next", busy == SessionControl.Next) { control(SessionControl.Next) }
                if (session.canSeek) ControlButton(Icons.Outlined.Forward10, "Forward 10 seconds", busy == SessionControl.Forward10) { control(SessionControl.Forward10) }
            }
            Spacer(Modifier.height(12.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
                if (session.supportsVolume) {
                    ControlButton(Icons.AutoMirrored.Outlined.VolumeDown, "Volume down", busy == SessionControl.VolumeDown) { control(SessionControl.VolumeDown) }
                    ControlButton(
                        if (session.isMuted) Icons.AutoMirrored.Outlined.VolumeOff else Icons.AutoMirrored.Outlined.VolumeUp,
                        if (session.isMuted) "Unmute" else "Mute",
                        busy == SessionControl.Mute,
                    ) { control(SessionControl.Mute) }
                    ControlButton(Icons.AutoMirrored.Outlined.VolumeUp, "Volume up", busy == SessionControl.VolumeUp) { control(SessionControl.VolumeUp) }
                }
                ControlButton(Icons.Filled.Stop, "Stop", busy == SessionControl.Stop) { control(SessionControl.Stop) }
            }
        } else {
            Text("This client does not accept remote control.", color = IOSColors.secondaryLabel, fontSize = 14.sp)
        }
        if (session.supportsMessages) {
            Spacer(Modifier.height(14.dp))
            if (composing) {
                Text("To ${session.deviceName.ifBlank { session.userLabel }}", color = IOSColors.secondaryLabel, fontSize = 12.sp)
                Spacer(Modifier.height(6.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(50))
                            .background(IOSColors.fill)
                            .padding(horizontal = 14.dp, vertical = 9.dp),
                    ) {
                        IOSTextField(value = message, onChange = { message = it }, placeholder = "Write a message", modifier = Modifier.fillMaxWidth())
                    }
                    Spacer(Modifier.width(10.dp))
                    if (sending) {
                        IOSSpinner(Modifier.size(20.dp))
                    } else {
                        PillButton("Send", enabled = message.isNotBlank()) { send() }
                    }
                }
                Spacer(Modifier.height(8.dp))
                Text(
                    "Cancel",
                    color = ZelefinCyan,
                    fontSize = 14.sp,
                    modifier = Modifier.clickable { composing = false }.padding(vertical = 4.dp),
                )
            } else {
                PillButton("Message", enabled = true) { composing = true }
            }
        }
        status?.let {
            Spacer(Modifier.height(10.dp))
            Text(it, color = IOSColors.secondaryLabel, fontSize = 13.sp)
        }
    }

    SessionSectionLabel("Playback")
    SessionCard {
        SessionFact("Status", if (!session.isPlaying) "Idle" else if (session.isPaused) "Paused" else "Playing")
        if (session.isPlaying) {
            SessionFact("Method", session.playMethod)
            SessionFact("Position", session.positionLabel)
        }
        session.volumeLevel?.let { SessionFact("Volume", if (session.isMuted) "Muted" else "$it%") }
    }
    SessionSectionLabel("Device")
    SessionCard {
        SessionFact("User", session.userLabel)
        if (session.client.isNotBlank()) SessionFact("Client", session.client)
        if (session.deviceName.isNotBlank()) SessionFact("Device", session.deviceName)
        session.deviceType?.takeIf { it.isNotBlank() }?.let { SessionFact("Type", it) }
        session.applicationVersion?.takeIf { it.isNotBlank() }?.let { SessionFact("Version", it) }
        session.remoteEndPoint?.takeIf { it.isNotBlank() }?.let { SessionFact("IP", it) }
        if (isThisDevice) SessionFact("Session", "This device")
    }
    if (session.transcoding.isNotEmpty()) {
        SessionSectionLabel("Transcoding")
        SessionCard {
            session.transcoding.forEach { (label, value) -> SessionFact(label, value) }
        }
    }
}

@Composable
private fun SessionArtwork(session: RemoteSession, saved: SavedSession, size: androidx.compose.ui.unit.Dp) {
    val item = session.nowPlaying
    if (item != null) {
        Box(
            Modifier
                .width(size * 2f / 3f)
                .height(size)
                .clip(RoundedCornerShape(6.dp))
                .background(IOSColors.fill),
        ) {
            CachedArtwork(
                urls = artworkCandidates(item, saved, landscape = false),
                contentDescription = item.name,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }
    } else {
        Box(
            Modifier
                .size(size)
                .clip(CircleShape)
                .background(ZelefinCyan.copy(alpha = 0.28f)),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                session.userLabel.firstOrNull()?.uppercaseChar()?.toString() ?: "?",
                color = ZelefinCyan,
                fontWeight = FontWeight.Bold,
                fontSize = (size.value * 0.4f).sp,
            )
        }
    }
}

@Composable
private fun SessionCard(contentPadding: androidx.compose.ui.unit.Dp = 16.dp, content: @Composable () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = SettingsGroupMargin)
            .clip(SettingsGroupShape)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .padding(contentPadding),
    ) { content() }
}

@Composable
private fun ControlButton(icon: ImageVector, description: String, busy: Boolean, large: Boolean = false, onClick: () -> Unit) {
    val accent = ZelefinCyan
    val onAccent = if (accent.luminance() > 0.6f) Color.Black else Color.White
    Box(
        Modifier
            .size(if (large) 60.dp else 46.dp)
            .clip(CircleShape)
            .background(if (large) accent else IOSColors.fill)
            .clickable(enabled = !busy, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        if (busy) {
            IOSSpinner(Modifier.size(18.dp), color = if (large) onAccent else IOSColors.spinner)
        } else {
            Icon(icon, contentDescription = null, tint = if (large) onAccent else Color.White, modifier = Modifier.size(if (large) 30.dp else 22.dp))
        }
    }
}

@Composable
private fun PillButton(label: String, enabled: Boolean, onClick: () -> Unit) {
    IOSCapsuleButton(label, onClick, prominent = label == "Send", enabled = enabled, height = 36.dp)
}

@Composable
private fun StatusChip(label: String) {
    val playing = label == "Playing"
    Text(
        label,
        color = if (playing) ZelefinCyan else IOSColors.secondaryLabel,
        fontWeight = FontWeight.SemiBold,
        fontSize = 12.sp,
        modifier = Modifier
            .padding(top = 2.dp)
            .clip(RoundedCornerShape(50))
            .background(if (playing) ZelefinCyan.copy(alpha = 0.22f) else IOSColors.fill)
            .padding(horizontal = 10.dp, vertical = 3.dp),
    )
}

@Composable
private fun SessionProgress(fraction: Float) {
    IOSProgressBar(fraction, Modifier.height(3.dp))
}

@Composable
private fun SessionFact(label: String, value: String) {
    Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).padding(vertical = 11.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = SettingsRowText)
        Spacer(Modifier.width(16.dp))
        Text(value, style = SettingsRowText.copy(color = IOSColors.secondaryLabel, textAlign = TextAlign.End), modifier = Modifier.weight(1f))
    }
}

@Composable
private fun SessionSectionLabel(text: String) {
    SettingsSectionLabel(text)
}

@Composable
private fun SessionDivider() {
    Box(Modifier.fillMaxWidth().padding(start = 66.dp).height(0.5.dp).background(IOSColors.separator))
}

@Composable
private fun SessionBackRow(onBack: () -> Unit) {
    Text(
        "All Sessions",
        color = ZelefinCyan,
        fontWeight = FontWeight.SemiBold,
        fontSize = 15.sp,
        modifier = Modifier
            .padding(horizontal = 16.dp)
            .clip(RoundedCornerShape(50))
            .clickable(onClick = onBack)
            .padding(vertical = 6.dp),
    )
}
