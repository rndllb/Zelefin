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
import androidx.compose.foundation.horizontalScroll
import app.zelefin.client.PlaybackPreferences
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
import android.net.Uri
import androidx.activity.result.PickVisualMediaRequest
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.KeyboardArrowUp
import androidx.compose.material.icons.outlined.PersonAdd
import androidx.compose.material.icons.outlined.PhotoCamera
import androidx.compose.material.icons.outlined.Wifi
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.lifecycle.viewmodel.compose.viewModel
import app.zelefin.client.ZelefinModel
import app.zelefin.client.ZelefinPlus
import app.zelefin.client.network.HomeNetwork
import app.zelefin.client.network.HomeNetworkProfile
import app.zelefin.core.ArtworkDiskKey
import app.zelefin.core.SavedSession
import coil.imageLoader
import coil.memory.MemoryCache
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

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
        SettingsLink(
            "Network",
            Icons.Outlined.Wifi,
            if (state.localServerUrl != null) "Using the local address" else "How this phone reaches the server",
        ) { onTopic("network") }
        SettingsLink("Cache", Icons.Outlined.Storage, "Posters and saved home data") { onTopic("cache") }
        SettingsLink("Interface", Icons.Outlined.Settings, "Accent color and Home rows") { onTopic("interface") }
        SettingsHeader("Zelefin")
        SettingsLink("Zelefin Plus", Icons.Outlined.Star, if (ZelefinPlus.UNLOCKED) "Included" else "Free") { onTopic("plus") }
        SettingsLink("About", Icons.Outlined.Info, "0.1.0 (6)") { onTopic("about") }
    }
}

@Composable
fun ProfileScreen(state: ZelefinUiState, onBack: () -> Unit) {
    val session = state.session
    val model: ZelefinModel = viewModel()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val haze = LocalZelefinHaze.current
    val silo = session?.usesSilo == true
    var uploading by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<Pair<String, Boolean>?>(null) }
    var removing by remember { mutableStateOf<SavedSession?>(null) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri: Uri? ->
        val current = session ?: return@rememberLauncherForActivityResult
        if (uri == null) return@rememberLauncherForActivityResult
        uploading = true
        status = null
        scope.launch {
            val oldKey = avatarImageUrl(current)?.let(ArtworkDiskKey::key)
            runCatching { model.updateProfilePhoto(uri) }
                .onSuccess {
                    oldKey?.let { key ->
                        context.imageLoader.memoryCache?.remove(MemoryCache.Key(key))
                        withContext(Dispatchers.IO) { context.imageLoader.diskCache?.remove(key) }
                    }
                    status = "Profile picture updated." to false
                }
                .onFailure { status = (it.message ?: "The server did not accept the photo.") to true }
            uploading = false
        }
    }
    PresentZelefinOverlay(visible = removing != null && haze != null) {
        val hazeState = haze ?: return@PresentZelefinOverlay
        val account = removing ?: return@PresentZelefinOverlay
        ZelefinGlassConfirm(
            hazeState = hazeState,
            title = "Remove ${account.userName}?",
            message = "This user leaves this phone. Sign in again to add them back.",
            confirmLabel = "Remove",
            destructive = true,
            onConfirm = {
                removing = null
                model.removeAccount(account)
            },
            onDismiss = { removing = null },
        )
    }
    SettingsPage(title = "Profile", onBack = onBack) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            val choosePhoto = {
                if (!uploading) picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
            }
            Box(Modifier.size(104.dp)) {
                AccountAvatar(session, onClick = { if (!silo) choosePhoto() }, diameter = 104.dp)
                if (uploading) {
                    Box(Modifier.size(104.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.48f)), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(24.dp))
                    }
                }
                if (!silo && session != null) {
                    Box(
                        Modifier
                            .align(Alignment.BottomEnd)
                            .size(32.dp)
                            .clip(CircleShape)
                            .background(Color.White)
                            .clickable(onClick = choosePhoto),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.Outlined.PhotoCamera, contentDescription = "Change Profile Picture", tint = Color.Black, modifier = Modifier.size(16.dp))
                    }
                }
            }
            Spacer(Modifier.height(16.dp))
            Text(session?.profileName?.takeIf { silo } ?: session?.userName ?: "Account", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 28.sp)
            Text(
                if (silo) "Silo account" else "Jellyfin account",
                color = Secondary,
                fontFamily = ZelefinFont,
                fontSize = 15.sp,
            )
            status?.let { (text, error) ->
                Text(
                    text,
                    color = if (error) Color(0xFFFF6B6B) else Secondary,
                    fontFamily = ZelefinFont,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 13.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(top = 10.dp),
                )
            }
        }
        Spacer(Modifier.height(22.dp))
        SettingsCard {
            InfoLine("Server", session?.displayServer ?: "—")
            InfoLine("Address", session?.serverUrl ?: "—")
            session?.profileName?.let { InfoLine("Profile", it) }
        }
        SettingsHeader(if (silo) "Accounts" else "Users")
        session?.let { current ->
            AccountCard(current, subtitle = "Signed in", current = true, onClick = null, onRemove = null)
            Spacer(Modifier.height(8.dp))
        }
        state.accounts.filter { it.accountId != session?.accountId }.forEach { account ->
            AccountCard(
                account,
                subtitle = if (account.displayServer == session?.displayServer) "On this phone" else account.displayServer,
                current = false,
                onClick = { model.switchAccount(account) },
                onRemove = { removing = account },
            )
            Spacer(Modifier.height(8.dp))
        }
        SettingsCard(onClick = {
            model.resetAddAccount()
            model.openSettingsTopic(AddAccountTopicId)
        }) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Icon(Icons.Outlined.PersonAdd, contentDescription = null, tint = ZelefinCyan, modifier = Modifier.size(22.dp))
                Text(if (silo) "Add Account" else "Add User", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, modifier = Modifier.weight(1f))
                Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = Caption)
            }
        }
        SettingsFooter(
            if (silo) {
                "Saved logins stay on this phone. People on a login are household profiles, not extra accounts."
            } else {
                "Add another person on ${session?.displayServer ?: "this server"}. Saved users stay on this phone."
            },
        )
    }
}

