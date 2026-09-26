package app.zelefin.client.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/** The user's accent color (Settings → Interface). Named for the default. */
val ZelefinCyan: Color get() = AccentPreferences.color
val ZelefinBlack = Color(0xFF000000)
val ZelefinInk = Color(0xFFF5F5F7)
val ZelefinMuted = Color(0xFF8E8E93)

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
