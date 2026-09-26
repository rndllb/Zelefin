package app.zelefin.client.ui

import android.content.Context
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.outlined.Link
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.client.R
import app.zelefin.client.ZelefinUiState
import app.zelefin.core.MediaBackend

private val Caption = Color.White.copy(alpha = 0.55f)
private val Secondary = Color.White.copy(alpha = 0.72f)
private val Divider = Color.White.copy(alpha = 0.12f)
private val Failure = Color(1f, 0.38f, 0.38f)
private val Cobalt = Color(0f, 0.22f, 0.98f)
private val CardShape = RoundedCornerShape(18.dp)

@Composable
fun ConnectScreen(
    state: ZelefinUiState,
    onBackend: (MediaBackend) -> Unit,
    onTest: (String) -> Unit,
    onSignIn: (String, String, String) -> Unit,
    onQuickConnect: (String) -> Unit,
    onCancelQuickConnect: () -> Unit,
    onGateway: (String, String) -> Unit,
) {
    val context = LocalContext.current
    val prefs = context.getSharedPreferences("zelefin.connect", Context.MODE_PRIVATE)
    var url by rememberSaveable { mutableStateOf(prefs.getString("last-server", "").orEmpty()) }
    var username by rememberSaveable { mutableStateOf(prefs.getString("last-username", "").orEmpty()) }
    var password by rememberSaveable { mutableStateOf("") }
    var advanced by rememberSaveable { mutableStateOf(state.gatewayId.isNotBlank() || state.gatewaySecret.isNotBlank()) }
    var gatewayId by rememberSaveable { mutableStateOf(state.gatewayId) }
    var gatewaySecret by rememberSaveable { mutableStateOf(state.gatewaySecret) }
    var passwordHelp by rememberSaveable { mutableStateOf(false) }
    val serverFocus = androidx.compose.runtime.remember { FocusRequester() }
    val usernameFocus = androidx.compose.runtime.remember { FocusRequester() }
    val passwordFocus = androidx.compose.runtime.remember { FocusRequester() }
    val focusManager = LocalFocusManager.current
    val wide = context.resources.configuration.smallestScreenWidthDp >= 600
    val markSize = if (wide) 196.dp else 168.dp
    val tileSize = if (wide) 96.dp else 86.dp

    LaunchedEffect(url) { prefs.edit().putString("last-server", url).apply() }
    LaunchedEffect(username) { prefs.edit().putString("last-username", username).apply() }
    LaunchedEffect(gatewayId, gatewaySecret) { onGateway(gatewayId, gatewaySecret) }

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .drawBehind {
                val radius = if (wide) {
                    kotlin.math.hypot((size.width / 2f).toDouble(), size.height.toDouble()).toFloat()
                } else {
                    maxOf(size.width * 0.72f, 220.dp.toPx())
                }
                drawRect(
                    brush = Brush.radialGradient(
                        colors = listOf(ZelefinCyan.copy(alpha = 0.28f), Cobalt.copy(alpha = 0.16f), Color.Black),
                        center = Offset(size.width / 2f, 0f),
                        radius = radius,
                    ),
                )
            },
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 26.dp, vertical = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(Modifier.widthIn(max = 440.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Spacer(Modifier.height(12.dp))
                Image(
                    painter = painterResource(R.drawable.zelefin_mark),
                    contentDescription = null,
                    modifier = Modifier.size(markSize),
                    contentScale = ContentScale.Fit,
                )
                Text(
                    "Zelefin",
                    fontFamily = ZelefinFont,
                    fontWeight = FontWeight.Bold,
                    fontSize = 34.sp,
                    color = Color.White,
                )
                Spacer(Modifier.height(22.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                    BackendTile(MediaBackend.Jellyfin, state.backend == MediaBackend.Jellyfin, tileSize) {
                        password = ""
                        onBackend(MediaBackend.Jellyfin)
                    }
                    Spacer(Modifier.width(18.dp))
                    BackendTile(MediaBackend.Silo, state.backend == MediaBackend.Silo, tileSize) {
                        password = ""
                        onBackend(MediaBackend.Silo)
                    }
                }
                Spacer(Modifier.height(22.dp))
                Column(
                    Modifier
                        .fillMaxWidth()
                        .clip(CardShape)
                        .background(Color.White.copy(alpha = 0.08f))
                        .border(1.dp, Divider, CardShape)
                        .padding(horizontal = 16.dp, vertical = 14.dp),
                ) {
                    LoginField(
                        label = "SERVER URL",
                        value = url,
                        icon = Icons.Outlined.Link,
                        placeholder = "https://media.example.com",
                        keyboard = KeyboardType.Uri,
                        ime = ImeAction.Next,
                        focusRequester = serverFocus,
                        onIme = { usernameFocus.requestFocus() },
                        onChange = { url = it },
                    )
                    LoginDivider(inset = true)
                    LoginField(
                        label = if (state.backend == MediaBackend.Silo) "USERNAME OR EMAIL" else "USERNAME",
                        value = username,
                        icon = Icons.Filled.Person,
                        placeholder = if (state.backend == MediaBackend.Silo) "username or you@example.com" else "username",
                        keyboard = if (state.backend == MediaBackend.Silo) KeyboardType.Email else KeyboardType.Text,
                        ime = ImeAction.Next,
                        focusRequester = usernameFocus,
                        onIme = { passwordFocus.requestFocus() },
                        onChange = { username = it },
                    )
                    LoginDivider(inset = true)
                    LoginField(
                        label = "PASSWORD",
                        value = password,
                        icon = Icons.Filled.Lock,
                        placeholder = "Password",
                        password = true,
                        forgot = { passwordHelp = true },
                        keyboard = KeyboardType.Password,
                        ime = ImeAction.Go,
                        focusRequester = passwordFocus,
                        onIme = {
                            focusManager.clearFocus()
                            if (url.isNotBlank() && username.isNotBlank() && !state.busy) onSignIn(url, username, password)
                        },
                        underline = true,
                        onChange = { password = it },
                    )
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp)
                            .clickable { advanced = !advanced },
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            "Advanced: access gateway",
                            color = Caption,
                            fontFamily = ZelefinFont,
                            fontWeight = FontWeight.SemiBold,
                            fontSize = 15.sp,
                            modifier = Modifier.weight(1f),
                        )
                        Icon(
                            if (advanced) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown,
                            contentDescription = null,
                            tint = Caption,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                    if (advanced) {
                        Spacer(Modifier.height(8.dp))
                        LoginField(
                            label = "CLIENT ID",
                            value = gatewayId,
                            icon = Icons.Filled.Lock,
                            placeholder = "Client ID or token ID",
                            onChange = { gatewayId = it },
                        )
                        LoginDivider(inset = true)
                        LoginField(
                            label = "CLIENT SECRET",
                            value = gatewaySecret,
                            icon = Icons.Filled.Lock,
                            placeholder = "Client secret or access token",
                            password = true,
                            onChange = { gatewaySecret = it },
                        )
                        Text(
                            "Needed when Jellyfin sits behind Cloudflare Zero Trust or Pangolin.",
                            color = Caption,
                            fontFamily = ZelefinFont,
                            fontSize = 12.sp,
                            modifier = Modifier.padding(top = 8.dp, bottom = 4.dp),
                        )
                    }
                }
                if (!state.busy) state.message?.let { message ->
                    Spacer(Modifier.height(14.dp))
                    Text(
                        message,
                        color = if (message.contains("reachable", ignoreCase = true)) Secondary else Failure,
                        fontFamily = ZelefinFont,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 13.sp,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                Spacer(Modifier.height(18.dp))
                val handshake = state.quickConnect
                if (handshake != null && state.backend == MediaBackend.Jellyfin) {
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .clip(CardShape)
                            .background(Color.White.copy(alpha = 0.08f))
                            .border(1.dp, Divider, CardShape)
                            .padding(20.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(
                            handshake.groupedCode,
                            color = ZelefinCyan,
                            fontFamily = ZelefinFont,
                            fontWeight = FontWeight.Bold,
                            fontSize = 40.sp,
                            letterSpacing = 4.sp,
                        )
                        Spacer(Modifier.height(8.dp))
                        Text(
                            "Enter this code on a device that is already signed in.",
                            color = Secondary,
                            fontFamily = ZelefinFont,
                            fontWeight = FontWeight.SemiBold,
                            fontSize = 13.sp,
                            textAlign = TextAlign.Center,
                        )
                    }
                    Spacer(Modifier.height(12.dp))
                    LoginButton("CANCEL", filled = false, enabled = true, onClick = onCancelQuickConnect)
                } else {
                    val canSignIn = !state.busy && url.isNotBlank() && username.isNotBlank()
                    LoginButton(
                        title = if (state.busy) "" else "SIGN IN",
                        filled = true,
                        enabled = canSignIn,
                        busy = state.busy,
                        onClick = { onSignIn(url, username, password) },
                    )
                    Spacer(Modifier.height(10.dp))
                    LoginButton(
                        title = "TEST CONNECTION",
                        filled = false,
                        enabled = url.isNotBlank() && !state.busy,
                        onClick = { onTest(url) },
                    )
                    if (state.backend == MediaBackend.Jellyfin) {
                        Spacer(Modifier.height(10.dp))
                        LoginButton(
                            title = "JELLYFIN QUICK CONNECT",
                            filled = false,
                            enabled = url.isNotBlank() && !state.busy,
                            onClick = { onQuickConnect(url) },
                        )
                    }
                }
                Spacer(Modifier.height(28.dp))
            }
        }
    }

    val haze = LocalZelefinHaze.current
    PresentZelefinOverlay(visible = passwordHelp && haze != null) {
        val hazeState = haze ?: return@PresentZelefinOverlay
        ZelefinGlassAlert(
            hazeState = hazeState,
            title = "Password",
            message = "Reset your password on the server, or ask the person who runs it.",
            onDismiss = { passwordHelp = false },
        )
    }
}

@Composable
private fun BackendTile(backend: MediaBackend, selected: Boolean, size: Dp, onClick: () -> Unit) {
    val silo = backend == MediaBackend.Silo
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.clickable(onClick = onClick)) {
        Box(
            Modifier
                .size(size)
                .clip(RoundedCornerShape(size * 0.24f))
                .background(Color.White.copy(alpha = if (selected) 0.16f else 0.08f))
                .border(
                    width = if (selected) 1.5.dp else 1.dp,
                    color = Color.White.copy(alpha = if (selected) 0.9f else 0.22f),
                    shape = RoundedCornerShape(size * 0.24f),
                ),
            contentAlignment = Alignment.Center,
        ) {
            Image(
                painter = painterResource(if (silo) R.drawable.silo_logo else R.drawable.jellyfin_logo),
                contentDescription = if (silo) "Silo" else "Jellyfin",
                colorFilter = ColorFilter.tint(Color.White.copy(alpha = if (silo) 1f else 0.72f)),
                modifier = Modifier
                    .fillMaxSize()
                    .padding(size * if (silo) 0.18f else 0.22f),
                contentScale = ContentScale.Fit,
            )
        }
        Spacer(Modifier.height(10.dp))
        Text(
            if (silo) "SILO" else "JELLYFIN",
            color = if (selected) Color.White else Caption,
            fontFamily = ZelefinFont,
            fontWeight = FontWeight.Bold,
            fontSize = 11.sp,
            letterSpacing = 1.sp,
        )
    }
}

