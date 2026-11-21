package app.zelefin.client.ui

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.PhotoCamera
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import app.zelefin.client.R
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import app.zelefin.client.ZelefinModel
import app.zelefin.client.ZelefinUiState
import app.zelefin.client.jellyfin.ActivityLogItem
import app.zelefin.client.jellyfin.AdminMediaFolder
import app.zelefin.client.jellyfin.ParentalRatingChoice
import app.zelefin.client.jellyfin.RemoteBitrateLimit
import app.zelefin.client.jellyfin.ScheduledTask
import app.zelefin.client.jellyfin.ServerBackup
import app.zelefin.client.jellyfin.ServerBranding
import app.zelefin.client.jellyfin.ServerUserAccount
import app.zelefin.client.jellyfin.SyncPlayGroup
import app.zelefin.client.jellyfin.UserPolicyDraft
import app.zelefin.client.jellyfin.formatAdminDate
import app.zelefin.client.jellyfin.settingsTitle
import app.zelefin.core.SavedSession
import coil.imageLoader
import coil.memory.MemoryCache
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.jellyfin.sdk.model.api.TaskCompletionStatus
import org.jellyfin.sdk.model.api.UnratedItem

private val AdminSecondary = IOSColors.secondaryLabel
private val AdminCaption = IOSColors.secondaryLabel
private val AdminError = IOSColors.red

@Composable
internal fun SyncPlayTopic(state: ZelefinUiState) {
    val model: ZelefinModel = viewModel()
    val scope = rememberCoroutineScope()
    var groups by remember { mutableStateOf(emptyList<SyncPlayGroup>()) }
    var loading by remember { mutableStateOf(true) }
    var working by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }

    suspend fun load() {
        runCatching { model.syncPlayGroups() }
            .onSuccess {
                groups = it
                error = null
            }
            .onFailure { if (it is CancellationException) throw it else error = it.message ?: "Jellyfin didn’t list SyncPlay groups." }
        loading = false
    }
    LaunchedEffect(Unit) { load() }

    fun run(work: suspend () -> Unit) {
        if (working) return
        working = true
        scope.launch {
            runCatching { work() }
                .onSuccess { error = null }
                .onFailure { if (it is CancellationException) throw it else error = it.message ?: "SyncPlay didn’t finish that." }
            runCatching { load() }
            working = false
        }
    }

    error?.let {
        SettingsCard { Text(it, color = AdminError, fontFamily = ZelefinFont, fontSize = 14.sp, modifier = Modifier.padding(vertical = 14.dp)) }
        Spacer(Modifier.height(12.dp))
    }
    state.syncPlayGroupName?.takeIf { state.syncPlayGroupId != null }?.let { joined ->
        SettingsHeader(stringResource(R.string.settings_this_device))
        SettingsCard {
            SettingsInfoRow("Joined", joined)
            SettingsCardDivider()
            SettingsSecondaryButton("Leave Group", enabled = !working) { run { model.leaveSyncPlayGroup() } }
        }
    }
    SettingsHeader(stringResource(R.string.ui_new_group))
    SettingsCard {
        SettingsTextField(
            label = "NAME",
            value = name,
            icon = Icons.Outlined.Groups,
            onChange = { name = it },
            placeholder = "Name",
            ime = ImeAction.Go,
            onIme = { if (name.isNotBlank() && !working) run { model.createSyncPlayGroup(name); name = "" } },
        )
        SettingsCardDivider()
        SettingsPrimaryButton("Create", busy = working, enabled = name.isNotBlank() && !working) {
            run { model.createSyncPlayGroup(name); name = "" }
        }
    }
    SettingsHeader(stringResource(R.string.ui_groups))
    SettingsCard {
        when {
            loading && groups.isEmpty() -> Box(Modifier.fillMaxWidth().padding(12.dp), contentAlignment = Alignment.Center) {
                IOSSpinner(Modifier.size(22.dp))
            }
            groups.isEmpty() -> Text(stringResource(R.string.ui_no_syncplay_groups_are_running), color = AdminSecondary, fontFamily = ZelefinFont, fontSize = 16.sp)
            else -> groups.forEachIndexed { index, group ->
                if (index > 0) SettingsCardDivider()
                val joined = state.syncPlayGroupId == group.id
                Column(
                    Modifier
                        .fillMaxWidth()
                        .clickable(enabled = !working && !joined) { run { model.joinSyncPlayGroup(group) } }
                        .padding(vertical = 11.dp),
                ) {
                    Text(group.name, style = SettingsRowText)
                    Text(group.subtitle, color = AdminCaption, fontFamily = ZelefinFont, fontSize = 13.sp)
                }
            }
        }
    }
}

