package app.zelefin.client.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.client.PluginsController
import app.zelefin.client.plugins.RemoteSubtitle
import app.zelefin.client.plugins.SubtitleSearchLanguage
import app.zelefin.core.MediaItem
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

private val SubtitleCaption = Color.White.copy(alpha = 0.55f)

/** Open Subtitles search for one movie or episode; saves the chosen file onto the Jellyfin server. */
@Composable
internal fun OpenSubtitlesSheet(
    item: MediaItem,
    plugins: PluginsController,
    onClose: () -> Unit,
    onSaved: () -> Unit,
) {
    var language by remember(item.id) { mutableStateOf(SubtitleSearchLanguage.preferred(null)) }
    var perfectMatch by remember(item.id) { mutableStateOf(false) }
    var languageOpen by remember(item.id) { mutableStateOf(false) }
    var matches by remember(item.id) { mutableStateOf(emptyList<RemoteSubtitle>()) }
    var searching by remember(item.id) { mutableStateOf(true) }
    var downloadingId by remember(item.id) { mutableStateOf<String?>(null) }
    var error by remember(item.id) { mutableStateOf<String?>(null) }
    var saved by remember(item.id) { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val emby = plugins.state.value.isEmbyServer

    LaunchedEffect(item.id, language.code, perfectMatch) {
        searching = true
        matches = emptyList()
        try {
            matches = plugins.searchSubtitles(item.id, language.code, perfectMatch)
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (failure: Throwable) {
            error = failure.message ?: if (emby) "The subtitle search didn’t respond." else "Open Subtitles didn’t respond."
        }
        searching = false
    }

    fun download(match: RemoteSubtitle) {
        if (downloadingId != null) return
        downloadingId = match.id
        scope.launch {
            try {
                plugins.downloadSubtitle(item.id, match.id)
                saved = true
                onSaved()
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (failure: Throwable) {
                error = failure.message ?: "That subtitle didn’t save."
            }
            downloadingId = null
        }
    }

    Column(Modifier.fillMaxSize()) {
        SheetBar(title = if (emby) "Find Subtitles" else "Add Subtitles", leading = "Close", onLeading = onClose)
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Column(Modifier.fillMaxWidth().clip(SheetGroupShape).background(SheetGroupFill)) {
                SheetPickerRow(
                    label = "Language",
                    value = language.name,
                    open = languageOpen,
                    options = SubtitleSearchLanguage.choices.map { it.code to it.name },
                    selected = language.code,
                    onToggle = { languageOpen = !languageOpen },
                    onChoose = { code ->
                        SubtitleSearchLanguage.choices.firstOrNull { it.code == code }?.let { language = it }
                        languageOpen = false
                    },
                )
                SheetGroupDivider()
                SheetToggleRow("Perfect match only", perfectMatch, enabled = true) { perfectMatch = it }
            }
            Text(
                if (emby) {
                    "Searches this Emby server’s subtitle providers and saves the file onto the server. Perfect match uses the file hash."
                } else {
                    "Downloads from Open Subtitles onto this Jellyfin server. Perfect match uses the file hash."
                },
                color = SubtitleCaption,
                fontFamily = ZelefinFont,
                fontSize = 13.sp,
                modifier = Modifier.padding(horizontal = 8.dp),
            )
            Text(
                "Results",
                color = SubtitleCaption,
                fontFamily = ZelefinFont,
                fontSize = 13.sp,
                modifier = Modifier.padding(start = 8.dp, top = 18.dp),
            )
            Column(Modifier.fillMaxWidth().clip(SheetGroupShape).background(SheetGroupFill)) {
                when {
                    searching && matches.isEmpty() -> Box(Modifier.fillMaxWidth().padding(18.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(22.dp))
                    }
                    matches.isEmpty() -> Text(
                        if (perfectMatch) "No hash match for this file in ${language.name}." else "No ${language.name} subtitles for this title.",
                        color = SubtitleCaption,
                        fontFamily = ZelefinFont,
                        fontSize = 16.sp,
                        modifier = Modifier.padding(16.dp),
                    )
                    else -> matches.forEachIndexed { index, match ->
                        if (index > 0) SheetGroupDivider()
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .clickable(enabled = downloadingId == null) { download(match) }
                                .padding(horizontal = 16.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.Top,
                        ) {
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(match.title, color = Color.White, fontFamily = ZelefinFont, fontSize = 16.sp)
                                if (match.detail.isNotEmpty()) {
                                    Text(match.detail, color = SubtitleCaption, fontFamily = ZelefinFont, fontSize = 12.sp)
                                }
                            }
                            if (downloadingId == match.id) {
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
    PresentZelefinOverlay(visible = (error != null || saved) && haze != null) {
        val hazeState = haze ?: return@PresentZelefinOverlay
        if (error != null) {
            ZelefinGlassAlert(
                hazeState = hazeState,
                title = "Subtitles",
                message = error.orEmpty(),
                onDismiss = { error = null },
            )
        } else {
            ZelefinGlassAlert(
                hazeState = hazeState,
                title = "Subtitles saved",
                message = "Jellyfin stored the file on the server. The subtitle list on this title is updated.",
                onDismiss = {
                    saved = false
                    onClose()
                },
            )
        }
    }
}
