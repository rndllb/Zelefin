package app.zelefin.client.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val ConfirmDestructive = Color(0xFFFF453A)

/** Two-button counterpart of [ZelefinGlassAlert] for confirmations. */
@Composable
fun ZelefinGlassConfirm(
    hazeState: ZelefinHazeState,
    title: String,
    message: String,
    confirmLabel: String,
    onConfirm: () -> Unit,
    onCancel: () -> Unit,
    cancelLabel: String = "Cancel",
    destructive: Boolean = false,
    enabled: Boolean = true,
) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Box(
            Modifier
                .fillMaxSize()
                .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) { if (enabled) onCancel() },
        )
        Column(
            Modifier
                .width(270.dp)
                .zelefinGlassChrome(hazeState, ZelefinOverlayShape)
                .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) {}
                .padding(top = 18.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                title,
                color = Color.White,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.SemiBold,
                fontSize = 17.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
            Spacer(Modifier.height(4.dp))
            Text(
                message,
                color = DockInactive,
                fontFamily = ZelefinFont,
                fontSize = 13.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
            Spacer(Modifier.height(14.dp))
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(0.5.dp)
                    .background(DockBorder),
            )
            Row(Modifier.fillMaxWidth().height(44.dp)) {
                Box(
                    Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .clickable(enabled = enabled, onClick = onCancel),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(cancelLabel, color = ZelefinCyan, fontFamily = ZelefinFont, fontSize = 17.sp)
                }
                Box(
                    Modifier
                        .width(0.5.dp)
                        .fillMaxHeight()
                        .background(DockBorder),
                )
                Box(
                    Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .clickable(enabled = enabled, onClick = onConfirm),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        confirmLabel,
                        color = (if (destructive) ConfirmDestructive else ZelefinCyan).copy(alpha = if (enabled) 1f else 0.5f),
                        fontFamily = ZelefinFont,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 17.sp,
                    )
                }
            }
        }
    }
}
