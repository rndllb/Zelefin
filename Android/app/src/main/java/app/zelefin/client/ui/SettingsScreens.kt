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
import app.zelefin.client.BuildConfig
import app.zelefin.client.push.ZelefinPush
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import app.zelefin.client.PlaybackPreferences
import app.zelefin.client.SubtitleAppearance
import app.zelefin.client.AdaptiveBitrateStore
import app.zelefin.client.BitrateProbeResult
import app.zelefin.client.NetworkPathSnapshot
import app.zelefin.client.JellyfinPlaybackPreferences
import app.zelefin.client.PlaybackLanguage
import app.zelefin.client.PlaybackQuality
import app.zelefin.client.SubtitlePlaybackModeChoices
import app.zelefin.client.summary
import app.zelefin.client.title
import androidx.compose.ui.draw.alpha
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.WindowInsets
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
import androidx.compose.material.icons.automirrored.outlined.List
import androidx.compose.material.icons.outlined.AdminPanelSettings
import androidx.compose.material.icons.outlined.Brush
import androidx.compose.material.icons.outlined.ClosedCaption
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
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

private val CardShape = ZelefinCardShape
private val Caption = ZelefinMuted
private val Secondary = ZelefinMuted

enum class SettingsBarAction { Done, Back, Cancel }

@Composable
fun SettingsScreen(
    state: ZelefinUiState,
    onBack: () -> Unit,
    onProfile: () -> Unit,
    onTopic: (String) -> Unit,
    bar: SettingsBarAction = SettingsBarAction.Done,
) {
    val session = state.session
    val model: ZelefinModel = viewModel()
    val pluginState by model.plugins.state.collectAsState()
    val showAdmin = session != null && !session.usesSilo && pluginState.isAdmin
    SettingsPage(title = "Settings", onBack = onBack, bar = bar) {
        SettingsGroup {
            SettingsProfileRow(session, onProfile)
        }
        SettingsGroup {
            SettingsNavRow("User Preferences", Icons.Outlined.Tune) { onTopic("user-preferences") }
            if (showAdmin) {
                SettingsGroupDivider()
                SettingsNavRow("Administration", Icons.Outlined.AdminPanelSettings) { onTopic("administration") }
            }
        }
        SettingsSectionLabel("Zelefin")
        SettingsGroup {
            SettingsNavRow("Plugins", Icons.Outlined.Settings) { onTopic("plugins") }
            SettingsGroupDivider()
            SettingsNavRow("Metadata", Icons.Outlined.Description) { onTopic("metadata") }
            SettingsGroupDivider()
            SettingsNavRow("Interface", Icons.Outlined.Settings) { onTopic("interface") }
            SettingsGroupDivider()
            SettingsNavRow("About", Icons.Outlined.Info, onClick = { onTopic("about") }, trailing = AppVersionLabel)
        }
    }
}

