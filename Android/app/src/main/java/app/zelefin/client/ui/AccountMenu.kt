package app.zelefin.client.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.LiveTv
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.PersonAdd
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.runtime.collectAsState
import androidx.lifecycle.viewmodel.compose.viewModel
import app.zelefin.client.ZelefinModel
import app.zelefin.core.SavedSession
import app.zelefin.core.ServerUrl
import app.zelefin.core.SiloAvatarUrl
import app.zelefin.core.SiloProfile

const val AddAccountTopicId = "add-account"

private val Destructive = Color(0xFFFF453A)

@Composable
fun AccountAvatarMenu(
    session: SavedSession?,
    onProfile: () -> Unit,
    onSessions: () -> Unit,
    onSettings: () -> Unit,
    onSignOut: () -> Unit,
) {
    val model: ZelefinModel = viewModel()
    val appState by model.state.collectAsState()
    var open by remember { mutableStateOf(false) }
    val anchor = remember { mutableStateOf(Rect.Zero) }
    val haze = LocalZelefinHaze.current
    val showSessions = session?.isSiloServer != true
    val showSyncPlay = session?.isSiloServer != true
    val others = appState.accounts.filter { it.accountId != session?.accountId }
    val currentProfileId = session?.siloLink?.profileId
    val profiles = if (currentProfileId == null) emptyList() else appState.household.profiles.filter { it.id != currentProfileId }

    LaunchedEffect(open) {
        if (open && currentProfileId != null) model.refreshHousehold()
    }

    PresentZelefinOverlay(visible = haze != null && open) {
        val hazeState = haze ?: return@PresentZelefinOverlay
        DockGlassMenu(
                hazeState = hazeState,
                anchor = anchor.value,
                showSessions = showSessions,
                showSyncPlay = showSyncPlay,
                silo = session?.isSiloServer == true,
                profiles = profiles,
                onSwitchProfile = { profile ->
                    open = false
                    model.switchSiloProfile(profile)
                },
                others = others,
                onDismiss = { open = false },
                onProfile = {
                    open = false
                    onProfile()
                },
                onSessions = {
                    open = false
                    onSessions()
                },
                onSyncPlay = {
                    open = false
                    model.openSettingsTopic("syncplay")
                },
                onSwitch = { account ->
                    open = false
                    model.switchAccount(account)
                },
                onAdd = {
                    open = false
                    model.resetAddAccount()
                    model.openSettingsTopic(AddAccountTopicId)
                },
                onSettings = {
                    open = false
                    onSettings()
                },
                onSignOut = {
                    open = false
                    onSignOut()
                },
            )
    }

    AccountAvatar(
        session,
        onClick = { open = !open },
        modifier = Modifier.onGloballyPositioned { anchor.value = it.boundsInRoot() },
        floating = true,
    )
}

@Composable
private fun DockGlassMenu(
    hazeState: ZelefinHazeState,
    anchor: Rect,
    showSessions: Boolean,
    showSyncPlay: Boolean,
    silo: Boolean,
    profiles: List<SiloProfile>,
    onSwitchProfile: (SiloProfile) -> Unit,
    others: List<SavedSession>,
    onDismiss: () -> Unit,
    onProfile: () -> Unit,
    onSessions: () -> Unit,
    onSyncPlay: () -> Unit,
    onSwitch: (SavedSession) -> Unit,
    onAdd: () -> Unit,
    onSettings: () -> Unit,
    onSignOut: () -> Unit,
) {
    AnchoredMenuFrame(anchor, alignTrailing = true, onDismiss = onDismiss) {
        Column(
            Modifier
                .zelefinGlassChrome(hazeState, ZelefinMenuShape)
                .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) {}
                .zelefinMenuWidth()
                .padding(vertical = 4.dp),
        ) {
            GlassMenuRow("Profile", Icons.Outlined.AccountCircle, onProfile)
            if (showSessions) GlassMenuRow("Sessions", Icons.Outlined.LiveTv, onSessions)
            if (showSyncPlay) GlassMenuRow("SyncPlay", Icons.Outlined.Groups, onSyncPlay)
            if (profiles.isNotEmpty()) {
                GlassMenuDivider()
                GlassMenuCaption("Switch Profile")
                profiles.forEach { profile -> GlassProfileRow(profile) { onSwitchProfile(profile) } }
            }
            if (others.isNotEmpty()) {
                GlassMenuDivider()
                GlassMenuCaption(if (silo) "Switch Account" else "Switch User")
                others.forEach { account -> GlassAccountRow(account) { onSwitch(account) } }
                GlassMenuDivider()
            }
            GlassMenuRow(if (silo) "Add Account" else "Add User", Icons.Outlined.PersonAdd, onAdd)
            GlassMenuRow("Settings", Icons.Outlined.Settings, onSettings)
            GlassMenuDivider()
            GlassMenuRow("Sign Out", Icons.AutoMirrored.Outlined.Logout, onSignOut, destructive = true)
        }
    }
}

@Composable
private fun GlassMenuCaption(title: String) {
    Text(
        title,
        color = DockInactive.copy(alpha = 0.6f),
        fontFamily = ZelefinFont,
        fontWeight = FontWeight.SemiBold,
        fontSize = 13.sp,
        maxLines = 1,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp, bottom = 2.dp),
    )
}

@Composable
private fun GlassMenuDivider() {
    Box(
        Modifier
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .fillMaxWidth()
            .height(0.5.dp)
            .background(DockBorder),
    )
}