@Composable
private fun AccountCard(account: SavedSession, subtitle: String, current: Boolean, onClick: (() -> Unit)?, onRemove: (() -> Unit)?) {
    SettingsCard(onClick = onClick) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            AccountAvatarImage(account, 40.dp)
            Column(Modifier.weight(1f)) {
                Text(account.profileName?.takeIf { account.usesSilo } ?: account.userName, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                Text(subtitle, color = Secondary, fontFamily = ZelefinFont, fontSize = 13.sp)
            }
            if (current) {
                Icon(Icons.Outlined.Check, contentDescription = "Signed in", tint = ZelefinCyan, modifier = Modifier.size(20.dp))
            } else if (onRemove != null) {
                Box(Modifier.size(32.dp).clip(CircleShape).clickable(onClick = onRemove), contentAlignment = Alignment.Center) {
                    Icon(Icons.Outlined.Close, contentDescription = "Remove ${account.userName}", tint = Caption, modifier = Modifier.size(18.dp))
                }
            }
        }
    }
}

/** iOS `AddAccountView`: sign in another user; Silo logins then pick a household profile. */
@Composable
private fun AddAccountTopic(state: ZelefinUiState) {
    val model: ZelefinModel = viewModel()
    val add = state.addAccount
    val silo = state.session?.usesSilo == true
    val label = if (silo) "Add Account" else "Add User"
    var url by remember { mutableStateOf(state.session?.serverUrl.orEmpty()) }
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var pin by remember { mutableStateOf("") }
    DisposableEffect(Unit) { onDispose { model.resetAddAccount() } }
    val pending = add.pending
    if (pending != null) {
        SettingsHeader("Who’s watching")
        SettingsCard {
            pending.profiles.forEachIndexed { index, profile ->
                if (index > 0) CardDivider()
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clickable(enabled = !add.busy) {
                            pin = ""
                            model.chooseAddedProfile(profile)
                        }
                        .padding(vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(profile.name, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                        val tags = listOfNotNull("Primary".takeIf { profile.isPrimary }, "Kids".takeIf { profile.isChild }, "PIN".takeIf { profile.hasPin })
                        if (tags.isNotEmpty()) Text(tags.joinToString(" · "), color = Caption, fontFamily = ZelefinFont, fontSize = 13.sp)
                    }
                    if (add.pinFor?.id == profile.id) Icon(Icons.Outlined.Lock, contentDescription = null, tint = ZelefinCyan, modifier = Modifier.size(18.dp))
                }
            }
        }
        add.pinFor?.let { profile ->
            Spacer(Modifier.height(12.dp))
            SettingsCard {
                LoginField(
                    label = "PIN FOR ${profile.name.uppercase()}",
                    value = pin,
                    icon = Icons.Outlined.Lock,
                    onChange = { pin = it.filter(Char::isDigit) },
                    placeholder = "PIN",
                    password = true,
                    keyboard = KeyboardType.NumberPassword,
                    ime = ImeAction.Go,
                    onIme = { if (pin.isNotEmpty()) model.submitAddedPin(pin) },
                )
                Spacer(Modifier.height(12.dp))
                SettingsButton("Continue", primary = true, destructive = false, enabled = pin.isNotEmpty(), busy = add.busy) { model.submitAddedPin(pin) }
            }
        }
        Spacer(Modifier.height(12.dp))
        SettingsButton("Cancel", primary = false, destructive = false, enabled = !add.busy, busy = false, onClick = model::resetAddAccount)
        add.message?.let { AddAccountMessage(it) }
        SettingsFooter("Continue Watching, recommendations, and watched flags follow the profile you pick.")
        return
    }
    SettingsHeader("Server")
    SettingsCard {
        LoginField(
            label = "SERVER",
            value = url,
            icon = Icons.Outlined.Link,
            onChange = { url = it },
            placeholder = "https://media.example.com",
            keyboard = KeyboardType.Uri,
            ime = ImeAction.Next,
        )
    }
    SettingsFooter(
        if (silo) {
            "New accounts are added on the Silo server you’re already using. After you sign in, pick a household profile."
        } else {
            "New users are added on the server you’re already using. Enter another address to add a user on a different Jellyfin server."
        },
    )
    SettingsHeader("Sign In")
    val canSubmit = url.isNotBlank() && username.isNotBlank() && password.isNotEmpty() && !add.busy
    SettingsCard {
        LoginField(
            label = if (silo) "USERNAME OR EMAIL" else "USERNAME",
            value = username,
            icon = Icons.Outlined.Person,
            onChange = { username = it },
            placeholder = if (silo) "Username or email" else "Username",
            keyboard = if (silo) KeyboardType.Email else KeyboardType.Text,
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
            keyboard = KeyboardType.Password,
            ime = ImeAction.Go,
            onIme = { if (canSubmit) model.addAccount(url, username, password) },
        )
        Spacer(Modifier.height(16.dp))
        SettingsButton(label, primary = true, destructive = false, enabled = canSubmit, busy = add.busy) {
            model.addAccount(url, username, password)
        }
        add.message?.let { AddAccountMessage(it) }
    }
}

