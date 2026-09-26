package app.zelefin.client.ui

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color

data class AccentPreset(val id: String, val name: String, val color: Color)

/** Mirrors iOS `AccentPreferences`. [ZelefinCyan] reads [color], so Compose redraws when it changes. */
object AccentPreferences {
    const val DEFAULT_ID = "cyan"

    val presets = listOf(
        AccentPreset("cyan", "Cyan", Color(0xFF64D2FF)),
        AccentPreset("red", "Red", Color(0xFFFA2D48)),
        AccentPreset("pink", "Pink", Color(0xFFFF3778)),
        AccentPreset("orange", "Orange", Color(0xFFFF9500)),
        AccentPreset("yellow", "Yellow", Color(0xFFFFD60A)),
        AccentPreset("green", "Green", Color(0xFF34C759)),
        AccentPreset("teal", "Teal", Color(0xFF30B0C7)),
        AccentPreset("blue", "Blue", Color(0xFF0A84FF)),
        AccentPreset("indigo", "Indigo", Color(0xFF5E5CE6)),
        AccentPreset("purple", "Purple", Color(0xFFBF5AF2)),
        AccentPreset("lightgray", "Light Gray", Color(0xFFACACB0)),
    )

    var presetId by mutableStateOf(DEFAULT_ID)
        private set

    val color: Color get() = presets.firstOrNull { it.id == presetId }?.color ?: presets.first().color

    fun load(context: Context) {
        presetId = prefs(context).getString(KEY, DEFAULT_ID) ?: DEFAULT_ID
    }

    fun select(context: Context, id: String) {
        presetId = id
        prefs(context).edit().putString(KEY, id).apply()
    }

    private const val KEY = "accent-preset"
}

enum class HomeRowKind(val title: String) {
    ContinueWatching("Continue Watching"),
    NextUp("Next Up"),
    RecentMovies("Recently Added Movies"),
    RecentShows("Recently Added Shows"),
}

/** Home layout choices from Interface settings. Home reads these directly, so changes show right away. */
object HomeLayoutPreferences {
    var order by mutableStateOf(HomeRowKind.entries.toList())
        private set
    var hidden by mutableStateOf(emptySet<HomeRowKind>())
        private set
    var showsFeatured by mutableStateOf(true)
        private set
    var mergeContinueAndNextUp by mutableStateOf(false)
        private set

    val visibleRows: List<HomeRowKind>
        get() = order.filter { it !in hidden && !(mergeContinueAndNextUp && it == HomeRowKind.NextUp) }

    fun load(context: Context) {
        val prefs = prefs(context)
        val stored = prefs.getString(ORDER, null)?.split(',')?.mapNotNull { name -> HomeRowKind.entries.firstOrNull { it.name == name } }
        order = stored.orEmpty().distinct() + HomeRowKind.entries.filter { it !in stored.orEmpty() }
        hidden = prefs.getString(HIDDEN, "").orEmpty().split(',').mapNotNull { name -> HomeRowKind.entries.firstOrNull { it.name == name } }.toSet()
        showsFeatured = prefs.getBoolean(FEATURED, true)
        mergeContinueAndNextUp = prefs.getBoolean(MERGE, false)
    }

    fun move(context: Context, row: HomeRowKind, offset: Int) {
        val list = order.toMutableList()
        val from = list.indexOf(row)
        val to = (from + offset).coerceIn(0, list.lastIndex)
        if (from < 0 || from == to) return
        list.removeAt(from)
        list.add(to, row)
        order = list
        prefs(context).edit().putString(ORDER, list.joinToString(",") { it.name }).apply()
    }

    fun setVisible(context: Context, row: HomeRowKind, visible: Boolean) {
        hidden = if (visible) hidden - row else hidden + row
        prefs(context).edit().putString(HIDDEN, hidden.joinToString(",") { it.name }).apply()
    }

    fun setShowsFeatured(context: Context, on: Boolean) {
        showsFeatured = on
        prefs(context).edit().putBoolean(FEATURED, on).apply()
    }

    fun setMergeContinueAndNextUp(context: Context, on: Boolean) {
        mergeContinueAndNextUp = on
        prefs(context).edit().putBoolean(MERGE, on).apply()
    }

    fun reset(context: Context) {
        prefs(context).edit().remove(ORDER).remove(HIDDEN).remove(FEATURED).remove(MERGE).apply()
        load(context)
    }

    private const val ORDER = "home-row-order"
    private const val HIDDEN = "home-row-hidden"
    private const val FEATURED = "home-featured"
    private const val MERGE = "home-merge-continue-next-up"
}

fun loadInterfacePreferences(context: Context) {
    AccentPreferences.load(context)
    HomeLayoutPreferences.load(context)
}

private fun prefs(context: Context) = context.getSharedPreferences("zelefin.interface", Context.MODE_PRIVATE)
