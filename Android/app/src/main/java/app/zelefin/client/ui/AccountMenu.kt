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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.LiveTv
import androidx.compose.material.icons.outlined.PersonAdd
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.runtime.collectAsState
import androidx.lifecycle.viewmodel.compose.viewModel
import app.zelefin.client.ZelefinModel
import app.zelefin.client.ZelefinPlus
import app.zelefin.core.SavedSession
import app.zelefin.core.ServerUrl

const val AddAccountTopicId = "add-account"

private val MenuWidth = 250.dp
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
    var plusNote by remember { mutableStateOf(false) }
    val anchor = remember { mutableStateOf(Rect.Zero) }
    val haze = LocalZelefinHaze.current
    val showSessions = session?.usesSilo != true
    val addLabel = if (session?.usesSilo == true) "Add Account" else "Add User"
    val others = appState.accounts.filter { it.accountId != session?.accountId }

    PresentZelefinOverlay(visible = haze != null && (open || plusNote)) {
        val hazeState = haze ?: return@PresentZelefinOverlay
        if (open) {
            DockGlassMenu(
                hazeState = hazeState,
                anchor = anchor.value,
                showSessions = showSessions,
                addLabel = addLabel,
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
                onSwitch = { account ->
                    open = false
                    model.switchAccount(account)
                },
                onAdd = {
                    open = false
                    if (ZelefinPlus.allows(ZelefinPlus.Feature.ExtraAccounts)) {
                        model.resetAddAccount()
                        model.openSettingsTopic(AddAccountTopicId)
                    } else {
                        plusNote = true
                    }
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
        } else {
            val (title, message) = ZelefinPlus.notice(ZelefinPlus.Feature.ExtraAccounts)
            ZelefinGlassAlert(
                hazeState = hazeState,
                title = title,
                message = message,
                onDismiss = { plusNote = false },
            )
        }
    }

    AccountAvatar(
        session,
        onClick = { open = !open },
        modifier = Modifier.onGloballyPositioned { anchor.value = it.boundsInRoot() },
    )
}

@Composable
private fun DockGlassMenu(
    hazeState: ZelefinHazeState,
    anchor: Rect,
    showSessions: Boolean,
    addLabel: String,
    others: List<SavedSession>,
    onDismiss: () -> Unit,
    onProfile: () -> Unit,
    onSessions: () -> Unit,
    onSwitch: (SavedSession) -> Unit,
    onAdd: () -> Unit,
    onSettings: () -> Unit,
    onSignOut: () -> Unit,
) {
    Box(Modifier.fillMaxSize()) {
        Box(
            Modifier
                .fillMaxSize()
                .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }, onClick = onDismiss),
        )
        Column(
            Modifier
                .offset {
                    val width = MenuWidth.roundToPx()
                    val gap = 8.dp.roundToPx()
                    IntOffset(
                        x = (anchor.right - width).toInt().coerceAtLeast(16.dp.roundToPx()),
                        y = (anchor.bottom + gap).toInt(),
                    )
                }
                .width(MenuWidth)
                .zelefinGlassChrome(hazeState, ZelefinOverlayShape)
                .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) {}
                .padding(vertical = 6.dp),
        ) {
            GlassMenuRow("Profile", Icons.Outlined.AccountCircle, onProfile)
            if (showSessions) GlassMenuRow("Sessions", Icons.Outlined.LiveTv, onSessions)
            if (others.isNotEmpty()) {
                GlassMenuDivider()
                others.forEach { account -> GlassAccountRow(account) { onSwitch(account) } }
                GlassMenuDivider()
            }
            GlassMenuRow(addLabel, Icons.Outlined.PersonAdd, onAdd)
            GlassMenuRow("Settings", Icons.Outlined.Settings, onSettings)
            GlassMenuDivider()
            GlassMenuRow("Sign Out", Icons.AutoMirrored.Outlined.Logout, onSignOut, destructive = true)
        }
    }
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
    Row(
        Modifier
            .fillMaxWidth()
            .height(52.dp)
            .padding(horizontal = 6.dp)
            .clip(RoundedCornerShape(26.dp))
            .background(if (pressed) DockSelectedFill else Color.Transparent)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(account.userName, color = DockInactive, fontFamily = ZelefinFont, fontSize = 17.sp, maxLines = 1)
            Text(account.displayServer, color = DockInactive.copy(alpha = 0.6f), fontFamily = ZelefinFont, fontSize = 12.sp, maxLines = 1)
        }
        Spacer(Modifier.width(10.dp))
        AccountAvatarImage(account, 28.dp)
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

