package app.zelefin.client.ui

import app.zelefin.client.plugins.PluginPresence
import app.zelefin.client.plugins.SkipPluginChoice
import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Intent
import android.os.Build
import android.os.PersistableBundle
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.LayoutDirection
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import app.zelefin.client.BuildConfig
import app.zelefin.client.LibraryKind
import app.zelefin.client.push.ZelefinPush
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.automirrored.outlined.List
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
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material.icons.outlined.Extension
import androidx.compose.material.icons.outlined.Dashboard
import androidx.compose.material.icons.outlined.Devices
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Person
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import app.zelefin.client.PluginsController
import app.zelefin.client.PluginsUiState
import app.zelefin.client.ZelefinUiState
import app.zelefin.client.plugins.JellyfinPluginState
import java.io.File
import android.net.Uri
import androidx.activity.result.PickVisualMediaRequest
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Home
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
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily

private val Caption = IOSColors.secondaryLabel
private val Secondary = IOSColors.secondaryLabel

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
    val scope = rememberCoroutineScope()
    val jellyfin = state.hasJellyfinExtras
    val tools = session?.hasServerTools == true
    val serverType = session?.serverTypeName ?: "Jellyfin"
    val showServer = tools && pluginState.isAdmin
    var confirmScan by remember { mutableStateOf(false) }
    var scanMessage by remember(session?.accountId) { mutableStateOf<String?>(null) }
    if (confirmScan) {
        SettingsAlertDialog(
            title = "Scan all libraries?",
            message = "$serverType will look for new files and refresh metadata. This can take a while on a large server.",
            confirmLabel = "Scan",
            onConfirm = {
                confirmScan = false
                scope.launch {
                    scanMessage = runCatching { model.scanLibraries() }
                        .map { "Scan started. $serverType is looking for new files." }
                        .getOrElse { it.message ?: "$serverType could not start the scan." }
                }
            },
            onDismiss = { confirmScan = false },
        )
    }
    val context = LocalContext.current
    val cacheSize by produceState<Long?>(null) {
        value = withContext(Dispatchers.IO) {
            val root = File(context.cacheDir, "Zelefin")
            (context.imageLoader.diskCache?.size ?: 0L) + folderBytes(File(root, "Artwork")) +
                SavedDataFolders.sumOf { folderBytes(File(root, it)) }
        }
    }
    SettingsPage(title = "Settings", onBack = onBack, bar = bar) {
        SettingsGroup { SettingsProfileRow(session, onClick = onProfile) }
        SettingsHeader("Account")
        SettingsNavGroup(
            buildList {
                add(SettingsHubItem("Notifications", "Alerts from your server", Icons.Outlined.Notifications) { onTopic("notifications") })
                if (tools) {
                    add(SettingsHubItem("Sessions", "Devices signed in to $serverType", Icons.Outlined.Devices) { onTopic("sessions") })
                }
                if (jellyfin) {
                    add(SettingsHubItem("SyncPlay", "Watch together in a group", Icons.Outlined.Groups) { onTopic("syncplay") })
                }
            },
        )
        SettingsHeader("Playback")
        SettingsNavGroup(
            listOf(
                SettingsHubItem("Playback", "Languages, quality, speed, skipping", Icons.Outlined.PlayArrow) { onTopic("playback") },
                SettingsHubItem("Subtitles", "Size, color, and background", Icons.Outlined.ClosedCaption) { onTopic("subtitles") },
                SettingsHubItem("Plugins", "Intro Skipper, Seerr, server plugins", Icons.Outlined.Extension) { onTopic("plugins") },
                SettingsHubItem("Metadata", "Ratings and title details", Icons.Outlined.Description) { onTopic("metadata") },
            ),
        )
        if (showServer) {
            SettingsHeader("Server")
            SettingsNavGroup(
                buildList {
                    add(SettingsHubItem("Users", "Permissions, libraries, and parental controls", Icons.Outlined.People) { onTopic("users") })
                    add(SettingsHubItem("Scheduled Tasks", "Start, cancel, and watch progress", Icons.Outlined.Schedule) { onTopic("scheduled-tasks") })
                    add(SettingsHubItem("Activity Log", "Sign-ins, scans, and failures", Icons.AutoMirrored.Outlined.List) { onTopic("activity") })
                    if (jellyfin) {
                        add(SettingsHubItem("Backups", "Archive and restore this server", Icons.Outlined.Inventory2) { onTopic("backups") })
                        add(SettingsHubItem("Branding", "Login disclaimer and splashscreen", Icons.Outlined.Brush) { onTopic("branding") })
                    }
                    add(SettingsHubItem("Scan Libraries", scanMessage ?: "Look for new files and refresh metadata", Icons.Outlined.Refresh) { confirmScan = true })
                },
            )
            SettingsFooter("Administer this $serverType server.")
        }
        SettingsHeader("This Device")
        SettingsNavGroup(
            listOf(
                SettingsHubItem("Network", session?.displayServer?.takeIf { it.isNotBlank() } ?: "How this device reaches the server", Icons.Outlined.Wifi) { onTopic("network") },
                SettingsHubItem("Cache", cacheSize?.takeIf { it > 0 }?.let(::formatBytes) ?: "Posters and saved home data", Icons.Outlined.Storage) { onTopic("cache") },
                SettingsHubItem("Interface", "Home rows, tabs, and Liquid Glass", Icons.Outlined.Dashboard) { onTopic("interface") },
                SettingsHubItem("Appearance", "Accent color", Icons.Outlined.Palette) { onTopic("appearance") },
            ),
        )
        SettingsHeader("Zelefin")
        SettingsNavGroup(
            listOf(SettingsHubItem("About", AppVersionLabel, Icons.Outlined.Info) { onTopic("about") }),
        )
    }
}

