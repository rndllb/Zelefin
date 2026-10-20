package app.zelefin.client.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.core.SavedSession

/** iOS 26 inset grouped list: borderless rounded sections, accent icons, secondary captions. */
internal val SettingsGroupShape = RoundedCornerShape(26.dp)
internal val SettingsGroupMargin = 16.dp
internal val SettingsContentInset = 16.dp

internal data class SettingsHubItem(
    val title: String,
    val caption: String? = null,
    val icon: ImageVector,
    val washUrl: String? = null,
    val onClick: () -> Unit,
)

/** Rows that share one bordered card, split by hairlines. */
@Composable
internal fun SettingsGroup(content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = SettingsGroupMargin)
            .clip(SettingsGroupShape)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh),
        content = content,
    )
}

@Composable
internal fun SettingsGroupDivider() {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(start = SettingsContentInset + 36.dp)
            .height(0.5.dp)
            .background(IOSColors.separator),
    )
}

/** Accent icon, white title, muted caption, chevron. */
@Composable
internal fun SettingsNavRow(
    title: String,
    icon: ImageVector,
    trailing: String? = null,
    summary: String? = null,
    onClick: () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = SettingsRowHeight)
            .clickable(onClick = onClick)
            .padding(horizontal = SettingsContentInset, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Icon(icon, contentDescription = null, tint = ZelefinCyan, modifier = Modifier.size(22.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = SettingsRowText, maxLines = 1, overflow = TextOverflow.Ellipsis)
            (summary ?: trailing)?.takeIf { it.isNotBlank() }?.let { text ->
                Text(text, color = IOSColors.secondaryLabel, fontFamily = ZelefinFont, fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
        }
        Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = IOSColors.tertiaryLabel)
    }
}

@Composable
internal fun SettingsProfileRow(session: SavedSession?, onClick: () -> Unit) {
    val name = session?.userName?.takeIf { it.isNotBlank() } ?: "Account"
    val handle = if (session?.usesSilo == true) "Silo account" else "Jellyfin account"
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(SettingsContentInset),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        AccountAvatar(session, onClick = onClick, diameter = 48.dp)
        Column(Modifier.weight(1f)) {
            Text(name, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(handle, color = IOSColors.secondaryLabel, fontFamily = ZelefinFont, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = IOSColors.tertiaryLabel)
    }
}

/** Small muted section caption above a card. */
@Composable
internal fun SettingsSectionLabel(title: String) {
    Text(
        title,
        color = IOSColors.secondaryLabel,
        fontFamily = ZelefinFont,
        fontSize = 13.sp,
        modifier = Modifier.padding(start = SettingsGroupMargin + SettingsContentInset, end = SettingsGroupMargin + SettingsContentInset, top = 24.dp, bottom = 7.dp),
    )
}

@Composable
internal fun SettingsNavGroup(items: List<SettingsHubItem>) {
    SettingsGroup {
        items.forEachIndexed { index, item ->
            if (index > 0) SettingsGroupDivider()
            SettingsNavRow(item.title, item.icon, summary = item.caption, onClick = item.onClick)
        }
    }
}
