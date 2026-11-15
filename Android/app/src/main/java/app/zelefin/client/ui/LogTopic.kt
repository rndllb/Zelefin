package app.zelefin.client.ui

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import app.zelefin.client.PluginsController
import app.zelefin.client.PluginsUiState
import app.zelefin.client.ZelefinLog
import app.zelefin.client.ZelefinModel
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
    val model: ZelefinModel = viewModel()
    val header = { logDiagnostics(state, pluginState) }
    val term = search.trim()
    val shown = lines.filter { line ->
        filter.includes(line.level) && (term.isEmpty() || line.raw.contains(term, ignoreCase = true))
    }

    SettingsCard {
        LogShowFilter(selected = filter, onSelect = { filter = it })
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
        "Zelefin notes what it does and what goes wrong: sign-ins, playback, downloads, and requests that fail. Passwords, tokens, and API keys are never written down. Report a problem to email help@randll.com or open a GitHub issue with the log attached.",
    )

    SettingsCard {
        SettingsActionRow("Report Issue") { model.openSettingsTopic("report") }
    }
    Spacer(Modifier.height(14.dp))

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
        SettingsActionRow("Clear Log", destructive = true) { confirmsClear = true }
    }
    if (confirmsClear) {
        SettingsAlertDialog(
            title = "Clear the log?",
            message = "Everything Zelefin has noted so far is removed from this device.",
            confirmLabel = "Clear Log",
            onConfirm = {
                ZelefinLog.clear()
                ZelefinLog.info("Log", "Cleared the log")
                confirmsClear = false
                revision += 1
            },
            onDismiss = { confirmsClear = false },
            destructive = true,
        )
    }

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

/** Compose a short problem report, then email help@randll.com and/or open a GitHub issue. Mirrors iOS `ReportIssueView`. */
@Composable
internal fun ReportIssueTopic(state: ZelefinUiState, plugins: PluginsController) {
    val context = LocalContext.current
    val pluginState by plugins.state.collectAsState()
    var summary by remember { mutableStateOf("") }
    var notice by remember { mutableStateOf<String?>(null) }
    val trimmed = summary.trim()
    val canSubmit = trimmed.isNotEmpty()
    val diagnostics = logDiagnostics(state, pluginState)

    SettingsCard {
        IOSTextField(
            value = summary,
            onChange = { summary = it },
            placeholder = "What’s going wrong?",
            singleLine = false,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
            modifier = Modifier.fillMaxWidth().heightIn(min = 88.dp).padding(vertical = 12.dp),
        )
    }
    SettingsFooter("Describe the problem in a sentence or two. The device log and diagnostics are included automatically.")

    SettingsCard {
        SettingsActionRow("Email help@randll.com", enabled = canSubmit) {
            notice = emailIssue(context, trimmed, diagnostics)
        }
        SettingsCardDivider()
        SettingsActionRow("Open GitHub Issue", enabled = canSubmit) {
            notice = null
            openGitHubIssue(context, trimmed, diagnostics)
        }
    }
    SettingsFooter("Email attaches the full log. GitHub opens a prefilled issue; attach the log there if the form is too short, or send it by email.")
    notice?.let { message ->
        Spacer(Modifier.height(14.dp))
        SettingsCard {
            Text(message, color = IOSColors.red, fontFamily = ZelefinFont, fontSize = 15.sp, modifier = Modifier.padding(vertical = 14.dp))
        }
    }
}

private fun logDiagnostics(state: ZelefinUiState, pluginState: PluginsUiState): String {
    val server = state.session?.let { saved ->
        val kind = if (saved.isEmbyServer) "Emby" else if (saved.isSiloServer) "Silo" else "Jellyfin"
        "$kind · ${runCatching { URI(saved.serverUrl).host }.getOrNull() ?: saved.serverUrl}"
    }
    return ZelefinLog.header(server, pluginState.requestService.title.takeIf { pluginState.seerrName != null })
}

private const val HELP_EMAIL = "help@randll.com"
private const val GITHUB_NEW_ISSUE = "https://github.com/rndllb/Zelefin/issues/new"

/** The newest this many lines; a full log is still in the shared file. */
private const val SHOWN_LIMIT = 3_000

@Composable
private fun LogShowFilter(selected: LogFilter, onSelect: (LogFilter) -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp)
            .clip(RoundedCornerShape(9.dp))
            .background(Color.White.copy(alpha = 0.08f))
            .padding(2.dp),
    ) {
        LogFilter.entries.forEach { option ->
            val on = option == selected
            Box(
                Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(7.dp))
                    .background(if (on) Color.White.copy(alpha = 0.16f) else Color.Transparent)
                    .clickable { onSelect(option) }
                    .padding(vertical = 7.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    option.title,
                    color = Color.White,
                    fontFamily = ZelefinFont,
                    fontWeight = if (on) FontWeight.SemiBold else FontWeight.Medium,
                    fontSize = 13.sp,
                )
            }
        }
    }
}

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
        /** Newest first, from the newest [SHOWN_LIMIT] lines. */
        fun parse(text: String): List<LogLine> = text.lineSequence()
            .filter { it.isNotBlank() }
            .toList()
            .takeLast(SHOWN_LIMIT)
            .map(::of)
            .asReversed()

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

/** Attaches the log when an email app can take it. Returns a notice when mail isn’t available. */
private fun emailIssue(context: Context, summary: String, diagnostics: String): String? {
    val subject = "Zelefin issue: $summary"
    val body = "$summary\n\n---\n$diagnostics"
    val file = ZelefinLog.exportFile(context, diagnostics)
    val uri = file?.let { FileProvider.getUriForFile(context, "${context.packageName}.logs", it) }
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "message/rfc822"
        putExtra(Intent.EXTRA_EMAIL, arrayOf(HELP_EMAIL))
        putExtra(Intent.EXTRA_SUBJECT, subject)
        putExtra(Intent.EXTRA_TEXT, body)
        if (uri != null) {
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newRawUri("Zelefin Log", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }
    try {
        val chooser = Intent.createChooser(send, "Email $HELP_EMAIL").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (uri != null) {
            chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            chooser.clipData = ClipData.newRawUri("Zelefin Log", uri)
        }
        context.startActivity(chooser)
        return null
    } catch (_: ActivityNotFoundException) {
        val mailto = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:$HELP_EMAIL")).apply {
            putExtra(Intent.EXTRA_SUBJECT, subject)
            putExtra(Intent.EXTRA_TEXT, body.take(1_800))
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            context.startActivity(mailto)
            "Mail isn’t set up on this device. A draft opened if possible — attach the log from Send Log."
        } catch (_: ActivityNotFoundException) {
            "Mail isn’t set up on this device. Use Send Log, then email $HELP_EMAIL."
        }
    }
}

private fun openGitHubIssue(context: Context, summary: String, diagnostics: String) {
    val body = """
        ### Summary
        $summary

        ### Diagnostics
        ```
        $diagnostics
        ```

        ### Steps to reproduce
        1.
        2.

        ### Expected
        -

        ### Actual
        -

        _Attach the Zelefin log from Settings → Log if you can._
    """.trimIndent().take(3_500)
    val url = Uri.parse(GITHUB_NEW_ISSUE).buildUpon()
        .appendQueryParameter("title", summary)
        .appendQueryParameter("body", body)
        .build()
    runCatching {
        context.startActivity(Intent(Intent.ACTION_VIEW, url).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
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
