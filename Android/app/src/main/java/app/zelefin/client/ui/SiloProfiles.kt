package app.zelefin.client.ui

import app.zelefin.client.R
import androidx.compose.ui.res.stringResource
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import app.zelefin.client.silo.SiloNotice
import app.zelefin.client.silo.SiloPinPrompt
import app.zelefin.client.silo.SiloProfilePicker
import app.zelefin.core.SiloProfile

private val PickerCaption = Color.White.copy(alpha = 0.55f)
private val PickerFailure = Color(1f, 0.38f, 0.38f)
private val PickerWarning = Color(1f, 0.8f, 0.45f)
private val ProfileSwatches = floatArrayOf(0.22f, 0.30f, 0.38f, 0.46f, 0.28f, 0.34f)

/** Kids, Primary, and PIN, in the order the picker badges show them. */
@Composable
fun siloProfileCaption(profile: SiloProfile): String = listOfNotNull(
    stringResource(R.string.connect_kids).takeIf { profile.isChild },
    stringResource(R.string.ui_primary).takeIf { profile.isPrimary },
    stringResource(R.string.connect_pin).takeIf { profile.hasPin },
).joinToString(" · ").ifEmpty { stringResource(R.string.account_profile) }

/** Up to two letters, matching iOS `HouseholdProfileAvatar`. */
private fun profileInitials(name: String): String {
    val letters = name.trim().split(Regex("\\s+"))
        .filter { it.isNotEmpty() }
        .take(2)
        .mapNotNull { part -> part.firstOrNull()?.uppercaseChar()?.toString() }
    return letters.joinToString("").ifEmpty { "•" }
}

private fun profileSwatch(id: String): Color {
    val gray = ProfileSwatches[id.hashCode().mod(ProfileSwatches.size)]
    return Color(gray, gray, gray)
}

@Composable
fun SiloProfileAvatar(profile: SiloProfile, diameter: Dp) {
    Box(
        Modifier
            .size(diameter)
            .clip(CircleShape)
            .background(profileSwatch(profile.id)),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            profileInitials(profile.name),
            color = Color.White.copy(alpha = 0.92f),
            fontFamily = ZelefinFont,
            fontWeight = FontWeight.SemiBold,
            fontSize = (diameter.value * 0.36f).sp,
        )
        profile.avatarUrl?.let { url ->
            CachedArtwork(url = url, contentDescription = profile.name, contentScale = ContentScale.Crop, modifier = Modifier.size(diameter).clip(CircleShape))
        }
    }
}

/** Full-screen "Who's watching?" after a Silo sign-in. */
@Composable
fun SiloProfilePickerScreen(picker: SiloProfilePicker, onChoose: (SiloProfile) -> Unit, onCancel: () -> Unit) {
    BackHandler(onBack = onCancel)
    Box(
        Modifier
            .fillMaxSize()
            .background(LoginPalette.Canvas)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {}
            .drawBehind {
                drawRect(
                    brush = Brush.radialGradient(
                        colors = listOf(LoginPalette.Lavender.copy(alpha = 0.26f), LoginPalette.Sky.copy(alpha = 0.12f), LoginPalette.Canvas),
                        center = Offset(size.width / 2f, 0f),
                        radius = maxOf(size.width * 0.8f, 260.dp.toPx()),
                    ),
                )
            }
            .systemBarsPadding(),
        contentAlignment = Alignment.TopCenter,
    ) {
        Column(
            Modifier.widthIn(max = 640.dp).fillMaxSize().padding(horizontal = 24.dp, vertical = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(24.dp))
            Text(stringResource(R.string.connect_who_is_watching), color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 30.sp)
            picker.warning?.let { warning ->
                Spacer(Modifier.height(16.dp))
                Text(
                    warning,
                    color = PickerWarning,
                    fontFamily = ZelefinFont,
                    fontSize = 13.sp,
                    textAlign = TextAlign.Center,
                )
            }
            if (picker.profiles.isEmpty()) {
                Text(
                    stringResource(R.string.connect_no_profiles),
                    color = PickerCaption,
                    fontFamily = ZelefinFont,
                    fontSize = 15.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.weight(1f).padding(top = 28.dp).fillMaxWidth(),
                )
            } else {
                Spacer(Modifier.height(32.dp))
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(128.dp),
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                    verticalArrangement = Arrangement.spacedBy(24.dp),
                    modifier = Modifier.weight(1f).fillMaxWidth(),
                ) {
                    items(picker.profiles, key = { it.id }) { profile ->
                        ProfileTile(
                            profile = profile,
                            busy = picker.busyProfileId == profile.id,
                            enabled = picker.busyProfileId == null,
                            onClick = { onChoose(profile) },
                        )
                    }
                }
            }
            picker.message?.let { message ->
                Text(
                    message,
                    color = PickerFailure,
                    fontFamily = ZelefinFont,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 13.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(bottom = 14.dp),
                )
            }
            Box(
                Modifier
                    .fillMaxWidth()
                    .widthIn(max = 440.dp)
                    .clip(RoundedCornerShape(18.dp))
                    .border(1.5.dp, Color.White.copy(alpha = 0.55f), RoundedCornerShape(18.dp))
                    .clickable(onClick = onCancel)
                    .padding(vertical = 16.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    "Use a different account",
                    color = PickerCaption,
                    fontFamily = ZelefinFont,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 15.sp,
                )
            }
        }
    }
}

