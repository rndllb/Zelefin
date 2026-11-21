package app.zelefin.client.ui

import app.zelefin.client.plugins.RequestService
import app.zelefin.client.plugins.PluginPresence
import app.zelefin.client.plugins.SkipPluginChoice
import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.ContextWrapper
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Intent
import android.os.Build
import android.os.PersistableBundle
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
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
import app.zelefin.client.push.NotificationPreferences
import app.zelefin.client.push.ZelefinPush
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
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
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.List
import androidx.compose.material.icons.outlined.Brush
import androidx.compose.material.icons.outlined.ClosedCaption
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.HelpOutline
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.OpenInNew
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.ManageAccounts
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.RemoveCircle
import androidx.compose.material.icons.outlined.PrivacyTip
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TimePicker
import androidx.compose.material3.TimePickerLayoutType
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.material.icons.outlined.Extension
import androidx.compose.material.icons.outlined.Dashboard
import androidx.compose.material.icons.outlined.Devices
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Person
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.saveable.rememberSaveable
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.lifecycle.viewmodel.compose.viewModel
import app.zelefin.client.R
import app.zelefin.client.ServerInfoSnapshot
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import app.zelefin.client.AccountBiometrics
import app.zelefin.client.AccountSwitchPin
import app.zelefin.client.ProfileAccountOverview
import app.zelefin.client.ZelefinModel
import app.zelefin.client.network.HomeNetwork
import app.zelefin.client.network.HomeNetworkProfile
import app.zelefin.client.session.ArtworkCacheStore
import app.zelefin.client.session.CachePreferences
import app.zelefin.core.ArtworkDiskKey
import app.zelefin.core.ArtworkImageKind
import app.zelefin.core.CacheBucket
import app.zelefin.core.CacheInventory
import app.zelefin.core.MetadataCacheFolder
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

/** Child settings pages (a session, a user, a task) replace the navigation title and back action. */
internal class SettingsChrome {
    var title by mutableStateOf<String?>(null)
    var onBack by mutableStateOf<(() -> Unit)?>(null)
}

internal val LocalSettingsChrome = compositionLocalOf { SettingsChrome() }

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
    val serverType = session?.serverTypeName ?: "Jellyfin"
    val showServer = session?.hasServerTools == true && pluginState.isAdmin
    var confirmScan by remember { mutableStateOf(false) }
    var scanMessage by remember(session?.accountId) { mutableStateOf<String?>(null) }
    if (confirmScan) {
        SettingsAlertDialog(
            title = "Scan every library?",
            message = "Jellyfin will look for new files and refresh metadata. This can take a while on a large server.",
            confirmLabel = "Scan Libraries",
            onConfirm = {
                confirmScan = false
                scope.launch {
                    scanMessage = runCatching { model.scanLibraries() }
                        .map { "Scan started" }
                        .getOrElse { it.message ?: "Jellyfin could not start the scan." }
                }
            },
            onDismiss = { confirmScan = false },
        )
    }
    val context = LocalContext.current
    val cacheSize by produceState<Long?>(null) {
        value = withContext(Dispatchers.IO) {
            val root = File(context.cacheDir, "Zelefin")
            ArtworkCacheStore.usage(context).total.bytes + CacheInventory.metadataUsage(root).total.bytes
        }
    }
    SettingsPage(title = stringResource(R.string.settings_title), onBack = onBack, bar = bar) {
        SettingsGroup {
            SettingsProfileRow(session, onClick = onProfile)
            SettingsGroupDivider()
            SettingsNavRow(
                if (state.isSiloServer) "Accounts" else "Users",
                Icons.Outlined.People,
                summary = if (state.isSiloServer) {
                    "Switch or add a login on this device"
                } else {
                    "Switch or add a user on this device"
                },
                onClick = { onTopic(DeviceAccountsTopicId) },
            )
            if (jellyfin) {
                SettingsGroupDivider()
                SettingsNavRow(stringResource(R.string.account_syncplay),
                    Icons.Outlined.Groups,
                    summary = "Watch together in a group",
                    onClick = { onTopic("syncplay") },
                )
            }
        }
        if (session != null && !state.isEmbyServer) {
            QuickConnectAuthorizeSection(session.userName)
        }
        SettingsHeader(stringResource(R.string.settings_account))
        SettingsNavGroup(
            listOf(
                SettingsHubItem("Notifications", "Alerts from your server", Icons.Outlined.Notifications) { onTopic("notifications") },
            ),
        )
        SettingsHeader(stringResource(R.string.settings_playback))
        SettingsNavGroup(
            listOf(
                SettingsHubItem(
                    stringResource(R.string.settings_playback),
                    stringResource(R.string.settings_playback_subtitle),
                    Icons.Outlined.PlayArrow,
                ) { onTopic("playback") },
                SettingsHubItem(stringResource(R.string.player_subtitles), "Size, color, and background", Icons.Outlined.ClosedCaption) {
                    onTopic("subtitles")
                },
                SettingsHubItem("Plugins", "Intro Skipper, Seerr, Ombi, server plugins", Icons.Outlined.Extension) { onTopic("plugins") },
                SettingsHubItem("Metadata", "Ratings and title details", Icons.Outlined.Description) { onTopic("metadata") },
            ),
        )
        if (showServer) {
            SettingsHeader(stringResource(R.string.settings_server))
            SettingsNavGroup(
                buildList {
                    if (!state.isSiloServer) {
                        add(
                            SettingsHubItem(
                                stringResource(R.string.account_sessions),
                                "Devices signed in to $serverType",
                                Icons.Outlined.Devices,
                            ) { onTopic("sessions") },
                        )
                    }
                    add(SettingsHubItem("User Access", "Permissions, libraries, and parental controls", Icons.Outlined.ManageAccounts) { onTopic("users") })
                    add(SettingsHubItem("Scheduled Tasks", "Start, cancel, and watch progress", Icons.Outlined.Schedule) { onTopic("scheduled-tasks") })
                    add(SettingsHubItem("Activity Log", "Sign-ins, scans, and failures", Icons.AutoMirrored.Outlined.List) { onTopic("activity") })
                    if (jellyfin) {
                        add(SettingsHubItem("Backups", "Archive and restore this server", Icons.Outlined.Inventory2) { onTopic("backups") })
                    }
                    add(SettingsHubItem("Branding", "Login disclaimer and splashscreen", Icons.Outlined.Brush) { onTopic("branding") })
                    add(SettingsHubItem("Scan Libraries", scanMessage ?: "Look for new files and refresh metadata", Icons.Outlined.Refresh) { confirmScan = true })
                },
            )
            SettingsFooter("Administer this $serverType server.")
        }
        SettingsHeader(stringResource(R.string.settings_this_device))
        SettingsNavGroup(
            listOf(
                SettingsHubItem(
                    stringResource(R.string.settings_server_info),
                    stringResource(R.string.settings_server_info_subtitle),
                    Icons.Outlined.Dns,
                ) { onTopic("server") },
                SettingsHubItem(
                    stringResource(R.string.settings_network),
                    session?.displayServer?.takeIf { it.isNotBlank() } ?: stringResource(R.string.settings_network_subtitle),
                    Icons.Outlined.Wifi,
                ) { onTopic("network") },
                SettingsHubItem(
                    stringResource(R.string.settings_cache),
                    cacheSize?.takeIf { it > 0 }?.let(::formatBytes) ?: stringResource(R.string.settings_cache_subtitle),
                    Icons.Outlined.Storage,
                ) { onTopic("cache") },
                SettingsHubItem(
                    stringResource(R.string.settings_interface),
                    stringResource(R.string.settings_interface_subtitle_phone),
                    Icons.Outlined.Dashboard,
                ) { onTopic("interface") },
                SettingsHubItem(
                    stringResource(R.string.settings_log),
                    stringResource(R.string.settings_log_subtitle),
                    Icons.Outlined.Description,
                ) { onTopic("log") },
            ),
        )
        SettingsHeader(stringResource(R.string.settings_zelefin_section))
        SettingsNavGroup(
            listOf(SettingsHubItem(stringResource(R.string.settings_about), AppVersionLabel, Icons.Outlined.Info) { onTopic("about") }),
        )
    }
}

