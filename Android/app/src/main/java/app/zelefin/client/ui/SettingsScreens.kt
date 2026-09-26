package app.zelefin.client.ui

import android.content.Context
import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.client.ZelefinUiState
import java.io.File

private val CardShape = RoundedCornerShape(28.dp)
private val Caption = Color.White.copy(alpha = 0.55f)
private val Secondary = Color.White.copy(alpha = 0.72f)

@Composable
fun SettingsScreen(
    state: ZelefinUiState,
    onBack: () -> Unit,
    onProfile: () -> Unit,
    onTopic: (String) -> Unit,
) {
    val session = state.session
    SettingsPage(title = "Settings", onBack = onBack) {
        SettingsCard(onClick = onProfile) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                AccountAvatar(session, onClick = onProfile, diameter = 48.dp)
                Column(Modifier.weight(1f)) {
                    Text(session?.userName ?: "Account", color = Color.White, fontFamily = Outfit, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
                    Text(
                        if (session?.usesSilo == true) "Silo account" else "Jellyfin account",
                        color = Secondary,
                        fontFamily = Outfit,
                        fontSize = 13.sp,
                    )
                }
                Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = Caption)
            }
        }
        SettingsHeader("Account")
        SettingsLink("Notifications", Icons.Outlined.Notifications, "Playback alerts for this account") { onTopic("notifications") }
        if (session?.usesSilo != true) {
            SettingsLink("Sessions", Icons.Outlined.PlayArrow, "Devices signed in to Jellyfin") { onTopic("sessions") }
        }
        SettingsHeader("Playback")
        SettingsLink("Playback", Icons.Outlined.PlayArrow, "Resume, skip, and the next episode") { onTopic("playback") }
        SettingsLink("Plugins", Icons.Outlined.Settings, "Intro Skipper and server plugins") { onTopic("plugins") }
        SettingsHeader("This Device")
        SettingsLink("Network", Icons.Outlined.Settings, "How this phone reaches the server") { onTopic("network") }
        SettingsLink("Cache", Icons.Outlined.Storage, "Posters and saved home data") { onTopic("cache") }
        SettingsLink("Interface", Icons.Outlined.Settings, "Home rows and the dock") { onTopic("interface") }
        SettingsHeader("Zelefin")
        SettingsLink("Zelefin Plus", Icons.Outlined.Star, "Free") { onTopic("plus") }
        SettingsLink("About", Icons.Outlined.Info, "0.1.0 (6)") { onTopic("about") }
    }
}

@Composable
fun ProfileScreen(state: ZelefinUiState, onBack: () -> Unit) {
    val session = state.session
    SettingsPage(title = "Profile", onBack = onBack) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            AccountAvatar(session, onClick = {}, diameter = 96.dp)
            Spacer(Modifier.height(16.dp))
            Text(session?.userName ?: "Account", color = Color.White, fontFamily = Outfit, fontWeight = FontWeight.Bold, fontSize = 28.sp)
            Text(
                if (session?.usesSilo == true) "Silo account" else "Jellyfin account",
                color = Secondary,
                fontFamily = Outfit,
                fontSize = 15.sp,
            )
        }
        Spacer(Modifier.height(22.dp))
        SettingsCard {
            InfoLine("Server", session?.displayServer ?: "—")
            InfoLine("Address", session?.serverUrl ?: "—")
            session?.profileName?.let { InfoLine("Profile", it) }
        }
    }
}

@Composable
fun SettingsTopicScreen(id: String, state: ZelefinUiState, onBack: () -> Unit) {
    val title = when (id) {
        "notifications" -> "Notifications"
        "sessions" -> "Sessions"
        "playback" -> "Playback"
        "plugins" -> "Plugins"
        "network" -> "Network"
        "cache" -> "Cache"
        "interface" -> "Interface"
        "plus" -> "Zelefin Plus"
        "about" -> "About"
        else -> "Settings"
    }
    SettingsPage(title = title, onBack = onBack) {
        when (id) {
            "playback" -> PlaybackTopic()
            "cache" -> CacheTopic()
            "sessions" -> SessionsTopic(state)
            "about" -> AboutTopic(state)
            "plus" -> Text(
                "Sign-in, browsing, and playback stay free. Downloads, extra accounts, and server tools are part of Zelefin Plus.",
                color = Secondary,
                fontFamily = Outfit,
                fontSize = 15.sp,
            )
            "notifications" -> Text(
                "Playback alerts will show up here once this install can register with the server.",
                color = Secondary,
                fontFamily = Outfit,
                fontSize = 15.sp,
            )
            "plugins" -> Text(
                "Intro Skipper and other server plugins will be listed here when the server reports them.",
                color = Secondary,
                fontFamily = Outfit,
                fontSize = 15.sp,
            )
            "network" -> NetworkTopic(state)
            "interface" -> Text(
                "Home, Movies, Shows, and Library stay in the dock. Search is the separate circle.",
                color = Secondary,
                fontFamily = Outfit,
                fontSize = 15.sp,
            )
            else -> Text("Nothing to change here yet.", color = Secondary, fontFamily = Outfit)
        }
    }
}

