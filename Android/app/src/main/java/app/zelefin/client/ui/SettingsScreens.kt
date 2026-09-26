package app.zelefin.client.ui

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import app.zelefin.client.push.ZelefinPush
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
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import app.zelefin.client.PluginsController
import app.zelefin.client.PluginsUiState
import app.zelefin.client.ZelefinUiState
import app.zelefin.client.plugins.SiloRequestSource
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
                    Text(session?.userName ?: "Account", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
                    Text(
                        if (session?.usesSilo == true) "Silo account" else "Jellyfin account",
                        color = Secondary,
                        fontFamily = ZelefinFont,
                        fontSize = 13.sp,
                    )
                }
                Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = Caption)
            }
        }
        SettingsHeader("Account")
        SettingsLink("Notifications", Icons.Outlined.Notifications, "Lock-screen alerts from your server") { onTopic("notifications") }
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
            Text(session?.userName ?: "Account", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 28.sp)
            Text(
                if (session?.usesSilo == true) "Silo account" else "Jellyfin account",
                color = Secondary,
                fontFamily = ZelefinFont,
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
fun SettingsTopicScreen(id: String, state: ZelefinUiState, plugins: PluginsController, onBack: () -> Unit) {
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
                fontFamily = ZelefinFont,
                fontSize = 15.sp,
            )
            "notifications" -> NotificationsTopic(state, plugins)
            "plugins" -> PluginsTopic(state, plugins)
            "network" -> NetworkTopic(state)
            "interface" -> Text(
                "Home, Movies, Shows, and Library stay in the dock. Search is the separate circle.",
                color = Secondary,
                fontFamily = ZelefinFont,
                fontSize = 15.sp,
            )
            else -> Text("Nothing to change here yet.", color = Secondary, fontFamily = ZelefinFont)
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
                Text("Autoplay next episode", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                Text("Start the next episode when one finishes.", color = Caption, fontFamily = ZelefinFont, fontSize = 13.sp)
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

/** Mirrors iOS `NotificationSettingsView`. */
@Composable
private fun NotificationsTopic(state: ZelefinUiState, plugins: PluginsController) {
    val context = LocalContext.current
    val pluginState by plugins.state.collectAsState()
    var granted by remember { mutableStateOf(ZelefinPush.permissionGranted(context)) }
    var asked by remember { mutableStateOf(ZelefinPush.hasAskedPermission(context)) }
    LaunchedEffect(Unit) { plugins.refresh() }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { granted = ZelefinPush.permissionGranted(context) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        granted = ZelefinPush.permissionGranted(context)
        if (!ok) plugins.setPushEnabled(false) else plugins.registerPush()
    }
    fun enable(on: Boolean) {
        plugins.setPushEnabled(on)
        if (!on || granted) return
        val activity = context as? Activity
        val canAsk = ZelefinPush.needsRuntimePermission() && (
            !asked || activity?.shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS) == true
            )
        if (canAsk) {
            ZelefinPush.markAskedPermission(context)
            asked = true
            permission.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            context.startActivity(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }

    if (!pluginState.companionAvailable) {
        SettingsCard {
            PluginStatusRow("Zelefin plugin", installed = false)
            Text(
                when {
                    state.session?.usesSilo == true ->
                        "Lock-screen alerts need the Zelefin plugin on a Jellyfin server. This Silo server cannot install that plugin, so notifications are not available here."
                    pluginState.detecting -> "Checking this server for the Zelefin plugin…"
                    else ->
                        "Install the Zelefin plugin on this Jellyfin server to get lock-screen alerts. The plugin watches the library and can notify this phone when titles are added, a stream starts, someone comes online, a scheduled task begins, or a Seerr request comes in — including while Zelefin is closed."
                },
                color = Secondary,
                fontFamily = ZelefinFont,
                fontSize = 14.sp,
                modifier = Modifier.padding(top = 6.dp),
            )
            if (state.session?.usesSilo != true && !pluginState.isAdmin && !pluginState.detecting) {
                Text(
                    "Ask a server administrator to add the Zelefin catalog in Jellyfin and install the plugin, or sign in with an admin account.",
                    color = Caption,
                    fontFamily = ZelefinFont,
                    fontSize = 13.sp,
                    modifier = Modifier.padding(top = 10.dp),
                )
            }
        }
        SettingsFooter(
            if (state.session?.usesSilo == true) {
                "Connect a Jellyfin server with the Zelefin plugin to receive notifications."
            } else {
                "In Jellyfin, open Dashboard → Plugins → Catalog, install Zelefin, then restart Jellyfin. You do not set up Firebase or paste a key on the server."
            },
        )
        return
    }

    val on = pluginState.pushEnabled && granted
    SettingsCard {
        SettingsToggle("Notifications", on, ::enable)
        if (on && ZelefinPush.isConfigured) {
            Spacer(Modifier.height(14.dp))
            SettingsButton(
                "Send Test Alert",
                primary = false,
                destructive = false,
                enabled = true,
                busy = pluginState.pushBusy,
                onClick = plugins::sendTestPush,
            )
        }
        pluginState.pushMessage?.let { message ->
            Text(
                message,
                color = if (message.startsWith("Sent")) Secondary else Color(0xFFFF6B6B),
                fontFamily = ZelefinFont,
                fontSize = 14.sp,
                modifier = Modifier.padding(top = 12.dp),
            )
        }
    }
    SettingsFooter(
        when {
            !ZelefinPush.isConfigured ->
                "This build of Zelefin was made without push setup, so the server cannot reach this phone yet."
            pluginState.pushEnabled && !granted && asked ->
                "Notifications are off in Android Settings. Turn them on for Zelefin so the plugin can deliver alerts for new titles, streams, users online, scheduled tasks, and Seerr requests."
            !granted ->
                "Zelefin asks Android for permission when you turn this on. The plugin then pushes new titles, streams, users online, scheduled tasks, and Seerr requests."
            else ->
                "The Zelefin plugin pushes lock-screen alerts for new titles, streams, users online, scheduled tasks, and Seerr requests while the app is open or closed. Restart Jellyfin after you install or remove the plugin."
        },
    )
}

@Composable
private fun PluginsTopic(state: ZelefinUiState, plugins: PluginsController) {
    val pluginState by plugins.state.collectAsState()
    LaunchedEffect(Unit) { plugins.refresh() }
    if (state.session?.usesSilo == true) {
        SiloRequestsSection(pluginState, plugins::setSiloSource)
        return
    }
    val jellyfin = pluginState.jellyfin
    SettingsHeader("Intro Skipper")
    SettingsCard {
        PluginStatusRow("Skip Intro / Outro", jellyfin.introSkipper)
        CardDivider()
        SettingsToggle("Automatically Skip Intros", pluginState.autoSkipIntro, plugins::setAutoSkipIntro)
        CardDivider()
        SettingsToggle("Automatically Skip Credits", pluginState.autoSkipCredits, plugins::setAutoSkipCredits)
    }
    SettingsFooter("Skip buttons appear during playback when the plugin is installed on this Jellyfin server.")

    SettingsHeader("Jellyfin Enhanced")
    SettingsCard { PluginStatusRow("Jellyfin Enhanced", jellyfin.enhanced) }
    SettingsFooter(
        "When this plugin is installed, you can remove titles from Continue Watching or Next Up without losing progress, and see reviews or awards on the title page.",
    )

    SettingsHeader("Notifications plugin")
    SettingsCard { PluginStatusRow("Zelefin", jellyfin.companion) }
    SettingsFooter(
        if (jellyfin.companion) {
            "This server has the Zelefin plugin. Lock-screen alerts from it reach this phone. Turn them on or off in Notifications."
        } else {
            "Notifications need the Zelefin plugin. Add the Zelefin catalog in Jellyfin, install it, then restart Jellyfin."
        },
    )

    SettingsHeader("Open Subtitles")
    SettingsCard { PluginStatusRow("Open Subtitles", jellyfin.openSubtitles) }
    SettingsFooter("When this plugin is installed, use More on a movie or episode to search Open Subtitles and save a file to the server.")

    SettingsHeader("Seerr")
    SeerrSignInCard(state, pluginState, plugins)
    SettingsFooter(
        "Jellyseerr or Seerr lets you request movies and shows that are missing from Jellyfin. Use your Jellyfin username and password. Search for a title, then tap Request.",
    )
}

@Composable
private fun SeerrSignInCard(state: ZelefinUiState, pluginState: PluginsUiState, plugins: PluginsController) {
    var url by remember { mutableStateOf(pluginState.seerrUrl) }
    var username by remember { mutableStateOf(state.session?.userName.orEmpty()) }
    var password by remember { mutableStateOf("") }
    val signedIn = pluginState.seerrName
    LaunchedEffect(signedIn) { if (signedIn != null) password = "" }
    SettingsCard {
        if (signedIn != null) {
            InfoLine("Server", pluginState.seerrUrl)
            CardDivider()
            InfoLine("Signed in as", signedIn)
            Spacer(Modifier.height(16.dp))
            SettingsButton("Sign Out", primary = false, destructive = true, enabled = true, busy = false, onClick = plugins::signOutSeerr)
        } else {
            LoginField(
                label = "SERVER",
                value = url,
                icon = Icons.Outlined.Link,
                onChange = { url = it },
                placeholder = "https://seerr.example.com",
                keyboard = KeyboardType.Uri,
                ime = ImeAction.Next,
            )
            CardDivider()
            LoginField(
                label = "USERNAME",
                value = username,
                icon = Icons.Outlined.Person,
                onChange = { username = it },
                placeholder = "Username or email",
                ime = ImeAction.Next,
            )
            CardDivider()
            LoginField(
                label = "PASSWORD",
                value = password,
                icon = Icons.Outlined.Lock,
                onChange = { password = it },
                placeholder = "Password",
                password = true,
                ime = ImeAction.Go,
                onIme = { if (url.isNotBlank() && username.isNotBlank() && password.isNotEmpty()) plugins.signInSeerr(url, username, password) },
            )
            Spacer(Modifier.height(16.dp))
            SettingsButton(
                "Sign In",
                primary = true,
                destructive = false,
                enabled = url.isNotBlank() && username.isNotBlank() && password.isNotEmpty(),
                busy = pluginState.seerrBusy,
                onClick = { plugins.signInSeerr(url, username, password) },
            )
        }
        pluginState.seerrMessage?.let { message ->
            val positive = message.startsWith("Signed in")
            Text(
                message,
                color = if (positive) Secondary else Color(0xFFFF6B6B),
                fontFamily = ZelefinFont,
                fontSize = 14.sp,
                modifier = Modifier.padding(top = 12.dp),
            )
        }
    }
}

@Composable
private fun SiloRequestsSection(pluginState: PluginsUiState, onSource: (SiloRequestSource) -> Unit) {
    val caps = pluginState.silo
    SettingsHeader("Requests")
    SettingsCard {
        PluginStatusRow("Seerr", caps.seerrPluginAvailable)
        CardDivider()
        PluginStatusRow("Sonarr & Radarr", caps.arrPluginAvailable)
        if (caps.seerrPluginAvailable && caps.arrPluginAvailable) {
            CardDivider()
            Text(
                "DISCOVER WITH",
                color = Caption,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.SemiBold,
                fontSize = 12.sp,
                letterSpacing = 0.6.sp,
                modifier = Modifier.padding(top = 6.dp, bottom = 4.dp),
            )
            SiloRequestSource.entries.forEach { source ->
                val selected = source == pluginState.siloSource
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clickable { onSource(source) }
                        .padding(vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(source.title, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, modifier = Modifier.weight(1f))
                    if (selected) Icon(Icons.Outlined.Check, contentDescription = "Selected", tint = ZelefinCyan, modifier = Modifier.size(20.dp))
                }
            }
        }
    }
    SettingsFooter(
        when {
            caps.seerrPluginAvailable && caps.arrPluginAvailable -> "Discover uses the plugin you pick. Silo handles the Seerr sign-in for you."
            caps.arrPluginAvailable -> "Discover uses this Silo server’s Sonarr and Radarr requests plugin."
            caps.seerrPluginAvailable -> "Discover uses this Silo server’s Seerr plugin. Silo handles the Seerr sign-in for you."
            caps.requestsEnabled -> "Requests are on for this Silo server. Discover is in Search."
            else -> "Install the Seerr plugin or the Sonarr & Radarr requests plugin on this Silo server to request titles from Search."
        },
    )
}

@Composable
private fun PluginStatusRow(title: String, installed: Boolean) {
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, modifier = Modifier.weight(1f))
        Text(
            if (installed) "Installed" else "Not on this server",
            color = if (installed) ZelefinCyan else Caption,
            fontFamily = ZelefinFont,
            fontWeight = FontWeight.SemiBold,
            fontSize = 14.sp,
        )
    }
}

@Composable
private fun SettingsToggle(title: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, modifier = Modifier.weight(1f))
        Switch(
            checked = checked,
            onCheckedChange = onChange,
            colors = SwitchDefaults.colors(checkedTrackColor = ZelefinCyan, checkedThumbColor = Color.Black),
        )
    }
}