@Composable
private fun ProfileTile(profile: SiloProfile, busy: Boolean, enabled: Boolean, onClick: () -> Unit) {
    Column(
        Modifier
            .alpha(if (enabled || busy) 1f else 0.5f)
            .clip(RoundedCornerShape(16.dp))
            .clickable(enabled = enabled, onClick = onClick)
            .padding(vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(contentAlignment = Alignment.Center) {
            SiloProfileAvatar(profile, 104.dp)
            if (busy) {
                Box(Modifier.size(104.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.5f)), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(28.dp))
                }
            }
            if (profile.hasPin) {
                Box(
                    Modifier
                        .align(Alignment.BottomEnd)
                        .size(30.dp)
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.72f))
                        .border(1.dp, Color.White.copy(alpha = 0.2f), CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Outlined.Lock, contentDescription = "PIN", tint = Color.White, modifier = Modifier.size(15.dp))
                }
            }
        }
        Spacer(Modifier.height(10.dp))
        Text(
            profile.name,
            color = Color.White,
            fontFamily = ZelefinFont,
            fontWeight = FontWeight.SemiBold,
            fontSize = 16.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (profile.isChild) {
            Text(stringResource(R.string.connect_kids), color = IOSColors.secondaryLabel, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 11.sp)
        }
    }
}

/** A profile tile for Profile → Who’s watching. Current and in-progress tiles get a white ring. */
@Composable
internal fun HouseholdProfileTile(
    profile: SiloProfile,
    isCurrent: Boolean,
    isSelected: Boolean,
    enabled: Boolean,
    dimmed: Boolean = false,
    onClick: () -> Unit,
    size: Dp = 76.dp,
) {
    Column(
        Modifier
            .alpha(if (dimmed) 0.5f else 1f)
            .width(size + 8.dp)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(contentAlignment = Alignment.Center) {
            SiloProfileAvatar(profile, size)
            if (isCurrent || isSelected) {
                Box(Modifier.size(size).border(3.dp, Color.White, CircleShape))
            }
            if (profile.hasPin) {
                Box(
                    Modifier
                        .align(Alignment.BottomEnd)
                        .size(24.dp)
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.72f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Filled.Lock, contentDescription = null, tint = Color.White, modifier = Modifier.size(12.dp))
                }
            }
        }
        Spacer(Modifier.height(10.dp))
        Text(
            profile.name,
            color = Color.White,
            fontFamily = ZelefinFont,
            fontWeight = FontWeight.SemiBold,
            fontSize = 15.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
        if (profile.isChild) {
            Text(stringResource(R.string.connect_kids), color = IOSColors.secondaryLabel, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 11.sp)
        }
    }
}