/** Two-button glass confirm (Cancel + action), the dock-glass stand-in for a confirmation dialog. */
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
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Box(
            Modifier
                .fillMaxSize()
                .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }, onClick = onDismiss),
        )
        Column(
            Modifier
                .width(270.dp)
                .zelefinGlassChrome(hazeState, ZelefinOverlayShape)
                .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) {}
                .padding(top = 18.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(title, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 16.dp))
            Spacer(Modifier.height(4.dp))
            Text(message, color = DockInactive, fontFamily = ZelefinFont, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 16.dp))
            Spacer(Modifier.height(14.dp))
            Box(Modifier.fillMaxWidth().height(0.5.dp).background(DockBorder))
            Row(Modifier.fillMaxWidth().height(44.dp)) {
                Box(Modifier.weight(1f).fillMaxSize().clickable(onClick = onDismiss), contentAlignment = Alignment.Center) {
                    Text("Cancel", color = ZelefinCyan, fontFamily = ZelefinFont, fontSize = 17.sp)
                }
                Box(Modifier.width(0.5.dp).fillMaxSize().background(DockBorder))
                Box(Modifier.weight(1f).fillMaxSize().clickable(onClick = onConfirm), contentAlignment = Alignment.Center) {
                    Text(
                        confirmLabel,
                        color = if (destructive) Destructive else ZelefinCyan,
                        fontFamily = ZelefinFont,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 17.sp,
                    )
                }
            }
        }
    }
}

@Composable
fun ZelefinGlassAlert(
    hazeState: ZelefinHazeState,
    title: String,
    message: String,
    onDismiss: () -> Unit,
) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Box(
            Modifier
                .fillMaxSize()
                .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }, onClick = onDismiss),
        )
        Column(
            Modifier
                .width(270.dp)
                .zelefinGlassChrome(hazeState, ZelefinOverlayShape)
                .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) {}
                .padding(horizontal = 16.dp, vertical = 18.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(title, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, textAlign = TextAlign.Center)
            Spacer(Modifier.height(4.dp))
            Text(message, color = DockInactive, fontFamily = ZelefinFont, fontSize = 13.sp, textAlign = TextAlign.Center)
            Spacer(Modifier.height(14.dp))
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(0.5.dp)
                    .background(DockBorder),
            )
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(44.dp)
                    .clickable(onClick = onDismiss),
                contentAlignment = Alignment.Center,
            ) {
                Text("OK", color = ZelefinCyan, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            }
        }
    }
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
    val tint = if (destructive) Destructive else DockInactive
    Row(
        Modifier
            .fillMaxWidth()
            .height(44.dp)
            .padding(horizontal = 6.dp)
            .clip(RoundedCornerShape(22.dp))
            .background(if (pressed) DockSelectedFill else Color.Transparent)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, color = tint, fontFamily = ZelefinFont, fontSize = 17.sp, modifier = Modifier.weight(1f))
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(20.dp))
    }
}

@Composable
fun AccountAvatar(
    session: SavedSession?,
    onClick: () -> Unit,
    diameter: androidx.compose.ui.unit.Dp = 45.dp,
    modifier: Modifier = Modifier,
) {
    val inset = maxOf(3.dp, diameter * 0.08f)
    val photo = diameter - inset * 2
    val initial = session?.userName?.trim()?.firstOrNull()?.uppercaseChar()?.toString() ?: "Z"
    val haze = LocalZelefinHaze.current
    Box(
        modifier
            .size(diameter)
            .then(
                if (haze != null) {
                    Modifier.zelefinGlassChrome(haze, CircleShape)
                } else {
                    Modifier
                        .clip(CircleShape)
                        .background(DockFill)
                        .border(0.5.dp, DockBorder, CircleShape)
                },
            )
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
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
}

fun avatarImageUrl(session: SavedSession): String? {
    if (session.usesSilo) return null
    val tag = session.userImageTag?.takeIf { it.isNotBlank() }?.let { "&tag=$it" }.orEmpty()
    return ServerUrl.resolve(
        session.serverUrl,
        "/Users/${session.userId}/Images/Primary?quality=90&maxHeight=180$tag",
        session.accessToken,
    )
}
