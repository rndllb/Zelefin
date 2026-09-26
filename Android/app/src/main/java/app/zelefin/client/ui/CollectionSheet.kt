package app.zelefin.client.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
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
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.client.jellyfin.CollectionEditor
import app.zelefin.core.MediaItem
import kotlinx.coroutines.launch

@Composable
fun CollectionSheet(
    item: MediaItem,
    onLoad: suspend (String) -> CollectionEditor,
    onSetMember: suspend (String, String, Boolean) -> Unit,
    onCreate: suspend (String, String) -> Unit,
    onDismiss: () -> Unit,
) {
    var editor by remember(item.id) { mutableStateOf<CollectionEditor?>(null) }
    var name by remember(item.id) { mutableStateOf("") }
    var error by remember(item.id) { mutableStateOf<String?>(null) }
    var loading by remember(item.id) { mutableStateOf(true) }
    var busy by remember(item.id) { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    suspend fun reload() {
        loading = editor == null
        error = null
        runCatching { onLoad(item.id) }
            .onSuccess { editor = it }
            .onFailure { error = it.message ?: "Couldn't load collections." }
        loading = false
    }

    LaunchedEffect(item.id) { reload() }

    fun toggle(collection: MediaItem) {
        val current = editor ?: return
        if (busy) return
        val member = collection.id in current.memberIds
        scope.launch {
            busy = true
            error = null
            runCatching { onSetMember(collection.id, item.id, !member) }
                .onSuccess {
                    val ids = current.memberIds.toMutableSet()
                    if (member) ids.remove(collection.id) else ids.add(collection.id)
                    editor = current.copy(memberIds = ids)
                }
                .onFailure { error = it.message ?: "Couldn't update this collection." }
            busy = false
        }
    }

    fun create() {
        val trimmed = name.trim()
        if (trimmed.isEmpty() || busy) return
        scope.launch {
            busy = true
            error = null
            runCatching { onCreate(trimmed, item.id) }
                .onSuccess {
                    name = ""
                    reload()
                }
                .onFailure { error = it.message ?: "Couldn't create that collection." }
            busy = false
        }
    }

    Column(Modifier.fillMaxSize()) {
        Spacer(Modifier.statusBarsPadding().height(12.dp))
        Column(
            Modifier
                .weight(1f)
                .fillMaxWidth()
                .clip(RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp))
                .background(Color(0xFF202022)),
        ) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Spacer(Modifier.size(46.dp))
                Text(
                    "Collections",
                    color = Color.White,
                    fontFamily = ZelefinFont,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 20.sp,
                    modifier = Modifier.weight(1f),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                )
                Box(
                    Modifier
                        .size(46.dp)
                        .clip(CircleShape)
                        .background(DockFill)
                        .border(0.5.dp, DockBorder, CircleShape)
                        .clickable(onClick = onDismiss),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("✕", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                }
            }
            Column(
                Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 24.dp)
                    .padding(bottom = 24.dp)
                    .navigationBarsPadding(),
                verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                Text("New Collection", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 22.sp)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    BasicTextField(
                        value = name,
                        onValueChange = { name = it },
                        singleLine = true,
                        textStyle = TextStyle(color = Color.White, fontFamily = ZelefinFont, fontSize = 16.sp),
                        cursorBrush = SolidColor(ZelefinCyan),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(onDone = { create() }),
                        modifier = Modifier.weight(1f),
                        decorationBox = { inner ->
                            Column {
                                Box(Modifier.padding(vertical = 10.dp)) {
                                    if (name.isEmpty()) {
                                        Text("Name", color = Color.White.copy(alpha = 0.4f), fontFamily = ZelefinFont, fontSize = 16.sp)
                                    }
                                    inner()
                                }
                                Box(Modifier.fillMaxWidth().height(0.5.dp).background(Color.White.copy(alpha = 0.16f)))
                            }
                        },
                    )
                    val canCreate = name.isNotBlank() && !busy
                    Text(
                        "Create",
                        color = if (canCreate) ZelefinCyan else Color.White.copy(alpha = 0.35f),
                        fontFamily = ZelefinFont,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 16.sp,
                        modifier = Modifier.clickable(enabled = canCreate, onClick = ::create),
                    )
                }
                Text("Collections", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 22.sp)
                error?.let {
                    Text(it, color = Color(0xFFFF453A), fontFamily = ZelefinFont, fontSize = 14.sp)
                }
                when {
                    loading && editor == null -> CircularProgressIndicator(color = ZelefinCyan, modifier = Modifier.size(28.dp))
                    editor?.collections.isNullOrEmpty() -> Text(
                        "No collections yet.",
                        color = Color.White.copy(alpha = 0.55f),
                        fontFamily = ZelefinFont,
                        fontSize = 16.sp,
                    )
                    else -> {
                        editor?.collections.orEmpty().forEach { collection ->
                            val member = collection.id in editor?.memberIds.orEmpty()
                            Row(
                                Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(12.dp))
                                    .clickable(enabled = !busy) { toggle(collection) }
                                    .padding(vertical = 12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(
                                    collection.name,
                                    color = Color.White,
                                    fontFamily = ZelefinFont,
                                    fontSize = 16.sp,
                                    modifier = Modifier.weight(1f),
                                )
                                if (member) {
                                    Icon(Icons.Outlined.Check, contentDescription = null, tint = Color.White, modifier = Modifier.size(20.dp))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