@Composable
private fun AddAccountMessage(text: String) {
    Text(text, color = Color(0xFFFF6B6B), fontFamily = ZelefinFont, fontSize = 14.sp, modifier = Modifier.padding(top = 12.dp))
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
        AddAccountTopicId -> if (state.session?.usesSilo == true) "Add Account" else "Add User"
        else -> "Settings"
    }
    SettingsPage(title = title, onBack = onBack) {
        when (id) {
            "playback" -> PlaybackTopic()
            "cache" -> CacheTopic()
            "sessions" -> SessionsTopic(state)
            "about" -> AboutTopic(state)
            "plus" -> PlusTopic()
            AddAccountTopicId -> AddAccountTopic(state)
            "notifications" -> NotificationsTopic(state, plugins)
            "plugins" -> PluginsTopic(state, plugins)
            "network" -> NetworkTopic(state)
            "interface" -> InterfaceTopic()
            else -> Text("Nothing to change here yet.", color = Secondary, fontFamily = ZelefinFont)
        }
    }
}

@Composable
private fun PlaybackTopic() {
    val context = LocalContext.current
    var autoplay by remember { mutableStateOf(PlaybackPreferences.autoplayNext(context)) }
    var back by remember { mutableStateOf(PlaybackPreferences.skipBackward(context)) }
    var forward by remember { mutableStateOf(PlaybackPreferences.skipForward(context)) }
    var rate by remember { mutableStateOf(PlaybackPreferences.defaultRate(context)) }
    var audio by remember { mutableStateOf(PlaybackPreferences.audioLanguage(context)) }
    var subtitles by remember { mutableStateOf(PlaybackPreferences.subtitleLanguage(context)) }
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
                    PlaybackPreferences.setAutoplayNext(context, it)
                },
                colors = SwitchDefaults.colors(checkedTrackColor = ZelefinCyan, checkedThumbColor = Color.Black),
            )
        }
    }
    SettingsHeader("Skip Buttons")
    SettingsCard {
        PlaybackChoices("Skip back", PlaybackPreferences.skipIntervals.map { it to "${it}s" }, back) {
            back = it
            PlaybackPreferences.setSkipBackward(context, it)
        }
        PlaybackChoices("Skip forward", PlaybackPreferences.skipIntervals.map { it to "${it}s" }, forward) {
            forward = it
            PlaybackPreferences.setSkipForward(context, it)
        }
    }
    SettingsHeader("Speed")
    SettingsCard {
        PlaybackChoices("Default speed", PlaybackPreferences.speeds.map { it to PlaybackPreferences.speedTitle(it) }, rate) {
            rate = it
            PlaybackPreferences.setDefaultRate(context, it)
        }
    }
    SettingsHeader("Languages")
    SettingsCard {
        PlaybackChoices("Audio", listOf(PlaybackPreferences.AUTOMATIC to "Automatic") + PlaybackLanguages, audio) {
            audio = it
            PlaybackPreferences.setAudioLanguage(context, it)
        }
        PlaybackChoices(
            "Subtitles",
            listOf(PlaybackPreferences.AUTOMATIC to "Automatic", PlaybackPreferences.OFF to "Off") + PlaybackLanguages,
            subtitles,
        ) {
            subtitles = it
            PlaybackPreferences.setSubtitleLanguage(context, it)
        }
    }
    SettingsFooter("Automatic follows each title's default tracks. You can still switch tracks from the player's More menu.")
}