@Composable
private fun QuickConnectAuthorizeSection(userName: String) {
    val model: ZelefinModel = viewModel()
    val scope = rememberCoroutineScope()
    var code by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<Pair<String, Boolean>?>(null) }
    val digits = code.filter(Char::isDigit)
    val canAuthorize = digits.length >= 4 && !busy
    fun authorize() {
        if (!canAuthorize) return
        busy = true
        status = null
        val submitted = digits
        scope.launch {
            runCatching { model.authorizeQuickConnect(submitted) }
                .onSuccess {
                    code = ""
                    status = "Authorized. The other device can finish signing in." to false
                }
                .onFailure { error ->
                    status = (error.message ?: "Quick Connect could not be authorized.") to true
                }
            busy = false
        }
    }
    SettingsHeader(stringResource(R.string.connect_quick_connect))
    SettingsCard {
        SettingsTextField(
            label = "",
            value = code,
            icon = Icons.Outlined.Link,
            onChange = { if (!busy) code = it.filter(Char::isDigit).take(12) },
            placeholder = "Quick Connect code",
            keyboard = KeyboardType.Number,
            ime = ImeAction.Go,
            onIme = { authorize() },
        )
        SettingsCardDivider()
        SettingsActionRow(
            title = if (busy) "Authorizing…" else "Authorize Quick Connect",
            busy = busy,
            enabled = canAuthorize,
            onClick = { authorize() },
        )
        status?.let { (text, error) ->
            SettingsCardDivider()
            Text(
                text,
                color = if (error) IOSColors.red else IOSColors.secondaryLabel,
                fontFamily = ZelefinFont,
                fontSize = 13.sp,
                modifier = Modifier.padding(vertical = 12.dp),
            )
        }
    }
    SettingsFooter("Enter the code shown on another device to sign it in as $userName.")
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
    var tokenVisible by remember { mutableStateOf(false) }
    var tokenCopied by remember { mutableStateOf(false) }
    val accountId = session?.accountId
    var hasPin by remember(accountId) { mutableStateOf(accountId?.let(model::accountHasPin) == true) }
    var biometricsOn by remember(accountId) { mutableStateOf(accountId?.let(model::accountBiometricsEnabled) == true) }
    var pinEditor by remember(accountId) { mutableStateOf<AccountPinEditor?>(null) }
    var pinGate by remember(accountId) { mutableStateOf<AccountPinGate?>(null) }
    var pinError by remember(accountId) { mutableStateOf<String?>(null) }
    var pinAttempt by remember(accountId) { mutableStateOf(0) }
    var overview by remember(accountId) { mutableStateOf<ProfileAccountOverview?>(null) }
    var overviewError by remember(accountId) { mutableStateOf<String?>(null) }
    var loadingOverview by remember(accountId) { mutableStateOf(false) }
    var refreshingOverview by remember(accountId) { mutableStateOf(false) }
    val serverLabel = session?.displayServer?.takeIf { it.isNotBlank() } ?: "this server"
    val serverAddress = session?.serverUrl?.trim().orEmpty()
    val siloLink = session?.siloLink
    val household = state.household
    val serverType = session?.serverTypeName ?: "Jellyfin"
    val canChangePhoto = session != null && (!silo || siloLink != null)
    val canRemovePhoto = !silo && session?.userImageTag != null
    val biometricsAvailable = AccountBiometrics.canUse(context)
    val biometricsName = if (biometricsAvailable) AccountBiometrics.name(context) else null
    val pinUnlockName = biometricsName ?: "Fingerprint or face unlock"
    val pinFooter = "A 4–6 digit PIN locks this account on this device so others can’t sign into it. $pinUnlockName can unlock it instead of typing the PIN."
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
    val accessToken = session?.accessToken.orEmpty()
    LaunchedEffect(accountId, session?.userId) {
        if (accountId == null) return@LaunchedEffect
        loadingOverview = overview == null
        overviewError = null
        runCatching { model.profileAccountOverview() }
            .onSuccess { overview = it }
            .onFailure {
                overview = null
                overviewError = it.message ?: "Could not load this account."
            }
        loadingOverview = false
        refreshingOverview = false
    }
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
    fun finishPinGate(gate: AccountPinGate) {
        pinError = null
        pinGate = null
        when (gate) {
            AccountPinGate.Change -> pinEditor = AccountPinEditor.Change
            AccountPinGate.Remove -> {
                model.removeAccountPin()
                hasPin = false
                biometricsOn = false
                status = "Account PIN removed." to false
            }
        }
    }
    pinGate?.let { gate ->
        val unlockLabel = if (biometricsAvailable && biometricsOn) biometricsName else null
        AccountPinUnlockDialog(
            name = session?.userName ?: "this account",
            error = pinError,
            attempt = pinAttempt,
            biometricsLabel = unlockLabel,
            onBiometricUnlocked = { finishPinGate(gate) },
            onSubmit = { pin ->
                val id = session?.accountId
                if (id == null || !model.verifyAccountPin(id, pin)) {
                    pinAttempt += 1
                    pinError = "That PIN is incorrect."
                    return@AccountPinUnlockDialog
                }
                finishPinGate(gate)
            },
            onCancel = {
                pinGate = null
                pinError = null
            },
        )
    }
    pinEditor?.let { editor ->
        AccountPinEditorDialog(
            mode = editor,
            onCancel = { pinEditor = null },
            onSave = { pin ->
                model.setAccountPin(pin)
                hasPin = true
                biometricsOn = accountId?.let(model::accountBiometricsEnabled) == true
                pinEditor = null
                status = "Account PIN saved on this device." to false
            },
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
    val identitySubtitle = if (serverAddress.isNotEmpty()) serverAddress else "$serverType · $serverLabel"
    SettingsPage(
        title = stringResource(R.string.account_profile),
        onBack = onBack,
        bar = bar,
        refreshing = refreshingOverview,
        onRefresh = {
            refreshingOverview = true
            scope.launch {
                overviewError = null
                runCatching { model.profileAccountOverview() }
                    .onSuccess { overview = it }
                    .onFailure {
                        overview = null
                        overviewError = it.message ?: "Could not load this account."
                    }
                refreshingOverview = false
                loadingOverview = false
            }
        },
    ) {
        SettingsCard {
            Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                val choosePhoto = {
                    when {
                        uploading -> Unit
                        siloLink != null -> avatarSheet = true
                        else -> picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                    }
                }
                Box(Modifier.size(64.dp)) {
                    AccountAvatar(session, onClick = { if (canChangePhoto) choosePhoto() }, diameter = 64.dp)
                    if (uploading) {
                        Box(Modifier.size(64.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.48f)), contentAlignment = Alignment.Center) {
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
                Spacer(Modifier.width(16.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        session?.userName?.takeIf { it.isNotBlank() } ?: "Account",
                        color = Color.White,
                        fontFamily = ZelefinFont,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 20.sp,
                    )
                    Text(
                        identitySubtitle,
                        color = IOSColors.secondaryLabel,
                        fontFamily = ZelefinFont,
                        fontSize = 15.sp,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    if (canRemovePhoto) {
                        Text(
                            stringResource(R.string.ui_remove_photo),
                            style = SettingsRowText.copy(color = IOSColors.red, fontSize = 13.sp),
                            modifier = Modifier
                                .padding(top = 4.dp)
                                .clip(RoundedCornerShape(8.dp))
                                .clickable(enabled = !uploading, role = Role.Button, onClick = removePhoto)
                                .padding(vertical = 2.dp),
                        )
                    }
                    status?.let { (text, error) ->
                        Text(
                            text,
                            color = if (error) IOSColors.red else IOSColors.secondaryLabel,
                            fontFamily = ZelefinFont,
                            fontSize = 13.sp,
                            modifier = Modifier.padding(top = 6.dp),
                        )
                    }
                }
            }
        }
        if (siloLink != null && household.profiles.isNotEmpty()) {
            SettingsHeader(stringResource(R.string.connect_who_is_watching))
            SettingsCard {
                Row(
                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(vertical = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(18.dp),
                ) {
                    household.profiles.forEach { householdProfile ->
                        val current = householdProfile.id == siloLink.profileId
                        HouseholdProfileTile(
                            profile = householdProfile,
                            isCurrent = current,
                            isSelected = household.switchingTo == householdProfile.id,
                            enabled = !current && household.switchingTo == null,
                            dimmed = household.switchingTo != null && household.switchingTo != householdProfile.id,
                            onClick = { model.switchSiloProfile(householdProfile) },
                        )
                    }
                }
                household.message?.takeIf { state.siloPin == null }?.let { message ->
                    SettingsCardDivider()
                    Text(message, color = IOSColors.red, fontFamily = ZelefinFont, fontSize = 13.sp, modifier = Modifier.padding(vertical = 12.dp))
                }
            }
            SettingsFooter(stringResource(R.string.ui_continue_watching_recommendations_and_watched_fl))
        }
        if (loadingOverview && overview == null) {
            SettingsCard {
                Row(Modifier.fillMaxWidth().padding(vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                    IOSSpinner()
                    Spacer(Modifier.width(12.dp))
                    Text(stringResource(R.string.ui_loading_account), color = IOSColors.secondaryLabel, fontFamily = ZelefinFont, fontSize = 16.sp)
                }
            }
        }
        if (overviewError != null && overview == null) {
            SettingsCard {
                Text(overviewError.orEmpty(), color = IOSColors.red, fontFamily = ZelefinFont, fontSize = 14.sp, modifier = Modifier.padding(vertical = 14.dp))
            }
        }
        if (session != null) {
            SettingsHeader(stringResource(R.string.settings_account))
            SettingsCard {
                if (hasPin) {
                    InfoLine(stringResource(R.string.ui_account_pin), "On")
                    if (biometricsName != null) {
                        SettingsCardDivider()
                        SettingsToggleRow("Unlock with $biometricsName", biometricsOn, { enabled ->
                            biometricsOn = enabled
                            model.setAccountBiometrics(enabled)
                        })
                    }
                    SettingsCardDivider()
                    SettingsActionRow("Change PIN") {
                        pinError = null
                        pinGate = AccountPinGate.Change
                    }
                    SettingsCardDivider()
                    SettingsActionRow("Remove PIN", destructive = true) {
                        pinError = null
                        pinGate = AccountPinGate.Remove
                    }
                } else {
                    SettingsActionRow("Create Account PIN") { pinEditor = AccountPinEditor.Create }
                }
                overview?.let { account ->
                    SettingsCardDivider()
                    InfoLine(stringResource(R.string.ui_name), account.displayName)
                    SettingsCardDivider()
                    InfoLine(stringResource(R.string.ui_role), account.role)
                    SettingsCardDivider()
                    InfoLine(stringResource(R.string.connect_password), if (account.hasPassword) "Set" else "Not set")
                    SettingsCardDivider()
                    InfoLine(stringResource(R.string.ui_last_sign_in), account.lastLoginLabel)
                    SettingsCardDivider()
                    InfoLine(stringResource(R.string.ui_last_active), account.lastActivityLabel)
                }
                status?.let { (text, error) ->
                    SettingsCardDivider()
                    Text(
                        text,
                        color = if (error) IOSColors.red else IOSColors.secondaryLabel,
                        fontFamily = ZelefinFont,
                        fontSize = 13.sp,
                        modifier = Modifier.padding(vertical = 12.dp),
                    )
                }
            }
            SettingsFooter(pinFooter)
        }
        overview?.let { account ->
            SettingsHeader(stringResource(R.string.settings_libraries))
            SettingsCard { InfoLine(stringResource(R.string.ui_access), account.librariesSummary) }
            SettingsHeader(stringResource(R.string.ui_limits))
            SettingsCard {
                InfoLine(stringResource(R.string.ui_maximum_rating), account.maxRatingLabel)
                SettingsCardDivider()
                InfoLine(stringResource(R.string.ui_unrated_titles), account.unratedLabel)
                SettingsCardDivider()
                InfoLine(stringResource(R.string.ui_allowed_time), account.accessScheduleLabel)
            }
            SettingsFooter(account.limitsFooter)
            SettingsHeader(stringResource(R.string.ui_capabilities))
            SettingsCard {
                account.capabilities.forEachIndexed { index, capability ->
                    if (index > 0) SettingsCardDivider()
                    ProfileCapabilityRow(capability.title, capability.isAllowed)
                }
            }
            SettingsFooter("What this login is allowed to do on $serverLabel.")
            SettingsHeader(stringResource(R.string.ui_preferences))
            SettingsCard {
                InfoLine(stringResource(R.string.ui_audio_language), account.audioLanguageLabel)
                SettingsCardDivider()
                ProfileCapabilityRow("Play the default audio track", account.playDefaultAudio)
                SettingsCardDivider()
                InfoLine(stringResource(R.string.ui_subtitle_language), account.subtitleLanguageLabel)
                SettingsCardDivider()
                InfoLine(stringResource(R.string.player_subtitles), account.subtitleModeLabel)
                SettingsCardDivider()
                ProfileCapabilityRow("Play next episode automatically", account.autoPlayNextEpisode)
                SettingsCardDivider()
                ProfileCapabilityRow("Remember audio choices", account.rememberAudio)
                SettingsCardDivider()
                ProfileCapabilityRow("Remember subtitle choices", account.rememberSubtitles)
                SettingsCardDivider()
                ProfileCapabilityRow("Hide watched titles in Latest", account.hideWatchedInLatest)
                SettingsCardDivider()
                Row(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = SettingsRowHeight)
                        .clickable { model.openSettingsTopic("playback") }
                        .padding(vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Edit in Playback", style = SettingsRowText, modifier = Modifier.weight(1f))
                    Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = IOSColors.tertiaryLabel)
                }
            }
            SettingsFooter(stringResource(R.string.ui_language_and_autoplay_defaults_live_on_the_serve))
        }
        if (accessToken.isNotEmpty()) {
            SettingsHeader(stringResource(R.string.ui_device_token))
            SettingsCard {
                InfoLine(stringResource(R.string.ui_device_token), if (tokenVisible) accessToken else "•".repeat(accessToken.length.coerceIn(12, 28)))
                SettingsCardDivider()
                SettingsActionRow(if (tokenVisible) "Hide Token" else "Show Token") { tokenVisible = !tokenVisible }
                SettingsCardDivider()
                SettingsActionRow(if (tokenCopied) "Copied" else "Copy Token", onClick = copyToken)
            }
            SettingsFooter("This token signs this device into $serverLabel. Copy it only into apps you trust.")
        }
    }
}

@Composable
private fun ProfileCapabilityRow(title: String, isAllowed: Boolean) {
    Row(Modifier.fillMaxWidth().heightIn(min = SettingsRowHeight).padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = SettingsRowText, modifier = Modifier.weight(1f).padding(end = 12.dp))
        Icon(
            if (isAllowed) Icons.Filled.CheckCircle else Icons.Outlined.RemoveCircle,
            contentDescription = if (isAllowed) "Allowed" else "Not allowed",
            tint = if (isAllowed) ZelefinCyan else IOSColors.tertiaryLabel,
            modifier = Modifier.size(22.dp),
        )
    }
}

@Composable
private fun DeviceAccountsTopic(state: ZelefinUiState) {
    val model: ZelefinModel = viewModel()
    val session = state.session
    val silo = state.isSiloServer
    val addTitle = if (silo) "Add Account" else "Add User"
    SettingsCard {
        session?.let { current ->
            DeviceAccountRow(current, subtitle = "Signed in", current = true, onClick = null)
            SettingsCardDivider()
        }
        state.accounts.filter { it.accountId != session?.accountId }.forEach { account ->
            DeviceAccountRow(
                account,
                subtitle = deviceAccountSubtitle(account, session),
                current = false,
                onClick = { model.switchAccount(account) },
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
            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = IOSColors.tertiaryLabel)
        }
    }
    SettingsFooter(deviceAccountsFooter(state))
}

@Composable
private fun DeviceAccountRow(account: SavedSession, subtitle: String, current: Boolean, onClick: (() -> Unit)?) {
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
            Text(account.userName, style = SettingsRowText, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(subtitle, color = IOSColors.secondaryLabel, fontFamily = ZelefinFont, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (current) {
            Icon(Icons.Outlined.Check, contentDescription = "Signed in", tint = ZelefinCyan, modifier = Modifier.size(20.dp))
        } else {
            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = IOSColors.tertiaryLabel)
        }
    }
}

private fun deviceAccountSubtitle(account: SavedSession, current: SavedSession?): String {
    val currentHost = current?.serverUrl?.let(::serverHost)
    val accountHost = serverHost(account.serverUrl)
    return if (currentHost != null && currentHost == accountHost) "On this device" else account.displayServer
}

private fun serverHost(url: String): String? = Uri.parse(url).host?.trim()?.lowercase()?.takeIf { it.isNotEmpty() }

private fun deviceAccountsFooter(state: ZelefinUiState): String {
    val session = state.session
    if (session?.siloLink != null) return "Household profiles switch under Profile. Saved users stay on this device."
    if (state.isSiloServer) return "Add another household profile by signing in as username#profile. Saved users stay on this device."
    val server = session?.displayServer?.takeIf { it.isNotBlank() } ?: "this server"
    return "Add another person on $server. Saved users stay on this device."
}

private enum class AccountPinEditor { Create, Change }

private enum class AccountPinGate { Change, Remove }

/** Asks for the device PIN before switching to a locked account, or before changing or removing it. */
@Composable
fun AccountPinUnlockDialog(
    name: String,
    error: String?,
    attempt: Int,
    biometricsLabel: String? = null,
    onBiometricUnlocked: () -> Unit = {},
    onSubmit: (String) -> Unit,
    onCancel: () -> Unit,
) {
    var pin by rememberSaveable(name, attempt) { mutableStateOf("") }
    val canSubmit = pin.length in 4..6
    val unlock = rememberBiometricUnlock()
    var showPin by remember(name, biometricsLabel) { mutableStateOf(biometricsLabel == null) }
    LaunchedEffect(name, biometricsLabel) {
        val label = biometricsLabel
        if (label == null) {
            showPin = true
            return@LaunchedEffect
        }
        showPin = false
        unlock("Unlock $name’s account") { ok ->
            if (ok) onBiometricUnlocked() else showPin = true
        }
    }
    if (!showPin) return
    Dialog(onDismissRequest = onCancel) {
        Column(
            Modifier
                .widthIn(max = 320.dp)
                .fillMaxWidth()
                .clip(RoundedCornerShape(34.dp))
                .background(IOSColors.alert)
                .padding(start = 22.dp, end = 22.dp, top = 22.dp, bottom = 18.dp),
        ) {
            Text(stringResource(R.string.ui_account_pin), color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            Spacer(Modifier.height(6.dp))
            Text(
                "Enter the PIN to unlock $name’s account on this device.",
                color = Color.White.copy(alpha = 0.82f),
                fontFamily = ZelefinFont,
                fontSize = 15.sp,
            )
            Spacer(Modifier.height(16.dp))
            AccountPinField(pin, { pin = it }, "PIN")
            if (!error.isNullOrBlank()) {
                Spacer(Modifier.height(10.dp))
                Text(error, color = IOSColors.red, fontFamily = ZelefinFont, fontSize = 13.sp)
            }
            Spacer(Modifier.height(20.dp))
            if (biometricsLabel != null) {
                IOSCapsuleButton(biometricsLabel, {
                    unlock("Unlock $name’s account") { ok -> if (ok) onBiometricUnlocked() }
                }, Modifier.fillMaxWidth())
                Spacer(Modifier.height(10.dp))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                IOSCapsuleButton("Cancel", onCancel, Modifier.weight(1f))
                IOSCapsuleButton("Unlock", { onSubmit(pin) }, Modifier.weight(1f), prominent = true, enabled = canSubmit)
            }
        }
    }
}

private fun android.content.Context.findFragmentActivity(): FragmentActivity? {
    var current = this
    while (current is ContextWrapper) {
        if (current is FragmentActivity) return current
        current = current.baseContext
    }
    return null
}

@Composable
private fun rememberBiometricUnlock(): (String, (Boolean) -> Unit) -> Unit {
    val activity = LocalContext.current.findFragmentActivity()
    return remember(activity) {
        { reason, onResult ->
            if (activity == null) {
                onResult(false)
            } else {
                var finished = false
                fun finish(ok: Boolean) {
                    if (finished) return
                    finished = true
                    onResult(ok)
                }
                val prompt = BiometricPrompt(
                    activity,
                    ContextCompat.getMainExecutor(activity),
                    object : BiometricPrompt.AuthenticationCallback() {
                        override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) = finish(true)
                        override fun onAuthenticationError(errorCode: Int, errString: CharSequence) = finish(false)
                    },
                )
                prompt.authenticate(
                    BiometricPrompt.PromptInfo.Builder()
                        .setTitle(reason)
                        .setNegativeButtonText("Enter PIN")
                        .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_WEAK)
                        .build(),
                )
            }
        }
    }
}

@Composable
private fun AccountPinEditorDialog(
    mode: AccountPinEditor,
    onSave: (String) -> Unit,
    onCancel: () -> Unit,
) {
    var pin by rememberSaveable(mode) { mutableStateOf("") }
    var confirm by rememberSaveable(mode) { mutableStateOf("") }
    var error by rememberSaveable(mode) { mutableStateOf<String?>(null) }
    val title = when (mode) {
        AccountPinEditor.Create -> "Create Account PIN"
        AccountPinEditor.Change -> "Change Account PIN"
    }
    val canSave = AccountSwitchPin.isValid(pin) && pin == confirm
    Dialog(onDismissRequest = onCancel) {
        Column(
            Modifier
                .widthIn(max = 320.dp)
                .fillMaxWidth()
                .clip(RoundedCornerShape(34.dp))
                .background(IOSColors.alert)
                .padding(start = 22.dp, end = 22.dp, top = 22.dp, bottom = 18.dp),
        ) {
            Text(title, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            Spacer(Modifier.height(6.dp))
            Text(
                stringResource(R.string.ui_use_4_to_6_digits_this_pin_stays_on_this_device),
                color = Color.White.copy(alpha = 0.82f),
                fontFamily = ZelefinFont,
                fontSize = 15.sp,
            )
            Spacer(Modifier.height(16.dp))
            AccountPinField(pin, { pin = it }, "PIN")
            Spacer(Modifier.height(10.dp))
            AccountPinField(confirm, { confirm = it }, "Confirm PIN")
            val pinError = error
            if (!pinError.isNullOrBlank()) {
                Spacer(Modifier.height(10.dp))
                Text(pinError, color = IOSColors.red, fontFamily = ZelefinFont, fontSize = 13.sp)
            }
            Spacer(Modifier.height(20.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                IOSCapsuleButton("Cancel", onCancel, Modifier.weight(1f))
                IOSCapsuleButton(
                    "Save",
                    {
                        if (pin != confirm) {
                            error = "The PINs do not match."
                            return@IOSCapsuleButton
                        }
                        runCatching { onSave(pin) }
                            .onFailure { error = it.message ?: "Zelefin could not save this PIN on the device." }
                    },
                    Modifier.weight(1f),
                    prominent = true,
                    enabled = canSave,
                )
            }
        }
    }
}

@Composable
private fun AccountPinField(value: String, onChange: (String) -> Unit, placeholder: String) {
    BasicTextField(
        value = value,
        onValueChange = { onChange(it.filter(Char::isDigit).take(6)) },
        singleLine = true,
        textStyle = TextStyle(
            color = Color.White,
            fontFamily = ZelefinFont,
            fontWeight = FontWeight.Bold,
            fontSize = 22.sp,
            letterSpacing = 6.sp,
            textAlign = TextAlign.Center,
        ),
        cursorBrush = SolidColor(ZelefinCyan),
        visualTransformation = PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword, imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(),
        decorationBox = { field ->
            Box(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(Color.White.copy(alpha = 0.08f))
                    .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(14.dp))
                    .padding(vertical = 12.dp),
                contentAlignment = Alignment.Center,
            ) {
                if (value.isEmpty()) {
                    Text(placeholder, color = IOSColors.tertiaryLabel, fontFamily = ZelefinFont, fontSize = 16.sp)
                }
                field()
            }
        },
    )
}

/** iOS `AddAccountView`: sign in another user on the server already in use. */
@Composable
private fun AddAccountTopic(state: ZelefinUiState) {
    val model: ZelefinModel = viewModel()
    val add = state.addAccount
    val serverUrl = state.session?.serverUrl.orEmpty()
    val serverLabel = state.session?.displayServer?.takeIf { it.isNotBlank() } ?: "Jellyfin"
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    DisposableEffect(Unit) { onDispose { model.resetAddAccount() } }
    SettingsHeader(stringResource(R.string.settings_server))
    SettingsCard {
        InfoLine(stringResource(R.string.settings_server), serverLabel)
    }
    SettingsFooter(
        if (state.isSiloServer) "Sign in as username#profile to add another household profile on this Silo server."
        else "New users are added on the server you’re already using.",
    )
    SettingsHeader(stringResource(R.string.connect_sign_in))
    val canSubmit = serverUrl.isNotBlank() && username.isNotBlank() && password.isNotEmpty() && !add.busy
    SettingsCard {
        SettingsTextField(
            label = "",
            value = username,
            icon = Icons.Outlined.Person,
            onChange = { username = it },
            placeholder = if (state.isSiloServer) "username#profile" else "Username",
            keyboard = KeyboardType.Text,
            ime = ImeAction.Next,
        )
        CardDivider()
        SettingsTextField(
            label = "",
            value = password,
            icon = Icons.Outlined.Lock,
            onChange = { password = it },
            placeholder = "Password",
            password = true,
            keyboard = KeyboardType.Password,
            ime = ImeAction.Go,
            onIme = { if (canSubmit) model.addAccount(serverUrl, username, password) },
        )
        SettingsCardDivider()
        SettingsButton(if (state.isSiloServer) "Add Account" else "Add User", primary = true, destructive = false, enabled = canSubmit, busy = add.busy) {
            model.addAccount(serverUrl, username, password)
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
    val topicId = if (id == "appearance") "interface" else id
    var editingInterface by remember { mutableStateOf(false) }
    val chrome = remember(id) { SettingsChrome() }
    val title = chrome.title ?: when (topicId) {
        "notifications" -> "Notifications"
        "sessions" -> "Sessions"
        "playback" -> "Playback"
        "subtitles" -> "Subtitles"
        "plugins" -> "Plugins"
        "metadata" -> "Metadata"
        "network" -> "Network"
        "cache" -> "Cache"
        "interface" -> "Interface"
        "server" -> "Server Info"
        "log" -> "Log"
        "report" -> "Report Issue"
        "about" -> "About"
        "syncplay" -> "SyncPlay"
        "users" -> "Users"
        DeviceAccountsTopicId -> if (state.isSiloServer) "Accounts" else "Users"
        "scheduled-tasks" -> "Scheduled Tasks"
        "activity" -> "Activity Log"
        "backups" -> "Backups"
        "branding" -> "Branding"
        AddAccountTopicId -> if (state.isSiloServer) "Add Account" else "Add User"
        else -> when {
            id.startsWith("user:") -> "User"
            id.startsWith("scheduled-task:") -> "Task"
            id.startsWith(LibraryIconTopicPrefix) ->
                state.libraries.firstOrNull { it.id == id.removePrefix(LibraryIconTopicPrefix) }?.name ?: "Icon"
            id.startsWith(CustomHomeTopicPrefix) ->
                app.zelefin.client.CustomHomeRows.row(id.removePrefix(CustomHomeTopicPrefix))?.title ?: "Custom Row"
            else -> "Settings"
        }
    }
    SettingsPage(
        title = title,
        onBack = { chrome.onBack?.invoke() ?: onBack() },
        bar = bar,
        trailing = if (topicId == "interface") {
            {
                val label = if (editingInterface) "Done" else "Edit"
                SettingsGlassButton(label, { editingInterface = !editingInterface }, circle = false) {
                    Text(
                        label,
                        color = Color.White,
                        fontFamily = ZelefinFont,
                        fontWeight = if (editingInterface) FontWeight.SemiBold else FontWeight.Normal,
                        fontSize = 17.sp,
                    )
                }
            }
        } else {
            null
        },
    ) {
        CompositionLocalProvider(LocalSettingsChrome provides chrome) {
        when (topicId) {
            "playback" -> PlaybackTopic(state)
            "subtitles" -> SubtitleAppearanceTopic()
            "cache" -> CacheTopic()
            "metadata" -> MetadataTopic()
            "sessions" -> SessionsTopic(state)
            "about" -> AboutTopic()
            AddAccountTopicId -> AddAccountTopic(state)
            "notifications" -> NotificationsTopic(state, plugins)
            "plugins" -> PluginsTopic(state, plugins)
            "network" -> NetworkTopic(state)
            "interface" -> InterfaceTopic(state, editingInterface)
            "server" -> ServerInfoTopic(state)
            "log" -> LogTopic(state, plugins)
            "report" -> ReportIssueTopic(state, plugins)
            "syncplay" -> SyncPlayTopic(state)
            "users" -> UsersTopic()
            DeviceAccountsTopicId -> DeviceAccountsTopic(state)
            "scheduled-tasks" -> ScheduledTasksTopic()
            "activity" -> ActivityLogTopic()
            "backups" -> BackupsTopic()
            "branding" -> BrandingTopic(state)
            else -> when {
                id.startsWith("user:") -> UserEditorTopic(id.removePrefix("user:"), state)
                id.startsWith("scheduled-task:") -> ScheduledTaskDetailTopic(id.removePrefix("scheduled-task:"))
                id.startsWith(LibraryIconTopicPrefix) -> LibraryIconPicker(id.removePrefix(LibraryIconTopicPrefix), state)
                id.startsWith(CustomHomeTopicPrefix) -> CustomHomeRowEditorTopic(
                    rowId = id.removePrefix(CustomHomeTopicPrefix),
                    onDeleted = onBack,
                )
                else -> Text("Nothing to change here yet.", color = Secondary, fontFamily = ZelefinFont)
            }
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
    var stillWatching by remember { mutableStateOf(PlaybackPreferences.stillWatchingEnabled(context)) }
    var autoPip by remember { mutableStateOf(PlaybackPreferences.autoPipOnLeave(context)) }
    var back by remember { mutableStateOf(PlaybackPreferences.skipBackward(context)) }
    var forward by remember { mutableStateOf(PlaybackPreferences.skipForward(context)) }
    var playerEngine by remember { mutableStateOf(PlaybackPreferences.playerEngine(context)) }
    var wifiOnly by remember { mutableStateOf(PlaybackPreferences.downloadWifiOnly(context)) }
    var themeSongs by remember { mutableStateOf(PlaybackPreferences.themeSongs(context)) }
    var themeVideos by remember { mutableStateOf(PlaybackPreferences.themeVideos(context)) }
    var themeVideoSound by remember { mutableStateOf(PlaybackPreferences.themeVideoSound(context)) }
    val languages = remember(context) { PlaybackLanguage.choices(context) }

    JellyfinPlaybackPreferencesSections(model, languages, serverName = if (state.isEmbyServer) "Emby" else "Jellyfin")

    SettingsHeader(stringResource(R.string.player_quality))
    SettingsCard {
        SettingsToggleRow(stringResource(R.string.ui_adaptive_bitrate), adaptive, {
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

    SettingsHeader(stringResource(R.string.Watching))
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
        SettingsToggleRow(stringResource(R.string.ui_auto_play_next_episode), autoplay, {
            autoplay = it
            PlaybackPreferences.setAutoplayNext(context, it)
        })
        if (autoplay) {
            SettingsCardDivider()
            SettingsToggleRow(stringResource(R.string.ui_ask_if_still_watching), stillWatching, {
                stillWatching = it
                PlaybackPreferences.setStillWatchingEnabled(context, it)
            })
        }
        SettingsCardDivider()
        SettingsToggleRow(stringResource(R.string.ui_picture_in_picture_when_leaving), autoPip, {
            autoPip = it
            PlaybackPreferences.setAutoPipOnLeave(context, it)
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
        SettingsToggleRow(stringResource(R.string.ui_wi_fi_only_downloads), wifiOnly, {
            wifiOnly = it
            PlaybackPreferences.setDownloadWifiOnly(context, it)
        })
    }
    val playerFooter = if (playerEngine == PlaybackPreferences.ENGINE_MPV) {
        "MPV Direct Plays every stream on this device and lists every audio and subtitle track in the file, including styled subtitles."
    } else {
        "ExoPlayer Direct Plays streams this device can open and lists the audio and subtitle tracks it can play."
    }
    SettingsFooter(
        "Speed, skip distance, and whether the next episode starts when this one ends. " +
            "Ask If Still Watching pauses binge auto-play after ${PlaybackPreferences.STILL_WATCHING_THRESHOLD} episodes. " +
            "Picture in Picture When Leaving keeps playback going in a small window when you close the player. " +
            playerFooter,
    )

    SettingsHeader(stringResource(R.string.ui_theme_media))
    SettingsCard {
        SettingsToggleRow(stringResource(R.string.ui_theme_songs), themeSongs, {
            themeSongs = it
            PlaybackPreferences.setThemeSongs(context, it)
        })
        if (!silo) {
            SettingsCardDivider()
            SettingsToggleRow(stringResource(R.string.ui_theme_videos), themeVideos, {
                themeVideos = it
                PlaybackPreferences.setThemeVideos(context, it)
            })
            if (themeVideos) {
                SettingsCardDivider()
                SettingsToggleRow(stringResource(R.string.ui_theme_video_sound), themeVideoSound, {
                    themeVideoSound = it
                    PlaybackPreferences.setThemeVideoSound(context, it)
                })
            }
        }
    }
    val serverName = if (state.isEmbyServer) "Emby" else "Jellyfin"
    SettingsFooter(
        if (silo) {
            "Plays a title's theme song on its page."
        } else {
            "Plays a title's $serverName theme video in place of the backdrop, or its theme song when it has no video. Theme videos are muted unless Theme Video Sound is on."
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
    val lift by animateDpAsState(
        (style.positionLift.coerceIn(0, 100) / 100f * 72f).dp,
        label = "subtitle-preview-lift",
    )
    SettingsHeader(stringResource(R.string.Style))
    SettingsCard {
        Box(
            Modifier
                .fillMaxWidth()
                .padding(vertical = 4.dp)
                .heightIn(min = 140.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(Color.Black.copy(alpha = 0.55f)),
            contentAlignment = Alignment.BottomCenter,
        ) {
            SubtitleSample(style, Modifier.padding(start = 12.dp, end = 12.dp, bottom = 10.dp + lift))
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
        SettingsCardDivider()
        SettingsSliderRow(
            label = "Raise",
            value = style.positionLift.toFloat(),
            valueText = style.positionLift.toString(),
            range = 0f..100f,
            steps = 99,
            onChange = {
                SubtitleAppearance.setPositionLift(context, (it + 0.5f).toInt().coerceIn(0, 100))
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
    SettingsFooter(stringResource(R.string.ui_raise_captions_from_the_bottom_of_the_picture_st))
}

/** Preview line with the same drop shadow, outline, and highlight as iOS `SubtitleTextChrome`. */
@Composable
private fun SubtitleSample(style: SubtitleAppearance.Snapshot, modifier: Modifier = Modifier) {
    val density = LocalDensity.current
    val ink = Color(style.foregroundArgb())
    val textStyle = TextStyle(
        color = ink,
        fontFamily = ZelefinFont,
        fontWeight = FontWeight.SemiBold,
        fontSize = (17 * style.sizeScale).sp,
        textAlign = TextAlign.Center,
    )
    val label = "Sample subtitle text"
    when (style.background) {
        SubtitleAppearance.BACK_HIGHLIGHT -> Text(
            label,
            style = textStyle,
            modifier = modifier
                .clip(RoundedCornerShape(4.dp))
                .background(Color(style.windowArgb()))
                .padding(horizontal = 8.dp, vertical = 4.dp),
        )
        SubtitleAppearance.BACK_OUTLINE -> Box(modifier, contentAlignment = Alignment.Center) {
            listOf(1 to 0, -1 to 0, 0 to 1, 0 to -1).forEach { (x, y) ->
                Text(label, style = textStyle.copy(color = Color.Black), modifier = Modifier.offset(x.dp, y.dp))
            }
            Text(label, style = textStyle)
        }
        SubtitleAppearance.BACK_SHADOW -> {
            val soft = with(density) {
                Shadow(Color.Black.copy(alpha = 0.95f), Offset(0f, 1.dp.toPx()), 2.dp.toPx())
            }
            Box(modifier, contentAlignment = Alignment.Center) {
                Text(label, style = textStyle.copy(color = Color.Black), modifier = Modifier.offset(y = 1.dp))
                Text(label, style = textStyle.copy(shadow = soft))
            }
        }
        else -> Text(label, style = textStyle, modifier = modifier)
    }
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
    val context = LocalContext.current
    var preferSdh by remember { mutableStateOf(PlaybackPreferences.preferSdh(context)) }

    SettingsHeader(if (loading) "Audio…" else "Audio")
    SettingsCard {
        LockedUntilReady(ready) {
            SettingsMenuPicker(
                label = "Preferred Language",
                choices = languageChoices(preferences?.audioLanguage),
                selected = shown.audioLanguage,
                onSelect = { code -> if (ready) update { it.copy(audioLanguage = code) } },
            )
            SettingsCardDivider()
            SettingsToggleRow(stringResource(R.string.ui_play_default_audio_track), shown.playDefaultAudioTrack, { on -> if (ready) update { it.copy(playDefaultAudioTrack = on) } })
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

    SettingsHeader(stringResource(R.string.player_subtitles))
    SettingsCard {
        LockedUntilReady(ready) {
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
            SettingsToggleRow(stringResource(R.string.ui_prefer_sdh_subtitles), preferSdh, { on ->
                if (!ready) return@SettingsToggleRow
                preferSdh = on
                PlaybackPreferences.setPreferSdh(context, on)
            })
            SettingsCardDivider()
            Row(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = SettingsRowHeight)
                    .clickable(enabled = ready) { model.openSettingsTopic("subtitles") }
                    .padding(vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(stringResource(R.string.ui_style_sync), style = SettingsRowText, modifier = Modifier.weight(1f))
                Text(
                    SubtitleAppearance.current(context).sizeTitle(),
                    style = SettingsRowText.copy(color = IOSColors.secondaryLabel),
                    maxLines = 1,
                )
                Icon(
                    Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                    contentDescription = null,
                    tint = IOSColors.tertiaryLabel,
                    modifier = Modifier.padding(start = 4.dp).size(20.dp),
                )
            }
        }
    }
    SettingsFooter(shown.subtitleMode.summary + " SDH prefers captions that describe music and sound. Style & Sync change how captions look and when they appear.")
}

/** Greys out and swallows taps until server playback preferences have loaded. */
@Composable
private fun LockedUntilReady(ready: Boolean, content: @Composable () -> Unit) {
    val block = remember { MutableInteractionSource() }
    Box(Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth().alpha(if (ready) 1f else 0.55f)) { content() }
        if (!ready) {
            Box(
                Modifier
                    .matchParentSize()
                    .clickable(interactionSource = block, indication = null, onClick = {}),
            )
        }
    }
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

    if (pluginState.detecting && !pluginState.webhooksAvailable) {
        SettingsCard {
            Box(Modifier.fillMaxWidth().padding(vertical = 18.dp), contentAlignment = Alignment.Center) {
                IOSSpinner()
            }
        }
        return
    }

    if (!pluginState.webhooksAvailable) {
        SettingsCard { PluginStatusRow(if (silo) "Silo Webhooks" else "Emby Webhooks", false) }
        SettingsFooter(
            when {
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
            "Silo alerts this phone when a show this profile follows gets a new episode, or a request changes. They arrive through Zelefin's push service while Zelefin is closed. Quiet hours and mute options can hold banners back."
        } else {
            "Emby sends these through Zelefin's push service to this phone while Zelefin is closed. It only sends events this account is allowed to see. Quiet hours and mute options can hold banners back."
        },
    )
    if (on) NotificationDeliverySections()

    pluginState.alertsAdminAddress?.let { address ->
        SettingsHeader(stringResource(R.string.ui_ask_an_administrator))
        SettingsCard {
            Text(address, color = Secondary, fontFamily = FontFamily.Monospace, fontSize = 13.sp)
            SettingsCardDivider()
            SettingsButton(
                stringResource(R.string.ui_copy_address),
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
        SettingsHeader(stringResource(R.string.ui_alert_me_about))
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

/** Quiet hours and mute, for every signed-in user once the master switch is on. */
@Composable
private fun NotificationDeliverySections() {
    val context = LocalContext.current
    var muteOpen by remember { mutableStateOf(NotificationPreferences.muteWhileOpen(context)) }
    var mutePlaying by remember { mutableStateOf(NotificationPreferences.muteWhilePlaying(context)) }
    var quiet by remember { mutableStateOf(NotificationPreferences.quietHoursEnabled(context)) }
    var startMinutes by remember { mutableIntStateOf(NotificationPreferences.quietHoursStartMinutes(context)) }
    var endMinutes by remember { mutableIntStateOf(NotificationPreferences.quietHoursEndMinutes(context)) }

    SettingsHeader(stringResource(R.string.ui_when_not_to_notify))
    SettingsCard {
        SettingsToggle("Mute while Zelefin is open", muteOpen) { next ->
            muteOpen = next
            NotificationPreferences.setMuteWhileOpen(context, next)
        }
        SettingsCardDivider()
        SettingsToggle("Mute while playing", mutePlaying) { next ->
            mutePlaying = next
            NotificationPreferences.setMuteWhilePlaying(context, next)
        }
    }
    SettingsFooter(
        stringResource(R.string.ui_hold_banners_back_while_you_are_using_zelefin_or),
    )

    SettingsHeader(stringResource(R.string.ui_quiet_hours))
    SettingsCard {
        SettingsToggle("Quiet Hours", quiet) { next ->
            quiet = next
            NotificationPreferences.setQuietHoursEnabled(context, next)
        }
        if (quiet) {
            SettingsCardDivider()
            QuietHourRow("Start", startMinutes) { picked ->
                startMinutes = picked
                NotificationPreferences.setQuietHoursStartMinutes(context, picked)
            }
            SettingsCardDivider()
            QuietHourRow("End", endMinutes) { picked ->
                endMinutes = picked
                NotificationPreferences.setQuietHoursEndMinutes(context, picked)
            }
        }
    }
    SettingsFooter(stringResource(R.string.ui_no_lock_screen_alerts_during_this_window_overnig))
}

@Composable
private fun QuietHourRow(label: String, minutes: Int, onPick: (Int) -> Unit) {
    val context = LocalContext.current
    var open by remember { mutableStateOf(false) }
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = SettingsRowHeight)
            .clickable(role = Role.Button) { open = true }
            .padding(vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = SettingsRowText, modifier = Modifier.weight(1f))
        Text(
            NotificationPreferences.timeLabel(context, minutes),
            style = SettingsRowText.copy(color = IOSColors.secondaryLabel),
        )
    }
    if (open) {
        QuietHourPickerDialog(
            title = label,
            minutes = minutes,
            onConfirm = { picked ->
                open = false
                onPick(picked)
            },
            onDismiss = { open = false },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun QuietHourPickerDialog(
    title: String,
    minutes: Int,
    onConfirm: (Int) -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val state = rememberTimePickerState(
        initialHour = minutes / 60,
        initialMinute = minutes % 60,
        is24Hour = android.text.format.DateFormat.is24HourFormat(context),
    )
    Dialog(onDismissRequest = onDismiss) {
        Column(
            Modifier
                .widthIn(max = 360.dp)
                .fillMaxWidth()
                .clip(RoundedCornerShape(28.dp))
                .background(IOSColors.alert)
                .padding(top = 20.dp, bottom = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(title, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            TimePicker(state = state, layoutType = TimePickerLayoutType.Vertical)
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                IOSCapsuleButton("Cancel", onDismiss, Modifier.weight(1f))
                IOSCapsuleButton(
                    "Done",
                    { onConfirm(state.hour * 60 + state.minute) },
                    Modifier.weight(1f),
                    prominent = true,
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
                        "Lock-screen alerts need the Zelefin plugin on a Jellyfin server. This Silo server cannot install that plugin, so notifications are not available here."
                    emby ->
                        "Lock-screen alerts need the Zelefin plugin on a Jellyfin server. Emby cannot run that plugin, so notifications are not available here."
                    else ->
                        "Install the Zelefin plugin on this Jellyfin server to get lock-screen alerts. The plugin watches the library and can notify this phone when titles are added, a stream starts, someone comes online, a scheduled task begins, or a Seerr request comes in — including while Zelefin is closed. This app no longer checks the server itself."
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
                    stringResource(R.string.ui_ask_a_server_administrator_to_install_the_zelefi),
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
                else -> "After install, restart Jellyfin so the plugin can load. You do not paste a Firebase key on the server."
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
                "Notifications are off in Android Settings. Turn them on for Zelefin so the plugin can deliver banners for new titles, streams, users online, scheduled tasks, and Seerr requests."
            !granted ->
                "Zelefin asks Android for permission when you turn this on. The plugin then pushes new titles, streams, users online, scheduled tasks, and Seerr requests."
            else ->
                "The Zelefin plugin pushes lock-screen alerts for new titles, streams, users online, scheduled tasks, and Seerr requests. Quiet hours and mute options hold banners back while Zelefin is open, while something is playing, or during the hours you choose. Restart Jellyfin after you install or remove the plugin."
        },
    )
    if (on) NotificationDeliverySections()
}

@Composable
private fun PluginsTopic(state: ZelefinUiState, plugins: PluginsController) {
    val pluginState by plugins.state.collectAsState()
    LaunchedEffect(Unit) { plugins.refresh() }
    val jellyfin = pluginState.jellyfin
    val silo = state.isSiloServer
    val emby = state.isEmbyServer
    SettingsHeader(stringResource(R.string.ui_skip_recaps_intros_credits_and_previews))
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
            emby -> "Skip buttons appear when Emby has marked an intro or credits, or the file has chapters named Intro or Credits. Emby has no TheIntroDB plugin, so for everything else Zelefin can ask TheIntroDB directly."
            else -> "Skip buttons come from Jellyfin's media segments, which Intro Skipper and the TheIntroDB plugin fill in once the Media Segment Scan task has run. For titles with none, Zelefin can ask TheIntroDB directly."
        },
    )
    if (!silo && !emby) JellyfinServerPlugins(state, jellyfin)
    if (emby) {
        SettingsHeader(stringResource(R.string.ui_open_subtitles))
        SettingsCard { PluginStatusRow("Open Subtitles", jellyfin.openSubtitles) }
        SettingsFooter(
            stringResource(R.string.ui_when_this_emby_plugin_is_installed_and_signed_in),
        )
    }

    SettingsHeader(stringResource(R.string.ui_requests))
    SeerrSignInCard(state, pluginState, plugins)
    SettingsFooter(
        if (pluginState.requestService == RequestService.Ombi) {
            "Ombi lets you request movies and shows that are not on the server yet. Use your Ombi username and password, or your Jellyfin or Emby ones if Ombi imported your account. Search for a title, then tap Request."
        } else {
            "Jellyseerr or Seerr lets you request movies and shows that are not on Jellyfin yet. Use your Jellyfin username and password. Search for a title, then tap Request."
        },
    )

    SettingsHeader(stringResource(R.string.TMDB))
    TmdbKeyCard(pluginState, plugins)
    SettingsFooter(
        stringResource(R.string.ui_discover_title_pages_show_a_titles_logo_when_its),
    )
}

@Composable
private fun TmdbKeyCard(pluginState: PluginsUiState, plugins: PluginsController) {
    var key by remember { mutableStateOf("") }
    SettingsCard {
        SettingsTextField(
            label = "API KEY OR READ ACCESS TOKEN",
            value = key,
            icon = Icons.Outlined.Lock,
            onChange = { key = it },
            placeholder = if (pluginState.hasTmdbKey) "Saved" else "TMDB key",
            password = true,
            ime = ImeAction.Done,
            onIme = { if (key.isNotBlank()) plugins.saveTmdbKey(key) },
        )
        SettingsCardDivider()
        if (pluginState.hasTmdbKey && key.isBlank()) {
            SettingsButton("Remove Key", primary = false, destructive = true, enabled = !pluginState.tmdbBusy, busy = false) {
                plugins.saveTmdbKey("")
            }
        } else {
            SettingsButton("Save Key", primary = true, destructive = false, enabled = key.isNotBlank(), busy = pluginState.tmdbBusy) {
                plugins.saveTmdbKey(key)
            }
        }
        pluginState.tmdbMessage?.let { message ->
            val positive = message.startsWith("Saved") || message.startsWith("Removed")
            Text(
                message,
                color = if (positive) Secondary else IOSColors.red,
                fontFamily = ZelefinFont,
                fontSize = 14.sp,
                modifier = Modifier.padding(top = 12.dp),
            )
        }
    }
    LaunchedEffect(pluginState.hasTmdbKey) { if (pluginState.hasTmdbKey) key = "" }
}

@Composable
private fun JellyfinServerPlugins(state: ZelefinUiState, jellyfin: JellyfinPluginState) {

    SettingsHeader(stringResource(R.string.ui_jellyfin_enhanced))
    SettingsCard { PluginStatusRow("Jellyfin Enhanced", jellyfin.enhanced) }
    SettingsFooter(
        stringResource(R.string.ui_when_this_plugin_is_installed_you_can_remove_tit),
    )

    SettingsHeader(stringResource(R.string.ui_notifications_plugin))
    SettingsCard { PluginStatusRow("Zelefin", jellyfin.companion) }
    SettingsFooter(
        if (jellyfin.companion) {
            "This server can push lock-screen alerts. Quiet hours and mute options in Notifications hold banners back while Zelefin is open, while something is playing, or during the hours you choose. Restart Jellyfin after you install or remove the plugin."
        } else {
            stringResource(R.string.ui_notifications_need_this_plugin_open_settings_not)
        },
    )

    SettingsHeader(stringResource(R.string.ui_open_subtitles))
    SettingsCard { PluginStatusRow("Open Subtitles", jellyfin.openSubtitles) }
    SettingsFooter(stringResource(R.string.ui_when_this_plugin_is_installed_use_more_on_a_movi))

    val youTubeRooms = state.libraries.filter { it.kind == LibraryKind.YouTube }
    SettingsHeader(stringResource(R.string.TubeArchivist))
    SettingsCard {
        PluginStatusRow(
            "TubeArchivist Metadata",
            youTubeRooms.isNotEmpty() ||
                state.libraries.any { it.name.contains("TubeArchivist", ignoreCase = true) } ||
                jellyfin.names.any { it.contains("TubeArchivist", ignoreCase = true) },
        )
    }
    SettingsFooter(
        if (youTubeRooms.isNotEmpty()) {
            "${youTubeRooms.joinToString { it.name }} appears as its own YouTube library, with channels and videos kept apart from your movies and shows."
        } else {
            stringResource(R.string.ui_when_this_plugin_fills_a_shows_library_zelefin_l)
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
            InfoLine(stringResource(R.string.connect_service), pluginState.requestService.title)
            CardDivider()
            InfoLine(stringResource(R.string.settings_server), pluginState.seerrUrl)
            CardDivider()
            InfoLine(stringResource(R.string.ui_signed_in_as), signedIn)
            SettingsCardDivider()
            SettingsButton("Sign Out", primary = false, destructive = true, enabled = true, busy = false, onClick = plugins::signOutSeerr)
        } else {
            SettingsMenuPicker(
                label = "Service",
                choices = RequestService.entries.map { SettingsChoice(it, it.title) },
                selected = pluginState.requestService,
                onSelect = plugins::setRequestService,
            )
            CardDivider()
            SettingsTextField(
                label = "SERVER",
                value = url,
                icon = Icons.Outlined.Link,
                onChange = { url = it },
                placeholder = if (pluginState.requestService == RequestService.Ombi) "https://ombi.example.com" else "https://seerr.example.com",
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

@Composable
private fun CacheTopic() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var usage by remember { mutableStateOf(app.zelefin.core.ArtworkCacheUsage()) }
    var revision by remember { mutableStateOf(0) }
    var confirmKind by remember { mutableStateOf<ArtworkImageKind?>(null) }
    var confirmAll by remember { mutableStateOf(false) }
    var autoRefresh by remember { mutableStateOf(CachePreferences.autoRefreshMissingImages(context)) }
    LaunchedEffect(revision) {
        usage = withContext(Dispatchers.IO) { ArtworkCacheStore.usage(context) }
    }
    confirmKind?.let { kind ->
        SettingsAlertDialog(
            title = "Clear this image cache?",
            message = "",
            confirmLabel = "Clear",
            destructive = true,
            onConfirm = {
                confirmKind = null
                scope.launch {
                    withContext(Dispatchers.IO) { ArtworkCacheStore.clear(context, kind) }
                    revision += 1
                }
            },
            onDismiss = { confirmKind = null },
        )
    }
    if (confirmAll) {
        SettingsAlertDialog(
            title = "Clear every cached image?",
            message = "",
            confirmLabel = "Clear All Images",
            destructive = true,
            onConfirm = {
                confirmAll = false
                scope.launch {
                    withContext(Dispatchers.IO) { ArtworkCacheStore.clear(context, null) }
                    revision += 1
                }
            },
            onDismiss = { confirmAll = false },
        )
    }
    SettingsHeader(stringResource(R.string.ui_images))
    SettingsCard {
        InfoLine(stringResource(R.string.ui_total), formatBytes(usage.total.bytes))
        ArtworkImageKind.entries.forEach { kind ->
            SettingsCardDivider()
            CacheBucketRow(kind.title, usage.bucket(kind)) { confirmKind = kind }
        }
        SettingsCardDivider()
        SettingsActionRow(
            "Clear All Images",
            destructive = true,
            enabled = !usage.total.isEmpty,
        ) { confirmAll = true }
        SettingsCardDivider()
        SettingsToggleRow(stringResource(R.string.ui_auto_refresh_missing_images), autoRefresh, { enabled ->
            autoRefresh = enabled
            CachePreferences.setAutoRefreshMissingImages(context, enabled)
        })
    }
    SettingsFooter(stringResource(R.string.ui_posters_backdrops_and_logos_stay_on_this_device))
}

@Composable
private fun MetadataTopic() {
    val context = LocalContext.current
    val model: ZelefinModel = viewModel()
    val scope = rememberCoroutineScope()
    val root = remember { File(context.cacheDir, "Zelefin") }
    var usage by remember { mutableStateOf(app.zelefin.core.MetadataCacheUsage()) }
    var revision by remember { mutableStateOf(0) }
    var confirmFolder by remember { mutableStateOf<MetadataCacheFolder?>(null) }
    var confirmAll by remember { mutableStateOf(false) }
    var autoRefresh by remember { mutableStateOf(CachePreferences.autoRefreshMissingMetadata(context)) }
    var refreshing by remember { mutableStateOf(false) }
    LaunchedEffect(revision) {
        usage = withContext(Dispatchers.IO) { CacheInventory.metadataUsage(root) }
    }
    fun refresh() {
        if (refreshing) return
        refreshing = true
        scope.launch {
            runCatching { model.refreshMissingMetadata() }
            revision += 1
            refreshing = false
        }
    }
    confirmFolder?.let { folder ->
        SettingsAlertDialog(
            title = "Clear this metadata cache?",
            message = "",
            confirmLabel = "Clear",
            destructive = true,
            onConfirm = {
                confirmFolder = null
                scope.launch {
                    withContext(Dispatchers.IO) { model.clearMetadataCache(folder.directoryName) }
                    revision += 1
                }
            },
            onDismiss = { confirmFolder = null },
        )
    }
    if (confirmAll) {
        SettingsAlertDialog(
            title = "Clear every metadata cache?",
            message = "",
            confirmLabel = "Clear All Metadata",
            destructive = true,
            onConfirm = {
                confirmAll = false
                scope.launch {
                    withContext(Dispatchers.IO) { model.clearMetadataCache(null) }
                    revision += 1
                }
            },
            onDismiss = { confirmAll = false },
        )
    }
    SettingsHeader(stringResource(R.string.ui_saved_home_data))
    SettingsCard {
        InfoLine(stringResource(R.string.ui_total), formatBytes(usage.total.bytes))
        MetadataCacheFolder.entries.forEach { folder ->
            SettingsCardDivider()
            CacheBucketRow(folder.title, usage.bucket(folder)) { confirmFolder = folder }
        }
        SettingsCardDivider()
        SettingsActionRow(
            "Clear All Metadata",
            destructive = true,
            enabled = !usage.total.isEmpty,
        ) { confirmAll = true }
        SettingsCardDivider()
        SettingsToggleRow(stringResource(R.string.ui_auto_refresh_missing_metadata), autoRefresh, { enabled ->
            autoRefresh = enabled
            CachePreferences.setAutoRefreshMissingMetadata(context, enabled)
            if (enabled) refresh()
        })
        SettingsCardDivider()
        SettingsActionRow("Refresh Missing Metadata", busy = refreshing, enabled = !refreshing) { refresh() }
    }
    SettingsFooter(stringResource(R.string.ui_home_rows_library_catalogs_and_title_pages_auto))
}

@Composable
private fun CacheBucketRow(title: String, bucket: CacheBucket, onClear: () -> Unit) {
    val enabled = !bucket.isEmpty
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, style = SettingsRowText)
            Text(formatBytes(bucket.bytes), color = IOSColors.secondaryLabel, fontFamily = ZelefinFont, fontSize = 15.sp)
        }
        Text(stringResource(R.string.common_clear),
            color = if (enabled) IOSColors.red else IOSColors.tertiaryLabel,
            fontFamily = ZelefinFont,
            fontWeight = FontWeight.Bold,
            fontSize = 12.sp,
            modifier = Modifier
                .clickable(enabled = enabled, onClick = onClear)
                .padding(horizontal = 4.dp, vertical = 8.dp),
        )
    }
}

@Composable
private fun SessionsTopic(state: ZelefinUiState) {
    val session = state.session
    if (session != null && session.hasServerTools) {
        SessionsPanel(session)
        return
    }
    SettingsCard {
        InfoLine(stringResource(R.string.ui_user), session?.userName ?: "—")
        InfoLine(stringResource(R.string.settings_server), session?.displayServer ?: "—")
        InfoLine(stringResource(R.string.ui_device), Build.MODEL ?: "Android")
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

/** Mirrors iOS `ServerInfoView`: public system info, plus the signed-in OS display name on Jellyfin. */
@Composable
private fun ServerInfoTopic(state: ZelefinUiState) {
    val model: ZelefinModel = viewModel()
    val session = state.session
    var snapshot by remember(session?.accountId, state.localServerUrl) {
        mutableStateOf(
            ServerInfoSnapshot(
                serverName = session?.serverName?.trim()?.ifEmpty { null },
                product = session?.serverTypeName,
                version = session?.serverVersion?.trim()?.ifEmpty { null },
                activeUrl = state.localServerUrl ?: session?.serverUrl,
            ),
        )
    }
    var loading by remember(session?.accountId, state.localServerUrl) { mutableStateOf(true) }
    var loadError by remember(session?.accountId, state.localServerUrl) { mutableStateOf<String?>(null) }
    LaunchedEffect(session?.accountId, state.localServerUrl) {
        if (session == null) {
            loadError = "Not signed in to a server."
            loading = false
            return@LaunchedEffect
        }
        loadError = null
        snapshot = model.loadServerInfo()
        loading = false
    }
    val waiting = loading && snapshot.serverName.isNullOrBlank() && snapshot.activeUrl.isNullOrBlank() && snapshot.version.isNullOrBlank()
    if (waiting) {
        Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
            IOSSpinner(Modifier.size(24.dp))
        }
        return
    }
    SettingsCard {
        InfoLine(stringResource(R.string.ui_server_name), snapshot.serverName.orDash())
        InfoLine(stringResource(R.string.ui_product), snapshot.product.orDash())
        InfoLine(stringResource(R.string.player_version), snapshot.version.orDash())
        InfoLine(stringResource(R.string.ui_operating_system), snapshot.operatingSystem.orDash())
        InfoLine(stringResource(R.string.ui_active_url), snapshot.activeUrl.orDash())
        InfoLine(stringResource(R.string.ui_local_address), snapshot.localAddress.orDash())
    }
    SettingsFooter(stringResource(R.string.ui_pulled_from_this_devices_connection_and_the_serv))
    loadError?.let { message ->
        Spacer(Modifier.height(14.dp))
        SettingsCard {
            Text(message, color = IOSColors.red, fontFamily = ZelefinFont, fontSize = 15.sp, modifier = Modifier.padding(vertical = 14.dp))
        }
    }
}

private fun String?.orDash(): String = this?.trim()?.ifEmpty { null } ?: "—"

/** Mirrors iOS `SettingsAboutView`: hero mark, version and build, support, and accent-tinted links. */
@Composable
private fun AboutTopic() {
    val context = LocalContext.current
    fun open(url: String) {
        runCatching {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(top = 12.dp),
        verticalArrangement = Arrangement.spacedBy(28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        AboutHero()
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            AboutStat("Version", BuildConfig.VERSION_NAME, Modifier.weight(1f))
            AboutStat("Build", BuildConfig.VERSION_CODE.toString(), Modifier.weight(1f))
        }
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            AboutLinkRow("zelefin.app", Icons.Outlined.Language) { open("https://zelefin.app") }
            AboutLinkRow("Support", Icons.Outlined.HelpOutline) { open("https://zelefin.app/support") }
            AboutLinkRow("Privacy Policy", Icons.Outlined.PrivacyTip) { open("https://zelefin.app/privacy") }
            AboutLinkRow("Terms of Use", Icons.Outlined.Description) { open("https://zelefin.app/terms") }
        }
        AboutCredits()
    }
}

@Composable
private fun AboutHero() {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.size(140.dp), contentAlignment = Alignment.Center) {
            Box(
                Modifier
                    .size(140.dp)
                    .drawBehind {
                        drawCircle(
                            brush = Brush.radialGradient(
                                colors = listOf(LoginPalette.Lavender.copy(alpha = 0.35f), Color.Transparent),
                                center = Offset(size.width / 2f, size.height / 2f + 10.dp.toPx()),
                                radius = size.minDimension * 0.48f,
                            ),
                        )
                    },
            )
            Image(
                painter = painterResource(R.drawable.zelefin_mark),
                contentDescription = null,
                modifier = Modifier.size(112.dp),
                contentScale = ContentScale.Fit,
            )
        }
        Text(stringResource(R.string.settings_zelefin_section), color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 34.sp)
        Spacer(Modifier.height(10.dp))
        Text(
            buildAnnotatedString {
                withStyle(SpanStyle(color = Color.White)) { append("Your library, ") }
                withStyle(SpanStyle(brush = Brush.horizontalGradient(listOf(LoginPalette.Lavender, LoginPalette.Sky)))) {
                    append("beautifully native.")
                }
            },
            fontFamily = ZelefinFont,
            fontWeight = FontWeight.SemiBold,
            fontSize = 20.sp,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(10.dp))
        Text(
            stringResource(R.string.settings_about_body),
            color = IOSColors.secondaryLabel,
            fontFamily = ZelefinFont,
            fontSize = 15.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = 8.dp),
        )
    }
}

@Composable
private fun AboutStat(title: String, value: String, modifier: Modifier) {
    val shape = RoundedCornerShape(18.dp)
    Column(
        modifier
            .clip(shape)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .border(1.dp, Color.White.copy(alpha = 0.08f), shape)
            .padding(vertical = 18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(
            title.uppercase(),
            color = IOSColors.tertiaryLabel,
            fontFamily = ZelefinFont,
            fontWeight = FontWeight.Bold,
            fontSize = 11.sp,
            letterSpacing = 1.1.sp,
        )
        Text(value, color = ZelefinCyan, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 20.sp)
    }
}

@Composable
private fun AboutLinkRow(title: String, icon: ImageVector, onClick: () -> Unit) {
    val shape = RoundedCornerShape(18.dp)
    Row(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .border(1.dp, ZelefinCyan.copy(alpha = 0.28f), shape)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Icon(icon, contentDescription = null, tint = ZelefinCyan, modifier = Modifier.size(22.dp))
        Text(
            title,
            color = Color.White,
            fontFamily = ZelefinFont,
            fontWeight = FontWeight.SemiBold,
            fontSize = 17.sp,
            modifier = Modifier.weight(1f),
        )
        Box(
            Modifier.size(28.dp).clip(CircleShape).background(ZelefinCyan.copy(alpha = 0.16f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Outlined.OpenInNew, contentDescription = null, tint = ZelefinCyan, modifier = Modifier.size(14.dp))
        }
    }
}

@Composable
private fun AboutCredits() {
    val shape = RoundedCornerShape(18.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.72f))
            .border(1.dp, Color.White.copy(alpha = 0.08f), shape)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(stringResource(R.string.settings_credits), color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
        Text(
            stringResource(R.string.settings_credits_body),
            color = IOSColors.tertiaryLabel,
            fontFamily = ZelefinFont,
            fontSize = 13.sp,
        )
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
    LaunchedEffect(gatewayId, gatewaySecret) {
        if (gatewayId != state.gatewayId || gatewaySecret != state.gatewaySecret) {
            model.saveGateway(gatewayId, gatewaySecret)
        }
    }

    SettingsHeader(stringResource(R.string.ui_this_connection))
    SettingsCard {
        InfoLine(stringResource(R.string.ui_remote_url), session?.serverUrl ?: "—")
        InfoLine(stringResource(R.string.ui_active_url), state.localServerUrl ?: session?.serverUrl ?: "—")
        InfoLine(stringResource(R.string.ui_wi_fi), ssid ?: "Unavailable")
        InfoLine(stringResource(R.string.ui_using), if (state.localServerUrl != null) "Local URL" else "Remote URL")
    }

    SettingsHeader(stringResource(R.string.ui_home_network))
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
    }
    SettingsFooter(stringResource(R.string.ui_when_you_join_a_saved_home_network_zelefin_uses))

    SettingsHeader(stringResource(R.string.ui_home_wi_fi))
    SettingsCard {
        if (profile.homeSsids.isEmpty()) {
            Text(stringResource(R.string.ui_no_networks_configured), style = SettingsRowText)
        } else {
            profile.homeSsids.forEachIndexed { index, name ->
                if (index > 0) CardDivider()
                Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Wifi, contentDescription = null, tint = ZelefinCyan, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.size(12.dp))
                    Text(name, style = SettingsRowText, modifier = Modifier.weight(1f))
                    Text(stringResource(R.string.common_remove),
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
        }
    }
    SettingsFooter(stringResource(R.string.ui_add_the_networks_that_should_use_the_local_url))

    SettingsHeader(stringResource(R.string.ui_access_gateway))
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
    }
    SettingsFooter(stringResource(R.string.ui_needed_when_this_server_sits_behind_cloudflare_z))
}

/** Mirrors iOS `TabCustomizationView`. */
@Composable
private fun InterfaceTopic(state: ZelefinUiState, editing: Boolean) {
    InterfaceSettings(state, editing)
}

private val SettingsBarHeight = 56.dp

/**
 * iOS 26 navigation bar: the page scrolls under a centered title, with a liquid glass back
 * circle, or a glass Done / Cancel capsule on pages that close the sheet.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsPage(
    title: String,
    onBack: () -> Unit,
    bar: SettingsBarAction,
    large: Boolean = false,
    trailing: (@Composable () -> Unit)? = null,
    refreshing: Boolean = false,
    onRefresh: (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    // iOS 26 sheets inset their bar buttons about 16pt from the rounded top edge.
    val topInset = if (LocalZelefinInSheet.current) Modifier.padding(top = 10.dp) else Modifier.statusBarsPadding()
    val canvas = MaterialTheme.colorScheme.surface
    val pageGlass = remember { GlassSource() }
    val refreshState = rememberPullToRefreshState()
    Box(Modifier.fillMaxSize().background(canvas)) {
        val scroller: @Composable () -> Unit = {
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
        }
        if (onRefresh != null) {
            PullToRefreshBox(
                isRefreshing = refreshing,
                onRefresh = onRefresh,
                state = refreshState,
                modifier = Modifier.fillMaxSize(),
                indicator = {
                    PullToRefreshDefaults.Indicator(
                        modifier = Modifier.align(Alignment.TopCenter).then(topInset).padding(top = SettingsBarHeight),
                        isRefreshing = refreshing,
                        state = refreshState,
                        containerColor = Color(0xFF1C1C1E),
                        color = ZelefinCyan,
                    )
                },
            ) { scroller() }
        } else {
            scroller()
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
                        Text(stringResource(R.string.common_cancel), color = Color.White, fontFamily = ZelefinFont, fontSize = 17.sp)
                    }
                    SettingsBarAction.Done -> SettingsGlassButton("Done", onBack, circle = false, modifier = Modifier.align(Alignment.CenterEnd)) {
                        Text(stringResource(R.string.common_done), color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
                    }
                }
                if (trailing != null) {
                    Box(Modifier.align(Alignment.CenterEnd)) { trailing() }
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

private fun formatBytes(bytes: Long): String = CacheInventory.formatBytes(bytes)
