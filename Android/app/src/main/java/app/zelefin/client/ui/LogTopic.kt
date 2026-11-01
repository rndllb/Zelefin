package app.zelefin.client.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import app.zelefin.client.PluginsController
import app.zelefin.client.ZelefinLog
import app.zelefin.client.ZelefinUiState
import java.net.URI
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Settings → Log: what Zelefin did and what went wrong, newest first, to read here or send on. Mirrors iOS `LogView`. */
@Composable
internal fun LogTopic(state: ZelefinUiState, plugins: PluginsController) {
    val context = LocalContext.current
    val pluginState by plugins.state.collectAsState()
    var revision by remember { mutableIntStateOf(0) }
    var lines by remember { mutableStateOf(emptyList<LogLine>()) }
    var filter by remember { mutableStateOf(LogFilter.All) }
    var search by remember { mutableStateOf("") }
    var confirmsClear by remember { mutableStateOf(false) }
    LaunchedEffect(revision) {
        lines = withContext(Dispatchers.IO) { LogLine.parse(ZelefinLog.contents()) }
    }
    val header = {
        val session = state.session
        val server = session?.let { saved ->
            val kind = if (saved.isEmbyServer) "Emby" else if (saved.isSiloServer) "Silo" else "Jellyfin"
            "$kind · ${runCatching { URI(saved.serverUrl).host }.getOrNull() ?: saved.serverUrl}"
        }
        ZelefinLog.header(server, pluginState.requestService.title.takeIf { pluginState.seerrName != null })
    }
    val term = search.trim()
    val shown = lines.filter { line ->
        filter.includes(line.level) && (term.isEmpty() || line.raw.contains(term, ignoreCase = true))
    }.take(SHOWN_LIMIT)

    SettingsCard {
        SettingsMenuPicker(
            label = "Show",
            choices = LogFilter.entries.map { SettingsChoice(it, it.title) },
            selected = filter,
            onSelect = { filter = it },
        )
        SettingsCardDivider()
        SettingsTextField(
            label = "SEARCH",
            value = search,
            icon = Icons.Outlined.Search,
            onChange = { search = it },
            placeholder = "Search the log",
        )
    }
    SettingsFooter(
        "Zelefin notes what it does and what goes wrong: sign-ins, playback, downloads, and requests that fail. Passwords, tokens, and API keys are never written down. Send the log when you report a problem.",
    )

    SettingsCard {
        SettingsActionRow("Send Log") { shareLog(context, header()) }
        SettingsCardDivider()
        SettingsActionRow("Copy Log") {
            val clipboard = context.getSystemService(ClipboardManager::class.java)
            clipboard?.setPrimaryClip(ClipData.newPlainText("Zelefin Log", header() + "\n\n" + ZelefinLog.contents()))
        }
        SettingsCardDivider()
        SettingsActionRow("Refresh") { revision += 1 }
        SettingsCardDivider()
        if (confirmsClear) {
            SettingsActionRow("Tap Again to Clear the Log", destructive = true) {
                ZelefinLog.clear()
                ZelefinLog.info("Log", "Cleared the log")
                confirmsClear = false
                revision += 1
            }
        } else {
            SettingsActionRow("Clear Log", destructive = true) { confirmsClear = true }
        }
    }

    SettingsHeader(if (shown.size >= SHOWN_LIMIT) "Newest $SHOWN_LIMIT entries" else "Entries")
    SettingsCard {
        if (shown.isEmpty()) {
            Text(
                if (lines.isEmpty()) "Nothing logged yet." else "No entries match.",
                color = IOSColors.secondaryLabel,
                fontFamily = ZelefinFont,
                fontSize = 15.sp,
                modifier = Modifier.padding(vertical = 14.dp),
            )
        } else {
            shown.forEachIndexed { index, line ->
                if (index > 0) SettingsCardDivider()
                LogLineRow(line)
            }
        }
    }
}

/** The newest this many entries; a full log is still in the shared file. */
private const val SHOWN_LIMIT = 500

private enum class LogFilter(val title: String) {
    All("All"),
    Problems("Problems"),
    Errors("Errors");

    fun includes(level: ZelefinLog.Level): Boolean = when (this) {
        All -> true
        Problems -> level != ZelefinLog.Level.Info
        Errors -> level == ZelefinLog.Level.Error
    }
}

internal data class LogLine(val time: String, val level: ZelefinLog.Level, val category: String, val message: String, val raw: String) {
    companion object {
        /** Newest first. */
        fun parse(text: String): List<LogLine> = text.lineSequence().filter { it.isNotBlank() }.map(::of).toList().asReversed()

        /** `2026-11-01 08:41:03.120 WARN [Network] GET host/path → 404` */
        fun of(raw: String): LogLine {
            val parts = raw.split(" ", limit = 4)
            val level = parts.getOrNull(2)?.let { label -> ZelefinLog.Level.entries.firstOrNull { it.label == label } }
            if (parts.size < 4 || level == null) return LogLine("", ZelefinLog.Level.Info, "", raw, raw)
            val rest = parts[3]
            val close = rest.indexOf(']')
            val (category, message) = if (rest.startsWith("[") && close > 0) {
                rest.substring(1, close) to rest.substring(close + 1).trim()
            } else {
                "" to rest
            }
            // "11-01 08:41:03": the month and day, then the time to the second.
            return LogLine("${parts[0].drop(5)} ${parts[1].take(8)}", level, category, message, raw)
        }
    }
}

@Composable
private fun LogLineRow(line: LogLine) {
    Column(Modifier.fillMaxWidth().padding(vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(line.level.label, color = line.level.color, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 11.sp)
            if (line.category.isNotEmpty()) {
                Spacer(Modifier.width(6.dp))
                Text(line.category, color = IOSColors.secondaryLabel, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 12.sp)
            }
            Spacer(Modifier.weight(1f))
            Text(line.time, color = IOSColors.secondaryLabel, fontFamily = FontFamily.Monospace, fontSize = 11.sp)
        }
        SelectionContainer {
            Text(line.message, color = Color.White, fontFamily = FontFamily.Monospace, fontSize = 13.sp)
        }
    }
}

private val ZelefinLog.Level.color: Color
    get() = when (this) {
        ZelefinLog.Level.Info -> IOSColors.secondaryLabel
        ZelefinLog.Level.Warning -> Color(0xFFFF9F0A)
        ZelefinLog.Level.Error -> IOSColors.red
    }

private fun shareLog(context: Context, header: String) {
    val file = ZelefinLog.exportFile(context, header) ?: return
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.logs", file)
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_STREAM, uri)
        putExtra(Intent.EXTRA_SUBJECT, "Zelefin Log")
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(send, "Send Zelefin Log").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}