/** Last loaded admin lists, so returning to a page shows them at once while a fresh copy loads. */
internal object AdminCache {
    private val values = mutableMapOf<String, Any>()

    @Suppress("UNCHECKED_CAST")
    fun <T> get(key: String): T? = values[key] as T?

    fun put(key: String, value: Any) {
        values[key] = value
    }
}

private fun adminCacheKey(model: ZelefinModel, page: String) = "${model.state.value.session?.accountId}:$page"

@Composable
internal fun UsersTopic() {
    val model: ZelefinModel = viewModel()
    val ui by model.state.collectAsState()
    val cacheKey = adminCacheKey(model, "users")
    var users by remember { mutableStateOf(AdminCache.get<List<ServerUserAccount>>(cacheKey).orEmpty()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) {
        runCatching { model.adminUsers() }
            .onSuccess { users = it; error = null; AdminCache.put(cacheKey, it) }
            .onFailure { error = it.message ?: "This server did not return any users." }
        loading = false
    }
    when {
        loading && users.isEmpty() -> Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
            IOSSpinner(Modifier.size(24.dp))
        }
        users.isEmpty() -> SettingsCard {
            SettingsUnavailable("No Users", error ?: "This server did not return any users.")
        }
        else -> {
            error?.let { SettingsCard { Text(it, color = AdminError, fontFamily = ZelefinFont, fontSize = 14.sp, modifier = Modifier.padding(vertical = 14.dp)) }; Spacer(Modifier.height(12.dp)) }
            SettingsCard {
                users.forEachIndexed { index, account ->
                    if (index > 0) SettingsCardDivider()
                    Row(
                        Modifier.fillMaxWidth().clickable { model.openSettingsTopic("user:${account.id}") }.padding(vertical = 11.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        UserAdminAvatar(ui.session, account, 48.dp)
                        Column(Modifier.weight(1f)) {
                            Text(account.name, style = SettingsRowText)
                            Text(account.statusSubtitle, color = AdminSecondary, fontFamily = ZelefinFont, fontSize = 13.sp)
                        }
                        Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = AdminCaption)
                    }
                }
            }
            SettingsFooter(stringResource(R.string.ui_administrators_can_change_photos_permissions_lib))
        }
    }
}

