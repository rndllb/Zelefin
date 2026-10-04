package app.zelefin.client.jellyfin

import app.zelefin.core.ZelefinException
import java.time.Duration
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.jellyfin.sdk.api.client.extensions.activityLogApi
import org.jellyfin.sdk.api.client.extensions.backupApi
import org.jellyfin.sdk.api.client.extensions.brandingApi
import org.jellyfin.sdk.api.client.extensions.configurationApi
import org.jellyfin.sdk.api.client.extensions.imageApi
import org.jellyfin.sdk.api.client.extensions.libraryApi
import org.jellyfin.sdk.api.client.extensions.localizationApi
import org.jellyfin.sdk.api.client.extensions.scheduledTasksApi
import org.jellyfin.sdk.api.client.extensions.userApi
import org.jellyfin.sdk.model.DateTime
import org.jellyfin.sdk.model.api.BackupOptionsDto
import org.jellyfin.sdk.model.api.BackupRestoreRequestDto
import org.jellyfin.sdk.model.api.BrandingOptionsDto
import org.jellyfin.sdk.model.api.TaskCompletionStatus
import org.jellyfin.sdk.model.api.TaskInfo
import org.jellyfin.sdk.model.api.TaskState
import org.jellyfin.sdk.model.api.UnratedItem
import org.jellyfin.sdk.model.api.UpdateUserPassword
import org.jellyfin.sdk.model.api.UserDto
import org.jellyfin.sdk.model.api.UserPolicy
import org.jellyfin.sdk.model.toFileInfo

data class ActivityLogItem(
    val id: String,
    val title: String,
    val detail: String?,
    val date: DateTime?,
    val type: String?,
) {
    val subtitle: String
        get() = listOfNotNull(type?.trim()?.takeIf { it.isNotEmpty() }, detail?.trim()?.takeIf { it.isNotEmpty() })
            .joinToString(" · ")
}

data class ServerBackup(
    val path: String,
    val dateCreated: DateTime?,
    val serverVersion: String?,
) {
    val id: String get() = path
    val fileName: String get() = path.substringAfterLast('/').substringAfterLast('\\').ifEmpty { path }
}

data class ServerBranding(
    val loginDisclaimer: String = "",
    val customCss: String = "",
    val splashscreenEnabled: Boolean = true,
)

data class ScheduledTask(
    val id: String,
    val name: String,
    val category: String,
    val summary: String,
    val state: TaskState,
    val progressPercentage: Double?,
    val isHidden: Boolean,
    val lastStatus: TaskCompletionStatus?,
    val lastStarted: DateTime?,
    val lastEnded: DateTime?,
    val lastError: String?,
) {
    val isActive: Boolean get() = state == TaskState.RUNNING || state == TaskState.CANCELLING
    val canStart: Boolean get() = state == TaskState.IDLE
    val canCancel: Boolean get() = state == TaskState.RUNNING
    val progressFraction: Float? get() = progressPercentage?.let { (it / 100.0).toFloat().coerceIn(0f, 1f) }
    val progressLabel: String? get() = progressPercentage?.let { "${it.toInt()}%" }
    val stateLabel: String
        get() = when (state) {
            TaskState.RUNNING -> "Running"
            TaskState.CANCELLING -> "Cancelling"
            TaskState.IDLE -> "Idle"
        }
    val lastStatusLabel: String?
        get() = when (lastStatus) {
            TaskCompletionStatus.COMPLETED -> "Completed"
            TaskCompletionStatus.FAILED -> "Failed"
            TaskCompletionStatus.CANCELLED -> "Cancelled"
            TaskCompletionStatus.ABORTED -> "Aborted"
            null -> null
        }
    val stateSubtitle: String
        get() = when {
            state == TaskState.RUNNING && progressLabel != null -> "Running · $progressLabel"
            state == TaskState.RUNNING -> "Running"
            state == TaskState.CANCELLING -> "Cancelling"
            else -> listOfNotNull(lastStatusLabel, lastEnded?.let(::formatAdminDate)).joinToString(" · ").ifEmpty { "Idle" }
        }
    val lastDurationLabel: String?
        get() {
            val start = lastStarted ?: return null
            val end = lastEnded ?: return null
            val seconds = Duration.between(start, end).seconds
            if (seconds < 0) return null
            val hours = seconds / 3600
            val minutes = (seconds % 3600) / 60
            val secs = seconds % 60
            return if (hours > 0) "%d:%02d:%02d".format(hours, minutes, secs) else "%d:%02d".format(minutes, secs)
        }

    companion object {
        fun from(dto: TaskInfo): ScheduledTask? {
            val id = dto.id?.takeIf { it.isNotBlank() } ?: return null
            return ScheduledTask(
                id = id,
                name = dto.name?.trim()?.ifEmpty { null } ?: "Scheduled task",
                category = dto.category?.trim()?.ifEmpty { null } ?: "Other",
                summary = dto.description?.trim().orEmpty(),
                state = dto.state,
                progressPercentage = dto.currentProgressPercentage,
                isHidden = dto.isHidden,
                lastStatus = dto.lastExecutionResult?.status,
                lastStarted = dto.lastExecutionResult?.startTimeUtc,
                lastEnded = dto.lastExecutionResult?.endTimeUtc,
                lastError = dto.lastExecutionResult?.errorMessage?.trim()?.ifEmpty { null },
            )
        }
    }
}