@Composable
fun ProfileScreen(state: ZelefinUiState, onBack: () -> Unit, bar: SettingsBarAction = SettingsBarAction.Done) {
    val session = state.session
    val model: ZelefinModel = viewModel()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val silo = state.isSiloServer
    var uploading by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<Pair<String, Boolean>?>(null) }
    var removing by remember { mutableStateOf<SavedSession?>(null) }
    var currentPassword by remember { mutableStateOf("") }
    var newPassword by remember { mutableStateOf("") }
    var confirmPassword by remember { mutableStateOf("") }
    var savingPassword by remember { mutableStateOf(false) }
    var tokenVisible by remember { mutableStateOf(false) }
    var tokenCopied by remember { mutableStateOf(false) }
    val serverLabel = session?.displayServer?.takeIf { it.isNotBlank() } ?: "this server"
    val siloLink = session?.siloLink
    val household = state.household
    val serverType = session?.serverTypeName ?: "Jellyfin"
    val managesAccount = !silo
    val canChangePhoto = session != null && (siloLink != null || managesAccount)
    val canRemovePhoto = siloLink == null && managesAccount && session?.userImageTag != null
    val canChangePassword = managesAccount
    val usersTitle = if (silo) "Accounts" else "Users"
    val addTitle = if (silo) "Add Account" else "Add User"
    var avatarSheet by remember { mutableStateOf(false) }
    val avatarMotion = rememberZelefinSheet(if (avatarSheet && siloLink != null) Unit else null)
    LaunchedEffect(siloLink?.profileId) { if (siloLink != null) model.refreshHousehold() }
    val profile = siloLink?.let { link -> household.profiles.firstOrNull { it.id == link.profileId } ?: link.profile }
    PresentZelefinOverlay(visible = avatarMotion.displayed != null) {
        Box(Modifier.fillMaxSize()) {
            Box(
                Modifier
                    .fillMaxSize()
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { avatarSheet = false },
            ) { ZelefinSheetScrim(avatarMotion.progress) }
            if (profile != null) {
                ZelefinSheetSurface(avatarMotion.progress) {
                    SiloAvatarSheet(
                        profile = profile,
                        uploadEnabled = household.avatarUploadEnabled,
                        onChoosePreset = model::chooseSiloAvatarPreset,
                        onUpload = model::updateProfilePhoto,
                        onRemove = model::removeProfilePhoto,
                        onClose = { avatarSheet = false },
                    )
                }
            }
        }
    }
    val passwordMismatch = confirmPassword.isNotEmpty() && newPassword != confirmPassword
    val accessToken = session?.accessToken.orEmpty()
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
    val removePhoto = {
        val current = session
        if (current != null && !uploading) {
            uploading = true
            status = null
            scope.launch {
                val oldKey = avatarImageUrl(current)?.let(ArtworkDiskKey::key)
                runCatching { model.removeProfilePhoto() }
                    .onSuccess {
                        oldKey?.let { key ->
                            context.imageLoader.memoryCache?.remove(MemoryCache.Key(key))
                            withContext(Dispatchers.IO) { context.imageLoader.diskCache?.remove(key) }
                        }
                        status = "Profile picture removed." to false
                    }
                    .onFailure { status = (it.message ?: "The server could not remove the photo.") to true }
                uploading = false
            }
        }
    }
    val copyToken = {
        val clip = ClipData.newPlainText("Zelefin device token", accessToken)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            clip.description.extras = PersistableBundle().apply { putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true) }
        }
        context.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(clip)
        tokenCopied = true
        status = "Access token copied." to false
    }
    SettingsPage(title = "Profile", onBack = onBack, bar = bar) {
        SettingsCard {
            Column(Modifier.fillMaxWidth().padding(vertical = 14.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                val choosePhoto = {
                    when {
                        uploading -> Unit
                        siloLink != null -> avatarSheet = true
                        else -> picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                    }
                }
                Box(Modifier.size(76.dp)) {
                    AccountAvatar(session, onClick = { if (canChangePhoto) choosePhoto() }, diameter = 72.dp)
                    if (uploading) {
                        Box(Modifier.size(72.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.48f)), contentAlignment = Alignment.Center) {
                            IOSSpinner(color = Color.White)
                        }
                    }
                    if (canChangePhoto) {
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
                Spacer(Modifier.height(12.dp))
                Text(
                    session?.userName ?: "Account",
                    color = Color.White,
                    fontFamily = ZelefinFont,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 20.sp,
                    textAlign = TextAlign.Center,
                )
                Text(
                    "$serverType · $serverLabel",
                    color = IOSColors.secondaryLabel,
                    fontFamily = ZelefinFont,
                    fontSize = 15.sp,
                    textAlign = TextAlign.Center,
                )
                if (canRemovePhoto) {
                    Spacer(Modifier.height(12.dp))
                    Text(
                        "Remove Photo",
                        style = SettingsRowText.copy(color = IOSColors.red),
                        modifier = Modifier
                            .clip(RoundedCornerShape(8.dp))
                            .clickable(enabled = !uploading, role = Role.Button, onClick = removePhoto)
                            .padding(horizontal = 8.dp, vertical = 4.dp),
                    )
                }
                status?.let { (text, error) ->
                    Text(
                        text,
                        color = if (error) IOSColors.red else IOSColors.secondaryLabel,
                        fontFamily = ZelefinFont,
                        fontSize = 13.sp,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(top = 10.dp),
                    )
                }
            }
        }
        SettingsHeader("Server")
        SettingsCard {
            InfoLine("Server", session?.displayServer ?: "—")
            SettingsCardDivider()
            InfoLine("Address", session?.serverUrl ?: "—")
            if (siloLink != null) {
                SettingsCardDivider()
                InfoLine("Silo Account", siloLink.accountName)
            }
        }
        if (siloLink != null) {
            SettingsHeader("Profiles")
            SettingsCard {
                val profiles = household.profiles
                if (profiles.isEmpty()) {
                    Row(Modifier.fillMaxWidth().heightIn(min = SettingsRowHeight), verticalAlignment = Alignment.CenterVertically) {
                        if (household.loading) {
                            IOSSpinner()
                        } else {
                            Text(
                                household.message ?: "No household profiles.",
                                style = SettingsRowText.copy(color = IOSColors.secondaryLabel),
                                modifier = Modifier.padding(vertical = 14.dp),
                            )
                        }
                    }
                }
                profiles.forEachIndexed { index, profile ->
                    if (index > 0) SettingsCardDivider()
                    val current = profile.id == siloLink.profileId
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .heightIn(min = SettingsRowHeight)
                            .clickable(enabled = !current && household.switchingTo == null, role = Role.Button) { model.switchSiloProfile(profile) }
                            .padding(vertical = 10.dp),
                        contentAlignment = Alignment.CenterStart,
                    ) {
                        SiloProfileRowContent(profile, current = current, busy = household.switchingTo == profile.id)
                    }
                }
                if (household.signInExpired) {
                    SettingsCardDivider()
                    SettingsActionRow("Sign In Again", onClick = model::signInToSiloAgain)
                }
            }
            SettingsFooter(
                if (household.signInExpired) household.message ?: "Your Silo sign-in expired. Sign in again."
                else household.message?.takeIf { household.profiles.isNotEmpty() } ?: "Switch to another profile in this Silo household.",
            )
        }
        SettingsHeader("Password")
        SettingsCard {
            if (canChangePassword) {
                SettingsTextField("Current Password", currentPassword, Icons.Outlined.Lock, { currentPassword = it }, password = true)
                SettingsCardDivider()
                SettingsTextField("New Password", newPassword, Icons.Outlined.Lock, { newPassword = it }, password = true)
                SettingsCardDivider()
                SettingsTextField("Confirm Password", confirmPassword, Icons.Outlined.Lock, { confirmPassword = it }, password = true)
                if (passwordMismatch) {
                    SettingsCardDivider()
                    Text(
                        "The new passwords do not match.",
                        color = IOSColors.red,
                        fontFamily = ZelefinFont,
                        fontSize = 13.sp,
                        modifier = Modifier.padding(vertical = 12.dp),
                    )
                }
                SettingsCardDivider()
                SettingsActionRow(
                    "Update Password",
                    busy = savingPassword,
                    enabled = currentPassword.isNotEmpty() && newPassword.isNotEmpty() && !passwordMismatch && confirmPassword.isNotEmpty(),
                ) {
                    savingPassword = true
                    status = null
                    scope.launch {
                        runCatching { model.changePassword(currentPassword, newPassword) }
                            .onSuccess {
                                currentPassword = ""
                                newPassword = ""
                                confirmPassword = ""
                                status = "Password updated." to false
                            }
                            .onFailure { status = (it.message ?: "The server did not accept the new password.") to true }
                        savingPassword = false
                    }
                }
            } else {
                Text(
                    "Change this password in $serverType.",
                    style = SettingsRowText.copy(color = IOSColors.secondaryLabel),
                    modifier = Modifier.padding(vertical = 14.dp),
                )
            }
        }
        SettingsFooter(
            if (canChangePassword) "Updates the password for this login on $serverLabel."
            else "$serverType manages the password for this login.",
        )
        if (accessToken.isNotEmpty()) {
            SettingsHeader("Device Token")
            SettingsCard {
                InfoLine("Device Token", if (tokenVisible) accessToken else "•".repeat(accessToken.length.coerceIn(12, 28)))
                SettingsCardDivider()
                SettingsActionRow(if (tokenVisible) "Hide Token" else "Show Token") { tokenVisible = !tokenVisible }
                SettingsCardDivider()
                SettingsActionRow(if (tokenCopied) "Copied" else "Copy Token", onClick = copyToken)
            }
            SettingsFooter("This token signs this device into $serverLabel. Copy it only into apps you trust.")
        }
        SettingsHeader(usersTitle)
        SettingsCard {
            session?.let { current ->
                AccountRow(current, subtitle = "Signed in", current = true, onClick = null, onRemove = null)
                SettingsCardDivider()
            }
            state.accounts.filter { it.accountId != session?.accountId }.forEach { account ->
                AccountRow(
                    account,
                    subtitle = if (account.displayServer == session?.displayServer) "On this device" else account.displayServer,
                    current = false,
                    onClick = { model.switchAccount(account) },
                    onRemove = { removing = account },
                )
                SettingsCardDivider()
            }
            Row(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = SettingsRowHeight)
                    .clickable {
                        model.resetAddAccount()
                        model.openSettingsTopic(AddAccountTopicId)
                    }
                    .padding(vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Icon(Icons.Outlined.PersonAdd, contentDescription = null, tint = ZelefinCyan, modifier = Modifier.size(22.dp))
                Text(addTitle, style = SettingsRowText, modifier = Modifier.weight(1f))
                Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = IOSColors.tertiaryLabel)
            }
        }
        SettingsFooter(
            if (silo) "Add another Silo account on ${session?.displayServer ?: "this server"}. Saved accounts stay on this device."
            else "Add another person on ${session?.displayServer ?: "this server"}. Saved users stay on this device.",
        )
    }
}

