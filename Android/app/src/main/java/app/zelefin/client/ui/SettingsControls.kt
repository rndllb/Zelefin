package app.zelefin.client.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.UnfoldMore
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** One option in a [SettingsMenuPicker]. */
data class SettingsChoice<T>(val value: T, val title: String)

/** Rows in an iOS 26 inset grouped list are at least this tall. */
internal val SettingsRowHeight = 52.dp

/** Small uppercase caption, iOS `SettingsFieldLabel` in `LoginChrome`. */
@Composable
fun SettingsFieldLabel(title: String, modifier: Modifier = Modifier) {
    Text(
        title.uppercase(),
        color = IOSColors.secondaryLabel,
        fontFamily = ZelefinFont,
        fontWeight = FontWeight.SemiBold,
        fontSize = 12.sp,
        letterSpacing = 0.6.sp,
        modifier = modifier,
    )
}

/** Hairline between rows. It runs from the row text to the card's trailing edge, like UIKit. */
@Composable
fun SettingsCardDivider() {
    Box(
        Modifier
            .layout { measurable, constraints ->
                val extra = SettingsContentInset.roundToPx()
                val width = constraints.maxWidth + extra
                val placeable = measurable.measure(constraints.copy(minWidth = width, maxWidth = width))
                layout(constraints.maxWidth, placeable.height) { placeable.placeRelative(0, 0) }
            }
            .height(0.5.dp)
            .background(IOSColors.separator),
    )
}

/** `LabeledContent`: title on the leading side, the value in secondary text on the trailing side. */
@Composable
fun SettingsInfoRow(label: String, value: String) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = SettingsRowHeight).padding(vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = SettingsRowText)
        Spacer(Modifier.width(16.dp))
        Text(
            value,
            style = SettingsRowText.copy(color = IOSColors.secondaryLabel, textAlign = TextAlign.End),
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
fun SettingsToggleRow(
    title: String,
    checked: Boolean,
    onChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    summary: String? = null,
) {
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = SettingsRowHeight)
            .toggleable(value = checked, role = Role.Switch, onValueChange = onChange)
            .padding(vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f).padding(end = 12.dp)) {
            Text(title, style = SettingsRowText)
            if (!summary.isNullOrBlank()) {
                Text(summary, color = IOSColors.secondaryLabel, fontFamily = ZelefinFont, fontSize = 13.sp)
            }
        }
        IOSSwitch(checked)
    }
}

/** A `Button` row in a `Form`: accent text on the leading side, a spinner while busy. */
@Composable
fun SettingsActionRow(
    title: String,
    busy: Boolean = false,
    enabled: Boolean = true,
    destructive: Boolean = false,
    onClick: () -> Unit,
) {
    val color = when {
        !enabled -> IOSColors.tertiaryLabel
        destructive -> IOSColors.red
        else -> ZelefinCyan
    }
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = SettingsRowHeight)
            .clickable(enabled = enabled && !busy, role = Role.Button, onClick = onClick)
            .padding(vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = SettingsRowText.copy(color = color), modifier = Modifier.weight(1f))
        if (busy) IOSSpinner()
    }
}

@Composable
fun SettingsPrimaryButton(title: String, busy: Boolean = false, enabled: Boolean = true, onClick: () -> Unit) {
    SettingsActionRow(title, busy = busy, enabled = enabled, onClick = onClick)
}

@Composable
fun SettingsSecondaryButton(title: String, enabled: Boolean = true, onClick: () -> Unit) {
    SettingsActionRow(title, enabled = enabled, onClick = onClick)
}

@Composable
fun <T> SettingsInlinePicker(
    label: String,
    choices: List<SettingsChoice<T>>,
    selected: T,
    onSelect: (T) -> Unit,
) {
    SettingsMenuPicker(label, choices, selected, onSelect)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsSliderRow(
    label: String,
    value: Float,
    valueText: String,
    range: ClosedFloatingPointRange<Float>,
    onChange: (Float) -> Unit,
    steps: Int = 0,
) {
    Column(Modifier.fillMaxWidth().padding(top = if (label.isBlank()) 4.dp else 12.dp, bottom = 6.dp)) {
        if (label.isNotBlank() || valueText.isNotBlank()) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(label, style = SettingsRowText, modifier = Modifier.weight(1f).padding(end = 12.dp))
                Text(valueText, style = SettingsRowText.copy(color = IOSColors.secondaryLabel))
            }
        }
        val shown = value.coerceIn(range.start, range.endInclusive)
        Slider(
            value = shown,
            onValueChange = onChange,
            valueRange = range,
            steps = steps,
            thumb = { IOSSliderThumb() },
            track = { state ->
                val span = state.valueRange.endInclusive - state.valueRange.start
                IOSSliderTrack(if (span == 0f) 0f else (state.value - state.valueRange.start) / span)
            },
        )
    }
}

