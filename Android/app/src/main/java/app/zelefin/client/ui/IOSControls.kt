package app.zelefin.client.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/** iOS dark-mode system colors, so settings read like UIKit rather than Material. */
internal object IOSColors {
    val secondaryLabel = Color(0x99EBEBF5)
    val tertiaryLabel = Color(0x4DEBEBF5)
    val separator = Color(0xA6545458)
    val fill = Color(0x5C787880)
    val switchOff = Color(0x52787880)
    val alert = Color(0xFF2A2A2C)
    val red = Color(0xFFFF453A)
    val spinner = Color(0xFF98989D)
}

/** UIKit body text in a grouped list row. */
internal val SettingsRowText = TextStyle(color = Color.White, fontFamily = ZelefinFont, fontSize = 17.sp)

/** iOS 26 switch: wide track with a capsule knob. Visual only; the row owns the toggle. */
@Composable
internal fun IOSSwitch(checked: Boolean, modifier: Modifier = Modifier, enabled: Boolean = true) {
    val progress by animateFloatAsState(
        targetValue = if (checked) 1f else 0f,
        animationSpec = spring(dampingRatio = 0.78f, stiffness = 520f),
        label = "iosSwitch",
    )
    val accent = ZelefinCyan
    Canvas(modifier.size(width = 63.dp, height = 28.dp).alpha(if (enabled) 1f else 0.5f)) {
        drawRoundRect(lerp(IOSColors.switchOff, accent, progress), cornerRadius = CornerRadius(size.height / 2))
        val inset = 2.dp.toPx()
        val knob = Size(37.dp.toPx(), size.height - inset * 2)
        val x = inset + (size.width - knob.width - inset * 2) * progress
        drawRoundRect(
            Color.Black.copy(alpha = 0.14f),
            topLeft = Offset(x, inset + 1.dp.toPx()),
            size = knob,
            cornerRadius = CornerRadius(knob.height / 2),
        )
        drawRoundRect(Color.White, topLeft = Offset(x, inset), size = knob, cornerRadius = CornerRadius(knob.height / 2))
    }
}

/** `UIActivityIndicatorView`: eight spokes fading around the circle. Defaults to 20dp. */
@Composable
internal fun IOSSpinner(modifier: Modifier = Modifier, color: Color = IOSColors.spinner) {
    val transition = rememberInfiniteTransition(label = "iosSpinner")
    val step by transition.animateFloat(
        initialValue = 0f,
        targetValue = 8f,
        animationSpec = infiniteRepeatable(tween(800, easing = LinearEasing)),
        label = "spoke",
    )
    Canvas(modifier.size(20.dp)) {
        val head = step.toInt() % 8
        val outer = size.minDimension / 2
        val stroke = outer * 0.2f
        val inner = outer * 0.46f
        repeat(8) { index ->
            val age = (head - index + 8) % 8
            val angle = index * PI / 4 - PI / 2
            val dx = cos(angle).toFloat()
            val dy = sin(angle).toFloat()
            drawLine(
                color.copy(alpha = color.alpha * (1f - age * 0.11f)),
                start = Offset(center.x + dx * inner, center.y + dy * inner),
                end = Offset(center.x + dx * (outer - stroke / 2), center.y + dy * (outer - stroke / 2)),
                strokeWidth = stroke,
                cap = StrokeCap.Round,
            )
        }
    }
}

/** `ProgressView(value:)` bar; a null [fraction] slides an indeterminate segment. */
@Composable
internal fun IOSProgressBar(fraction: Float?, modifier: Modifier = Modifier) {
    if (fraction == null) {
        IndeterminateBar(modifier)
        return
    }
    val accent = ZelefinCyan
    Canvas(modifier.fillMaxWidth().height(4.dp)) {
        val radius = CornerRadius(size.height / 2)
        drawRoundRect(IOSColors.fill, cornerRadius = radius)
        drawRoundRect(accent, size = Size(size.width * fraction.coerceIn(0f, 1f), size.height), cornerRadius = radius)
    }
}

@Composable
private fun IndeterminateBar(modifier: Modifier) {
    val accent = ZelefinCyan
    val transition = rememberInfiniteTransition(label = "iosBar")
    val sweep by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1200, easing = LinearEasing)),
        label = "sweep",
    )
    Canvas(modifier.fillMaxWidth().height(4.dp)) {
        val radius = CornerRadius(size.height / 2)
        drawRoundRect(IOSColors.fill, cornerRadius = radius)
        val width = size.width * 0.3f
        clipRect {
            drawRoundRect(accent, topLeft = Offset((size.width + width) * sweep - width, 0f), size = Size(width, size.height), cornerRadius = radius)
        }
    }
}

