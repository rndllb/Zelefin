package app.zelefin.client.ui

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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.UnfoldMore
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt

/**
 * Settings building blocks that mirror iOS `LoginChrome` (`SettingsFieldLabel`,
 * `SettingsCardDivider`, `SettingsPrimaryButton`, `SettingsSecondaryButton`) and the
 * menu-style `Picker` iOS settings use inside cards.
 */

private val FieldCaption = Color.White.copy(alpha = 0.55f)

@Composable
fun SettingsFieldLabel(title: String, modifier: Modifier = Modifier) {
    Text(
        title.uppercase(),
        color = FieldCaption,
        fontFamily = ZelefinFont,
        fontWeight = FontWeight.SemiBold,
        fontSize = 12.sp,
        letterSpacing = 0.6.sp,
        modifier = modifier,
    )
}

@Composable
fun SettingsCardDivider() {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 12.dp)
            .height(1.dp)
            .background(ZelefinCardStroke),
    )
}

@Composable
fun SettingsInfoRow(label: String, value: String) {
    Column(Modifier.fillMaxWidth()) {
        SettingsFieldLabel(label)
        Spacer(Modifier.height(8.dp))
        Text(value, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
    }
}

@Composable
fun SettingsToggleRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(
            title,
            color = Color.White,
            fontFamily = ZelefinFont,
            fontWeight = FontWeight.SemiBold,
            fontSize = 17.sp,
            modifier = Modifier.weight(1f).padding(end = 12.dp),
        )
        Switch(
            checked = checked,
            onCheckedChange = onChange,
            colors = SwitchDefaults.colors(checkedTrackColor = ZelefinCyan, checkedThumbColor = Color.White),
        )
    }
}

@Composable
fun SettingsPrimaryButton(title: String, busy: Boolean = false, enabled: Boolean = true, onClick: () -> Unit) {
    val shape = RoundedCornerShape(18.dp)
    Box(
        Modifier
            .fillMaxWidth()
            .alpha(if (enabled) 1f else 0.42f)
            .clip(shape)
            .background(ZelefinCyan)
            .clickable(enabled = enabled && !busy, onClick = onClick)
            .padding(vertical = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        if (busy) {
            CircularProgressIndicator(color = Color.Black, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
        } else {
            Text(title.uppercase(), color = Color.Black, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 12.sp, letterSpacing = 0.8.sp)
        }
    }
}

@Composable
fun SettingsSecondaryButton(title: String, enabled: Boolean = true, onClick: () -> Unit) {
    val shape = RoundedCornerShape(18.dp)
    Box(
        Modifier
            .fillMaxWidth()
            .alpha(if (enabled) 1f else 0.42f)
            .clip(shape)
            .border(1.5.dp, FieldCaption, shape)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(vertical = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(title.uppercase(), color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 12.sp, letterSpacing = 0.8.sp)
    }
}

/** One option in a [SettingsMenuPicker]. */
data class SettingsChoice<T>(val value: T, val title: String)

/**
 * iOS `.pickerStyle(.menu)` inside a settings card: uppercase caption, then the current value
 * in the accent color with an up/down chevron. Tapping opens a glass menu with a check on the
 * selected option.
 */
@Composable
fun <T> SettingsMenuPicker(
    label: String,
    choices: List<SettingsChoice<T>>,
    selected: T,
    onSelect: (T) -> Unit,
) {
    var anchor by remember { mutableStateOf(Rect.Zero) }
    var open by remember { mutableStateOf(false) }
    val current = choices.firstOrNull { it.value == selected }?.title ?: choices.firstOrNull()?.title.orEmpty()
    Column(Modifier.fillMaxWidth()) {
        SettingsFieldLabel(label)
        Spacer(Modifier.height(8.dp))
        Row(
            Modifier
                .onGloballyPositioned { anchor = it.boundsInWindow() }
                .clip(RoundedCornerShape(8.dp))
                .clickable { open = true }
                .padding(vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(current, color = ZelefinCyan, fontFamily = ZelefinFont, fontSize = 17.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Icon(Icons.Rounded.UnfoldMore, contentDescription = null, tint = ZelefinCyan, modifier = Modifier.size(16.dp))
        }
    }
    val haze = LocalZelefinHaze.current
    PresentZelefinOverlay(visible = open && haze != null) {
        val hazeState = haze ?: return@PresentZelefinOverlay
        SettingsMenuPanel(
            hazeState = hazeState,
            anchor = anchor,
            choices = choices,
            selected = selected,
            onDismiss = { open = false },
            onSelect = {
                open = false
                onSelect(it)
            },
        )
    }
}

@Composable
private fun <T> SettingsMenuPanel(
    hazeState: ZelefinHazeState,
    anchor: Rect,
    choices: List<SettingsChoice<T>>,
    selected: T,
    onDismiss: () -> Unit,
    onSelect: (T) -> Unit,
) {
    val density = LocalDensity.current
    val configuration = LocalConfiguration.current
    val screenHeight = with(density) { configuration.screenHeightDp.dp.toPx() }
    val rowHeight = with(density) { 44.dp.toPx() }
    val maxHeight = (screenHeight * 0.6f)
    val natural = (choices.size * rowHeight + with(density) { 12.dp.toPx() }).coerceAtMost(maxHeight)
    val gap = with(density) { 6.dp.toPx() }
    val margin = with(density) { 16.dp.toPx() }
    val y = if (anchor.bottom + gap + natural > screenHeight - margin) {
        (anchor.top - gap - natural).coerceAtLeast(margin)
    } else {
        anchor.bottom + gap
    }
    Box(Modifier.fillMaxSize()) {
        Box(
            Modifier
                .fillMaxSize()
                .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }, onClick = onDismiss),
        )
        Column(
            Modifier
                .offset { IntOffset(anchor.left.roundToInt().coerceAtLeast(margin.roundToInt()), y.roundToInt()) }
                .widthIn(min = 220.dp, max = 300.dp)
                .heightIn(max = with(density) { maxHeight.toDp() })
                .zelefinGlassChrome(hazeState, RoundedCornerShape(22.dp))
                .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) {}
                .verticalScroll(rememberScrollState())
                .padding(vertical = 6.dp),
        ) {
            choices.forEach { choice ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .height(44.dp)
                        .clickable { onSelect(choice.value) }
                        .padding(horizontal = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.width(26.dp)) {
                        if (choice.value == selected) {
                            Icon(Icons.Rounded.Check, contentDescription = "Selected", tint = Color.White, modifier = Modifier.size(18.dp))
                        }
                    }
                    Text(choice.title, color = Color.White, fontFamily = ZelefinFont, fontSize = 17.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}