@Composable
internal fun UserEditorTopic(userId: String, state: ZelefinUiState) {
    val model: ZelefinModel = viewModel()
    val context = LocalContext.current
    val session = state.session
    val scope = rememberCoroutineScope()
    var account by remember { mutableStateOf<ServerUserAccount?>(null) }
    var draft by remember { mutableStateOf<UserPolicyDraft?>(null) }
    var username by remember { mutableStateOf("") }
    var folders by remember { mutableStateOf(emptyList<AdminMediaFolder>()) }
    var ratings by remember { mutableStateOf(emptyList<ParentalRatingChoice>()) }
    var ratingId by remember { mutableStateOf("none") }
    var ratingsReady by remember { mutableStateOf(false) }
    var newPassword by remember { mutableStateOf("") }
    var confirmPassword by remember { mutableStateOf("") }
    var status by remember { mutableStateOf<Pair<String, Boolean>?>(null) }
    var saving by remember { mutableStateOf(false) }
    var photoBusy by remember { mutableStateOf(false) }
    var confirmDisable by remember { mutableStateOf(false) }
    var confirmReset by remember { mutableStateOf(false) }
    var confirmDemote by remember { mutableStateOf(false) }
    val chrome = LocalSettingsChrome.current

    suspend fun reload() {
        val latest = model.adminUser(userId)
        account = latest
        draft = latest.policy
        username = latest.name
        ratingId = ratings.firstOrNull { it.value == latest.policy?.maxParentalRating }?.id ?: "none"
    }

    LaunchedEffect(userId) {
        runCatching {
            val latest = model.adminUser(userId)
            account = latest
            draft = latest.policy
            username = latest.name
            folders = model.adminMediaFolders()
            ratings = model.parentalRatings()
            ratingId = ratings.firstOrNull { it.value == latest.policy?.maxParentalRating }?.id ?: "none"
            ratingsReady = true
        }.onFailure { status = (it.message ?: "Could not load this user.") to true }
    }

    fun run(success: String = "Saved.", work: suspend () -> Unit) {
        if (saving) return
        saving = true
        status = null
        scope.launch {
            runCatching { work(); reload() }
                .onSuccess { status = success to false }
                .onFailure { status = (it.message ?: "The server did not save that change.") to true }
            saving = false
        }
    }

    fun savePolicy(next: UserPolicyDraft) {
        val current = account ?: return
        if (current.policy == null) {
            status = "This user has no policy on the server." to true
            return
        }
        draft = next
        run { model.updateUserPolicy(current.id, next) }
    }

    if (confirmDisable) {
        SettingsAlertDialog(
            title = "Disable this account?",
            message = "They will not be able to sign in until you turn the account back on.",
            confirmLabel = "Disable Account",
            destructive = true,
            onConfirm = {
                confirmDisable = false
                draft?.let { savePolicy(it.copy(isDisabled = true)) }
            },
            onDismiss = { confirmDisable = false },
        )
    }
    if (confirmReset) {
        SettingsAlertDialog(
            title = "Reset this password?",
            message = "Jellyfin clears the password. They set a new one the next time they sign in.",
            confirmLabel = "Reset Password",
            destructive = true,
            onConfirm = {
                confirmReset = false
                run("Password reset.") { model.resetUserPassword(userId) }
            },
            onDismiss = { confirmReset = false },
        )
    }
    if (confirmDemote) {
        SettingsAlertDialog(
            title = "Remove administrator access?",
            message = "",
            confirmLabel = "Remove Access",
            destructive = true,
            onConfirm = {
                confirmDemote = false
                draft?.let { savePolicy(it.copy(isAdministrator = false)) }
            },
            onDismiss = { confirmDemote = false },
        )
    }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri: Uri? ->
        uri ?: return@rememberLauncherForActivityResult
        photoBusy = true
        status = null
        scope.launch {
            val oldKey = session?.let { userAvatarUrl(it, userId, account?.primaryImageTag) }?.let { coil.memory.MemoryCache.Key(it) }
            runCatching { model.uploadUserPhoto(userId, uri) }
                .onSuccess {
                    oldKey?.let { key ->
                        context.imageLoader.memoryCache?.remove(key)
                        withContext(Dispatchers.IO) { context.imageLoader.diskCache?.remove(key.toString()) }
                    }
                    status = "Profile picture updated." to false
                    runCatching { reload() }
                }
                .onFailure { status = (it.message ?: "The server did not accept the photo.") to true }
            photoBusy = false
        }
    }

    val current = account
    val policy = draft
    SideEffect {
        current?.name?.let { chrome.title = it }
    }
    DisposableEffect(Unit) {
        onDispose { chrome.title = null }
    }
    if (current == null || policy == null) {
        Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
            if (status?.second == true) Text(status?.first.orEmpty(), color = AdminError, fontFamily = ZelefinFont, fontSize = 14.sp)
            else IOSSpinner(Modifier.size(24.dp))
        }
        return
    }

    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.size(104.dp)) {
            UserAdminAvatar(session, current, 104.dp)
            if (photoBusy) {
                Box(Modifier.size(104.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.48f)), contentAlignment = Alignment.Center) {
                    IOSSpinner(Modifier.size(24.dp))
                }
            }
            Box(
                Modifier
                    .align(Alignment.BottomEnd)
                    .size(32.dp)
                    .clip(CircleShape)
                    .background(Color.White)
                    .clickable(enabled = !photoBusy) { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Outlined.PhotoCamera, contentDescription = "Change Profile Picture", tint = Color.Black, modifier = Modifier.size(16.dp))
            }
        }
        Spacer(Modifier.height(12.dp))
        Text(current.name, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 22.sp)
        Text(if (current.isDisabled) "Disabled" else current.statusSubtitle, color = AdminSecondary, fontFamily = ZelefinFont, fontSize = 14.sp)
        if (current.primaryImageTag != null) {
            Spacer(Modifier.height(10.dp))
            Text(
                stringResource(R.string.ui_remove_photo),
                color = AdminError,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.SemiBold,
                fontSize = 14.sp,
                modifier = Modifier.clickable(enabled = !photoBusy && !saving) {
                    photoBusy = true
                    scope.launch {
                        runCatching { model.deleteUserImage(userId); reload() }
                            .onSuccess { status = "Profile picture removed." to false }
                            .onFailure { status = (it.message ?: "Could not remove the photo.") to true }
                        photoBusy = false
                    }
                },
            )
        }
    }
    SettingsFooter(stringResource(R.string.ui_administrators_can_change_this_users_profile_pic))

    SettingsCard {
        SettingsTextField(label = "USERNAME", value = username, icon = Icons.Outlined.Person, onChange = { username = it }, placeholder = "Username")
        SettingsCardDivider()
        SettingsPrimaryButton("Save Username", busy = saving, enabled = username.trim().isNotEmpty() && username.trim() != current.name && !photoBusy) {
            run { model.renameUser(current, username) }
        }
    }

    SettingsHeader(stringResource(R.string.Permissions))
    SettingsCard {
        SettingsToggleRow(stringResource(R.string.ui_administrator), policy.isAdministrator, {
            if (!it && policy.isAdministrator) confirmDemote = true else savePolicy(policy.copy(isAdministrator = it))
        })
        SettingsCardDivider()
        SettingsToggleRow(stringResource(R.string.ui_edit_subtitles), policy.enableSubtitleManagement, { savePolicy(policy.copy(enableSubtitleManagement = it)) })
        SettingsCardDivider()
        SettingsToggleRow(stringResource(R.string.ui_disable_account), policy.isDisabled, {
            if (it && !policy.isDisabled) confirmDisable = true else savePolicy(policy.copy(isDisabled = it))
        })
    }
    SettingsFooter(stringResource(R.string.ui_administrators_can_manage_users_sessions_and_ser))

    SettingsHeader(stringResource(R.string.Streaming))
    val bitrateChoices = remember(policy.remoteClientBitrateLimit) {
        val values = (RemoteBitrateLimit.bits + policy.remoteClientBitrateLimit).distinct().sorted()
        values.map { SettingsChoice(it, RemoteBitrateLimit.title(it)) }
    }
    SettingsCard {
        SettingsMenuPicker("Remote Bitrate", bitrateChoices, policy.remoteClientBitrateLimit) { savePolicy(policy.copy(remoteClientBitrateLimit = it)) }
    }
    SettingsFooter(stringResource(R.string.ui_caps_how_fast_this_user_can_pull_video_from_outs))

    SettingsHeader(stringResource(R.string.connect_password))
    SettingsCard {
        SettingsTextField(label = "New Password", value = newPassword, icon = Icons.Outlined.Lock, onChange = { newPassword = it }, placeholder = "New Password", password = true, keyboard = KeyboardType.Password)
        SettingsCardDivider()
        SettingsTextField(label = "Confirm Password", value = confirmPassword, icon = Icons.Outlined.Lock, onChange = { confirmPassword = it }, placeholder = "Confirm Password", password = true, keyboard = KeyboardType.Password)
        if (confirmPassword.isNotEmpty() && newPassword != confirmPassword) {
            Text(stringResource(R.string.ui_the_new_passwords_do_not_match), color = AdminError, fontFamily = ZelefinFont, fontSize = 13.sp, modifier = Modifier.padding(top = 12.dp))
        }
        SettingsCardDivider()
        SettingsPrimaryButton("Set Password", busy = saving, enabled = newPassword.isNotEmpty() && newPassword == confirmPassword) {
            run("Password saved.") {
                model.setUserPassword(userId, newPassword)
                newPassword = ""
                confirmPassword = ""
            }
        }
        SettingsCardDivider()
        SettingsSecondaryButton("Reset Password", enabled = !saving) { confirmReset = true }
    }
    SettingsFooter(stringResource(R.string.ui_reset_clears_the_password_on_the_server_set_pass))

    SettingsHeader(stringResource(R.string.ui_parental_controls))
    val ratingChoices = listOf(SettingsChoice("none", "None")) + ratings.map { SettingsChoice(it.id, it.name) }
    SettingsCard {
        SettingsMenuPicker("Maximum Rating", ratingChoices, ratingId) { selected ->
            if (!ratingsReady) return@SettingsMenuPicker
            ratingId = selected
            val value = ratings.firstOrNull { it.id == selected }?.value
            if (policy.maxParentalRating != value) savePolicy(policy.copy(maxParentalRating = value))
        }
        UnratedItem.entries.forEach { item ->
            SettingsCardDivider()
            SettingsToggleRow(item.settingsTitle, policy.blockUnratedItems.contains(item), { on ->
                savePolicy(policy.copy(blockUnratedItems = if (on) policy.blockUnratedItems + item else policy.blockUnratedItems - item))
            })
        }
    }
    SettingsFooter(stringResource(R.string.ui_maximum_rating_hides_titles_above_that_score_blo))

    SettingsHeader(stringResource(R.string.ui_library_access))
    SettingsCard {
        SettingsToggleRow(stringResource(R.string.ui_all_libraries), policy.enableAllFolders, { savePolicy(policy.copy(enableAllFolders = it)) })
        if (!policy.enableAllFolders) {
            folders.forEach { folder ->
                SettingsCardDivider()
                SettingsToggleRow(folder.name, policy.enabledFolders.contains(folder.id), { on ->
                    savePolicy(policy.copy(enabledFolders = if (on) policy.enabledFolders + folder.id else policy.enabledFolders - folder.id))
                })
            }
        }
    }
    SettingsFooter(stringResource(R.string.ui_turn_off_all_libraries_to_pick_which_folders_thi))

    status?.let { (text, isError) ->
        SettingsCard { Text(text, color = if (isError) AdminError else AdminSecondary, fontFamily = ZelefinFont, fontSize = 14.sp, modifier = Modifier.padding(vertical = 14.dp)) }
    }
}

