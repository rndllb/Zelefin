package app.zelefin.client.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

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

@Composable
fun ZelefinTheme(content: @Composable () -> Unit) {
    val accent = ZelefinCyan
    val colors = remember(accent) {
        darkColorScheme(
            primary = accent,
            onPrimary = Color.Black,
            background = ZelefinBlack,
            surface = ZelefinBlack,
            onBackground = ZelefinInk,
            onSurface = ZelefinInk,
        )
    }
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
