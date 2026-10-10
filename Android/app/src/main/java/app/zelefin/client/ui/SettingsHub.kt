package app.zelefin.client.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.zelefin.core.SavedSession

internal data class SettingsHubItem(
    val title: String,
    val caption: String? = null,
    val icon: ImageVector,
    val washUrl: String? = null,
    val onClick: () -> Unit,
)

@Composable
internal fun SettingsGroup(content: @Composable ColumnScope.() -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(content = content)
    }
}

@Composable
internal fun SettingsGroupDivider() {
    HorizontalDivider(Modifier.padding(start = 72.dp))
}

@Composable
internal fun SettingsNavRow(
    title: String,
    icon: ImageVector,
    trailing: String? = null,
    onClick: () -> Unit,
) {
    ListItem(
        headlineContent = {
            Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis)
        },
        leadingContent = {
            Icon(icon, contentDescription = null)
        },
        trailingContent = {
            Row {
                if (!trailing.isNullOrBlank()) {
                    Text(
                        trailing,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        modifier = Modifier.padding(end = 4.dp),
                    )
                }
                Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier.clickable(onClick = onClick),
    )
}

@Composable
internal fun SettingsProfileRow(session: SavedSession?, onClick: () -> Unit) {
    val name = session?.userName?.takeIf { it.isNotBlank() } ?: "Account"
    val handle = if (session?.usesSilo == true) "Silo account" else "Jellyfin account"
    ListItem(
        headlineContent = {
            Text(name, maxLines = 1, overflow = TextOverflow.Ellipsis)
        },
        supportingContent = {
            Text(handle, maxLines = 1, overflow = TextOverflow.Ellipsis)
        },
        leadingContent = {
            AccountAvatar(session, onClick = onClick, diameter = 44.dp)
        },
        trailingContent = {
            Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier.clickable(onClick = onClick),
    )
}

@Composable
internal fun SettingsSectionLabel(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(start = 16.dp, top = 24.dp, bottom = 8.dp),
    )
}

@Composable
internal fun SettingsNavGroup(items: List<SettingsHubItem>) {
    SettingsGroup {
        items.forEachIndexed { index, item ->
            if (index > 0) SettingsGroupDivider()
            SettingsNavRow(item.title, item.icon, onClick = item.onClick)
        }
    }
}