@Composable
private fun UserAdminAvatar(session: SavedSession?, account: ServerUserAccount, diameter: androidx.compose.ui.unit.Dp) {
    Box(
        Modifier.size(diameter).clip(CircleShape).background(Color.White.copy(alpha = 0.12f)),
        contentAlignment = Alignment.Center,
    ) {
        Text(account.name.take(1).uppercase(), color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = (diameter.value * 0.38f).sp)
        session?.let { userAvatarUrl(it, account.id, account.primaryImageTag) }?.let { url ->
            CachedArtwork(url = url, contentDescription = account.name, contentScale = ContentScale.Crop, modifier = Modifier.size(diameter).clip(CircleShape))
        }
    }
}

@Composable
internal fun ScheduledTasksTopic() {
    val model: ZelefinModel = viewModel()
    val cacheKey = adminCacheKey(model, "tasks")
    var tasks by remember { mutableStateOf(AdminCache.get<List<ScheduledTask>>(cacheKey).orEmpty()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf<String?>(null) }

    suspend fun load() {
        runCatching { model.scheduledTasks() }
            .onSuccess { tasks = it; error = null; AdminCache.put(cacheKey, it) }
            .onFailure { if (tasks.isEmpty()) error = it.message }
        loading = false
    }
    LaunchedEffect(Unit) {
        load()
        while (true) {
            delay(if (tasks.any { it.isActive }) 2_000 else 4_000)
            load()
        }
    }

    val scope = rememberCoroutineScope()
    fun act(id: String, work: suspend () -> Unit) {
        busy = id
        scope.launch {
            runCatching { work(); delay(400); load() }.onFailure { error = it.message }
            busy = null
        }
    }

    when {
        loading && tasks.isEmpty() -> Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
            IOSSpinner(Modifier.size(24.dp))
        }
        tasks.isEmpty() -> SettingsCard {
            SettingsUnavailable("No Scheduled Tasks", error ?: "This server did not return any scheduled tasks.")
        }
        else -> {
            error?.let { SettingsCard { Text(it, color = AdminError, fontFamily = ZelefinFont, fontSize = 14.sp, modifier = Modifier.padding(vertical = 14.dp)) }; Spacer(Modifier.height(12.dp)) }
            val running = tasks.filter { it.isActive }
            val idle = tasks.filter { !it.isActive && !it.isHidden }.groupBy { it.category }.toSortedMap(String.CASE_INSENSITIVE_ORDER)
            if (running.isNotEmpty()) {
                SettingsHeader(stringResource(R.string.ui_running))
                SettingsCard {
                    running.forEachIndexed { index, task ->
                        if (index > 0) SettingsCardDivider()
                        ScheduledTaskRow(task, busy == task.id, { model.openSettingsTopic("scheduled-task:${task.id}") }, { act(task.id) { model.startScheduledTask(task.id) } }, { act(task.id) { model.stopScheduledTask(task.id) } })
                    }
                }
            }
            idle.forEach { (category, group) ->
                SettingsHeader(category)
                SettingsCard {
                    group.forEachIndexed { index, task ->
                        if (index > 0) SettingsCardDivider()
                        ScheduledTaskRow(task, busy == task.id, { model.openSettingsTopic("scheduled-task:${task.id}") }, { act(task.id) { model.startScheduledTask(task.id) } }, { act(task.id) { model.stopScheduledTask(task.id) } })
                    }
                }
            }
        }
    }
}