/** The capsule knob iOS 26 sliders share with switches. */
@Composable
internal fun IOSSliderThumb() {
    Canvas(Modifier.size(width = 38.dp, height = 24.dp)) {
        val radius = CornerRadius(size.height / 2)
        drawRoundRect(Color.Black.copy(alpha = 0.18f), topLeft = Offset(0f, 1.5.dp.toPx()), cornerRadius = radius)
        drawRoundRect(Color.White, cornerRadius = radius)
    }
}

@Composable
internal fun IOSSliderTrack(fraction: Float) {
    val accent = ZelefinCyan
    Canvas(Modifier.fillMaxWidth().height(6.dp)) {
        val radius = CornerRadius(size.height / 2)
        drawRoundRect(IOSColors.fill, cornerRadius = radius)
        drawRoundRect(accent, size = Size(size.width * fraction.coerceIn(0f, 1f), size.height), cornerRadius = radius)
    }
}

/** Plain UIKit text field: no outline, gray placeholder, accent caret. */
@Composable
internal fun IOSTextField(
    value: String,
    onChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    singleLine: Boolean = true,
    textAlign: TextAlign = TextAlign.Start,
    style: TextStyle = SettingsRowText,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    keyboardActions: KeyboardActions = KeyboardActions.Default,
) {
    val textStyle = style.copy(textAlign = textAlign)
    BasicTextField(
        value = value,
        onValueChange = onChange,
        modifier = modifier,
        singleLine = singleLine,
        textStyle = textStyle,
        cursorBrush = SolidColor(ZelefinCyan),
        visualTransformation = visualTransformation,
        keyboardOptions = keyboardOptions,
        keyboardActions = keyboardActions,
        decorationBox = { field ->
            Box(contentAlignment = if (textAlign == TextAlign.End) Alignment.CenterEnd else Alignment.CenterStart) {
                if (value.isEmpty()) {
                    Text(placeholder, style = textStyle.copy(color = IOSColors.tertiaryLabel), maxLines = if (singleLine) 1 else Int.MAX_VALUE)
                }
                field()
            }
        },
    )
}

/** A capsule button like the iOS 26 alert and sheet actions. */
@Composable
internal fun IOSCapsuleButton(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    prominent: Boolean = false,
    destructive: Boolean = false,
    enabled: Boolean = true,
    height: Dp = 48.dp,
) {
    val accent = ZelefinCyan
    val fill = if (prominent && !destructive) accent else IOSColors.fill
    val text = when {
        destructive -> IOSColors.red
        prominent -> if (accent.luminance() > 0.6f) Color.Black else Color.White
        else -> Color.White
    }
    Box(
        modifier
            .heightIn(min = height)
            .alpha(if (enabled) 1f else 0.45f)
            .clip(RoundedCornerShape(50))
            .background(fill)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 18.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            title,
            color = text,
            fontFamily = ZelefinFont,
            fontWeight = if (prominent || destructive) FontWeight.SemiBold else FontWeight.Normal,
            fontSize = 17.sp,
            maxLines = 1,
        )
    }
}

/** iOS 26 alert: rounded panel, leading title and message, side-by-side capsule actions. */
@Composable
internal fun IOSAlert(
    title: String,
    message: String,
    confirmLabel: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
    cancelLabel: String,
    destructive: Boolean,
    enabled: Boolean,
) {
    Dialog(onDismissRequest = { if (enabled) onDismiss() }) {
        Column(
            Modifier
                .widthIn(max = 320.dp)
                .fillMaxWidth()
                .clip(RoundedCornerShape(34.dp))
                .background(IOSColors.alert)
                .padding(start = 22.dp, end = 22.dp, top = 22.dp, bottom = 18.dp),
        ) {
            Text(title, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            if (message.isNotBlank()) {
                Spacer(Modifier.height(6.dp))
                Text(message, color = Color.White.copy(alpha = 0.82f), fontFamily = ZelefinFont, fontSize = 15.sp)
            }
            Spacer(Modifier.height(20.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                IOSCapsuleButton(cancelLabel, onDismiss, Modifier.weight(1f), enabled = enabled)
                IOSCapsuleButton(confirmLabel, onConfirm, Modifier.weight(1f), prominent = true, destructive = destructive, enabled = enabled)
            }
        }
    }
}