private val PlaybackLanguages = listOf(
    "en" to "English",
    "es" to "Spanish",
    "fr" to "French",
    "de" to "German",
    "it" to "Italian",
    "pt" to "Portuguese",
    "ja" to "Japanese",
    "ko" to "Korean",
    "zh" to "Chinese",
)

@Composable
private fun <T> PlaybackChoices(title: String, options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit) {
    Column(Modifier.padding(vertical = 6.dp)) {
        Text(title, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
        Row(
            Modifier
                .padding(top = 8.dp)
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            options.forEach { (value, label) ->
                val on = value == selected
                Text(
                    label,
                    color = if (on) Color.Black else Color.White,
                    fontFamily = ZelefinFont,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 14.sp,
                    modifier = Modifier
                        .clip(RoundedCornerShape(50))
                        .background(if (on) ZelefinCyan else Color.White.copy(alpha = 0.10f))
                        .clickable { onSelect(value) }
                        .padding(horizontal = 14.dp, vertical = 8.dp),
                )
            }
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

private enum class CacheClear { Artwork, Saved }

private val SavedDataFolders = listOf("HomeSnapshots", "CatalogSnapshots", "ItemDetailSnapshots")

@Composable
private fun CacheTopic() {
    val context = LocalContext.current
    val model: ZelefinModel = viewModel()
    val scope = rememberCoroutineScope()
    val haze = LocalZelefinHaze.current
    val root = remember { File(context.cacheDir, "Zelefin") }
    var sizes by remember { mutableStateOf<Map<String, Long>>(emptyMap()) }
    var revision by remember { mutableStateOf(0) }
    var confirm by remember { mutableStateOf<CacheClear?>(null) }
    LaunchedEffect(revision) {
        sizes = withContext(Dispatchers.IO) {
            (listOf("Artwork") + SavedDataFolders).associateWith { folderBytes(File(root, it)) }
        }
    }
    PresentZelefinOverlay(visible = confirm != null && haze != null) {
        val hazeState = haze ?: return@PresentZelefinOverlay
        val target = confirm ?: return@PresentZelefinOverlay
        ZelefinGlassConfirm(
            hazeState = hazeState,
            title = if (target == CacheClear.Artwork) "Clear Artwork?" else "Clear Saved Home Data?",
            message = if (target == CacheClear.Artwork) {
                "Posters and backdrops download again as you browse."
            } else {
                "Home, Movies, Shows, and title pages reload from the server."
            },
            confirmLabel = "Clear",
            destructive = true,
            onConfirm = {
                confirm = null
                scope.launch {
                    withContext(Dispatchers.IO) {
                        when (target) {
                            CacheClear.Artwork -> context.imageLoader.diskCache?.clear()
                            CacheClear.Saved -> SavedDataFolders.forEach { File(root, it).deleteRecursively() }
                        }
                    }
                    if (target == CacheClear.Artwork) context.imageLoader.memoryCache?.clear() else model.refreshLibrary()
                    revision += 1
                }
            },
            onDismiss = { confirm = null },
        )
    }
    val artwork = sizes["Artwork"] ?: 0L
    SettingsHeader("Images")
    SettingsCard {
        InfoLine("Artwork", formatBytes(artwork))
        Spacer(Modifier.height(14.dp))
        SettingsButton("Clear Artwork", primary = false, destructive = true, enabled = artwork > 0, busy = false) { confirm = CacheClear.Artwork }
    }
    SettingsFooter("Posters, backdrops, logos, and profile pictures saved on this phone.")
    val saved = SavedDataFolders.sumOf { sizes[it] ?: 0L }
    SettingsHeader("Saved Home Data")
    SettingsCard {
        InfoLine("Home", formatBytes(sizes["HomeSnapshots"] ?: 0L))
        InfoLine("Catalogs", formatBytes(sizes["CatalogSnapshots"] ?: 0L))
        InfoLine("Title Pages", formatBytes(sizes["ItemDetailSnapshots"] ?: 0L))
        Spacer(Modifier.height(14.dp))
        SettingsButton("Clear Saved Home Data", primary = false, destructive = true, enabled = saved > 0, busy = false) { confirm = CacheClear.Saved }
    }
    SettingsFooter("Home rows, library catalogs, and title pages saved so Zelefin opens right away.")
}

@Composable
private fun SessionsTopic(state: ZelefinUiState) {
    val session = state.session
    if (session != null && !session.usesSilo) {
        SessionsPanel(session)
        return
    }
    SettingsCard {
        InfoLine("User", session?.userName ?: "—")
        InfoLine("Server", session?.displayServer ?: "—")
        InfoLine("Device", Build.MODEL ?: "Android")
        InfoLine("App", "Zelefin 0.1.0 (6)")
    }
    Text(
        "Silo manages its sessions in the Silo admin console.",
        color = Caption,
        fontFamily = ZelefinFont,
        fontSize = 13.sp,
        modifier = Modifier.padding(start = 8.dp, end = 8.dp, top = 8.dp),
    )
}

@Composable
private fun AboutTopic(state: ZelefinUiState) {
    val context = LocalContext.current
    fun open(url: String) {
        runCatching {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
    SettingsCard {
        InfoLine("Version", "0.1.0 (6)")
        InfoLine("Server", state.session?.displayServer ?: "—")
        InfoLine("Backend", if (state.session?.usesSilo == true) "Silo" else "Jellyfin")
    }
    SettingsFooter("A native Jellyfin and Silo client for Android.")
    Spacer(Modifier.height(14.dp))
    SettingsCard {
        LinkRow("Privacy Policy") { open("https://zelefin.app/privacy") }
        CardDivider()
        LinkRow("Terms of Use") { open("https://zelefin.app/terms") }
        CardDivider()
        LinkRow("zelefin.app") { open("https://zelefin.app") }
    }
}

@Composable
private fun LinkRow(title: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, modifier = Modifier.weight(1f))
        Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = Caption)
    }
}

/** Mirrors iOS `NetworkSettingsView` and `AccessGatewaySection`. */
@Composable
private fun NetworkTopic(state: ZelefinUiState) {
    val model: ZelefinModel = viewModel()
    val context = LocalContext.current
    val session = state.session
    var profile by remember(session?.accountId) { mutableStateOf(model.homeNetwork()) }
    var localText by remember(session?.accountId) { mutableStateOf(profile.localUrl) }
    var ssid by remember { mutableStateOf(HomeNetwork.currentSsid(context)) }
    var located by remember { mutableStateOf(HomeNetwork.hasLocationPermission(context)) }
    var manual by remember { mutableStateOf("") }
    var gatewayId by remember { mutableStateOf(state.gatewayId) }
    var gatewaySecret by remember { mutableStateOf(state.gatewaySecret) }
    fun save(next: HomeNetworkProfile) {
        profile = next
        model.saveHomeNetwork(next)
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        located = HomeNetwork.hasLocationPermission(context)
        ssid = HomeNetwork.currentSsid(context)
        model.refreshRoute()
    }
    fun askLocation() {
        permission.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
    }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        located = HomeNetwork.hasLocationPermission(context)
        ssid = HomeNetwork.currentSsid(context)
    }
    LaunchedEffect(state.localServerUrl) { ssid = HomeNetwork.currentSsid(context) }
    LaunchedEffect(localText) {
        delay(600)
        if (localText.trim() != profile.localUrl) save(profile.copy(localUrl = localText.trim()))
    }

    SettingsHeader("This Connection")
    SettingsCard {
        InfoLine("Remote URL", session?.serverUrl ?: "—")
        InfoLine("Active URL", state.localServerUrl ?: session?.serverUrl ?: "—")
        InfoLine("Wi-Fi", ssid ?: if (located) "Unavailable" else "Allow location to show the network name")
        InfoLine("Using", if (state.localServerUrl != null) "Local address" else "Remote address")
    }

    SettingsHeader("Home Network")
    SettingsCard {
        SettingsToggle("Auto-switch on home Wi-Fi", profile.autoSwitch) { on ->
            save(profile.copy(autoSwitch = on, localUrl = localText.trim()))
            if (on && !located) askLocation()
        }
        CardDivider()
        LoginField(
            label = "LOCAL URL",
            value = localText,
            icon = Icons.Outlined.Home,
            onChange = { localText = it },
            placeholder = if (session?.usesSilo == true) "http://192.168.1.100" else "http://192.168.1.100:8096",
            keyboard = KeyboardType.Uri,
            ime = ImeAction.Done,
        )
        if (localText.isNotBlank() && HomeNetwork.normalizedLocal(localText) == null) {
            Text("Enter an address like http://192.168.1.100:8096.", color = Color(0xFFFF6B6B), fontFamily = ZelefinFont, fontSize = 13.sp)
        }
    }
    SettingsFooter(
        "On a saved home network, Zelefin uses the local URL when it answers and the remote one everywhere else. With no saved networks, any Wi-Fi where the local URL answers counts as home.",
    )

    SettingsHeader("Home Wi-Fi")
    SettingsCard {
        if (profile.homeSsids.isEmpty()) {
            Text("No networks saved", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
            Text("Add a network so auto-switch knows when you’re home.", color = Caption, fontFamily = ZelefinFont, fontSize = 13.sp)
        } else {
            profile.homeSsids.forEachIndexed { index, name ->
                if (index > 0) CardDivider()
                Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Wifi, contentDescription = null, tint = ZelefinCyan, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.size(12.dp))
                    Text(name, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, modifier = Modifier.weight(1f))
                    Text(
                        "Remove",
                        color = Color(0xFFFF6B6B),
                        fontFamily = ZelefinFont,
                        fontWeight = FontWeight.Bold,
                        fontSize = 13.sp,
                        modifier = Modifier.clickable { save(profile.copy(homeSsids = profile.homeSsids - name)) }.padding(8.dp),
                    )
                }
            }
        }
        val current = ssid
        if (current != null && !HomeNetwork.isHome(current, profile.homeSsids)) {
            Spacer(Modifier.height(14.dp))
            SettingsButton("Add “$current”", primary = true, destructive = false, enabled = true, busy = false) {
                save(profile.copy(homeSsids = HomeNetwork.adding(current, profile.homeSsids)))
            }
        } else if (current == null) {
            CardDivider()
            LoginField(
                label = "NETWORK NAME",
                value = manual,
                icon = Icons.Outlined.Wifi,
                onChange = { manual = it },
                placeholder = "Network name",
                ime = ImeAction.Done,
            )
            SettingsButton("Add Network", primary = true, destructive = false, enabled = manual.isNotBlank(), busy = false) {
                save(profile.copy(homeSsids = HomeNetwork.adding(manual, profile.homeSsids)))
                manual = ""
            }
            if (!located) {
                Spacer(Modifier.height(10.dp))
                SettingsButton("Use Current Network", primary = false, destructive = false, enabled = true, busy = false, onClick = ::askLocation)
            }
        }
    }
    SettingsFooter("Android shares the Wi-Fi name with Zelefin only with location access and Location turned on.")

    SettingsHeader("Access Gateway")
    SettingsCard {
        LoginField(
            label = "CLIENT ID",
            value = gatewayId,
            icon = Icons.Outlined.Lock,
            onChange = { gatewayId = it },
            placeholder = "Client ID or token ID",
            ime = ImeAction.Next,
        )
        CardDivider()
        LoginField(
            label = "CLIENT SECRET",
            value = gatewaySecret,
            icon = Icons.Outlined.Lock,
            onChange = { gatewaySecret = it },
            placeholder = "Client secret or access token",
            password = true,
        )
        val changed = gatewayId.trim() != state.gatewayId || gatewaySecret.trim() != state.gatewaySecret
        Spacer(Modifier.height(14.dp))
        SettingsButton(if (changed) "Save" else "Saved", primary = changed, destructive = false, enabled = changed, busy = false) {
            model.saveGateway(gatewayId, gatewaySecret)
        }
    }
    SettingsFooter("Needed when the server sits behind Cloudflare Zero Trust or Pangolin. Zelefin sends these with every request.")
}
@Composable
private fun PlusTopic() {
    SettingsCard {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Icon(Icons.Outlined.Star, contentDescription = null, tint = ZelefinCyan, modifier = Modifier.size(28.dp))
            Column(Modifier.weight(1f)) {
                Text("Zelefin Plus", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 20.sp)
                Text(if (ZelefinPlus.UNLOCKED) "Included on Android" else "Free", color = Secondary, fontFamily = ZelefinFont, fontSize = 14.sp)
            }
        }
    }
    SettingsHeader("Included")
    SettingsCard {
        val features = listOf(
            ZelefinPlus.Feature.Downloads to "Save movies and episodes to watch offline.",
            ZelefinPlus.Feature.ExtraAccounts to "Keep more than one user on this phone and switch in a tap.",
            ZelefinPlus.Feature.Sessions to "See and control what’s playing on other devices.",
            ZelefinPlus.Feature.SyncPlay to "Watch together in sync with other Jellyfin users.",
            ZelefinPlus.Feature.AdminTools to "Users, scheduled tasks, and library scans for administrators.",
        )
        features.forEachIndexed { index, (feature, detail) ->
            if (index > 0) CardDivider()
            Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(
                        feature.title.replaceFirstChar { it.uppercase() },
                        color = Color.White,
                        fontFamily = ZelefinFont,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 16.sp,
                    )
                    Text(detail, color = Caption, fontFamily = ZelefinFont, fontSize = 13.sp)
                }
                if (ZelefinPlus.allows(feature)) {
                    Icon(Icons.Outlined.Check, contentDescription = "Included", tint = ZelefinCyan, modifier = Modifier.size(20.dp))
                } else {
                    Icon(Icons.Outlined.Lock, contentDescription = "Plus", tint = Caption, modifier = Modifier.size(18.dp))
                }
            }
        }
    }
    SettingsFooter(
        if (ZelefinPlus.UNLOCKED) {
            "Everything in Zelefin Plus is included on Android for now. Sign in, browsing, and playback are always free."
        } else {
            "Sign in, browsing, and playback are always free."
        },
    )
}

