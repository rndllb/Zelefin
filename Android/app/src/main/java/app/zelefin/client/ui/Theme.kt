package app.zelefin.client.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import app.zelefin.client.R

val ZelefinCyan = Color(0xFF64D2FF)
val ZelefinBlack = Color(0xFF000000)
val ZelefinInk = Color(0xFFF5F5F7)
val ZelefinMuted = Color(0xFF8E8E93)

val Outfit = FontFamily(Font(R.font.outfit, FontWeight.Normal))

private val Colors = darkColorScheme(
    primary = ZelefinCyan,
    onPrimary = Color.Black,
    background = ZelefinBlack,
    surface = ZelefinBlack,
    onBackground = ZelefinInk,
    onSurface = ZelefinInk,
)

@Composable
fun ZelefinTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = Colors,
        typography = MaterialTheme.typography.copy(
            headlineLarge = TextStyle(fontFamily = Outfit, fontWeight = FontWeight.SemiBold, fontSize = 34.sp, color = ZelefinInk),
            headlineMedium = TextStyle(fontFamily = Outfit, fontWeight = FontWeight.SemiBold, fontSize = 28.sp, color = ZelefinInk),
            titleLarge = TextStyle(fontFamily = Outfit, fontWeight = FontWeight.Medium, fontSize = 22.sp, color = ZelefinInk),
            titleMedium = TextStyle(fontFamily = Outfit, fontWeight = FontWeight.Medium, fontSize = 17.sp, color = ZelefinInk),
            bodyLarge = TextStyle(fontFamily = Outfit, fontSize = 16.sp, color = ZelefinInk),
            bodyMedium = TextStyle(fontFamily = Outfit, fontSize = 14.sp, color = ZelefinMuted),
            labelLarge = TextStyle(fontFamily = Outfit, fontWeight = FontWeight.Medium, fontSize = 16.sp),
        ),
        content = content,
    )
}