@Composable
private fun ScheduledTaskRow(task: ScheduledTask, isBusy: Boolean, onOpen: () -> Unit, onStart: () -> Unit, onCancel: () -> Unit) {
    Column(Modifier.fillMaxWidth().clickable(onClick = onOpen).padding(vertical = 11.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(task.name, style = SettingsRowText)
                Text(
                    task.stateSubtitle,
                    color = if (task.lastStatus == TaskCompletionStatus.FAILED && !task.isActive) AdminError else AdminCaption,
                    fontFamily = ZelefinFont,
                    fontSize = 13.sp,
                )
            }
            when {
                isBusy -> IOSSpinner(Modifier.size(18.dp))
                task.canCancel -> Text(stringResource(R.string.common_cancel), color = AdminError, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, modifier = Modifier.clickable(onClick = onCancel).padding(8.dp))
                task.canStart -> Text(stringResource(R.string.ui_start), color = ZelefinCyan, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, modifier = Modifier.clickable(onClick = onStart).padding(8.dp))
            }
            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = AdminCaption)
        }
        if (task.isActive) {
            if (task.progressFraction != null) IOSProgressBar(task.progressFraction!!)
            else IOSProgressBar(null)
        }
    }
}

@Composable
internal fun ScheduledTaskDetailTopic(taskId: String) {
    val model: ZelefinModel = viewModel()
    var task by remember { mutableStateOf<ScheduledTask?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    suspend fun load() {
        runCatching { model.scheduledTasks() }
            .onSuccess { list ->
                val match = list.firstOrNull { it.id == taskId }
                if (match != null) { task = match; error = null }
                else if (task == null) error = "That scheduled task is not on this server."
            }
            .onFailure { if (task == null) error = it.message }
    }
    LaunchedEffect(taskId) {
        load()
        while (true) {
            delay(if (task?.isActive == true) 2_000 else 4_000)
            load()
        }
    }
    val scope = rememberCoroutineScope()
    fun act(work: suspend () -> Unit) {
        busy = true
        scope.launch {
            runCatching { work(); delay(400); load() }.onFailure { error = it.message }
            busy = false
        }
    }
    val current = task
    val chrome = LocalSettingsChrome.current
    SideEffect { current?.name?.let { chrome.title = it } }
    DisposableEffect(Unit) { onDispose { chrome.title = null } }
    if (current == null) {
        if (error != null) {
            SettingsCard { SettingsUnavailable("Can’t Load Task", error.orEmpty()) }
        } else {
            Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
                IOSSpinner(Modifier.size(24.dp))
            }
        }
        return
    }
    error?.let { SettingsCard { Text(it, color = AdminError, fontFamily = ZelefinFont, fontSize = 14.sp, modifier = Modifier.padding(vertical = 14.dp)) }; Spacer(Modifier.height(12.dp)) }
    SettingsCard {
        SettingsInfoRow("Status", current.stateLabel)
        if (current.isActive && current.progressLabel != null) {
            SettingsCardDivider()
            SettingsInfoRow("Progress", current.progressLabel!!)
        }
        if (current.isActive) {
            SettingsCardDivider()
            if (current.progressFraction != null) IOSProgressBar(current.progressFraction!!)
            else IOSProgressBar(null)
        }
    }
    if (current.summary.isNotEmpty()) {
        SettingsHeader(stringResource(R.string.detail_about))
        SettingsCard { Text(current.summary, color = AdminSecondary, fontFamily = ZelefinFont, fontSize = 15.sp, modifier = Modifier.padding(vertical = 14.dp)) }
    }
    if (current.lastStatus != null || current.lastEnded != null) {
        SettingsHeader(stringResource(R.string.ui_last_run))
        SettingsCard {
            current.lastStatusLabel?.let { SettingsInfoRow("Result", it) }
            current.lastEnded?.let {
                if (current.lastStatus != null) SettingsCardDivider()
                SettingsInfoRow("Finished", formatAdminDate(it))
            }
            current.lastDurationLabel?.let {
                SettingsCardDivider()
                SettingsInfoRow("Duration", it)
            }
            current.lastError?.let { Text(it, color = AdminError, fontFamily = ZelefinFont, fontSize = 14.sp, modifier = Modifier.padding(top = 12.dp)) }
        }
    }
    if (current.canStart || current.canCancel) {
        Spacer(Modifier.height(20.dp))
        SettingsCard {
            if (current.canStart) {
                SettingsPrimaryButton("Start Task", busy = busy) { act { model.startScheduledTask(taskId) } }
            }
            if (current.canCancel) {
                if (current.canStart) SettingsCardDivider()
                SettingsActionRow("Cancel Task", enabled = !busy, destructive = true) { act { model.stopScheduledTask(taskId) } }
            }
        }
    }
}