@Composable
private fun AccountRow(account: SavedSession, subtitle: String, current: Boolean, onClick: (() -> Unit)?, onRemove: (() -> Unit)?) {
    Row(
        Modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        AccountAvatarImage(account, 40.dp)
        Column(Modifier.weight(1f)) {
            Text(account.userName, style = SettingsRowText)
            Text(subtitle, color = IOSColors.secondaryLabel, fontFamily = ZelefinFont, fontSize = 13.sp)
        }
        if (current) {
            Icon(Icons.Outlined.Check, contentDescription = "Signed in", tint = ZelefinCyan, modifier = Modifier.size(20.dp))
        } else if (onRemove != null) {
            Box(Modifier.size(32.dp).clip(CircleShape).clickable(onClick = onRemove), contentAlignment = Alignment.Center) {
                Icon(Icons.Outlined.Close, contentDescription = "Remove ${account.userName}", tint = IOSColors.tertiaryLabel, modifier = Modifier.size(18.dp))
            }
        }
    }
}

/** iOS `AddAccountView`: sign in another user. */
@Composable
private fun AddAccountTopic(state: ZelefinUiState) {
    val model: ZelefinModel = viewModel()
    val add = state.addAccount
    var url by remember { mutableStateOf(state.session?.serverUrl.orEmpty()) }
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    DisposableEffect(Unit) { onDispose { model.resetAddAccount() } }
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
        when {
            state.isSiloServer -> "New accounts are added on the server you’re already using. Enter another address to add an account on a different server."
            state.isEmbyServer -> "New users are added on the server you’re already using. Enter another address to add a user on a different Emby or Jellyfin server."
            else -> "New users are added on the server you’re already using. Enter another address to add a user on a different Jellyfin server."
        },
    )
    SettingsHeader("Sign In")
    val canSubmit = url.isNotBlank() && username.isNotBlank() && password.isNotEmpty() && !add.busy
    SettingsCard {
        SettingsTextField(
            label = "USERNAME",
            value = username,
            icon = Icons.Outlined.Person,
            onChange = { username = it },
            placeholder = "Username",
            keyboard = KeyboardType.Text,
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
        SettingsCardDivider()
        SettingsButton(if (state.isSiloServer) "Add Account" else "Add User", primary = true, destructive = false, enabled = canSubmit, busy = add.busy) {
            model.addAccount(url, username, password)
        }
        add.message?.let { AddAccountMessage(it) }
    }
}