@Composable
internal fun LoginField(
    label: String,
    value: String,
    icon: ImageVector,
    onChange: (String) -> Unit,
    placeholder: String = "",
    password: Boolean = false,
    forgot: (() -> Unit)? = null,
    keyboard: KeyboardType = KeyboardType.Text,
    ime: ImeAction = ImeAction.Default,
    focusRequester: FocusRequester? = null,
    onIme: () -> Unit = {},
    underline: Boolean = false,
) {
    val fieldStyle = TextStyle(
        color = Color.White,
        fontFamily = ZelefinFont,
        fontWeight = FontWeight.SemiBold,
        fontSize = 16.sp,
    )
    Column(Modifier.fillMaxWidth().padding(vertical = 12.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                label,
                color = Caption,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.SemiBold,
                fontSize = 12.sp,
                letterSpacing = 0.6.sp,
            )
            if (forgot != null) {
                Spacer(Modifier.weight(1f))
                Text(
                    "FORGOT",
                    color = ZelefinCyan,
                    fontFamily = ZelefinFont,
                    fontWeight = FontWeight.Bold,
                    fontSize = 12.sp,
                    letterSpacing = 0.8.sp,
                    modifier = Modifier.clickable(onClick = forgot),
                )
            }
        }
        Spacer(Modifier.height(10.dp))
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(22.dp), contentAlignment = Alignment.Center) {
                Icon(icon, contentDescription = null, tint = Caption, modifier = Modifier.size(15.dp))
            }
            Spacer(Modifier.width(12.dp))
            BasicTextField(
                value = value,
                onValueChange = onChange,
                singleLine = true,
                textStyle = fieldStyle,
                cursorBrush = SolidColor(ZelefinCyan),
                visualTransformation = if (password) PasswordVisualTransformation() else VisualTransformation.None,
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.None,
                    autoCorrectEnabled = false,
                    keyboardType = keyboard,
                    imeAction = ime,
                ),
                keyboardActions = KeyboardActions(onNext = { onIme() }, onGo = { onIme() }, onDone = { onIme() }),
                modifier = Modifier
                    .weight(1f)
                    .then(if (focusRequester != null) Modifier.focusRequester(focusRequester) else Modifier),
                decorationBox = { inner ->
                    Box(Modifier.fillMaxWidth().defaultMinSize(minHeight = 24.dp), contentAlignment = Alignment.CenterStart) {
                        if (value.isEmpty() && placeholder.isNotEmpty()) {
                            Text(placeholder, style = fieldStyle, color = Caption, maxLines = 1)
                        }
                        inner()
                    }
                },
            )
        }
        if (underline) {
            Spacer(Modifier.height(12.dp))
            Box(Modifier.fillMaxWidth().height(1.dp).background(Divider))
        }
    }
}

@Composable
private fun LoginDivider(inset: Boolean) {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(start = if (inset) 34.dp else 0.dp)
            .height(1.dp)
            .background(Divider),
    )
}

@Composable
private fun LoginButton(
    title: String,
    filled: Boolean,
    enabled: Boolean,
    busy: Boolean = false,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(18.dp)
    val active = enabled && !busy
    Box(
        Modifier
            .fillMaxWidth()
            .alpha(if (active) 1f else 0.42f)
            .clip(shape)
            .background(if (filled) ZelefinCyan else Color.Transparent)
            .border(if (filled) 0.dp else 1.5.dp, Color.White.copy(alpha = 0.55f), shape)
            .clickable(enabled = active, onClick = onClick)
            .padding(vertical = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        if (busy && filled) {
            CircularProgressIndicator(color = Color.Black, modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
        } else {
            Text(
                title,
                color = if (filled) Color.Black else Color.White,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.Bold,
                fontSize = 12.sp,
                letterSpacing = 0.8.sp,
            )
        }
    }
}
