package app.zelefin.client.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.client.jellyfin.SyncPlayGroup
import app.zelefin.core.MediaItem
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

private val SyncCaption = Color.White.copy(alpha = 0.55f)

/** iOS `SyncPlayPlaySheet`: start a new group or join one, queue this title for everyone, then play it here. */
@Composable
internal fun SyncPlaySheet(
    item: MediaItem,
    defaultGroupName: String,
    onLoad: suspend () -> List<SyncPlayGroup>,
    onStart: suspend (item: MediaItem, joinGroupId: String?, newGroupName: String?) -> Unit,
    onClose: () -> Unit,
) {
    var groups by remember(item.id) { mutableStateOf(emptyList<SyncPlayGroup>()) }
    var loading by remember(item.id) { mutableStateOf(true) }
    var reload by remember(item.id) { mutableIntStateOf(0) }
    var name by remember(item.id) { mutableStateOf(defaultGroupName) }
    var working by remember(item.id) { mutableStateOf<String?>(null) }
    var error by remember(item.id) { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(item.id, reload) {
        loading = true
        try {
            groups = onLoad()
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (failure: Throwable) {
            error = failure.message ?: "Jellyfin didn’t list SyncPlay groups."
        }
        loading = false
    }

    fun start(joinId: String?) {
        if (working != null) return
        working = joinId ?: "new"
        scope.launch {
            try {
                onStart(item, joinId, if (joinId == null) name else null)
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (failure: Throwable) {
                error = failure.message ?: "SyncPlay didn’t start. Try again in a moment."
            }
            working = null
        }
    }

    Column(Modifier.fillMaxSize()) {
        SheetBar(title = "SyncPlay", leading = "Cancel", onLeading = onClose, trailing = "Refresh", onTrailing = { reload++ })
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SyncLabel("New Group")
            Row(
                Modifier
                    .fillMaxWidth()
                    .clip(SheetGroupShape)
                    .background(SheetGroupFill)
                    .padding(horizontal = 16.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                BasicTextField(
                    value = name,
                    onValueChange = { name = it },
                    singleLine = true,
                    textStyle = TextStyle(color = Color.White, fontFamily = ZelefinFont, fontSize = 16.sp),
                    cursorBrush = SolidColor(ZelefinCyan),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Go),
                    keyboardActions = KeyboardActions(onGo = { if (name.isNotBlank()) start(null) }),
                    modifier = Modifier.weight(1f),
                    decorationBox = { inner ->
                        Column {
                            Box(Modifier.padding(vertical = 10.dp)) {
                                if (name.isEmpty()) Text("Name", color = Color.White.copy(alpha = 0.4f), fontFamily = ZelefinFont, fontSize = 16.sp)
                                inner()
                            }
                            Box(Modifier.fillMaxWidth().height(0.5.dp).background(Color.White.copy(alpha = 0.16f)))
                        }
                    },
                )
                Box(Modifier.width(12.dp))
                val canStart = name.isNotBlank() && working == null
                if (working == "new") {
                    CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
                } else {
                    Text(
                        "Start",
                        color = if (canStart) ZelefinCyan else ZelefinMuted,
                        fontFamily = ZelefinFont,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 16.sp,
                        modifier = Modifier.clickable(enabled = canStart) { start(null) }.padding(vertical = 8.dp),
                    )
                }
            }
            Text(
                "Everyone in the group watches ${item.name} together. It starts here once the group is ready.",
                color = SyncCaption,
                fontFamily = ZelefinFont,
                fontSize = 13.sp,
                modifier = Modifier.padding(horizontal = 8.dp),
            )
            SyncLabel("Join and Play")
            Column(Modifier.fillMaxWidth().clip(SheetGroupShape).background(SheetGroupFill)) {
                when {
                    loading && groups.isEmpty() -> Box(Modifier.fillMaxWidth().padding(18.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(22.dp))
                    }
                    groups.isEmpty() -> Text(
                        "No groups yet. Create one to watch together.",
                        color = SyncCaption,
                        fontFamily = ZelefinFont,
                        fontSize = 16.sp,
                        modifier = Modifier.padding(16.dp),
                    )
                    else -> groups.forEachIndexed { index, group ->
                        if (index > 0) SheetGroupDivider()
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .clickable(enabled = working == null) { start(group.id) }
                                .padding(horizontal = 16.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(Icons.Outlined.Groups, contentDescription = null, tint = ZelefinCyan, modifier = Modifier.size(22.dp))
                            Box(Modifier.width(12.dp))
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(group.name, color = Color.White, fontFamily = ZelefinFont, fontSize = 16.sp)
                                Text(group.subtitle, color = SyncCaption, fontFamily = ZelefinFont, fontSize = 12.sp, maxLines = 1)
                            }
                            if (working == group.id) {
                                Box(Modifier.width(8.dp))
                                CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
                            }
                        }
                    }
                }
            }
        }
    }

    val haze = LocalZelefinHaze.current
    PresentZelefinOverlay(visible = error != null && haze != null) {
        val hazeState = haze ?: return@PresentZelefinOverlay
        ZelefinGlassAlert(hazeState = hazeState, title = "SyncPlay", message = error.orEmpty(), onDismiss = { error = null })
    }
}

@Composable
private fun SyncLabel(text: String) {
    Text(text, color = SyncCaption, fontFamily = ZelefinFont, fontSize = 13.sp, modifier = Modifier.padding(start = 8.dp, top = 10.dp))
}