data class ServerUserAccount(
    val id: String,
    val name: String,
    val primaryImageTag: String?,
    val policy: UserPolicy?,
    val dto: UserDto,
) {
    val isAdministrator: Boolean get() = policy?.isAdministrator == true
    val isDisabled: Boolean get() = policy?.isDisabled == true
    val statusSubtitle: String
        get() = buildList {
            if (isAdministrator) add("Administrator")
            if (isDisabled) add("Disabled")
            if (isEmpty()) add("User")
        }.joinToString(" · ")
}

data class AdminMediaFolder(val id: String, val name: String)

data class ParentalRatingChoice(val name: String, val value: Int?) {
    val id: String get() = "${value ?: -1}-$name"
}

data class UserPolicyDraft(
    val isAdministrator: Boolean,
    val isDisabled: Boolean,
    val enableSubtitleManagement: Boolean,
    val remoteClientBitrateLimit: Int,
    val maxParentalRating: Int?,
    val blockUnratedItems: Set<UnratedItem>,
    val enableAllFolders: Boolean,
    val enabledFolders: Set<String>,
) {
    constructor(policy: UserPolicy) : this(
        isAdministrator = policy.isAdministrator,
        isDisabled = policy.isDisabled,
        enableSubtitleManagement = policy.enableSubtitleManagement,
        remoteClientBitrateLimit = policy.remoteClientBitrateLimit.coerceAtLeast(0),
        maxParentalRating = policy.maxParentalRating,
        blockUnratedItems = policy.blockUnratedItems.orEmpty().toSet(),
        enableAllFolders = policy.enableAllFolders,
        enabledFolders = policy.enabledFolders.orEmpty().map { it.toString() }.toSet(),
    )

    fun applyTo(policy: UserPolicy): UserPolicy = policy.copy(
        isAdministrator = isAdministrator,
        isDisabled = isDisabled,
        enableSubtitleManagement = enableSubtitleManagement,
        remoteClientBitrateLimit = remoteClientBitrateLimit,
        maxParentalRating = maxParentalRating,
        blockUnratedItems = blockUnratedItems.sortedBy { it.serialName },
        enableAllFolders = enableAllFolders,
        enabledFolders = if (enableAllFolders) emptyList() else enabledFolders.map { UUID.fromString(it) }.sortedBy { it.toString() },
    )
}

enum class RemoteBitrateLimit(val bits: Int, val title: String) {
    Unlimited(0, "Unlimited"),
    Kbps420(420_000, "420 kbps"),
    Kbps720(720_000, "720 kbps"),
    Mbps1(1_000_000, "1 Mbps"),
    Mbps2(2_000_000, "2 Mbps"),
    Mbps4(4_000_000, "4 Mbps"),
    Mbps8(8_000_000, "8 Mbps"),
    Mbps15(15_000_000, "15 Mbps"),
    Mbps40(40_000_000, "40 Mbps"),
    Mbps80(80_000_000, "80 Mbps"),
    Mbps120(120_000_000, "120 Mbps"),
    ;