/** Asks for a household profile's PIN, for the picker and for profile switching. */
@Composable
fun SiloPinDialog(prompt: SiloPinPrompt, switching: Boolean = false, onSubmit: (String) -> Unit, onCancel: () -> Unit) {
    var pin by rememberSaveable(prompt.profile.id) { mutableStateOf("") }
    val focus = remember { FocusRequester() }
    LaunchedEffect(prompt.profile.id) { runCatching { focus.requestFocus() } }
    LaunchedEffect(prompt.message) { if (prompt.message != null) pin = "" }
    val canSubmit = pin.isNotBlank() && !prompt.busy
    Dialog(onDismissRequest = onCancel) {
        Column(
            Modifier
                .widthIn(max = 320.dp)
                .fillMaxWidth()
                .clip(RoundedCornerShape(34.dp))
                .background(IOSColors.alert)
                .padding(start = 22.dp, end = 22.dp, top = 24.dp, bottom = 18.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (!switching) {
                SiloProfileAvatar(prompt.profile, 64.dp)
                Spacer(Modifier.height(12.dp))
            }
            Text(
                "PIN for ${prompt.profile.name}",
                color = Color.White,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.SemiBold,
                fontSize = 17.sp,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                prompt.message ?: if (switching) "This profile is locked." else "Enter this profile’s PIN.",
                color = if (prompt.message != null && switching) IOSColors.red else Color.White.copy(alpha = 0.72f),
                fontFamily = ZelefinFont,
                fontSize = 15.sp,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(16.dp))
            BasicTextField(
                value = pin,
                onValueChange = { next -> pin = next.filter(Char::isDigit) },
                singleLine = true,
                enabled = !prompt.busy,
                textStyle = TextStyle(
                    color = Color.White,
                    fontFamily = ZelefinFont,
                    fontWeight = FontWeight.Bold,
                    fontSize = 26.sp,
                    letterSpacing = 8.sp,
                    textAlign = TextAlign.Center,
                ),
                cursorBrush = SolidColor(LoginPalette.Periwinkle),
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { if (canSubmit) onSubmit(pin) }),
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(Color.White.copy(alpha = 0.08f))
                    .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(14.dp))
                    .padding(vertical = 12.dp)
                    .focusRequester(focus),
            )
            if (!switching) {
                prompt.message?.let { message ->
                    Spacer(Modifier.height(10.dp))
                    Text(message, color = IOSColors.red, fontFamily = ZelefinFont, fontSize = 13.sp, textAlign = TextAlign.Center)
                }
            }
            Spacer(Modifier.height(20.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                IOSCapsuleButton("Cancel", onCancel, Modifier.weight(1f))
                if (prompt.busy) {
                    Box(Modifier.weight(1f).height(48.dp), contentAlignment = Alignment.Center) { IOSSpinner(color = Color.White) }
                } else {
                    IOSCapsuleButton(if (switching) "Switch" else "Continue", { onSubmit(pin) }, Modifier.weight(1f), prominent = true, enabled = canSubmit)
                }
            }
        }
    }
}

@Composable
fun SiloNoticeDialog(notice: SiloNotice, onDismiss: () -> Unit, onSignInAgain: () -> Unit) {
    if (notice.signInAgain) {
        SettingsAlertDialog(
            title = notice.title,
            message = notice.message,
            confirmLabel = "Sign In Again",
            onConfirm = onSignInAgain,
            onDismiss = onDismiss,
            cancelLabel = "Not Now",
        )
    } else {
        Dialog(onDismissRequest = onDismiss) {
            Column(
                Modifier
                    .widthIn(max = 320.dp)
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(34.dp))
                    .background(IOSColors.alert)
                    .padding(start = 22.dp, end = 22.dp, top = 22.dp, bottom = 18.dp),
            ) {
                Text(notice.title, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
                Spacer(Modifier.height(6.dp))
                Text(notice.message, color = Color.White.copy(alpha = 0.82f), fontFamily = ZelefinFont, fontSize = 15.sp)
                Spacer(Modifier.height(20.dp))
                IOSCapsuleButton("OK", onDismiss, Modifier.fillMaxWidth(), prominent = true)
            }
        }
    }
}

