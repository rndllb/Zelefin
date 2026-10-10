package app.zelefin.client.ui

import androidx.compose.foundation.background
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.dp
import androidx.compose.material3.MaterialTheme

/** Material 3 surface for controls drawn over video. */
@Composable
internal fun Modifier.playerGlass(shape: Shape): Modifier {
    return this
        .shadow(6.dp, shape, clip = false, ambientColor = Color.Black.copy(alpha = 0.28f), spotColor = Color.Black.copy(alpha = 0.36f))
        .clip(shape)
        .background(MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.94f))
}