@Composable
private fun PlaybackTopic() {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("zelefin.playback", Context.MODE_PRIVATE) }
    var autoplay by remember { mutableStateOf(prefs.getBoolean("autoplay-next", true)) }
    SettingsCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Autoplay next episode", color = Color.White, fontFamily = Outfit, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                Text("Start the next episode when one finishes.", color = Caption, fontFamily = Outfit, fontSize = 13.sp)
            }
            Switch(
                checked = autoplay,
                onCheckedChange = {
                    autoplay = it
                    prefs.edit().putBoolean("autoplay-next", it).apply()
                },
                colors = SwitchDefaults.colors(checkedTrackColor = ZelefinCyan, checkedThumbColor = Color.Black),
            )
        }
    }
}

@Composable
private fun CacheTopic() {
    val context = LocalContext.current
    val root = remember { File(context.cacheDir, "Zelefin") }
    val rows = remember(root) {
        listOf("Artwork", "HomeSnapshots", "CatalogSnapshots", "ItemDetailSnapshots").map { name ->
            name to folderBytes(File(root, name))
        }
    }
    SettingsCard {
        rows.forEach { (name, bytes) ->
            InfoLine(name.replace("Snapshots", ""), formatBytes(bytes))
        }
    }
}

@Composable
private fun SessionsTopic(state: ZelefinUiState) {
    val session = state.session
    SettingsCard {
        InfoLine("User", session?.userName ?: "—")
        InfoLine("Server", session?.displayServer ?: "—")
        InfoLine("Device", Build.MODEL ?: "Android")
        InfoLine("App", "Zelefin 0.1.0 (6)")
    }
}

@Composable
private fun AboutTopic(state: ZelefinUiState) {
    SettingsCard {
        InfoLine("Version", "0.1.0 (6)")
        InfoLine("Server", state.session?.displayServer ?: "—")
        InfoLine("Backend", if (state.session?.usesSilo == true) "Silo" else "Jellyfin")
    }
}

@Composable
private fun NetworkTopic(state: ZelefinUiState) {
    SettingsCard {
        InfoLine("Server", state.session?.serverUrl ?: "—")
        InfoLine(
            "Access gateway",
            if (state.gatewayId.isNotBlank()) "On" else "Off",
        )
    }
}

@Composable
private fun SettingsPage(title: String, onBack: () -> Unit, content: @Composable () -> Unit) {
    val topInset = if (LocalZelefinInSheet.current) Modifier else Modifier.statusBarsPadding()
    Column(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .then(topInset)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp)
            .navigationBarsPadding()
            .padding(bottom = 28.dp),
    ) {
        Box(Modifier.fillMaxWidth().height(44.dp), contentAlignment = Alignment.Center) {
            Text(title, color = Color.White, fontFamily = Outfit, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            TextButton(onClick = onBack, modifier = Modifier.align(Alignment.CenterStart)) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back", tint = ZelefinCyan, modifier = Modifier.size(22.dp))
            }
        }
        Spacer(Modifier.height(8.dp))
        content()
    }
}

@Composable
private fun SettingsHeader(title: String) {
    Text(
        title,
        color = Caption,
        fontFamily = Outfit,
        fontSize = 13.sp,
        modifier = Modifier.padding(start = 8.dp, top = 22.dp, bottom = 8.dp),
    )
}

@Composable
private fun SettingsLink(title: String, icon: ImageVector, subtitle: String, onClick: () -> Unit) {
    SettingsCard(onClick = onClick) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Icon(icon, contentDescription = null, tint = ZelefinCyan, modifier = Modifier.size(22.dp))
            Column(Modifier.weight(1f)) {
                Text(title, color = Color.White, fontFamily = Outfit, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                Text(subtitle, color = Secondary, fontFamily = Outfit, fontSize = 13.sp)
            }
            Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = Caption)
        }
    }
    Spacer(Modifier.height(8.dp))
}

@Composable
private fun SettingsCard(onClick: (() -> Unit)? = null, content: @Composable () -> Unit) {
    val haze = LocalZelefinHaze.current
    Column(
        Modifier
            .fillMaxWidth()
            .then(
                if (haze != null) {
                    Modifier.zelefinGlassChrome(haze, CardShape)
                } else {
                    Modifier.background(DockFill, CardShape).border(0.5.dp, DockBorder, CardShape)
                },
            )
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(16.dp),
    ) { content() }
}

@Composable
private fun InfoLine(label: String, value: String) {
    Column(Modifier.padding(vertical = 6.dp)) {
        Text(label.uppercase(), color = Caption, fontFamily = Outfit, fontWeight = FontWeight.SemiBold, fontSize = 12.sp, letterSpacing = 0.6.sp)
        Text(value, color = Color.White, fontFamily = Outfit, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
    }
}

private fun folderBytes(directory: File): Long {
    if (!directory.exists()) return 0L
    return directory.walkTopDown().filter { it.isFile }.sumOf { it.length() }
}

private fun formatBytes(bytes: Long): String = when {
    bytes < 1024 -> "$bytes B"
    bytes < 1024 * 1024 -> "${bytes / 1024} KB"
    else -> "${bytes / (1024 * 1024)} MB"
}