/** Mirrors the Android-relevant parts of iOS `TabCustomizationView`. */
@Composable
private fun InterfaceTopic() {
    val context = LocalContext.current
    SettingsHeader("Accent Color")
    SettingsCard {
        AccentPreferences.presets.chunked(4).forEach { row ->
            Row(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
                row.forEach { preset ->
                    val selected = preset.id == AccentPreferences.presetId
                    Column(
                        Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(12.dp))
                            .clickable { AccentPreferences.select(context, preset.id) }
                            .padding(vertical = 4.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Box(
                            Modifier
                                .size(44.dp)
                                .background(preset.color, RoundedCornerShape(10.dp))
                                .then(if (selected) Modifier.border(2.5.dp, Color.White, RoundedCornerShape(10.dp)) else Modifier),
                            contentAlignment = Alignment.Center,
                        ) {
                            if (selected) Icon(Icons.Outlined.Check, contentDescription = null, tint = Color.White, modifier = Modifier.size(18.dp))
                        }
                        Spacer(Modifier.height(6.dp))
                        Text(
                            preset.name,
                            color = if (selected) Color.White else Caption,
                            fontFamily = ZelefinFont,
                            fontSize = 11.sp,
                            maxLines = 1,
                        )
                    }
                }
                repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
    SettingsFooter("Accent color tints buttons, highlights, and icons throughout the app.")

    SettingsHeader("Home")
    SettingsCard {
        SettingsToggle("Featured hero", HomeLayoutPreferences.showsFeatured) { HomeLayoutPreferences.setShowsFeatured(context, it) }
        CardDivider()
        SettingsToggle("Combine Continue Watching and Next Up", HomeLayoutPreferences.mergeContinueAndNextUp) {
            HomeLayoutPreferences.setMergeContinueAndNextUp(context, it)
        }
    }
    SettingsFooter("The featured hero cycles through recently added titles at the top of Home. Combining puts Next Up episodes after Continue Watching in one row.")

    SettingsHeader("Home Rows")
    SettingsCard {
        val order = HomeLayoutPreferences.order
        order.forEachIndexed { index, row ->
            if (index > 0) CardDivider()
            val merged = HomeLayoutPreferences.mergeContinueAndNextUp && row == HomeRowKind.NextUp
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(row.title, color = if (merged) Caption else Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                    if (merged) Text("In Continue Watching", color = Caption, fontFamily = ZelefinFont, fontSize = 12.sp)
                }
                ReorderButton(Icons.Outlined.KeyboardArrowUp, "Move ${row.title} up", enabled = index > 0) {
                    HomeLayoutPreferences.move(context, row, -1)
                }
                ReorderButton(Icons.Outlined.KeyboardArrowDown, "Move ${row.title} down", enabled = index < order.lastIndex) {
                    HomeLayoutPreferences.move(context, row, 1)
                }
                Switch(
                    checked = row !in HomeLayoutPreferences.hidden,
                    onCheckedChange = { HomeLayoutPreferences.setVisible(context, row, it) },
                    colors = SwitchDefaults.colors(checkedTrackColor = ZelefinCyan, checkedThumbColor = Color.Black),
                )
            }
        }
        Spacer(Modifier.height(14.dp))
        SettingsButton("Reset Home Layout", primary = false, destructive = false, enabled = true, busy = false) {
            HomeLayoutPreferences.reset(context)
        }
    }
    SettingsFooter("Turn rows on or off and use the arrows to set their order on Home.")

    SettingsHeader("Dock")
    SettingsCard {
        Text(
            "Home, Movies, Shows, and Library stay in the dock. Search is the separate circle.",
            color = Secondary,
            fontFamily = ZelefinFont,
            fontSize = 15.sp,
        )
    }
}

@Composable
private fun ReorderButton(icon: ImageVector, description: String, enabled: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .size(36.dp)
            .clip(CircleShape)
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = description, tint = if (enabled) ZelefinCyan else Caption.copy(alpha = 0.3f), modifier = Modifier.size(22.dp))
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