@Composable
private fun GlassAccountRow(account: SavedSession, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val run = LocalMenuAction.current
    Row(
        Modifier
            .fillMaxWidth()
            .height(48.dp)
            .padding(horizontal = 4.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(if (pressed) DockSelectedFill else Color.Transparent)
            .clickable(interactionSource = interaction, indication = null) { run(onClick) }
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AccountAvatarImage(account, 28.dp)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(account.userName, color = DockInactive, fontFamily = ZelefinFont, fontSize = 17.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(account.displayServer, color = DockInactive.copy(alpha = 0.6f), fontFamily = ZelefinFont, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun GlassProfileRow(profile: SiloProfile, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val run = LocalMenuAction.current
    Row(
        Modifier
            .fillMaxWidth()
            .height(48.dp)
            .padding(horizontal = 4.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(if (pressed) DockSelectedFill else Color.Transparent)
            .clickable(interactionSource = interaction, indication = null) { run(onClick) }
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SiloProfileAvatar(profile, 28.dp)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(profile.name, color = DockInactive, fontFamily = ZelefinFont, fontSize = 17.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(siloProfileCaption(profile), color = DockInactive.copy(alpha = 0.6f), fontFamily = ZelefinFont, fontSize = 12.sp, maxLines = 1)
        }
        if (profile.hasPin) {
            Icon(Icons.Outlined.Lock, contentDescription = "PIN", tint = DockInactive.copy(alpha = 0.6f), modifier = Modifier.size(16.dp))
        }
    }
}

/** Plain round avatar for lists; the photo when the server has one, otherwise the initial. */
@Composable
fun AccountAvatarImage(account: SavedSession, diameter: androidx.compose.ui.unit.Dp) {
    val initial = account.userName.trim().firstOrNull()?.uppercaseChar()?.toString() ?: "Z"
    Box(
        Modifier
            .size(diameter)
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.12f)),
        contentAlignment = Alignment.Center,
    ) {
        Text(initial, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = (diameter.value * 0.4f).sp)
        avatarImageUrl(account)?.let { url ->
            CachedArtwork(url = url, contentDescription = account.userName, contentScale = ContentScale.Crop, modifier = Modifier.size(diameter).clip(CircleShape))
        }
    }
}

/** Two-button confirm (Cancel + action). */
@Composable
fun ZelefinGlassConfirm(
    hazeState: ZelefinHazeState,
    title: String,
    message: String,
    confirmLabel: String,
    destructive: Boolean,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    SettingsAlertDialog(
        title = title,
        message = message,
        confirmLabel = confirmLabel,
        onConfirm = onConfirm,
        onDismiss = onDismiss,
        destructive = destructive,
    )
}

@Composable
private fun GlassMenuRow(
    title: String,
    icon: ImageVector,
    onClick: () -> Unit,
    destructive: Boolean = false,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val run = LocalMenuAction.current
    val textTint = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface
    val iconTint = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface
    Row(
        Modifier
            .fillMaxWidth()
            .height(44.dp)
            .padding(horizontal = 4.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(if (pressed) DockSelectedFill else Color.Transparent)
            .clickable(interactionSource = interaction, indication = null) { run(onClick) }
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = iconTint, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(12.dp))
        Text(
            title,
            color = textTint,
            fontFamily = ZelefinFont,
            fontSize = 17.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
fun AccountAvatar(
    session: SavedSession?,
    onClick: () -> Unit,
    diameter: androidx.compose.ui.unit.Dp = 45.dp,
    modifier: Modifier = Modifier,
    /** Page headers float the avatar on the dock's liquid glass, drawn above the page. */
    floating: Boolean = false,
) {
    val inset = maxOf(3.dp, diameter * 0.08f)
    val photo = diameter - inset * 2
    if (floating && LocalZelefinGlassHost.current != null) {
        Box(
            modifier
                .size(diameter)
                .zelefinGlassFaceDisc(
                    key = "account-avatar",
                    description = "Account",
                    onClick = onClick,
                    face = { AvatarPhoto(session, photo) },
                ),
        )
        return
    }
    Box(
        modifier
            .size(diameter)
            .zelefinGlassChrome(CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        AvatarPhoto(session, photo)
    }
}

@Composable
private fun AvatarPhoto(session: SavedSession?, photo: androidx.compose.ui.unit.Dp) {
    val initial = session?.userName?.trim()?.firstOrNull()?.uppercaseChar()?.toString() ?: "Z"
    Box(
        Modifier
            .size(photo)
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.12f)),
        contentAlignment = Alignment.Center,
    ) {
        Text(initial, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 16.sp, textAlign = TextAlign.Center)
        val url = session?.let(::avatarImageUrl)
        if (url != null) {
            CachedArtwork(
                url = url,
                contentDescription = session.userName,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(photo).clip(CircleShape),
            )
        }
    }
}

fun avatarImageUrl(session: SavedSession): String? =
    session.siloLink?.profileAvatarUrl?.let(SiloAvatarUrl::displayable) ?: userAvatarUrl(session, session.userId, session.userImageTag)

fun userAvatarUrl(session: SavedSession, userId: String, tag: String?): String? {
    val stamped = tag?.takeIf { it.isNotBlank() }?.let { "&tag=$it" }.orEmpty()
    return ServerUrl.resolve(
        session.serverUrl,
        "/Users/$userId/Images/Primary?quality=90&maxHeight=180$stamped",
        session.accessToken,
    )
}
