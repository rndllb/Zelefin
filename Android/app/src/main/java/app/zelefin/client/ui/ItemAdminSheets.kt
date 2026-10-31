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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.client.jellyfin.ItemMetadataDraft
import app.zelefin.client.jellyfin.RemoteIdentifyHit
import app.zelefin.client.jellyfin.itemMetadataDraft
import app.zelefin.core.MediaItem
import kotlinx.coroutines.launch

private val ErrorRed = Color(0xFFFF6B6B)
private val RowHairline = Color.White.copy(alpha = 0.08f)

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
    var applying by remember { mutableStateOf<RemoteIdentifyHit?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(item.id) {
        loading = true
        runCatching { onSearch(item) }
            .onSuccess { hits = it }
            .onFailure { error = it.message }
        loading = false
    }
    Column(Modifier.fillMaxSize()) {
        SheetBar(title = "Identify", leading = "Close", leadingEnabled = applying == null, onLeading = onClose)
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(top = 8.dp, bottom = 32.dp)
                .navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SheetSectionTitle("Matches for ${item.name}")
            Column(Modifier.fillMaxWidth().clip(SheetGroupShape).background(SheetGroupFill)) {
                when {
                    loading -> Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        CircularProgressIndicator(color = ZelefinCyan, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                        Text("Searching…", color = ZelefinMuted, fontFamily = ZelefinFont, fontSize = 16.sp)
                    }
                    error != null -> Text(error!!, color = ErrorRed, fontFamily = ZelefinFont, fontSize = 15.sp, modifier = Modifier.padding(16.dp))
                    hits.isEmpty() -> Text("No matches found.", color = ZelefinMuted, fontFamily = ZelefinFont, fontSize = 16.sp, modifier = Modifier.padding(16.dp))
                    else -> hits.forEachIndexed { index, hit ->
                        if (index > 0) Box(Modifier.fillMaxWidth().padding(start = 82.dp).height(0.5.dp).background(RowHairline))
                        IdentifyHitRow(hit, applying = applying == hit, enabled = applying == null) {
                            applying = hit
                            scope.launch {
                                runCatching { onApply(item, hit) }
                                    .onSuccess { onClose() }
                                    .onFailure { error = it.message }
                                applying = null
                            }
                        }
                    }
                }
            }
            SheetFootnote("Choosing a match replaces this title's metadata and artwork with the provider's.")
        }
    }
}

@Composable
private fun IdentifyHitRow(hit: RemoteIdentifyHit, applying: Boolean, enabled: Boolean, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(Modifier.size(width = 52.dp, height = 78.dp).posterChrome(6.dp).background(Color.White.copy(alpha = 0.08f))) {
            CachedArtwork(url = hit.imageUrl, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                listOfNotNull(hit.name, hit.year?.toString()).joinToString(" · "),
                color = Color.White,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.SemiBold,
                fontSize = 16.sp,
            )
            hit.overview?.takeIf { it.isNotBlank() }?.let {
                Text(it, color = ZelefinMuted, fontFamily = ZelefinFont, fontSize = 14.sp, maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
        }
        if (applying) {
            CircularProgressIndicator(color = ZelefinCyan, strokeWidth = 2.dp, modifier = Modifier.size(18.dp).align(Alignment.CenterVertically))
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
    fun save() {
        busy = true
        error = null
        scope.launch {
            runCatching { onSave(item, draft) }
                .onSuccess { onClose() }
                .onFailure { error = it.message }
            busy = false
        }
    }
    Column(Modifier.fillMaxSize()) {
        SheetBar(
            title = "Edit Metadata",
            leading = "Close",
            leadingEnabled = !busy,
            onLeading = onClose,
            trailing = if (busy) "Saving…" else "Save",
            trailingEnabled = !busy,
            onTrailing = ::save,
        )
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(top = 8.dp, bottom = 32.dp)
                .navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            error?.let { Text(it, color = ErrorRed, fontFamily = ZelefinFont, fontSize = 15.sp, modifier = Modifier.padding(horizontal = 4.dp)) }
            SheetSectionTitle("Title")
            SheetFieldGroup {
                MetadataField("Name", draft.name) { draft = draft.copy(name = it) }
                MetadataField("Year", draft.year, prompt = "2021") { draft = draft.copy(year = it) }
                MetadataField("Rating", draft.officialRating, prompt = "PG-13", last = true) { draft = draft.copy(officialRating = it) }
            }
            SheetSectionTitle("Categories")
            SheetFieldGroup {
                MetadataField("Genres", draft.genres, prompt = "Drama, Science Fiction") { draft = draft.copy(genres = it) }
                MetadataField("Tags", draft.tags, last = true) { draft = draft.copy(tags = it) }
            }
            SheetFootnote("Separate genres and tags with commas.")
            SheetSectionTitle("Overview")
            SheetFieldGroup {
                MetadataField("Description", draft.overview, multiline = true, last = true) { draft = draft.copy(overview = it) }
            }
        }
    }
}

@Composable
private fun SheetSectionTitle(title: String) {
    Text(
        title,
        color = Color.White,
        fontFamily = ZelefinFont,
        fontWeight = FontWeight.SemiBold,
        fontSize = 17.sp,
        modifier = Modifier.padding(start = 4.dp, top = 12.dp),
    )
}

@Composable
private fun SheetFootnote(text: String) {
    Text(text, color = ZelefinMuted, fontFamily = ZelefinFont, fontSize = 13.sp, modifier = Modifier.padding(horizontal = 4.dp))
}

@Composable
private fun SheetFieldGroup(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().clip(SheetGroupShape).background(SheetGroupFill)) { content() }
}

/** A labeled field with the label above, so long values have the row's full width. */
@Composable
private fun MetadataField(
    label: String,
    value: String,
    prompt: String = "",
    multiline: Boolean = false,
    last: Boolean = false,
    onChange: (String) -> Unit,
) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(label, color = ZelefinMuted, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
        BasicTextField(
            value = value,
            onValueChange = onChange,
            singleLine = !multiline,
            minLines = if (multiline) 5 else 1,
            textStyle = TextStyle(color = Color.White, fontFamily = ZelefinFont, fontSize = 17.sp),
            cursorBrush = SolidColor(ZelefinCyan),
            modifier = Modifier.fillMaxWidth(),
            decorationBox = { inner ->
                Box {
                    if (value.isEmpty() && prompt.isNotEmpty()) {
                        Text(prompt, color = Color.White.copy(alpha = 0.35f), fontFamily = ZelefinFont, fontSize = 17.sp)
                    }
                    inner()
                }
            },
        )
    }
    if (!last) Box(Modifier.fillMaxWidth().padding(start = 16.dp).height(0.5.dp).background(RowHairline))
}