    companion object {
        val bits = entries.map { it.bits }
        fun title(bitsPerSecond: Int): String =
            entries.firstOrNull { it.bits == bitsPerSecond }?.title ?: "${maxOf(1, bitsPerSecond / 1_000)} kbps"
    }
}

val UnratedItem.settingsTitle: String
    get() = when (this) {
        UnratedItem.MOVIE -> "Movies"
        UnratedItem.TRAILER -> "Trailers"
        UnratedItem.SERIES -> "Shows"
        UnratedItem.MUSIC -> "Music"
        UnratedItem.BOOK -> "Books"
        UnratedItem.LIVE_TV_CHANNEL -> "Live TV channels"
        UnratedItem.LIVE_TV_PROGRAM -> "Live TV programs"
        UnratedItem.CHANNEL_CONTENT -> "Channel content"
        UnratedItem.OTHER -> "Other"
    }

private val adminDateFormat: DateTimeFormatter =
    DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).withLocale(Locale.getDefault())

fun formatAdminDate(value: DateTime?): String {
    value ?: return ""
    return runCatching { (value as LocalDateTime).format(adminDateFormat) }.getOrElse { value.toString() }
}

suspend fun JellyfinLibrary.activityLog(limit: Int = 80): List<ActivityLogItem> = withContext(Dispatchers.IO) {
    sdk.activityLogApi.getLogEntries(startIndex = 0, limit = limit).content.items.mapNotNull { entry ->
        val title = entry.name.trim()
        if (title.isEmpty()) return@mapNotNull null
        ActivityLogItem(
            id = "${entry.id}",
            title = title,
            detail = entry.shortOverview ?: entry.overview,
            date = entry.date,
            type = entry.type,
        )
    }
}

suspend fun JellyfinLibrary.serverBackups(): List<ServerBackup> = withContext(Dispatchers.IO) {
    sdk.backupApi.listBackups().content.mapNotNull { dto ->
        dto.path.takeIf { it.isNotBlank() }?.let { ServerBackup(it, dto.dateCreated, dto.serverVersion) }
    }
}

suspend fun JellyfinLibrary.createServerBackup(): ServerBackup = withContext(Dispatchers.IO) {
    val dto = sdk.backupApi.createBackup(BackupOptionsDto(metadata = true, trickplay = true, subtitles = true, database = true)).content
    val path = dto.path.takeIf { it.isNotBlank() } ?: throw ZelefinException.server("The server did not return a backup path.")
    ServerBackup(path, dto.dateCreated, dto.serverVersion)
}

suspend fun JellyfinLibrary.restoreServerBackup(backup: ServerBackup) = withContext(Dispatchers.IO) {
    sdk.backupApi.startRestoreBackup(BackupRestoreRequestDto(archiveFileName = backup.fileName))
    Unit
}

suspend fun JellyfinLibrary.serverBranding(): ServerBranding = withContext(Dispatchers.IO) {
    val dto = sdk.brandingApi.getBrandingOptions().content
    ServerBranding(
        loginDisclaimer = dto.loginDisclaimer.orEmpty(),
        customCss = dto.customCss.orEmpty(),
        splashscreenEnabled = dto.splashscreenEnabled,
    )
}

suspend fun JellyfinLibrary.updateServerBranding(branding: ServerBranding) = withContext(Dispatchers.IO) {
    sdk.configurationApi.updateBrandingConfiguration(
        BrandingOptionsDto(
            loginDisclaimer = branding.loginDisclaimer,
            customCss = branding.customCss,
            splashscreenEnabled = branding.splashscreenEnabled,
        ),
    )
    Unit
}

suspend fun JellyfinLibrary.uploadSplashscreen(jpeg: ByteArray) = withContext(Dispatchers.IO) {
    sdk.imageApi.uploadCustomSplashscreen(jpeg.toFileInfo("image/jpeg"))
    Unit
}

suspend fun JellyfinLibrary.deleteSplashscreen() = withContext(Dispatchers.IO) {
    sdk.imageApi.deleteCustomSplashscreen()
    Unit
}

