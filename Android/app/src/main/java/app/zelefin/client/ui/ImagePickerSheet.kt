package app.zelefin.client.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.client.jellyfin.RemoteArtworkKind
import app.zelefin.client.jellyfin.RemoteImageChoice
import app.zelefin.core.MediaItem
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

private val PickerCaption = Color.White.copy(alpha = 0.55f)

/** iOS `RemoteImagePickerView`: pick provider artwork for one image slot; Jellyfin downloads and applies it. */
@Composable
internal fun ImagePickerSheet(
    item: MediaItem,
    onLoad: suspend (MediaItem, RemoteArtworkKind) -> List<RemoteImageChoice>,
    onChoose: suspend (MediaItem, RemoteArtworkKind, RemoteImageChoice) -> Unit,
    onClose: () -> Unit,
) {
    var kind by remember(item.id) { mutableStateOf(RemoteArtworkKind.Poster) }
    var choices by remember(item.id) { mutableStateOf(emptyList<RemoteImageChoice>()) }
    var loading by remember(item.id) { mutableStateOf(true) }
    var applying by remember(item.id) { mutableStateOf<String?>(null) }
    var error by remember(item.id) { mutableStateOf<String?>(null) }
    var applied by remember(item.id) { mutableStateOf<RemoteArtworkKind?>(null) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(item.id, kind) {
        loading = true
        choices = emptyList()
        try {
            choices = onLoad(item, kind)
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (failure: Throwable) {
            error = failure.message ?: "Jellyfin didn’t return ${kind.title.lowercase()} options."
        }
        loading = false
    }

    fun choose(choice: RemoteImageChoice) {
        if (applying != null) return
        applying = choice.url
        val slot = kind
        scope.launch {
            try {
                onChoose(item, slot, choice)
                applied = slot
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (failure: Throwable) {
                error = failure.message ?: "Jellyfin didn’t save that image."
            }
            applying = null
        }
    }

    Column(Modifier.fillMaxSize()) {
        SheetBar(title = "Edit Images", leading = "Close", onLeading = onClose)
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(SheetGroupFill)
                .padding(3.dp),
        ) {
            RemoteArtworkKind.entries.forEach { option ->
                val selected = option == kind
                Box(
                    Modifier
                        .weight(1f)
                        .height(32.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(if (selected) Color.White.copy(alpha = 0.18f) else Color.Transparent)
                        .clickable(enabled = applying == null) { kind = option },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        option.title,
                        color = if (selected) Color.White else PickerCaption,
                        fontFamily = ZelefinFont,
                        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                        fontSize = 13.sp,
                    )
                }
            }
        }
        when {
            loading -> Column(
                Modifier.fillMaxWidth().padding(top = 48.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(24.dp))
                Text("Loading ${kind.title.lowercase()}s", color = PickerCaption, fontFamily = ZelefinFont, fontSize = 14.sp)
            }
            choices.isEmpty() -> Text(
                "Jellyfin did not return any ${kind.title.lowercase()} options.",
                color = PickerCaption,
                fontFamily = ZelefinFont,
                fontSize = 16.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 48.dp),
            )
            else -> LazyVerticalGrid(
                columns = GridCells.Fixed(if (kind == RemoteArtworkKind.Poster) 3 else 2),
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 32.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                item(span = { GridItemSpan(maxLineSpan) }) {
                    Text(
                        "Tap an image to download it to Jellyfin and use it for this title.",
                        color = PickerCaption,
                        fontFamily = ZelefinFont,
                        fontSize = 13.sp,
                        modifier = Modifier.padding(horizontal = 8.dp),
                    )
                }
                items(choices, key = { it.url }) { choice ->
                    Column(
                        Modifier.clickable(enabled = applying == null) { choose(choice) },
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .aspectRatio(kind.aspect)
                                .clip(RoundedCornerShape(8.dp))
                                .background(Color.White.copy(alpha = 0.08f)),
                            contentAlignment = Alignment.Center,
                        ) {
                            CachedArtwork(
                                urls = listOfNotNull(choice.thumbnailUrl, choice.url).distinct(),
                                contentDescription = choice.provider,
                                contentScale = if (kind == RemoteArtworkKind.Logo) ContentScale.Fit else ContentScale.Crop,
                                modifier = Modifier.fillMaxSize(),
                            )
                            if (applying == choice.url) {
                                Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.5f)), contentAlignment = Alignment.Center) {
                                    CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(22.dp))
                                }
                            }
                        }
                        Text(choice.provider, color = Color.White, fontFamily = ZelefinFont, fontSize = 12.sp, maxLines = 1)
                        choice.sizeLabel?.let { Text(it, color = PickerCaption, fontFamily = ZelefinFont, fontSize = 11.sp, maxLines = 1) }
                    }
                }
            }
        }
    }

    val haze = LocalZelefinHaze.current
    PresentZelefinOverlay(visible = (error != null || applied != null) && haze != null) {
        val hazeState = haze ?: return@PresentZelefinOverlay
        if (error != null) {
            ZelefinGlassAlert(hazeState = hazeState, title = "Edit Images", message = error.orEmpty(), onDismiss = { error = null })
        } else {
            ZelefinGlassAlert(
                hazeState = hazeState,
                title = "${applied?.title ?: "Image"} updated",
                message = "Jellyfin saved the new image. This title shows it now.",
                onDismiss = {
                    applied = null
                    onClose()
                },
            )
        }
    }
}