@Composable
private fun SettingsButton(
    title: String,
    primary: Boolean,
    destructive: Boolean,
    enabled: Boolean,
    busy: Boolean,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(50)
    Box(
        Modifier
            .fillMaxWidth()
            .height(50.dp)
            .background(
                when {
                    primary -> Color.White.copy(alpha = if (enabled) 1f else 0.35f)
                    else -> Color.White.copy(alpha = 0.1f)
                },
                shape,
            )
            .clickable(enabled = enabled && !busy, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        if (busy) {
            CircularProgressIndicator(color = if (primary) Color.Black else Color.White, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
        } else {
            Text(
                title,
                color = when {
                    primary -> Color.Black
                    destructive -> Color(0xFFFF6B6B)
                    else -> Color.White
                },
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.SemiBold,
                fontSize = 16.sp,
            )
        }
    }
}

@Composable
private fun CardDivider() {
    Box(Modifier.fillMaxWidth().padding(vertical = 6.dp).height(0.5.dp).background(Color.White.copy(alpha = 0.12f)))
}

@Composable
private fun SettingsFooter(text: String) {
    Text(
        text,
        color = Caption,
        fontFamily = ZelefinFont,
        fontSize = 13.sp,
        modifier = Modifier.padding(start = 8.dp, end = 8.dp, top = 8.dp),
    )
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
            Text(title, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
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
        fontFamily = ZelefinFont,
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
                Text(title, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                Text(subtitle, color = Secondary, fontFamily = ZelefinFont, fontSize = 13.sp)
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
        Text(label.uppercase(), color = Caption, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 12.sp, letterSpacing = 0.6.sp)
        Text(value, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
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