/**
 * iOS `.pickerStyle(.menu)` in a `Form`: the title on the leading side, the current value and an
 * up/down chevron in secondary text on the trailing side. Tapping opens a glass menu with a check
 * on the selected option.
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
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = SettingsRowHeight)
            .clickable(role = Role.DropdownList) { open = true }
            .padding(vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = SettingsRowText, modifier = Modifier.weight(1f))
        Row(
            Modifier.onGloballyPositioned { anchor = it.boundsInRoot() },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(current, style = SettingsRowText.copy(color = IOSColors.secondaryLabel), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Icon(Icons.Rounded.UnfoldMore, contentDescription = null, tint = IOSColors.secondaryLabel, modifier = Modifier.size(16.dp))
        }
    }
    PresentZelefinOverlay(visible = open) {
        SettingsMenuPanel(
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
    anchor: Rect,
    choices: List<SettingsChoice<T>>,
    selected: T,
    onDismiss: () -> Unit,
    onSelect: (T) -> Unit,
) {
    val screenHeight = LocalConfiguration.current.screenHeightDp.dp
    AnchoredMenuFrame(anchor, alignTrailing = true, onDismiss = onDismiss) {
        val run = LocalMenuAction.current
        Column(
            Modifier
                .zelefinGlassChrome(ZelefinMenuShape)
                .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) {}
                .heightIn(max = screenHeight * 0.6f)
                .verticalScroll(rememberScrollState())
                .zelefinMenuWidth()
                .padding(vertical = 4.dp),
        ) {
            choices.forEach { choice ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .height(44.dp)
                        .selectable(selected = choice.value == selected, role = Role.RadioButton) { run { onSelect(choice.value) } }
                        .padding(horizontal = 20.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.width(22.dp)) {
                        if (choice.value == selected) {
                            Icon(Icons.Rounded.Check, contentDescription = "Selected", tint = Color.White, modifier = Modifier.size(16.dp))
                        }
                    }
                    Text(choice.title, style = SettingsRowText, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

@Composable
fun SettingsAlertDialog(
    title: String,
    message: String,
    confirmLabel: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
    cancelLabel: String = "Cancel",
    destructive: Boolean = false,
    enabled: Boolean = true,
) {
    IOSAlert(
        title = title,
        message = message,
        confirmLabel = confirmLabel,
        onConfirm = onConfirm,
        onDismiss = onDismiss,
        cancelLabel = cancelLabel,
        destructive = destructive,
        enabled = enabled,
    )
}

/**
 * A `TextField` row in a `Form`. With a [placeholder] the [label] sits on the leading side and the
 * entry on the trailing side, like `LabeledContent`; otherwise the label is the placeholder.
 */
@Composable
fun SettingsTextField(
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
    val title = label.lowercase().split(" ").joinToString(" ") { word -> word.replaceFirstChar { it.titlecase() } }
    val labeled = placeholder.isNotEmpty() && !placeholder.equals(title, ignoreCase = true)
    Row(
        Modifier.fillMaxWidth().heightIn(min = SettingsRowHeight).padding(vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (labeled) {
            Text(title, style = SettingsRowText)
            Spacer(Modifier.width(16.dp))
        }
        IOSTextField(
            value = value,
            onChange = onChange,
            placeholder = if (labeled) placeholder else title,
            textAlign = if (labeled) TextAlign.End else TextAlign.Start,
            visualTransformation = if (password) PasswordVisualTransformation() else VisualTransformation.None,
            keyboardOptions = KeyboardOptions(keyboardType = keyboard, imeAction = ime),
            keyboardActions = KeyboardActions(onDone = { onIme() }, onGo = { onIme() }, onNext = { onIme() }),
            modifier = Modifier
                .weight(1f)
                .then(if (focusRequester != null) Modifier.focusRequester(focusRequester) else Modifier),
        )
        if (forgot != null) {
            Spacer(Modifier.width(12.dp))
            Text(
                "Forgot",
                style = SettingsRowText.copy(color = ZelefinCyan),
                modifier = Modifier.clickable(role = Role.Button, onClick = forgot),
            )
        }
    }
}