@Composable
private fun AddAccountMessage(text: String) {
    Text(text, color = IOSColors.red, fontFamily = ZelefinFont, fontSize = 14.sp, modifier = Modifier.padding(top = 12.dp))
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
        AddAccountTopicId -> if (state.isSiloServer) "Add Account" else "Add User"
        else -> when {
            id.startsWith("user:") -> "User"
            id.startsWith("scheduled-task:") -> "Task"
            else -> "Settings"
        }
    }
    SettingsPage(title = title, onBack = onBack, bar = bar) {
        when (id) {
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

/** Mirrors iOS `PlaybackSettingsView`: Languages, Quality, Watching. */
@Composable
private fun PlaybackTopic(state: ZelefinUiState) {
    val model: ZelefinModel = viewModel()
    val context = LocalContext.current
    val silo = state.isSiloServer
    var adaptive by remember { mutableStateOf(PlaybackPreferences.adaptiveBitrate(context)) }
    var quality by remember { mutableStateOf(PlaybackPreferences.selectedQuality(context)) }
    var rate by remember { mutableStateOf(PlaybackPreferences.defaultRate(context)) }
    var autoplay by remember { mutableStateOf(PlaybackPreferences.autoplayNext(context)) }
    var back by remember { mutableStateOf(PlaybackPreferences.skipBackward(context)) }
    var forward by remember { mutableStateOf(PlaybackPreferences.skipForward(context)) }
    var playerEngine by remember { mutableStateOf(PlaybackPreferences.playerEngine(context)) }
    var wifiOnly by remember { mutableStateOf(PlaybackPreferences.downloadWifiOnly(context)) }
    var themeSongs by remember { mutableStateOf(PlaybackPreferences.themeSongs(context)) }
    var themeVideos by remember { mutableStateOf(PlaybackPreferences.themeVideos(context)) }
    var themeVideoSound by remember { mutableStateOf(PlaybackPreferences.themeVideoSound(context)) }
    val languages = remember(context) { PlaybackLanguage.choices(context) }

    JellyfinPlaybackPreferencesSections(model, languages, serverName = if (state.isEmbyServer) "Emby" else "Jellyfin")

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
        if (adaptive) {
            "Auto Direct Plays when the file fits this connection. The server transcodes when it does not. Test Connection measures this path."
        } else {
            "Auto Direct Plays when the file fits this device. Lower quality asks the server to transcode."
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

    SettingsHeader("Theme Media")
    SettingsCard {
        SettingsToggleRow("Theme Songs", themeSongs, {
            themeSongs = it
            PlaybackPreferences.setThemeSongs(context, it)
        })
        if (!silo) {
            SettingsCardDivider()
            SettingsToggleRow("Theme Videos", themeVideos, {
                themeVideos = it
                PlaybackPreferences.setThemeVideos(context, it)
            })
            if (themeVideos) {
                SettingsCardDivider()
                SettingsToggleRow("Theme Video Sound", themeVideoSound, {
                    themeVideoSound = it
                    PlaybackPreferences.setThemeVideoSound(context, it)
                })
            }
        }
    }
    SettingsFooter(
        if (silo) {
            "Plays a title's theme song on its page. Silo has no theme videos."
        } else {
            "Plays a title's Jellyfin theme video in place of the backdrop, or its theme song when it has no video. Theme videos are muted unless Theme Video Sound is on."
        },
    )
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
private fun JellyfinPlaybackPreferencesSections(model: ZelefinModel, languages: List<String>, serverName: String) {
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
            .onFailure { error = "Zelefin could not load your $serverName playback settings. ${it.message.orEmpty()}".trim() }
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
                    error = "$serverName did not save that change. ${it.message.orEmpty()}".trim()
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
            Text(it, color = IOSColors.red, fontFamily = ZelefinFont, fontSize = 14.sp, modifier = Modifier.padding(top = 12.dp))
        }
    }
    SettingsFooter(
        if (shown.playDefaultAudioTrack) {
            "The file’s default audio track plays even when a track in your preferred language exists. Saved to your $serverName account."
        } else {
            "Titles start on the audio track in your preferred language when the file has one. Saved to your $serverName account."
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
        Text(it, color = IOSColors.red, fontFamily = ZelefinFont, fontSize = 14.sp, modifier = Modifier.padding(top = 12.dp))
    }
    SettingsCardDivider()
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

/**
 * Lock-screen alerts for servers that post webhooks instead of running the Zelefin plugin. Emby's Webhooks
 * notifier, or a personal webhook on the active Silo profile, posts to an address Zelefin's push service
 * gives this phone.
 */
@Composable
private fun WebhookNotificationsTopic(state: ZelefinUiState, pluginState: PluginsUiState, plugins: PluginsController) {
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    val silo = state.isSiloServer
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        if (ok) plugins.setWebhookAlerts(true)
    }
    fun turnOn() {
        if (ZelefinPush.permissionGranted(context) || !ZelefinPush.needsRuntimePermission()) {
            plugins.setWebhookAlerts(true)
        } else {
            ZelefinPush.markAskedPermission(context)
            permission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    if (!pluginState.webhooksAvailable) {
        SettingsCard { PluginStatusRow(if (silo) "Silo Webhooks" else "Emby Webhooks", false) }
        SettingsFooter(
            when {
                pluginState.detecting -> "Checking this server for webhooks…"
                silo && state.session?.siloLink == null ->
                    "Notifications on Silo need your Silo account. Sign out and sign in with your Silo account to turn them on."
                silo -> "This Silo server has personal webhooks turned off. An administrator can turn them on in Silo's notification settings."
                else -> "Lock-screen alerts on Emby use its Webhooks notifier, which comes with Emby Premiere. When this server has it, turn on Notifications here and Zelefin sets it up."
            },
        )
        return
    }

    val on = pluginState.alertsOn
    val waitingForAdmin = pluginState.alertsAdminAddress != null
    SettingsCard {
        SettingsToggle("Notifications", on) { next -> if (next) turnOn() else plugins.setWebhookAlerts(false) }
        if (on && !waitingForAdmin) {
            SettingsCardDivider()
            SettingsButton(
                "Send Test Alert",
                primary = false,
                destructive = false,
                enabled = !pluginState.alertsBusy,
                busy = pluginState.alertsBusy,
                onClick = plugins::sendWebhookTestAlert,
            )
        }
        pluginState.alertsMessage?.let { message ->
            Text(
                message,
                color = if (pluginState.alertsMessageIsError) IOSColors.red else Secondary,
                fontFamily = ZelefinFont,
                fontSize = 14.sp,
                modifier = Modifier.padding(top = 12.dp),
            )
        }
    }
    SettingsFooter(
        if (silo) {
            "Silo alerts this phone when a show this profile follows gets a new episode, or a request changes. They arrive through Zelefin's push service, also while Zelefin is closed."
        } else {
            "Emby sends these through Zelefin's push service to this phone, also while Zelefin is closed. It only sends events this account is allowed to see."
        },
    )

    pluginState.alertsAdminAddress?.let { address ->
        SettingsHeader("Ask an Administrator")
        SettingsCard {
            Text(address, color = Secondary, fontFamily = FontFamily.Monospace, fontSize = 13.sp)
            SettingsCardDivider()
            SettingsButton(
                "Copy Address",
                primary = false,
                destructive = false,
                enabled = true,
                busy = false,
                onClick = { clipboard.setText(AnnotatedString(address)) },
            )
        }
        SettingsFooter(
            "This server only lets administrators add notifications. In Emby, an admin opens your user's Settings → Notifications, adds Webhooks, pastes this address, and picks the events.",
        )
    }

    if (on && !waitingForAdmin && pluginState.alertOptions.isNotEmpty()) {
        SettingsHeader("Alert Me About")
        SettingsCard {
            pluginState.alertOptions.forEachIndexed { index, (id, title) ->
                if (index > 0) CardDivider()
                SettingsToggle(title, id in pluginState.alertCategories) { next ->
                    if (!pluginState.alertsBusy) plugins.setWebhookAlertCategory(id, next)
                }
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

    if (state.isEmbyServer || state.isSiloServer) {
        WebhookNotificationsTopic(state, pluginState, plugins)
        return
    }

    if (!pluginState.companionAvailable) {
        val silo = state.isSiloServer
        val emby = state.isEmbyServer
        val canInstall = state.hasJellyfinExtras && pluginState.isAdmin
        SettingsCard {
            PluginStatusRow(
                "Zelefin plugin",
                installed = pluginState.pluginNeedsRestart,
                installedLabel = "Restart needed",
            )
            Text(
                when {
                    silo ->
                        "Lock-screen alerts need the Zelefin plugin on a Jellyfin server. Silo does not run Jellyfin plugins, so notifications are not available here."
                    emby ->
                        "Lock-screen alerts need the Zelefin plugin on a Jellyfin server. Emby does not run Jellyfin plugins, so notifications are not available here."
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
                SettingsCardDivider()
                SettingsPrimaryButton(
                    if (pluginState.pluginInstalling) "Installing…" else "Install Plugin",
                    busy = pluginState.pluginInstalling,
                    enabled = !pluginState.pluginInstalling && !pluginState.pluginNeedsRestart,
                    onClick = plugins::installZelefinPlugin,
                )
                if (pluginState.pluginNeedsRestart) {
                    SettingsCardDivider()
                    SettingsSecondaryButton(
                        if (pluginState.pluginRestarting) "Restarting…" else "Restart Jellyfin",
                        enabled = !pluginState.pluginRestarting,
                        onClick = plugins::restartJellyfin,
                    )
                }
            } else if (!silo && !emby && !pluginState.detecting) {
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
                    color = if (message.contains("could not") || message.contains("Sign in as")) IOSColors.red else Secondary,
                    fontFamily = ZelefinFont,
                    fontSize = 14.sp,
                    modifier = Modifier.padding(top = 12.dp),
                )
            }
        }
        SettingsFooter(
            when {
                silo || emby -> "Connect a Jellyfin server with the Zelefin plugin to receive notifications."
                canInstall -> "After install, restart Jellyfin so the plugin can load. You do not set up Firebase or paste a key on the server."
                else -> "In Jellyfin, open Dashboard → Plugins → Catalog, install Zelefin, then restart Jellyfin. You do not set up Firebase or paste a key on the server."
            },
        )
        return
    }

    val on = pluginState.pushEnabled && granted
    SettingsCard {
        SettingsToggle("Notifications", on, ::enable)
        if (on && ZelefinPush.isConfigured && pluginState.isAdmin) {
            SettingsCardDivider()
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
                color = if (message.startsWith("Sent")) Secondary else IOSColors.red,
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
    val jellyfin = pluginState.jellyfin
    val silo = state.isSiloServer
    val emby = state.isEmbyServer
    SettingsHeader("Skip Recaps, Intros, Credits and Previews")
    SettingsCard {
        if (!silo && !emby) {
            SkipPluginRow("Intro Skipper", jellyfin.introSkipper, "TheIntroDB", jellyfin.theIntroDB)
            CardDivider()
            SkipPluginRow("TheIntroDB", jellyfin.theIntroDB, "Intro Skipper", jellyfin.introSkipper)
            CardDivider()
        }
        SettingsToggle("Automatically Skip Recaps", pluginState.autoSkipRecap, plugins::setAutoSkipRecap)
        CardDivider()
        SettingsToggle("Automatically Skip Intros", pluginState.autoSkipIntro, plugins::setAutoSkipIntro)
        CardDivider()
        SettingsToggle("Automatically Skip Credits", pluginState.autoSkipCredits, plugins::setAutoSkipCredits)
        CardDivider()
        SettingsToggle("Automatically Skip Previews", pluginState.autoSkipPreview, plugins::setAutoSkipPreview)
        CardDivider()
        SettingsToggle("Look Up Skip Times on TheIntroDB", pluginState.usesTheIntroDB, plugins::setUsesTheIntroDB)
    }
    SettingsFooter(
        when {
            silo -> "Skip buttons appear when Silo has found a recap, intro, credits or preview, including from its built-in TheIntroDB support. For titles with none, Zelefin can ask TheIntroDB directly."
            emby -> "Skip buttons appear when Emby has marked an intro or credits. Emby has no TheIntroDB plugin, so for everything else Zelefin can ask TheIntroDB directly."
            else -> "Skip buttons come from Jellyfin's media segments, which Intro Skipper and the TheIntroDB plugin fill in once the Media Segment Scan task has run. For titles with none, Zelefin can ask TheIntroDB directly. Plugins only show as installed to an administrator."
        },
    )
    if (!silo && !emby) JellyfinServerPlugins(state, jellyfin)
    if (emby) {
        SettingsHeader("Open Subtitles")
        SettingsCard { PluginStatusRow("Open Subtitles", jellyfin.openSubtitles) }
        SettingsFooter(
            "When this Emby plugin is installed and signed in to an Open Subtitles account, use More on a movie or episode to search for subtitles and save a file to the server.",
        )
    }

    SettingsHeader("Seerr")
    SeerrSignInCard(state, pluginState, plugins)
    SettingsFooter(
        if (silo) {
            "Jellyseerr or Seerr lets you request movies and shows that are missing from Silo. Use your Seerr sign-in. Search for a title, then tap Request."
        } else if (emby) {
            "Jellyseerr or Seerr lets you request movies and shows that are missing from Emby. Use your Emby username and password. Search for a title, then tap Request."
        } else {
            "Jellyseerr or Seerr lets you request movies and shows that are missing from Jellyfin. Use your Jellyfin username and password. Search for a title, then tap Request."
        },
    )
}

@Composable
private fun JellyfinServerPlugins(state: ZelefinUiState, jellyfin: JellyfinPluginState) {

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

    val youTubeRooms = state.libraries.filter { it.kind == LibraryKind.YouTube }
    SettingsHeader("TubeArchivist")
    SettingsCard {
        PluginStatusRow(
            "TubeArchivist Metadata",
            youTubeRooms.isNotEmpty() || jellyfin.names.any { it.contains("TubeArchivist", ignoreCase = true) },
        )
    }
    SettingsFooter(
        if (youTubeRooms.isNotEmpty()) {
            "${youTubeRooms.joinToString { it.name }} appears as its own YouTube library, with channels and videos kept apart from your movies and shows."
        } else {
            "When this plugin fills a Shows library, Zelefin lists it as its own YouTube library, with channels and videos kept apart from your movies and shows."
        },
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
            SettingsCardDivider()
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
            SettingsCardDivider()
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
                color = if (positive) Secondary else IOSColors.red,
                fontFamily = ZelefinFont,
                fontSize = 14.sp,
                modifier = Modifier.padding(top = 12.dp),
            )
        }
    }
}

/** Fixed status colors, independent of the accent (iOS `LoginPalette.success`). */
private val StatusInstalled = Color(0xFF38C76B)
private val StatusMissing = IOSColors.red
private val StatusDisabled = Color(0xFFFF9F0A)

@Composable
private fun SkipPluginRow(title: String, presence: PluginPresence, otherName: String, other: PluginPresence) {
    val greyed = SkipPluginChoice.isGreyedOut(presence, other)
    Column(Modifier.fillMaxWidth().alpha(if (greyed) 0.5f else 1f).padding(vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = SettingsRowText, modifier = Modifier.weight(1f))
            Text(
                presence.label,
                color = when {
                    greyed -> Color.White.copy(alpha = 0.6f)
                    presence == PluginPresence.Enabled -> StatusInstalled
                    presence == PluginPresence.Disabled -> StatusDisabled
                    else -> StatusMissing
                },
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.Bold,
                fontSize = 13.sp,
            )
        }
        if (greyed) {
            Text(
                "Only one skip plugin can be enabled at a time. $otherName is enabled.",
                color = Color.White.copy(alpha = 0.6f),
                fontFamily = ZelefinFont,
                fontSize = 12.sp,
                modifier = Modifier.padding(top = 2.dp),
            )
        }
    }
}

@Composable
private fun PluginStatusRow(title: String, installed: Boolean, installedLabel: String = "Installed") {
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = SettingsRowText, modifier = Modifier.weight(1f))
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
    SettingsActionRow(title, busy = busy, enabled = enabled, destructive = destructive, onClick = onClick)
}

@Composable
private fun CardDivider() {
    SettingsCardDivider()
}

@Composable
internal fun SettingsFooter(text: String) {
    Text(
        text,
        color = IOSColors.secondaryLabel,
        fontFamily = ZelefinFont,
        fontSize = 13.sp,
        modifier = Modifier.padding(start = SettingsGroupMargin + SettingsContentInset, end = SettingsGroupMargin + SettingsContentInset, top = 7.dp),
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
        SettingsCardDivider()
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
        SettingsCardDivider()
        SettingsButton("Clear Saved Home Data", primary = false, destructive = true, enabled = saved > 0, busy = false) { confirm = true }
    }
    SettingsFooter("Home rows, library catalogs, and title pages saved so Zelefin opens right away.")
}

@Composable
private fun SessionsTopic(state: ZelefinUiState) {
    val session = state.session
    if (session != null && session.hasServerTools) {
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
        InfoLine(
            "Server Type",
            when {
                state.isSiloServer -> "Silo (Jellyfin API)"
                state.isEmbyServer -> "Emby"
                else -> "Jellyfin"
            },
        )
    }
    SettingsFooter("A native Jellyfin client for Android.")
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
        Text(title, style = SettingsRowText, modifier = Modifier.weight(1f))
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
            placeholder = "http://192.168.1.100:8096",
            keyboard = KeyboardType.Uri,
            ime = ImeAction.Done,
        )
        if (localText.isNotBlank() && HomeNetwork.normalizedLocal(localText) == null) {
            Text("Enter an address like http://192.168.1.100:8096.", color = IOSColors.red, fontFamily = ZelefinFont, fontSize = 13.sp)
        }
    }
    SettingsFooter(
        "On a saved home network, Zelefin uses the local URL when it answers and the remote one everywhere else. With no saved networks, any Wi-Fi where the local URL answers counts as home.",
    )

    SettingsHeader("Home Wi-Fi")
    SettingsCard {
        if (profile.homeSsids.isEmpty()) {
            Text("No networks saved", style = SettingsRowText)
            Text("Add a network so auto-switch knows when you’re home.", color = Caption, fontFamily = ZelefinFont, fontSize = 13.sp)
        } else {
            profile.homeSsids.forEachIndexed { index, name ->
                if (index > 0) CardDivider()
                Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Wifi, contentDescription = null, tint = ZelefinCyan, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.size(12.dp))
                    Text(name, style = SettingsRowText, modifier = Modifier.weight(1f))
                    Text(
                        "Remove",
                        color = IOSColors.red,
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
            SettingsCardDivider()
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
                SettingsCardDivider()
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
        SettingsCardDivider()
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

private val SettingsBarHeight = 56.dp

/**
 * iOS 26 navigation bar: the page scrolls under a centered title, with a liquid glass back
 * circle, or a glass Done / Cancel capsule on pages that close the sheet.
 */
@Composable
private fun SettingsPage(
    title: String,
    onBack: () -> Unit,
    bar: SettingsBarAction,
    large: Boolean = false,
    content: @Composable () -> Unit,
) {
    // iOS 26 sheets inset their bar buttons about 16pt from the rounded top edge.
    val topInset = if (LocalZelefinInSheet.current) Modifier.padding(top = 10.dp) else Modifier.statusBarsPadding()
    val canvas = MaterialTheme.colorScheme.surface
    val pageGlass = remember { GlassSource() }
    Box(Modifier.fillMaxSize().background(canvas)) {
        Column(
            Modifier
                .fillMaxSize()
                .glassSource(pageGlass)
                .background(canvas)
                .verticalScroll(rememberScrollState())
                .then(topInset)
                .navigationBarsPadding()
                .padding(top = SettingsBarHeight, bottom = 28.dp),
        ) {
            content()
        }
        Box(
            Modifier
                .fillMaxWidth()
                .background(Brush.verticalGradient(listOf(canvas, canvas.copy(alpha = 0.82f), canvas.copy(alpha = 0f))))
                .then(topInset)
                .height(SettingsBarHeight + 14.dp),
        )
        CompositionLocalProvider(LocalGlassSource provides pageGlass) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .then(topInset)
                    .height(SettingsBarHeight)
                    .padding(horizontal = 16.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    title,
                    color = Color.White,
                    fontFamily = ZelefinFont,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 17.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(horizontal = 72.dp),
                )
                when (bar) {
                    SettingsBarAction.Back -> SettingsGlassButton("Back", onBack, circle = true, modifier = Modifier.align(Alignment.CenterStart)) {
                        GlassBackChevron()
                    }
                    SettingsBarAction.Cancel -> SettingsGlassButton("Cancel", onBack, circle = false, modifier = Modifier.align(Alignment.CenterStart)) {
                        Text("Cancel", color = Color.White, fontFamily = ZelefinFont, fontSize = 17.sp)
                    }
                    SettingsBarAction.Done -> SettingsGlassButton("Done", onBack, circle = false, modifier = Modifier.align(Alignment.CenterEnd)) {
                        Text("Done", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
                    }
                }
            }
        }
    }
}

/** A 44dp liquid glass circle or capsule that swells a little while pressed, like iOS bar buttons. */
@Composable
private fun SettingsGlassButton(
    description: String,
    onClick: () -> Unit,
    circle: Boolean,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (pressed) 1.08f else 1f,
        animationSpec = spring(dampingRatio = 0.6f, stiffness = 600f),
        label = "glassPress",
    )
    Box(
        modifier
            .height(44.dp)
            .then(if (circle) Modifier.width(44.dp) else Modifier.widthIn(min = 44.dp))
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
            }
            .clickable(interactionSource = interaction, indication = null, role = Role.Button, onClickLabel = description, onClick = onClick)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        LiquidGlassPane(22.dp, Modifier.matchParentSize())
        Box(Modifier.padding(horizontal = if (circle) 0.dp else 16.dp)) { content() }
    }
}

/** SF Symbols `chevron.left` at the bar's semibold weight. */
@Composable
private fun GlassBackChevron() {
    val mirrored = LocalLayoutDirection.current == LayoutDirection.Rtl
    Canvas(Modifier.size(20.dp).graphicsLayer { scaleX = if (mirrored) -1f else 1f }) {
        val path = Path().apply {
            moveTo(size.width * 0.64f, size.height * 0.14f)
            lineTo(size.width * 0.3f, size.height * 0.5f)
            lineTo(size.width * 0.64f, size.height * 0.86f)
        }
        drawPath(path, Color.White, style = Stroke(width = 2.6.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

@Composable
internal fun SettingsHeader(title: String) {
    SettingsSectionLabel(title)
}

/** One inset grouped section; rows inside bring their own height and are split by [SettingsCardDivider]. */
@Composable
internal fun SettingsCard(onClick: (() -> Unit)? = null, content: @Composable () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = SettingsGroupMargin)
            .clip(SettingsGroupShape)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .heightIn(min = SettingsRowHeight)
            .padding(horizontal = SettingsContentInset, vertical = 2.dp),
        verticalArrangement = Arrangement.Center,
    ) { content() }
}

@Composable
private fun InfoLine(label: String, value: String) {
    SettingsInfoRow(label, value)
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