@Composable
internal fun ActivityLogTopic() {
    val model: ZelefinModel = viewModel()
    val cacheKey = adminCacheKey(model, "activity")
    var entries by remember { mutableStateOf(AdminCache.get<List<ActivityLogItem>>(cacheKey).orEmpty()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) {
        runCatching { model.activityLog() }
            .onSuccess { entries = it; error = null; AdminCache.put(cacheKey, it) }
            .onFailure { error = it.message ?: "This server has not logged any recent activity." }
        loading = false
    }
    when {
        loading && entries.isEmpty() -> Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
            IOSSpinner(Modifier.size(24.dp))
        }
        entries.isEmpty() -> SettingsCard {
            SettingsUnavailable("No Activity", error ?: "This server has not logged any recent activity.")
        }
        else -> {
            error?.let { SettingsCard { Text(it, color = AdminError, fontFamily = ZelefinFont, fontSize = 14.sp, modifier = Modifier.padding(vertical = 14.dp)) }; Spacer(Modifier.height(12.dp)) }
            SettingsCard {
                entries.forEachIndexed { index, entry ->
                    if (index > 0) SettingsCardDivider()
                    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                        Text(entry.title, style = SettingsRowText)
                        if (entry.subtitle.isNotEmpty()) Text(entry.subtitle, color = AdminSecondary, fontFamily = ZelefinFont, fontSize = 13.sp)
                        formatAdminDate(entry.date).takeIf { it.isNotEmpty() }?.let {
                            Text(it, color = AdminCaption, fontFamily = ZelefinFont, fontSize = 12.sp)
                        }
                    }
                }
            }
        }
    }
}

