package app.zelefin.client.ui

import android.content.Context
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.core.ArtworkDiskKey
import app.zelefin.core.SiloAvatarPreset
import app.zelefin.core.SiloAvatarPresets
import app.zelefin.core.SiloAvatarStyle
import app.zelefin.core.SiloProfile
import coil.imageLoader
import coil.memory.MemoryCache
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private val SheetCaption = Color.White.copy(alpha = 0.55f)
private val TileShape = RoundedCornerShape(22.dp)
private const val UploadBusy = "upload"
private const val RemoveBusy = "remove"

/** Silo's premade avatars plus "Choose Photo", for the signed-in Silo profile (Silo web's avatar picker). */
@Composable
internal fun SiloAvatarSheet(
    profile: SiloProfile,
    uploadEnabled: Boolean,
    onChoosePreset: suspend (SiloAvatarPreset) -> Unit,
    onUpload: suspend (Uri) -> Unit,
    onRemove: suspend () -> Unit,
    onClose: () -> Unit,
) {
    BackHandler(onBack = onClose)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val selectedId = SiloAvatarPresets.selectedId(profile.avatar)
    var style by rememberSaveable { mutableStateOf(SiloAvatarPresets.style(selectedId) ?: SiloAvatarStyle.Identicon) }
    var batch by rememberSaveable { mutableIntStateOf(0) }
    var busy by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val presets = remember(style, batch) { SiloAvatarPresets.batch(style, batch) }
    val hasPicture = profile.avatarUrl != null || profile.avatarSource == "preset" || profile.avatarSource == "upload"

    fun run(tag: String, action: suspend () -> Unit) {
        if (busy != null) return
        busy = tag
        error = null
        val previous = profile.avatarUrl
        scope.launch {
            try {
                action()
                previous?.let { evictAvatar(context, it) }
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (failure: Throwable) {
                error = failure.message ?: "Silo did not change the picture."
            }
            busy = null
        }
    }

    val photoPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri: Uri? ->
        if (uri != null) run(UploadBusy) { onUpload(uri) }
    }

    Column(Modifier.fillMaxSize()) {
        SheetBar(title = "Profile Picture", leading = "Close", onLeading = onClose)
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .navigationBarsPadding()
                .padding(bottom = 28.dp),
        ) {
            Column(Modifier.fillMaxWidth().padding(top = 4.dp, bottom = 18.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Box(contentAlignment = Alignment.Center) {
                    SiloProfileAvatar(profile, 88.dp)
                    if (busy == UploadBusy || busy == RemoveBusy) {
                        Box(Modifier.size(88.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.5f)), contentAlignment = Alignment.Center) {
                            IOSSpinner(color = Color.White)
                        }
                    }
                }
                Spacer(Modifier.height(10.dp))
                Text(profile.name, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 20.sp)
                Text(
                    if (uploadEnabled) "Pick a premade picture or use your own photo." else "Pick a premade picture.",
                    color = SheetCaption,
                    fontFamily = ZelefinFont,
                    fontSize = 14.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(top = 2.dp, start = 24.dp, end = 24.dp),
                )
            }
            Row(
                Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                SiloAvatarStyle.entries.forEach { option ->
                    StyleChip(option.title, selected = option == style, enabled = busy == null) {
                        if (style != option) {
                            style = option
                            batch = 0
                        }
                    }
                }
                StyleChip("More", selected = false, enabled = busy == null, showRefresh = true) { batch += 1 }
            }
            Spacer(Modifier.height(16.dp))
            BoxWithConstraints(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                val columns = if (maxWidth >= 560.dp) 6 else 3
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    presets.chunked(columns).forEach { row ->
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            row.forEach { preset ->
                                PresetTile(
                                    preset = preset,
                                    selected = preset.id == selectedId,
                                    busy = busy == preset.id,
                                    enabled = busy == null,
                                    modifier = Modifier.weight(1f),
                                ) { run(preset.id) { onChoosePreset(preset) } }
                            }
                            repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
            }
            error?.let { message ->
                Text(
                    message,
                    color = IOSColors.red,
                    fontFamily = ZelefinFont,
                    fontSize = 13.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(start = 24.dp, end = 24.dp, top = 16.dp),
                )
            }
            if (uploadEnabled || hasPicture) {
                Spacer(Modifier.height(20.dp))
                SettingsCard {
                    if (uploadEnabled) {
                        SettingsActionRow("Choose Photo", busy = busy == UploadBusy, enabled = busy == null) {
                            photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                        }
                    }
                    if (uploadEnabled && hasPicture) SettingsCardDivider()
                    if (hasPicture) {
                        SettingsActionRow("Remove Picture", busy = busy == RemoveBusy, enabled = busy == null, destructive = true) {
                            run(RemoveBusy) { onRemove() }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun StyleChip(title: String, selected: Boolean, enabled: Boolean, showRefresh: Boolean = false, onClick: () -> Unit) {
    Row(
        Modifier
            .alpha(if (enabled) 1f else 0.5f)
            .clip(RoundedCornerShape(50))
            .background(if (selected) ZelefinCyan else SheetGroupFill)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(PaddingValues(horizontal = 14.dp, vertical = 8.dp)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (showRefresh) {
            Icon(Icons.Outlined.Refresh, contentDescription = null, tint = Color.White, modifier = Modifier.size(15.dp))
            Spacer(Modifier.width(5.dp))
        }
        Text(
            title,
            color = if (selected) Color.Black else Color.White,
            fontFamily = ZelefinFont,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            fontSize = 14.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun PresetTile(
    preset: SiloAvatarPreset,
    selected: Boolean,
    busy: Boolean,
    enabled: Boolean,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    Box(
        modifier
            .aspectRatio(1f)
            .clip(TileShape)
            .background(SheetGroupFill)
            .then(if (selected) Modifier.border(3.dp, ZelefinCyan, TileShape) else Modifier)
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        CachedArtwork(
            url = preset.previewUrl,
            contentDescription = preset.label,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize().padding(if (selected) 6.dp else 0.dp).clip(RoundedCornerShape(if (selected) 16.dp else 22.dp)),
        )
        if (busy) {
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.5f)), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(24.dp))
            }
        }
    }
}

/** Drops the old picture from Coil so avatars that keep their URL after an upload reload. */
private suspend fun evictAvatar(context: Context, url: String) {
    val key = ArtworkDiskKey.key(url)
    context.imageLoader.memoryCache?.remove(MemoryCache.Key(key))
    withContext(Dispatchers.IO) { context.imageLoader.diskCache?.remove(key) }
}
