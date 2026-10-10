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
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.PhotoCamera
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
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

private val AdminSecondary = ZelefinMuted
private val AdminCaption = ZelefinMuted
private val AdminError = Color(0xFFFF453A)

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
        SettingsCard { Text(it, color = AdminError, fontFamily = ZelefinFont, fontSize = 14.sp) }
        Spacer(Modifier.height(12.dp))
    }
    state.syncPlayGroupName?.takeIf { state.syncPlayGroupId != null }?.let { joined ->
        SettingsHeader("This Device")
        SettingsCard {
            SettingsInfoRow("Joined", joined)
            Spacer(Modifier.height(16.dp))
            SettingsSecondaryButton("Leave Group", enabled = !working) { run { model.leaveSyncPlayGroup() } }
        }
    }
    SettingsHeader("New Group")
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
        Spacer(Modifier.height(16.dp))
        SettingsPrimaryButton("Create", busy = working, enabled = name.isNotBlank() && !working) {
            run { model.createSyncPlayGroup(name); name = "" }
        }
    }
    SettingsHeader("Groups")
    SettingsCard {
        when {
            loading && groups.isEmpty() -> Box(Modifier.fillMaxWidth().padding(12.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.size(22.dp))
            }
            groups.isEmpty() -> Text("No SyncPlay groups are running.", color = AdminSecondary, fontFamily = ZelefinFont, fontSize = 16.sp)
            else -> groups.forEachIndexed { index, group ->
                if (index > 0) SettingsCardDivider()
                val joined = state.syncPlayGroupId == group.id
                Column(
                    Modifier
                        .fillMaxWidth()
                        .clickable(enabled = !working && !joined) { run { model.joinSyncPlayGroup(group) } }
                        .padding(vertical = 4.dp),
                ) {
                    Text(group.name, style = MaterialTheme.typography.titleMedium)
                    Text(group.subtitle, color = AdminCaption, fontFamily = ZelefinFont, fontSize = 13.sp)
                }
            }
        }
    }
}

