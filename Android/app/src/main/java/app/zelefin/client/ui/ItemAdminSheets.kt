package app.zelefin.client.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.client.jellyfin.ItemMetadataDraft
import app.zelefin.client.jellyfin.RemoteIdentifyHit
import app.zelefin.client.jellyfin.itemMetadataDraft
import app.zelefin.core.MediaItem
import kotlinx.coroutines.launch

@Composable
fun IdentifySheet(
    item: MediaItem,
    onSearch: suspend (MediaItem) -> List<RemoteIdentifyHit>,
    onApply: suspend (MediaItem, RemoteIdentifyHit) -> Unit,
    onClose: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var hits by remember(item.id) { mutableStateOf<List<RemoteIdentifyHit>>(emptyList()) }
    var loading by remember(item.id) { mutableStateOf(true) }
    var applying by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(item.id) {
        loading = true
        runCatching { onSearch(item) }
            .onSuccess { hits = it }
            .onFailure { error = it.message }
        loading = false
    }
    Column(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .padding(20.dp),
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("Identify", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 22.sp)
            TextButton(onClick = onClose) { Text("Close", color = ZelefinCyan) }
        }
        Text("Match this title to a metadata provider.", color = ZelefinMuted, fontSize = 14.sp)
        Spacer(Modifier.height(16.dp))
        when {
            loading -> Text("Searching…", color = ZelefinMuted)
            error != null -> Text(error!!, color = Color(0xFFFF6B6B))
            hits.isEmpty() -> Text("No matches found.", color = ZelefinMuted)
            else -> Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                hits.forEach { hit ->
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .background(Color.White.copy(alpha = 0.06f))
                            .clickable(enabled = applying == null) {
                                applying = hit.name
                                scope.launch {
                                    runCatching { onApply(item, hit) }
                                        .onSuccess { onClose() }
                                        .onFailure { error = it.message }
                                    applying = null
                                }
                            }
                            .padding(14.dp),
                    ) {
                        Text(
                            listOfNotNull(hit.name, hit.year?.toString()).joinToString(" · "),
                            color = Color.White,
                            fontFamily = ZelefinFont,
                            fontWeight = FontWeight.SemiBold,
                        )
                        hit.overview?.let { Text(it, color = ZelefinMuted, fontSize = 13.sp, maxLines = 3) }
                        if (applying == hit.name) Text("Applying…", color = ZelefinCyan, fontSize = 13.sp)
                    }
                }
            }
        }
    }
}

@Composable
fun EditMetadataSheet(
    item: MediaItem,
    onSave: suspend (MediaItem, ItemMetadataDraft) -> Unit,
    onClose: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var draft by remember(item.id) { mutableStateOf(itemMetadataDraft(item)) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val fieldColors = OutlinedTextFieldDefaults.colors(
        focusedTextColor = Color.White,
        unfocusedTextColor = Color.White,
        focusedBorderColor = ZelefinCyan,
        unfocusedBorderColor = Color.White.copy(alpha = 0.24f),
        focusedLabelColor = ZelefinCyan,
        unfocusedLabelColor = ZelefinMuted,
        cursorColor = ZelefinCyan,
    )
    Column(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("Edit Metadata", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 22.sp)
            TextButton(onClick = onClose) { Text("Close", color = ZelefinCyan) }
        }
        OutlinedTextField(draft.name, { draft = draft.copy(name = it) }, label = { Text("Name") }, colors = fieldColors, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(draft.year, { draft = draft.copy(year = it) }, label = { Text("Year") }, colors = fieldColors, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(draft.officialRating, { draft = draft.copy(officialRating = it) }, label = { Text("Rating") }, colors = fieldColors, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(draft.genres, { draft = draft.copy(genres = it) }, label = { Text("Genres") }, colors = fieldColors, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(draft.tags, { draft = draft.copy(tags = it) }, label = { Text("Tags") }, colors = fieldColors, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(
            draft.overview,
            { draft = draft.copy(overview = it) },
            label = { Text("Overview") },
            colors = fieldColors,
            modifier = Modifier.fillMaxWidth(),
            minLines = 4,
        )
        error?.let { Text(it, color = Color(0xFFFF6B6B)) }
        TextButton(
            enabled = !busy,
            onClick = {
                busy = true
                scope.launch {
                    runCatching { onSave(item, draft) }
                        .onSuccess { onClose() }
                        .onFailure { error = it.message }
                    busy = false
                }
            },
        ) {
            Text(if (busy) "Saving…" else "Save", color = ZelefinCyan, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold)
        }
    }
}