@Composable
internal fun BackupsTopic() {
    val model: ZelefinModel = viewModel()
    val scope = rememberCoroutineScope()
    val cacheKey = adminCacheKey(model, "backups")
    var backups by remember { mutableStateOf(AdminCache.get<List<ServerBackup>>(cacheKey).orEmpty()) }
    var loading by remember { mutableStateOf(true) }
    var creating by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var restore by remember { mutableStateOf<ServerBackup?>(null) }

    suspend fun load() {
        runCatching { model.serverBackups() }
            .onSuccess { backups = it; error = null; AdminCache.put(cacheKey, it) }
            .onFailure { error = it.message ?: "Sign in as an administrator to manage backups." }
        loading = false
    }
    LaunchedEffect(Unit) { load() }

    restore?.let { target ->
        SettingsAlertDialog(
            title = "Restore this backup?",
            message = "Jellyfin will restart and replace the current database with this archive. This cannot be undone from the app.",
            confirmLabel = "Restore and Restart Server",
            destructive = true,
            onConfirm = {
                restore = null
                scope.launch {
                    runCatching { model.restoreServerBackup(target) }
                        .onFailure { error = it.message ?: "Jellyfin could not restore that backup." }
                }
            },
            onDismiss = { restore = null },
        )
    }

    if (loading && backups.isEmpty() && error == null) {
        Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
            IOSSpinner(Modifier.size(24.dp))
        }
        return
    }
    error?.let { SettingsCard { Text(it, color = AdminError, fontFamily = ZelefinFont, fontSize = 14.sp, modifier = Modifier.padding(vertical = 14.dp)) }; Spacer(Modifier.height(12.dp)) }
    SettingsCard {
        SettingsPrimaryButton("Create Backup", busy = creating) {
            creating = true
            scope.launch {
                runCatching { model.createServerBackup(); load() }.onFailure { error = it.message }
                creating = false
            }
        }
    }
    SettingsFooter(stringResource(R.string.ui_a_backup_archives_this_servers_database_and_meta))
    SettingsHeader(stringResource(R.string.Archives))
    SettingsCard {
        if (backups.isEmpty()) {
            Text("No backups on this server yet.", color = AdminSecondary, fontFamily = ZelefinFont, fontSize = 16.sp)
        } else {
            backups.forEachIndexed { index, backup ->
                if (index > 0) SettingsCardDivider()
                Text(backup.fileName, style = SettingsRowText)
                val subtitle = listOfNotNull(formatAdminDate(backup.dateCreated).takeIf { it.isNotEmpty() }, backup.serverVersion?.takeIf { it.isNotEmpty() }?.let { "Jellyfin $it" }).joinToString(" · ")
                if (subtitle.isNotEmpty()) Text(subtitle, color = AdminCaption, fontFamily = ZelefinFont, fontSize = 13.sp)
                SettingsCardDivider()
                SettingsSecondaryButton("Restore…") { restore = backup }
            }
        }
    }
}

