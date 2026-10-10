package app.zelefin.client.ui

import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.graphics.ColorUtils
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

/** The user's accent color (Settings → Interface). Named for the default. */
val ZelefinCyan: Color get() = AccentPreferences.color
val ZelefinBlack = Color(0xFF000000)
val ZelefinInk = Color(0xFFF5F5F7)
val ZelefinMuted = Color(0xFF8E8E93)

/** iOS `systemGroupedBackground` at the elevated (sheet) level in dark mode. */
val ZelefinSheetCanvas = Color(0xFF1C1C1E)

/** Matches iOS `LoginCardBackground`: white 8% fill, white 12% hairline, 18pt continuous corners. */
val ZelefinCardFill = Color.White.copy(alpha = 0.08f)
val ZelefinCardStroke = Color.White.copy(alpha = 0.12f)
val ZelefinCardShape = androidx.compose.foundation.shape.RoundedCornerShape(18.dp)

/** Background of the surface a page is drawn on: black full screen, grey inside sheets. */
val LocalZelefinCanvas = androidx.compose.runtime.compositionLocalOf { ZelefinBlack }

val ZelefinFont = FontFamily.Default

private val ErrorSeed = Color(0xFFFF453A)

@Composable
fun ZelefinTheme(content: @Composable () -> Unit) {
    val accent = ZelefinCyan
    val colors = remember(accent) { accentColorScheme(accent) }
    MaterialTheme(
        colorScheme = colors,
        typography = MaterialTheme.typography.copy(
            headlineLarge = TextStyle(fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 34.sp, color = ZelefinInk),
            headlineMedium = TextStyle(fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 28.sp, color = ZelefinInk),
            titleLarge = TextStyle(fontFamily = ZelefinFont, fontWeight = FontWeight.Medium, fontSize = 22.sp, color = ZelefinInk),
            titleMedium = TextStyle(fontFamily = ZelefinFont, fontWeight = FontWeight.Medium, fontSize = 17.sp, color = ZelefinInk),
            bodyLarge = TextStyle(fontFamily = ZelefinFont, fontSize = 16.sp, color = ZelefinInk),
            bodyMedium = TextStyle(fontFamily = ZelefinFont, fontSize = 14.sp, color = ZelefinMuted),
            labelLarge = TextStyle(fontFamily = ZelefinFont, fontWeight = FontWeight.Medium, fontSize = 16.sp),
        ),
        content = content,
    )
}

/**
 * Dark Material 3 scheme from the user's accent seed.
 * Chromatic and surface-container roles follow the dark tone scale so the
 * navigation bar (`surfaceContainer`) shifts with the accent.
 */
internal fun accentColorScheme(seed: Color): ColorScheme {
    val primary = seed.tones(chroma = seed.labChroma().coerceAtLeast(36.0))
    val secondary = seed.tones(chroma = 16.0)
    val tertiary = seed.tones(chroma = 24.0, hueShift = 60.0)
    val error = ErrorSeed.tones(chroma = ErrorSeed.labChroma().coerceAtLeast(36.0))
    val neutral = seed.tones(chroma = 8.0)
    val neutralVariant = seed.tones(chroma = 16.0)
    return darkColorScheme(
        primary = primary(80),
        onPrimary = primary(20),
        primaryContainer = primary(30),
        onPrimaryContainer = primary(90),
        inversePrimary = primary(40),
        secondary = secondary(80),
        onSecondary = secondary(20),
        secondaryContainer = secondary(30),
        onSecondaryContainer = secondary(90),
        tertiary = tertiary(80),
        onTertiary = tertiary(20),
        tertiaryContainer = tertiary(30),
        onTertiaryContainer = tertiary(90),
        error = error(80),
        onError = error(20),
        errorContainer = error(30),
        onErrorContainer = error(90),
        background = ZelefinBlack,
        onBackground = neutral(90),
        surface = neutral(6),
        onSurface = neutral(90),
        surfaceVariant = neutralVariant(30),
        onSurfaceVariant = neutralVariant(80),
        surfaceTint = primary(80),
        inverseSurface = neutral(90),
        inverseOnSurface = neutral(20),
        outline = neutralVariant(60),
        outlineVariant = neutralVariant(30),
        scrim = Color.Black,
        surfaceDim = neutral(6),
        surfaceBright = neutral(24),
        surfaceContainerLowest = neutral(4),
        surfaceContainerLow = neutral(10),
        surfaceContainer = neutral(12),
        surfaceContainerHigh = neutral(17),
        surfaceContainerHighest = neutral(22),
    )
}

private fun Color.labChroma(): Double {
    val lab = lab()
    return hypot(lab[1], lab[2])
}

private fun Color.tones(chroma: Double, hueShift: Double = 0.0): (Int) -> Color {
    val lab = lab()
    val angle = atan2(lab[2], lab[1]) + Math.toRadians(hueShift)
    val a = chroma * cos(angle)
    val b = chroma * sin(angle)
    return { tone -> Color(ColorUtils.LABToColor(tone.toDouble().coerceIn(0.0, 100.0), a, b)) }
}

private fun Color.lab(): DoubleArray = DoubleArray(3).also { ColorUtils.colorToLAB(toArgb(), it) }