@Composable
fun ProfileScreen(state: ZelefinUiState, onBack: () -> Unit, bar: SettingsBarAction = SettingsBarAction.Done) {
    val session = state.session
    val model: ZelefinModel = viewModel()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
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
    removing?.let { account ->
        SettingsAlertDialog(
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
    SettingsPage(title = "Profile", onBack = onBack, bar = bar) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            val choosePhoto = {
                if (!uploading) picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
            }
            Box(Modifier.size(104.dp)) {
                AccountAvatar(session, onClick = { if (!silo) choosePhoto() }, diameter = 104.dp)
                if (uploading) {
                    Box(Modifier.size(104.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.48f)), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.size(24.dp))
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
            Text(session?.profileName?.takeIf { silo } ?: session?.userName ?: "Account", style = MaterialTheme.typography.headlineMedium)
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
                Icon(Icons.Outlined.PersonAdd, contentDescription = null, tint = MaterialTheme.colorScheme.onSurface, modifier = Modifier.size(22.dp))
                Text(if (silo) "Add Account" else "Add User", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
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
                Text(account.profileName?.takeIf { account.usesSilo } ?: account.userName, style = MaterialTheme.typography.titleMedium)
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
                        Text(profile.name, style = MaterialTheme.typography.titleMedium)
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
                SettingsTextField(
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
        SettingsTextField(
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
        SettingsTextField(
            label = if (silo) "USERNAME OR EMAIL" else "USERNAME",
            value = username,
            icon = Icons.Outlined.Person,
            onChange = { username = it },
            placeholder = if (silo) "Username or email" else "Username",
            keyboard = if (silo) KeyboardType.Email else KeyboardType.Text,
            ime = ImeAction.Next,
        )
        CardDivider()
        SettingsTextField(
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
fun SettingsTopicScreen(
    id: String,
    state: ZelefinUiState,
    plugins: PluginsController,
    onBack: () -> Unit,
    bar: SettingsBarAction = SettingsBarAction.Back,
) {
    val title = when (id) {
        "user-preferences" -> "User Preferences"
        "administration" -> "Administration"
        "appearance" -> "Appearance"
        "notifications" -> "Notifications"
        "sessions" -> "Sessions"
        "playback" -> "Playback"
        "subtitles" -> "Subtitles"
        "plugins" -> "Plugins"
        "metadata" -> "Metadata"
        "network" -> "Network"
        "cache" -> "Cache"
        "interface" -> "Interface"
        "about" -> "About"
        "syncplay" -> "SyncPlay"
        "users" -> "Users"
        "scheduled-tasks" -> "Scheduled Tasks"
        "activity" -> "Activity Log"
        "backups" -> "Backups"
        "branding" -> "Branding"
        AddAccountTopicId -> if (state.session?.usesSilo == true) "Add Account" else "Add User"
        else -> when {
            id.startsWith("user:") -> "User"
            id.startsWith("scheduled-task:") -> "Task"
            else -> "Settings"
        }
    }
    SettingsPage(title = title, onBack = onBack, bar = bar) {
        when (id) {
            "user-preferences" -> UserPreferencesTopic(state)
            "administration" -> AdministrationTopic()
            "appearance" -> AppearanceSettings()
            "playback" -> PlaybackTopic(state)
            "subtitles" -> SubtitleAppearanceTopic()
            "cache" -> CacheTopic()
            "metadata" -> MetadataTopic()
            "sessions" -> SessionsTopic(state)
            "about" -> AboutTopic(state)
            AddAccountTopicId -> AddAccountTopic(state)
            "notifications" -> NotificationsTopic(state, plugins)
            "plugins" -> PluginsTopic(state, plugins)
            "network" -> NetworkTopic(state)
            "interface" -> InterfaceTopic(state)
            "syncplay" -> SyncPlayTopic(state)
            "users" -> UsersTopic()
            "scheduled-tasks" -> ScheduledTasksTopic()
            "activity" -> ActivityLogTopic()
            "backups" -> BackupsTopic()
            "branding" -> BrandingTopic(state)
            else -> when {
                id.startsWith("user:") -> UserEditorTopic(id.removePrefix("user:"), state)
                id.startsWith("scheduled-task:") -> ScheduledTaskDetailTopic(id.removePrefix("scheduled-task:"))
                else -> Text("Nothing to change here yet.", color = Secondary, fontFamily = ZelefinFont)
            }
        }
    }
}

@Composable
private fun UserPreferencesTopic(state: ZelefinUiState) {
    val session = state.session
    val model: ZelefinModel = viewModel()
    SettingsNavGroup(
        buildList {
            add(SettingsHubItem("Notifications", icon = Icons.Outlined.Notifications) { model.openSettingsTopic("notifications") })
            if (session?.usesSilo != true) {
                add(SettingsHubItem("Sessions", icon = Icons.Outlined.PlayArrow) { model.openSettingsTopic("sessions") })
                add(SettingsHubItem("SyncPlay", icon = Icons.Outlined.Groups) { model.openSettingsTopic("syncplay") })
            }
            add(SettingsHubItem("Playback", icon = Icons.Outlined.PlayArrow) { model.openSettingsTopic("playback") })
            add(SettingsHubItem("Subtitles", icon = Icons.Outlined.ClosedCaption) { model.openSettingsTopic("subtitles") })
            add(SettingsHubItem("Appearance", icon = Icons.Outlined.Palette) { model.openSettingsTopic("appearance") })
        },
    )
    SettingsSectionLabel("This Device")
    SettingsNavGroup(
        listOf(
            SettingsHubItem("Network", icon = Icons.Outlined.Wifi) { model.openSettingsTopic("network") },
            SettingsHubItem("Cache", icon = Icons.Outlined.Storage) { model.openSettingsTopic("cache") },
        ),
    )
}

@Composable
private fun AdministrationTopic() {
    val model: ZelefinModel = viewModel()
    val scope = rememberCoroutineScope()
    var confirmScan by remember { mutableStateOf(false) }
    var scanMessage by remember { mutableStateOf<String?>(null) }
    if (confirmScan) {
        SettingsAlertDialog(
            title = "Scan all libraries?",
            message = "Jellyfin will look for new files and refresh metadata. This can take a while on a large server.",
            confirmLabel = "Scan",
            onConfirm = {
                confirmScan = false
                scope.launch {
                    scanMessage = runCatching { model.scanLibraries() }
                        .map { "Scan started. Jellyfin is looking for new files." }
                        .getOrElse { it.message ?: "Jellyfin could not start the scan." }
                }
            },
            onDismiss = { confirmScan = false },
        )
    }
    SettingsNavGroup(
        listOf(
            SettingsHubItem("Users", icon = Icons.Outlined.People) { model.openSettingsTopic("users") },
            SettingsHubItem("Scheduled Tasks", icon = Icons.Outlined.Schedule) { model.openSettingsTopic("scheduled-tasks") },
            SettingsHubItem("Activity Log", icon = Icons.AutoMirrored.Outlined.List) { model.openSettingsTopic("activity") },
            SettingsHubItem("Backups", icon = Icons.Outlined.Inventory2) { model.openSettingsTopic("backups") },
            SettingsHubItem("Branding", icon = Icons.Outlined.Brush) { model.openSettingsTopic("branding") },
            SettingsHubItem("Scan Libraries", icon = Icons.Outlined.Refresh) { confirmScan = true },
        ),
    )
}

/** Mirrors iOS `PlaybackSettingsView`: Languages, Quality, Watching. */
@Composable
private fun PlaybackTopic(state: ZelefinUiState) {
    val model: ZelefinModel = viewModel()
    val context = LocalContext.current
    val silo = state.session?.usesSilo == true
    var audio by remember { mutableStateOf(PlaybackPreferences.audioLanguage(context)) }
    var subtitles by remember { mutableStateOf(PlaybackPreferences.subtitleLanguage(context)) }
    var adaptive by remember { mutableStateOf(PlaybackPreferences.adaptiveBitrate(context)) }
    var quality by remember { mutableStateOf(PlaybackPreferences.selectedQuality(context)) }
    var rate by remember { mutableStateOf(PlaybackPreferences.defaultRate(context)) }
    var autoplay by remember { mutableStateOf(PlaybackPreferences.autoplayNext(context)) }
    var back by remember { mutableStateOf(PlaybackPreferences.skipBackward(context)) }
    var forward by remember { mutableStateOf(PlaybackPreferences.skipForward(context)) }
    var preferSdh by remember { mutableStateOf(PlaybackPreferences.preferSdh(context)) }
    var playerEngine by remember { mutableStateOf(PlaybackPreferences.playerEngine(context)) }
    var wifiOnly by remember { mutableStateOf(PlaybackPreferences.downloadWifiOnly(context)) }
    val languages = remember(context) { PlaybackLanguage.choices(context) }

    if (silo) {
        SettingsHeader("Languages")
        SettingsCard {
            SettingsMenuPicker(
                label = "Audio",
                choices = (listOf(PlaybackPreferences.AUTOMATIC) + languages).map { SettingsChoice(it, PlaybackLanguage.displayName(it)) },
                selected = audio,
                onSelect = {
                    audio = it
                    model.applyPlaybackLanguages(it, subtitles)
                },
            )
            SettingsCardDivider()
            SettingsMenuPicker(
                label = "Subtitles",
                choices = (listOf(PlaybackPreferences.AUTOMATIC, PlaybackPreferences.OFF) + languages)
                    .map { SettingsChoice(it, PlaybackLanguage.displayName(it)) },
                selected = subtitles,
                onSelect = {
                    subtitles = it
                    model.applyPlaybackLanguages(audio, it)
                },
            )
            SettingsCardDivider()
            SettingsToggleRow("Prefer SDH Subtitles", preferSdh, {
                preferSdh = it
                PlaybackPreferences.setPreferSdh(context, it)
            })
        }
        SettingsFooter("Automatic uses the title default. A language is used when that track exists. SDH prefers captions that describe music and sound.")
    } else {
        JellyfinPlaybackPreferencesSections(model, languages)
    }

    SettingsHeader("Quality")
    SettingsCard {
        SettingsToggleRow("Adaptive Bitrate", adaptive, {
            adaptive = it
            PlaybackPreferences.setAdaptiveBitrate(context, it)
        })
        SettingsCardDivider()
        SettingsMenuPicker(
            label = if (adaptive) "Maximum Quality" else "Quality",
            choices = PlaybackQuality.entries.map { SettingsChoice(it, it.title) },
            selected = quality,
            onSelect = {
                quality = it
                PlaybackPreferences.setSelectedQuality(context, it)
            },
        )
        SettingsCardDivider()
        PlaybackConnectionTest(model, signedIn = state.session != null, quality = quality)
    }
    SettingsFooter(
        when {
            adaptive && silo -> "Auto Direct Plays the original file. A lower Maximum Quality is the only start cap. Test Connection measures this path if playback later stalls."
            adaptive -> "Auto Direct Plays when the file fits this connection. Jellyfin transcodes when it does not. Test Connection measures this path."
            silo -> "Auto Direct Plays when the file fits this device. Lower quality asks Silo to transcode."
            else -> "Auto Direct Plays when the file fits this device. Lower quality asks Jellyfin to transcode."
        },
    )

    SettingsHeader("Watching")
    SettingsCard {
        SettingsMenuPicker(
            label = "Playback Speed",
            choices = PlaybackPreferences.speeds.map { SettingsChoice(it, PlaybackPreferences.speedTitle(it)) },
            selected = rate,
            onSelect = {
                rate = it
                PlaybackPreferences.setDefaultRate(context, it)
            },
        )
        SettingsCardDivider()
        SettingsToggleRow("Auto Play Next Episode", autoplay, {
            autoplay = it
            PlaybackPreferences.setAutoplayNext(context, it)
        })
        SettingsCardDivider()
        SettingsMenuPicker(
            label = "Skip Backward",
            choices = PlaybackPreferences.skipIntervals.map { SettingsChoice(it, PlaybackPreferences.intervalTitle(it)) },
            selected = back,
            onSelect = {
                back = it
                PlaybackPreferences.setSkipBackward(context, it)
            },
        )
        SettingsCardDivider()
        SettingsMenuPicker(
            label = "Skip Forward",
            choices = PlaybackPreferences.skipIntervals.map { SettingsChoice(it, PlaybackPreferences.intervalTitle(it)) },
            selected = forward,
            onSelect = {
                forward = it
                PlaybackPreferences.setSkipForward(context, it)
            },
        )
        SettingsCardDivider()
        SettingsMenuPicker(
            label = "Player Engine",
            choices = listOf(
                SettingsChoice(PlaybackPreferences.ENGINE_MPV, "MPV"),
                SettingsChoice(PlaybackPreferences.ENGINE_EXOPLAYER, "ExoPlayer"),
            ),
            selected = playerEngine,
            onSelect = {
                playerEngine = it
                PlaybackPreferences.setPlayerEngine(context, it)
            },
        )
        SettingsCardDivider()
        SettingsToggleRow("Wi-Fi Only Downloads", wifiOnly, {
            wifiOnly = it
            PlaybackPreferences.setDownloadWifiOnly(context, it)
        })
    }
    SettingsFooter("Speed, skip distance, and whether the next episode starts when this one ends. MPV uses libass for advanced subtitles.")
}

@Composable
private fun SubtitleAppearanceTopic() {
    val context = LocalContext.current
    var style by remember { mutableStateOf(SubtitleAppearance.current(context)) }
    fun refresh() {
        style = SubtitleAppearance.current(context)
    }
    SettingsHeader("Style")
    SettingsCard {
        Box(
            Modifier
                .fillMaxWidth()
                .height(112.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(MaterialTheme.colorScheme.surfaceContainerHighest),
            contentAlignment = Alignment.Center,
        ) {
            val preview = style
            val color = Color(preview.foregroundArgb())
            Text(
                "Sample subtitle text",
                color = color,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.SemiBold,
                fontSize = (17 * preview.sizeScale).sp,
                textAlign = TextAlign.Center,
                modifier = when (preview.background) {
                    SubtitleAppearance.BACK_HIGHLIGHT -> Modifier
                        .clip(RoundedCornerShape(4.dp))
                        .background(Color(preview.windowArgb()))
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                    else -> Modifier
                },
            )
        }
    }
    SettingsCard {
        SettingsInlinePicker(
            label = "Font Size",
            choices = SubtitleAppearance.sizes.map { SettingsChoice(it, SubtitleAppearance.sizeTitle(it)) },
            selected = style.size,
            onSelect = {
                SubtitleAppearance.setSize(context, it)
                refresh()
            },
        )
        SettingsCardDivider()
        SettingsInlinePicker(
            label = "Text Color",
            choices = SubtitleAppearance.colors.map { SettingsChoice(it, SubtitleAppearance.colorTitle(it)) },
            selected = style.color,
            onSelect = {
                SubtitleAppearance.setColor(context, it)
                refresh()
            },
        )
        SettingsCardDivider()
        SettingsInlinePicker(
            label = "Background",
            choices = SubtitleAppearance.backgrounds.map { SettingsChoice(it, SubtitleAppearance.backgroundTitle(it)) },
            selected = style.background,
            onSelect = {
                SubtitleAppearance.setBackground(context, it)
                refresh()
            },
        )
        SettingsCardDivider()
        SettingsSliderRow(
            label = "Brightness",
            value = style.brightness.toFloat(),
            valueText = style.brightness.toString(),
            range = 10f..100f,
            onChange = {
                SubtitleAppearance.setBrightness(context, it.toInt())
                refresh()
            },
        )
        SettingsCardDivider()
        SettingsInlinePicker(
            label = "Position",
            choices = listOf(SettingsChoice(false, "Default"), SettingsChoice(true, "Raised")),
            selected = style.positionLift > 0,
            onSelect = {
                SubtitleAppearance.setPosition(context, it)
                refresh()
            },
        )
        SettingsSliderRow(
            label = "",
            value = style.positionLift.toFloat(),
            valueText = "",
            range = 0f..100f,
            onChange = {
                SubtitleAppearance.setPositionLift(context, it.toInt())
                refresh()
            },
        )
        SettingsCardDivider()
        SettingsSliderRow(
            label = "Sync",
            value = style.syncSeconds.toFloat(),
            valueText = style.syncTitle(),
            range = -10f..10f,
            onChange = {
                SubtitleAppearance.setSyncSeconds(context, it.toDouble())
                refresh()
            },
        )
    }
    SettingsFooter("Raise captions from the bottom of the picture. Style applies to text subtitles. Positive sync shows captions later; negative shows them earlier. Sync is applied by MPV.")
}

/**
 * Mirrors the iOS Audio and Subtitles sections of `PlaybackSettingsView`: the signed-in user's
 * Jellyfin settings (preferred languages, play default audio track, subtitle mode), which the
 * server uses to pick the streams a title starts on.
 */
@Composable
private fun JellyfinPlaybackPreferencesSections(model: ZelefinModel, languages: List<String>) {
    val scope = rememberCoroutineScope()
    var preferences by remember { mutableStateOf<JellyfinPlaybackPreferences?>(null) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }

    suspend fun load() {
        loading = true
        runCatching { model.jellyfinPlaybackPreferences() }
            .onSuccess {
                preferences = it
                error = null
            }
            .onFailure { error = "Zelefin could not load your Jellyfin playback settings. ${it.message.orEmpty()}".trim() }
        loading = false
    }
    LaunchedEffect(Unit) { load() }

    fun update(change: (JellyfinPlaybackPreferences) -> JellyfinPlaybackPreferences) {
        val current = preferences ?: return
        val next = change(current)
        if (next == current) return
        preferences = next
        scope.launch {
            runCatching { model.saveJellyfinPlaybackPreferences(next) }
                .onSuccess { error = null }
                .onFailure {
                    error = "Jellyfin did not save that change. ${it.message.orEmpty()}".trim()
                    load()
                }
        }
    }

    fun languageChoices(current: String?): List<SettingsChoice<String>> {
        val codes = (listOf(JellyfinPlaybackPreferences.ANY_LANGUAGE) + languages).toMutableList()
        if (!current.isNullOrEmpty() && current !in codes) codes += current
        return codes.map { SettingsChoice(it, PlaybackLanguage.displayName(it)) }
    }

    val ready = preferences != null
    val shown = preferences ?: JellyfinPlaybackPreferences()
    val dimmed = Modifier.alpha(if (ready) 1f else 0.55f)

    SettingsHeader(if (loading) "Audio…" else "Audio")
    SettingsCard {
        Column(dimmed) {
            SettingsMenuPicker(
                label = "Preferred Language",
                choices = languageChoices(preferences?.audioLanguage),
                selected = shown.audioLanguage,
                onSelect = { code -> if (ready) update { it.copy(audioLanguage = code) } },
            )
            SettingsCardDivider()
            SettingsToggleRow("Play Default Audio Track", shown.playDefaultAudioTrack, { on -> if (ready) update { it.copy(playDefaultAudioTrack = on) } })
        }
        error?.let {
            Text(it, color = Color(0xFFFF6B6B), fontFamily = ZelefinFont, fontSize = 14.sp, modifier = Modifier.padding(top = 12.dp))
        }
    }
    SettingsFooter(
        if (shown.playDefaultAudioTrack) {
            "The file’s default audio track plays even when a track in your preferred language exists. Saved to your Jellyfin account."
        } else {
            "Titles start on the audio track in your preferred language when the file has one. Saved to your Jellyfin account."
        },
    )

    SettingsHeader("Subtitles")
    SettingsCard {
        Column(dimmed) {
            SettingsMenuPicker(
                label = "Preferred Language",
                choices = languageChoices(preferences?.subtitleLanguage),
                selected = shown.subtitleLanguage,
                onSelect = { code -> if (ready) update { it.copy(subtitleLanguage = code) } },
            )
            SettingsCardDivider()
            SettingsMenuPicker(
                label = "Subtitle Mode",
                choices = SubtitlePlaybackModeChoices.map { SettingsChoice(it, it.title) },
                selected = shown.subtitleMode,
                onSelect = { mode -> if (ready) update { it.copy(subtitleMode = mode) } },
            )
            SettingsCardDivider()
            val context = LocalContext.current
            var preferSdh by remember { mutableStateOf(PlaybackPreferences.preferSdh(context)) }
            SettingsToggleRow("Prefer SDH Subtitles", preferSdh, {
                preferSdh = it
                PlaybackPreferences.setPreferSdh(context, it)
            })
        }
    }
    SettingsFooter(shown.subtitleMode.summary + " SDH prefers captions that describe music and sound.")
}

/** Connection row, measured / recommended results, and the Test Connection button of the Quality card. */
@Composable
private fun PlaybackConnectionTest(model: ZelefinModel, signedIn: Boolean, quality: PlaybackQuality) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var transport by remember { mutableStateOf(NetworkPathSnapshot.current(context).transport) }
    var testing by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<BitrateProbeResult?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) {
        while (true) {
            transport = NetworkPathSnapshot.current(context).transport
            delay(2_000)
        }
    }
    SettingsInfoRow("Connection", transport.title)
    result?.let { measured ->
        val recommended = remember(measured, quality) { AdaptiveBitrateStore.recommendedQuality(context, measured) }
        SettingsCardDivider()
        SettingsInfoRow("Measured", measuredBitrateLabel(measured.bitsPerSecond))
        SettingsCardDivider()
        SettingsInfoRow("Recommended", recommended.title)
    }
    error?.let {
        Text(it, color = Color(0xFFFF6B6B), fontFamily = ZelefinFont, fontSize = 14.sp, modifier = Modifier.padding(top = 12.dp))
    }
    Spacer(Modifier.height(16.dp))
    SettingsPrimaryButton("Test Connection", busy = testing, enabled = signedIn) {
        if (!signedIn) {
            error = "Sign in to test this connection."
            return@SettingsPrimaryButton
        }
        testing = true
        error = null
        scope.launch {
            runCatching { model.testConnection() }
                .onSuccess { result = it }
                .onFailure {
                    result = null
                    error = it.message ?: "Zelefin could not download the demo file from this server. Check the connection and try again."
                }
            transport = NetworkPathSnapshot.current(context).transport
            testing = false
        }
    }
}

private fun measuredBitrateLabel(bitsPerSecond: Int): String {
    if (bitsPerSecond <= 0) return "—"
    val megabits = bitsPerSecond / 1_000_000.0
    return when {
        megabits >= 10 -> String.format(java.util.Locale.US, "%.1f Mbps", megabits)
        megabits >= 1 -> String.format(java.util.Locale.US, "%.2f Mbps", megabits)
        else -> String.format(java.util.Locale.US, "%.0f kbps", bitsPerSecond / 1_000.0)
    }
}

/** `0.1.0 (10)`, read from the build so it tracks `versionName`/`versionCode` in build.gradle.kts. */
internal val AppVersionLabel = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"

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
        val silo = state.session?.usesSilo == true
        val canInstall = !silo && pluginState.isAdmin
        SettingsCard {
            PluginStatusRow(
                "Zelefin plugin",
                installed = pluginState.pluginNeedsRestart,
                installedLabel = "Restart needed",
            )
            Text(
                when {
                    silo ->
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
            if (canInstall) {
                Spacer(Modifier.height(14.dp))
                SettingsPrimaryButton(
                    if (pluginState.pluginInstalling) "Installing…" else "Install Plugin",
                    busy = pluginState.pluginInstalling,
                    enabled = !pluginState.pluginInstalling && !pluginState.pluginNeedsRestart,
                    onClick = plugins::installZelefinPlugin,
                )
                if (pluginState.pluginNeedsRestart) {
                    Spacer(Modifier.height(10.dp))
                    SettingsSecondaryButton(
                        if (pluginState.pluginRestarting) "Restarting…" else "Restart Jellyfin",
                        enabled = !pluginState.pluginRestarting,
                        onClick = plugins::restartJellyfin,
                    )
                }
            } else if (!silo && !pluginState.detecting) {
                Text(
                    "Ask a server administrator to install the Zelefin plugin from Settings → Notifications, or sign in with an admin account.",
                    color = Caption,
                    fontFamily = ZelefinFont,
                    fontSize = 13.sp,
                    modifier = Modifier.padding(top = 10.dp),
                )
            }
            pluginState.pluginInstallMessage?.let { message ->
                Text(
                    message,
                    color = if (message.contains("could not") || message.contains("Sign in as")) Color(0xFFFF6B6B) else Secondary,
                    fontFamily = ZelefinFont,
                    fontSize = 14.sp,
                    modifier = Modifier.padding(top = 12.dp),
                )
            }
        }
        SettingsFooter(
            when {
                silo -> "Connect a Jellyfin server with the Zelefin plugin to receive notifications."
                canInstall -> "After install, restart Jellyfin so the plugin can load. You do not set up Firebase or paste a key on the server."
                else -> "In Jellyfin, open Dashboard → Plugins → Catalog, install Zelefin, then restart Jellyfin. You do not set up Firebase or paste a key on the server."
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
            SettingsTextField(
                label = "SERVER",
                value = url,
                icon = Icons.Outlined.Link,
                onChange = { url = it },
                placeholder = "https://seerr.example.com",
                keyboard = KeyboardType.Uri,
                ime = ImeAction.Next,
            )
            CardDivider()
            SettingsTextField(
                label = "USERNAME",
                value = username,
                icon = Icons.Outlined.Person,
                onChange = { username = it },
                placeholder = "Username or email",
                ime = ImeAction.Next,
            )
            CardDivider()
            SettingsTextField(
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
                    Text(source.title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
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

/** Fixed status colors, independent of the accent (iOS `LoginPalette.success`). */
private val StatusInstalled = Color(0xFF38C76B)
private val StatusMissing = Color(0xFFFF6B6B)

@Composable
private fun PluginStatusRow(title: String, installed: Boolean, installedLabel: String = "Installed") {
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
        Text(
            if (installed) installedLabel else "Not on this server",
            color = if (installed) StatusInstalled else StatusMissing,
            fontFamily = ZelefinFont,
            fontWeight = FontWeight.Bold,
            fontSize = 13.sp,
        )
    }
}

@Composable
private fun SettingsToggle(title: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    SettingsToggleRow(title, checked, onChange)
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
    when {
        primary && !destructive -> SettingsPrimaryButton(title, busy = busy, enabled = enabled, onClick = onClick)
        else -> {
            val color = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary
            OutlinedButton(
                onClick = onClick,
                enabled = enabled && !busy,
                modifier = Modifier.fillMaxWidth().height(48.dp),
            ) {
                if (busy) {
                    CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                } else {
                    Text(title, color = color)
                }
            }
        }
    }
}

@Composable
private fun CardDivider() {
    SettingsCardDivider()
}

@Composable
internal fun SettingsFooter(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 4.dp),
    )
}

private val SavedDataFolders = listOf("HomeSnapshots", "CatalogSnapshots", "ItemDetailSnapshots")

@Composable
private fun CacheTopic() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val root = remember { File(context.cacheDir, "Zelefin") }
    var artwork by remember { mutableStateOf(0L) }
    var revision by remember { mutableStateOf(0) }
    var confirm by remember { mutableStateOf(false) }
    LaunchedEffect(revision) {
        artwork = withContext(Dispatchers.IO) {
            (context.imageLoader.diskCache?.size ?: 0L) + folderBytes(File(root, "Artwork"))
        }
    }
    if (confirm) {
        SettingsAlertDialog(
            title = "Clear Artwork?",
            message = "Posters and backdrops download again as you browse.",
            confirmLabel = "Clear",
            destructive = true,
            onConfirm = {
                confirm = false
                scope.launch {
                    withContext(Dispatchers.IO) { context.imageLoader.diskCache?.clear() }
                    context.imageLoader.memoryCache?.clear()
                    revision += 1
                }
            },
            onDismiss = { confirm = false },
        )
    }
    SettingsHeader("Images")
    SettingsCard {
        InfoLine("Artwork", formatBytes(artwork))
        Spacer(Modifier.height(14.dp))
        SettingsButton("Clear Artwork", primary = false, destructive = true, enabled = artwork > 0, busy = false) { confirm = true }
    }
    SettingsFooter("Posters, backdrops, logos, and profile pictures saved on this phone.")
}

@Composable
private fun MetadataTopic() {
    val context = LocalContext.current
    val model: ZelefinModel = viewModel()
    val scope = rememberCoroutineScope()
    val root = remember { File(context.cacheDir, "Zelefin") }
    var sizes by remember { mutableStateOf<Map<String, Long>>(emptyMap()) }
    var revision by remember { mutableStateOf(0) }
    var confirm by remember { mutableStateOf(false) }
    LaunchedEffect(revision) {
        sizes = withContext(Dispatchers.IO) {
            SavedDataFolders.associateWith { folderBytes(File(root, it)) }
        }
    }
    if (confirm) {
        SettingsAlertDialog(
            title = "Clear Saved Home Data?",
            message = "Home, Movies, Shows, and title pages reload from the server.",
            confirmLabel = "Clear",
            destructive = true,
            onConfirm = {
                confirm = false
                scope.launch {
                    withContext(Dispatchers.IO) { SavedDataFolders.forEach { File(root, it).deleteRecursively() } }
                    model.refreshLibrary()
                    revision += 1
                }
            },
            onDismiss = { confirm = false },
        )
    }
    val saved = SavedDataFolders.sumOf { sizes[it] ?: 0L }
    SettingsHeader("Saved Home Data")
    SettingsCard {
        InfoLine("Home", formatBytes(sizes["HomeSnapshots"] ?: 0L))
        InfoLine("Catalogs", formatBytes(sizes["CatalogSnapshots"] ?: 0L))
        InfoLine("Title Pages", formatBytes(sizes["ItemDetailSnapshots"] ?: 0L))
        Spacer(Modifier.height(14.dp))
        SettingsButton("Clear Saved Home Data", primary = false, destructive = true, enabled = saved > 0, busy = false) { confirm = true }
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
        InfoLine("App", "Zelefin $AppVersionLabel")
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
        InfoLine("Version", AppVersionLabel)
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
        Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
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
        SettingsTextField(
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
            Text("No networks saved", style = MaterialTheme.typography.titleMedium)
            Text("Add a network so auto-switch knows when you’re home.", color = Caption, fontFamily = ZelefinFont, fontSize = 13.sp)
        } else {
            profile.homeSsids.forEachIndexed { index, name ->
                if (index > 0) CardDivider()
                Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Wifi, contentDescription = null, tint = ZelefinCyan, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.size(12.dp))
                    Text(name, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
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
            SettingsTextField(
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
        SettingsTextField(
            label = "CLIENT ID",
            value = gatewayId,
            icon = Icons.Outlined.Lock,
            onChange = { gatewayId = it },
            placeholder = "Client ID or token ID",
            ime = ImeAction.Next,
        )
        CardDivider()
        SettingsTextField(
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

/** Mirrors iOS `TabCustomizationView`. */
@Composable
private fun InterfaceTopic(state: ZelefinUiState) {
    InterfaceSettings(state)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsPage(
    title: String,
    onBack: () -> Unit,
    bar: SettingsBarAction,
    content: @Composable () -> Unit,
) {
    val topInset = if (LocalZelefinInSheet.current) Modifier else Modifier.statusBarsPadding()
    Column(
        Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surface)
            .then(topInset),
    ) {
        TopAppBar(
            title = { Text(title) },
            windowInsets = WindowInsets(0, 0, 0, 0),
            navigationIcon = {
                when (bar) {
                    SettingsBarAction.Back -> IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back from $title")
                    }
                    SettingsBarAction.Cancel -> TextButton(onClick = onBack) {
                        Text("Cancel", fontWeight = FontWeight.SemiBold)
                    }
                    SettingsBarAction.Done -> Unit
                }
            },
            actions = {
                if (bar == SettingsBarAction.Done) {
                    TextButton(onClick = onBack) {
                        Text("Done", fontWeight = FontWeight.SemiBold)
                    }
                }
            },
            colors = TopAppBarDefaults.topAppBarColors(
                containerColor = MaterialTheme.colorScheme.surface,
                titleContentColor = MaterialTheme.colorScheme.onSurface,
                navigationIconContentColor = MaterialTheme.colorScheme.onSurface,
                actionIconContentColor = MaterialTheme.colorScheme.primary,
            ),
        )
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .navigationBarsPadding()
                .padding(bottom = 28.dp),
        ) {
            content()
        }
    }
}

@Composable
internal fun SettingsHeader(title: String) {
    SettingsSectionLabel(title)
}

@Composable
private fun SettingsLinkRow(title: String, icon: ImageVector, subtitle: String, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurface, modifier = Modifier.size(22.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun SettingsLink(title: String, icon: ImageVector, subtitle: String, onClick: () -> Unit) {
    SettingsCard(onClick = onClick) {
        SettingsLinkRow(title, icon, subtitle, onClick)
    }
    Spacer(Modifier.height(8.dp))
}

@Composable
internal fun SettingsCard(onClick: (() -> Unit)? = null, content: @Composable () -> Unit) {
    val colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh)
    val elevation = CardDefaults.cardElevation(defaultElevation = 0.dp)
    val modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)
    val body = @Composable { Column(Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) { content() } }
    if (onClick != null) {
        Card(onClick = onClick, modifier = modifier, shape = RoundedCornerShape(12.dp), colors = colors, elevation = elevation) { body() }
    } else {
        Card(modifier = modifier, shape = RoundedCornerShape(12.dp), colors = colors, elevation = elevation) { body() }
    }
}

@Composable
private fun InfoLine(label: String, value: String) {
    Column(Modifier.padding(vertical = 6.dp)) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodyLarge)
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