@Composable
internal fun BrandingTopic(state: ZelefinUiState) {
    val model: ZelefinModel = viewModel()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var branding by remember { mutableStateOf(ServerBranding()) }
    var loading by remember { mutableStateOf(true) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        runCatching { model.serverBranding() }
            .onSuccess { branding = it; error = null }
            .onFailure { error = it.message ?: "Sign in as an administrator to edit branding." }
        loading = false
    }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri: Uri? ->
        uri ?: return@rememberLauncherForActivityResult
        scope.launch {
            runCatching {
                val jpeg = app.zelefin.client.session.AccountPhoto.jpeg(context, uri)
                model.uploadSplashscreen(jpeg)
            }.onSuccess { error = null }.onFailure { error = it.message ?: "Could not read that image." }
        }
    }

    val canEdit = !state.isEmbyServer
    val serverLabel = state.session?.displayServer?.takeIf { it.isNotBlank() } ?: "This server"
    SettingsCard { SettingsInfoRow("Server", serverLabel) }
    error?.let { Spacer(Modifier.height(12.dp)); SettingsCard { Text(it, color = AdminError, fontFamily = ZelefinFont, fontSize = 14.sp, modifier = Modifier.padding(vertical = 14.dp)) } }
    SettingsHeader(stringResource(R.string.ui_sign_in))
    SettingsCard {
        AdminMultilineField(
            branding.loginDisclaimer,
            { branding = branding.copy(loginDisclaimer = it) },
            "Login Disclaimer",
            enabled = canEdit,
        )
        if (canEdit) {
            SettingsCardDivider()
            SettingsToggleRow(stringResource(R.string.ui_show_splashscreen), branding.splashscreenEnabled, { on -> branding = branding.copy(splashscreenEnabled = on) })
        }
    }
    if (!canEdit) SettingsFooter(stringResource(R.string.ui_embys_branding_is_read_only_here_change_it_in_em))
    SettingsHeader(stringResource(R.string.ui_custom_css))
    SettingsCard {
        AdminMultilineField(
            branding.customCss,
            { branding = branding.copy(customCss = it) },
            "CSS",
            monospaced = true,
            enabled = canEdit,
        )
    }
    if (!canEdit) return
    SettingsHeader(stringResource(R.string.ui_splash_image))
    SettingsCard {
        SettingsPrimaryButton("Upload Splashscreen", enabled = !loading) {
            picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
        }
        SettingsCardDivider()
        SettingsSecondaryButton("Remove Custom Splashscreen") {
            scope.launch {
                runCatching { model.deleteSplashscreen() }.onSuccess { error = null }.onFailure { error = it.message }
            }
        }
    }
    Spacer(Modifier.height(20.dp))
    SettingsCard {
        SettingsPrimaryButton("Save Branding", busy = saving, enabled = !loading) {
            saving = true
            scope.launch {
                runCatching { model.updateServerBranding(branding) }
                    .onSuccess { error = null }
                    .onFailure { error = it.message ?: "Jellyfin did not save branding." }
                saving = false
            }
        }
    }
}

@Composable
private fun AdminMultilineField(
    value: String,
    onChange: (String) -> Unit,
    placeholder: String,
    monospaced: Boolean = false,
    enabled: Boolean = true,
) {
    IOSTextField(
        value = value,
        onChange = onChange,
        placeholder = placeholder,
        singleLine = false,
        enabled = enabled,
        style = if (monospaced) SettingsRowText.copy(fontFamily = FontFamily.Monospace, fontSize = 14.sp) else SettingsRowText,
        modifier = Modifier.fillMaxWidth().height(if (monospaced) 160.dp else 120.dp).padding(vertical = 12.dp),
    )
}