@Composable
internal fun UsersTopic() {
    val model: ZelefinModel = viewModel()
    var users by remember { mutableStateOf(emptyList<ServerUserAccount>()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) {
        runCatching { model.adminUsers() }
            .onSuccess { users = it; error = null }
            .onFailure { error = it.message ?: "This server did not return any users." }
        loading = false
    }
    when {
        loading && users.isEmpty() -> Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.size(24.dp))
        }
        users.isEmpty() -> SettingsCard {
            Text(error ?: "This server did not return any users.", color = AdminSecondary, fontFamily = ZelefinFont, fontSize = 15.sp)
        }
        else -> {
            error?.let { SettingsCard { Text(it, color = AdminError, fontFamily = ZelefinFont, fontSize = 14.sp) }; Spacer(Modifier.height(12.dp)) }
            SettingsCard {
                users.forEachIndexed { index, account ->
                    if (index > 0) SettingsCardDivider()
                    Row(
                        Modifier.fillMaxWidth().clickable { model.openSettingsTopic("user:${account.id}") }.padding(vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(account.name, style = MaterialTheme.typography.titleMedium)
                            Text(account.statusSubtitle, color = AdminSecondary, fontFamily = ZelefinFont, fontSize = 13.sp)
                        }
                        Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = AdminCaption)
                    }
                }
            }
            SettingsFooter("Administrators can change photos, permissions, library access, and parental controls on this Jellyfin server.")
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

    suspend fun reload() {
        val latest = model.adminUser(userId)
        account = latest
        draft = latest.policy?.let(::UserPolicyDraft)
        username = latest.name
        ratingId = ratings.firstOrNull { it.value == latest.policy?.maxParentalRating }?.id ?: "none"
    }

    LaunchedEffect(userId) {
        runCatching {
            val latest = model.adminUser(userId)
            account = latest
            draft = latest.policy?.let(::UserPolicyDraft)
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
                .onFailure { status = (it.message ?: "Jellyfin did not save that change.") to true }
            saving = false
        }
    }

    fun savePolicy(next: UserPolicyDraft) {
        val current = account ?: return
        val policy = current.policy
        if (policy == null) {
            status = "This user has no policy on the server." to true
            return
        }
        draft = next
        run { model.updateUserPolicy(current.id, next.applyTo(policy)) }
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
            message = "This user will no longer be able to manage the server.",
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
    if (current == null || policy == null) {
        Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
            if (status?.second == true) Text(status?.first.orEmpty(), color = AdminError, fontFamily = ZelefinFont, fontSize = 14.sp)
            else CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.size(24.dp))
        }
        return
    }

    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.size(104.dp)) {
            UserAdminAvatar(session, current, 104.dp)
            if (photoBusy) {
                Box(Modifier.size(104.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.48f)), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.size(24.dp))
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
        Text(current.name, style = MaterialTheme.typography.headlineMedium)
        Text(current.statusSubtitle, color = AdminSecondary, fontFamily = ZelefinFont, fontSize = 14.sp)
        if (current.primaryImageTag != null) {
            Spacer(Modifier.height(10.dp))
            Text(
                "Remove Photo",
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
    SettingsFooter("Administrators can change this user's profile picture on the server.")

    SettingsCard {
        SettingsTextField(label = "USERNAME", value = username, icon = Icons.Outlined.Person, onChange = { username = it }, placeholder = "Username")
        Spacer(Modifier.height(16.dp))
        SettingsPrimaryButton("Save Username", busy = saving, enabled = username.trim().isNotEmpty() && username.trim() != current.name && !photoBusy) {
            run { model.renameUser(current, username) }
        }
    }

    SettingsHeader("Permissions")
    SettingsCard {
        SettingsToggleRow("Administrator", policy.isAdministrator, {
            if (!it && policy.isAdministrator) confirmDemote = true else savePolicy(policy.copy(isAdministrator = it))
        })
        SettingsCardDivider()
        SettingsToggleRow("Edit Subtitles", policy.enableSubtitleManagement, { savePolicy(policy.copy(enableSubtitleManagement = it)) })
        SettingsCardDivider()
        SettingsToggleRow("Disable Account", policy.isDisabled, {
            if (it && !policy.isDisabled) confirmDisable = true else savePolicy(policy.copy(isDisabled = it))
        })
    }
    SettingsFooter("Administrators can manage users, sessions, and server settings. Edit Subtitles lets this user search and download subtitles onto the server, same as an administrator.")

    SettingsHeader("Streaming")
    val bitrateChoices = remember(policy.remoteClientBitrateLimit) {
        val values = (RemoteBitrateLimit.bits + policy.remoteClientBitrateLimit).distinct().sorted()
        values.map { SettingsChoice(it, RemoteBitrateLimit.title(it)) }
    }
    SettingsCard {
        SettingsMenuPicker("Remote bitrate", bitrateChoices, policy.remoteClientBitrateLimit) { savePolicy(policy.copy(remoteClientBitrateLimit = it)) }
    }
    SettingsFooter("Caps how fast this user can pull video from outside the local network. Unlimited leaves the client in charge.")

    SettingsHeader("Password")
    SettingsCard {
        SettingsTextField(label = "NEW", value = newPassword, icon = Icons.Outlined.Lock, onChange = { newPassword = it }, placeholder = "New", password = true, keyboard = KeyboardType.Password)
        SettingsCardDivider()
        SettingsTextField(label = "CONFIRM", value = confirmPassword, icon = Icons.Outlined.Lock, onChange = { confirmPassword = it }, placeholder = "Confirm", password = true, keyboard = KeyboardType.Password)
        if (confirmPassword.isNotEmpty() && newPassword != confirmPassword) {
            Text("The new passwords do not match.", color = AdminError, fontFamily = ZelefinFont, fontSize = 13.sp, modifier = Modifier.padding(top = 12.dp))
        }
        Spacer(Modifier.height(16.dp))
        SettingsPrimaryButton("Set Password", busy = saving, enabled = newPassword.isNotEmpty() && newPassword == confirmPassword) {
            run("Password saved.") {
                model.setUserPassword(userId, newPassword)
                newPassword = ""
                confirmPassword = ""
            }
        }
        Spacer(Modifier.height(10.dp))
        SettingsSecondaryButton("Reset Password", enabled = !saving) { confirmReset = true }
    }
    SettingsFooter("Reset clears the password on the server. Set Password stores the new one now.")

    SettingsHeader("Parental Controls")
    val ratingChoices = listOf(SettingsChoice("none", "None")) + ratings.map { SettingsChoice(it.id, it.name) }
    SettingsCard {
        SettingsMenuPicker("Maximum rating", ratingChoices, ratingId) { selected ->
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
    SettingsFooter("Maximum rating hides titles above that score. Blocked types stay hidden even when they have no rating.")

    SettingsHeader("Library Access")
    SettingsCard {
        SettingsToggleRow("All libraries", policy.enableAllFolders, { savePolicy(policy.copy(enableAllFolders = it)) })
        if (!policy.enableAllFolders) {
            folders.forEach { folder ->
                SettingsCardDivider()
                SettingsToggleRow(folder.name, policy.enabledFolders.contains(folder.id), { on ->
                    savePolicy(policy.copy(enabledFolders = if (on) policy.enabledFolders + folder.id else policy.enabledFolders - folder.id))
                })
            }
        }
    }
    SettingsFooter("Turn off All libraries to pick which folders this user can see.")

    status?.let { (text, isError) ->
        SettingsCard { Text(text, color = if (isError) AdminError else AdminSecondary, fontFamily = ZelefinFont, fontSize = 14.sp) }
    }
}

@Composable
private fun UserAdminAvatar(session: SavedSession?, account: ServerUserAccount, diameter: androidx.compose.ui.unit.Dp) {
    Box(
        Modifier.size(diameter).clip(CircleShape).background(Color.White.copy(alpha = 0.12f)),
        contentAlignment = Alignment.Center,
    ) {
        Text(account.name.take(1).uppercase(), color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 36.sp)
        session?.let { userAvatarUrl(it, account.id, account.primaryImageTag) }?.let { url ->
            CachedArtwork(url = url, contentDescription = account.name, contentScale = ContentScale.Crop, modifier = Modifier.size(diameter).clip(CircleShape))
        }
    }
}

@Composable
internal fun ScheduledTasksTopic() {
    val model: ZelefinModel = viewModel()
    var tasks by remember { mutableStateOf(emptyList<ScheduledTask>()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf<String?>(null) }

    suspend fun load() {
        runCatching { model.scheduledTasks() }
            .onSuccess { tasks = it; error = null }
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
            CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.size(24.dp))
        }
        tasks.isEmpty() -> SettingsCard { Text(error ?: "This server did not return any scheduled tasks.", color = AdminSecondary, fontFamily = ZelefinFont, fontSize = 15.sp) }
        else -> {
            error?.let { SettingsCard { Text(it, color = AdminError, fontFamily = ZelefinFont, fontSize = 14.sp) }; Spacer(Modifier.height(12.dp)) }
            val running = tasks.filter { it.isActive }
            val idle = tasks.filter { !it.isActive && !it.isHidden }.groupBy { it.category }.toSortedMap(String.CASE_INSENSITIVE_ORDER)
            if (running.isNotEmpty()) {
                SettingsHeader("Running")
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
    Column(Modifier.fillMaxWidth().clickable(onClick = onOpen).padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(task.name, style = MaterialTheme.typography.titleMedium)
                Text(
                    task.stateSubtitle,
                    color = if (task.lastStatus == TaskCompletionStatus.FAILED && !task.isActive) AdminError else AdminCaption,
                    fontFamily = ZelefinFont,
                    fontSize = 13.sp,
                )
            }
            when {
                isBusy -> CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                task.canCancel -> Text("Cancel", color = AdminError, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, modifier = Modifier.clickable(onClick = onCancel).padding(8.dp))
                task.canStart -> Text("Start", color = ZelefinCyan, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, modifier = Modifier.clickable(onClick = onStart).padding(8.dp))
            }
            Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = AdminCaption)
        }
        if (task.isActive) {
            if (task.progressFraction != null) LinearProgressIndicator(progress = { task.progressFraction!! }, color = MaterialTheme.colorScheme.primary, trackColor = MaterialTheme.colorScheme.surfaceContainerHighest, modifier = Modifier.fillMaxWidth())
            else LinearProgressIndicator(color = MaterialTheme.colorScheme.primary, trackColor = MaterialTheme.colorScheme.surfaceContainerHighest, modifier = Modifier.fillMaxWidth())
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
    if (current == null) {
        Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
            if (error != null) Text(error.orEmpty(), color = AdminError, fontFamily = ZelefinFont, fontSize = 14.sp)
            else CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.size(24.dp))
        }
        return
    }
    error?.let { SettingsCard { Text(it, color = AdminError, fontFamily = ZelefinFont, fontSize = 14.sp) }; Spacer(Modifier.height(12.dp)) }
    SettingsCard {
        SettingsInfoRow("Status", current.stateLabel)
        if (current.isActive && current.progressLabel != null) {
            SettingsCardDivider()
            SettingsInfoRow("Progress", current.progressLabel!!)
        }
        if (current.isActive) {
            SettingsCardDivider()
            if (current.progressFraction != null) LinearProgressIndicator(progress = { current.progressFraction!! }, color = MaterialTheme.colorScheme.primary, trackColor = MaterialTheme.colorScheme.surfaceContainerHighest, modifier = Modifier.fillMaxWidth())
            else LinearProgressIndicator(color = MaterialTheme.colorScheme.primary, trackColor = MaterialTheme.colorScheme.surfaceContainerHighest, modifier = Modifier.fillMaxWidth())
        }
    }
    if (current.summary.isNotEmpty()) {
        SettingsHeader("About")
        SettingsCard { Text(current.summary, color = AdminSecondary, fontFamily = ZelefinFont, fontSize = 15.sp) }
    }
    if (current.lastStatus != null || current.lastEnded != null) {
        SettingsHeader("Last run")
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
    if (current.canStart) {
        Spacer(Modifier.height(16.dp))
        SettingsPrimaryButton("Start Task", busy = busy) { act { model.startScheduledTask(taskId) } }
    }
    if (current.canCancel) {
        Spacer(Modifier.height(10.dp))
        SettingsSecondaryButton("Cancel Task", enabled = !busy) { act { model.stopScheduledTask(taskId) } }
    }
}

@Composable
internal fun ActivityLogTopic() {
    val model: ZelefinModel = viewModel()
    var entries by remember { mutableStateOf(emptyList<ActivityLogItem>()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) {
        runCatching { model.activityLog() }
            .onSuccess { entries = it; error = null }
            .onFailure { error = it.message ?: "This server has not logged any recent activity." }
        loading = false
    }
    when {
        loading && entries.isEmpty() -> Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.size(24.dp))
        }
        entries.isEmpty() -> SettingsCard { Text(error ?: "This server has not logged any recent activity.", color = AdminSecondary, fontFamily = ZelefinFont, fontSize = 15.sp) }
        else -> {
            error?.let { SettingsCard { Text(it, color = AdminError, fontFamily = ZelefinFont, fontSize = 14.sp) }; Spacer(Modifier.height(12.dp)) }
            SettingsCard {
                entries.forEachIndexed { index, entry ->
                    if (index > 0) SettingsCardDivider()
                    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                        Text(entry.title, style = MaterialTheme.typography.titleMedium)
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
    var backups by remember { mutableStateOf(emptyList<ServerBackup>()) }
    var loading by remember { mutableStateOf(true) }
    var creating by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var restore by remember { mutableStateOf<ServerBackup?>(null) }

    suspend fun load() {
        runCatching { model.serverBackups() }
            .onSuccess { backups = it; error = null }
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
            CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.size(24.dp))
        }
        return
    }
    error?.let { SettingsCard { Text(it, color = AdminError, fontFamily = ZelefinFont, fontSize = 14.sp) }; Spacer(Modifier.height(12.dp)) }
    SettingsPrimaryButton("Create Backup", busy = creating) {
        creating = true
        scope.launch {
            runCatching { model.createServerBackup(); load() }.onFailure { error = it.message }
            creating = false
        }
    }
    SettingsFooter("A backup archives this server’s database and metadata. Restoring one restarts Jellyfin.")
    SettingsHeader("Archives")
    SettingsCard {
        if (backups.isEmpty()) {
            Text("No backups on this server yet.", color = AdminSecondary, fontFamily = ZelefinFont, fontSize = 16.sp)
        } else {
            backups.forEachIndexed { index, backup ->
                if (index > 0) SettingsCardDivider()
                Text(backup.fileName, style = MaterialTheme.typography.titleMedium)
                val subtitle = listOfNotNull(formatAdminDate(backup.dateCreated).takeIf { it.isNotEmpty() }, backup.serverVersion?.takeIf { it.isNotEmpty() }?.let { "Jellyfin $it" }).joinToString(" · ")
                if (subtitle.isNotEmpty()) Text(subtitle, color = AdminCaption, fontFamily = ZelefinFont, fontSize = 13.sp)
                Spacer(Modifier.height(12.dp))
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

    error?.let { SettingsCard { Text(it, color = AdminError, fontFamily = ZelefinFont, fontSize = 14.sp) }; Spacer(Modifier.height(12.dp)) }
    SettingsHeader("Sign-In")
    SettingsCard {
        SettingsFieldLabel("Login disclaimer")
        Spacer(Modifier.height(8.dp))
        AdminMultilineField(branding.loginDisclaimer, { branding = branding.copy(loginDisclaimer = it) }, "Shown on the sign-in screen")
        SettingsCardDivider()
        SettingsToggleRow("Show splashscreen", branding.splashscreenEnabled, { branding = branding.copy(splashscreenEnabled = it) })
    }
    SettingsHeader("Custom CSS")
    SettingsCard {
        SettingsFieldLabel("CSS")
        Spacer(Modifier.height(8.dp))
        AdminMultilineField(branding.customCss, { branding = branding.copy(customCss = it) }, "CSS", monospaced = true)
    }
    SettingsHeader("Splash Image")
    SettingsCard {
        SettingsPrimaryButton("Upload Splashscreen", enabled = !loading) {
            picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
        }
        Spacer(Modifier.height(10.dp))
        SettingsSecondaryButton("Remove Custom Splashscreen") {
            scope.launch {
                runCatching { model.deleteSplashscreen() }.onSuccess { error = null }.onFailure { error = it.message }
            }
        }
    }
    Spacer(Modifier.height(16.dp))
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

@Composable
private fun AdminMultilineField(value: String, onChange: (String) -> Unit, placeholder: String, monospaced: Boolean = false) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        modifier = Modifier.fillMaxWidth().height(if (monospaced) 160.dp else 120.dp),
        placeholder = { Text(placeholder) },
        textStyle = if (monospaced) {
            MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace)
        } else {
            MaterialTheme.typography.bodyLarge
        },
    )
}