suspend fun JellyfinLibrary.scheduledTasks(): List<ScheduledTask> = withContext(Dispatchers.IO) {
    sdk.scheduledTasksApi.getTasks().content.mapNotNull(ScheduledTask::from)
        .sortedWith(compareByDescending<ScheduledTask> { it.isActive }.thenBy(String.CASE_INSENSITIVE_ORDER) { it.category }.thenBy(String.CASE_INSENSITIVE_ORDER) { it.name })
}

suspend fun JellyfinLibrary.startScheduledTask(id: String) = withContext(Dispatchers.IO) {
    sdk.scheduledTasksApi.startTask(id)
    Unit
}

suspend fun JellyfinLibrary.stopScheduledTask(id: String) = withContext(Dispatchers.IO) {
    sdk.scheduledTasksApi.stopTask(id)
    Unit
}

suspend fun JellyfinLibrary.adminUsers(): List<ServerUserAccount> = withContext(Dispatchers.IO) {
    sdk.userApi.getUsers().content.mapNotNull(::serverUser).sortedBy { it.name.lowercase() }
}

suspend fun JellyfinLibrary.adminUser(id: String): ServerUserAccount = withContext(Dispatchers.IO) {
    serverUser(sdk.userApi.getUserById(UUID.fromString(id)).content)
        ?: throw ZelefinException.missingUser()
}

suspend fun JellyfinLibrary.adminMediaFolders(): List<AdminMediaFolder> = withContext(Dispatchers.IO) {
    sdk.libraryApi.getMediaFolders().content.items.orEmpty().mapNotNull { item ->
        val id = item.id?.toString()?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
        AdminMediaFolder(id, item.name?.trim()?.ifEmpty { null } ?: "Library")
    }
}

suspend fun JellyfinLibrary.parentalRatings(): List<ParentalRatingChoice> = withContext(Dispatchers.IO) {
    val seen = mutableSetOf<String>()
    sdk.localizationApi.getParentalRatings().content.mapNotNull { rating ->
        val name = rating.name.trim()
        if (name.isEmpty()) return@mapNotNull null
        val choice = ParentalRatingChoice(name, rating.value)
        if (!seen.add(choice.id)) return@mapNotNull null
        choice
    }
}

suspend fun JellyfinLibrary.updateUserPolicy(userId: String, policy: UserPolicy) = withContext(Dispatchers.IO) {
    sdk.userApi.updateUserPolicy(UUID.fromString(userId), policy)
    Unit
}

suspend fun JellyfinLibrary.renameUser(account: ServerUserAccount, name: String) = withContext(Dispatchers.IO) {
    val trimmed = name.trim()
    if (trimmed.isEmpty()) throw ZelefinException.server("Enter a username.")
    sdk.userApi.updateUser(UUID.fromString(account.id), account.dto.copy(name = trimmed))
    Unit
}

suspend fun JellyfinLibrary.resetUserPassword(userId: String) = withContext(Dispatchers.IO) {
    sdk.userApi.updateUserPassword(UUID.fromString(userId), UpdateUserPassword(resetPassword = true))
    Unit
}

suspend fun JellyfinLibrary.setUserPassword(userId: String, newPassword: String) = withContext(Dispatchers.IO) {
    if (newPassword.isEmpty()) throw ZelefinException.server("Enter a new password.")
    sdk.userApi.updateUserPassword(UUID.fromString(userId), UpdateUserPassword(resetPassword = false, newPw = newPassword))
    Unit
}

suspend fun JellyfinLibrary.deleteUserImage(userId: String) = withContext(Dispatchers.IO) {
    sdk.imageApi.deleteUserImage(UUID.fromString(userId))
    Unit
}

private fun serverUser(dto: UserDto): ServerUserAccount? {
    val id = dto.id.toString().takeIf { it.isNotBlank() } ?: return null
    return ServerUserAccount(
        id = id,
        name = dto.name?.trim()?.ifEmpty { null } ?: "User",
        primaryImageTag = dto.primaryImageTag,
        policy = dto.policy,
        dto = dto,
    )
}
