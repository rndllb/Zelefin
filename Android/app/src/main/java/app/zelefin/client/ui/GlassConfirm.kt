package app.zelefin.client.ui

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable

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
    SettingsAlertDialog(
        title = title,
        message = message,
        confirmLabel = confirmLabel,
        onConfirm = onConfirm,
        onDismiss = onCancel,
        cancelLabel = cancelLabel,
        destructive = destructive,
        enabled = enabled,
    )
}

@Composable
fun ZelefinGlassAlert(
    hazeState: ZelefinHazeState,
    title: String,
    message: String,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(message) },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("OK") }
        },
    )
}
