package app.zelefin.client.ui

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import app.zelefin.client.AppTab
import app.zelefin.client.LibraryKind
import app.zelefin.client.LibraryRoom
import app.zelefin.core.FeaturedHero
import app.zelefin.core.MediaItem
import kotlin.math.roundToInt

data class AccentPreset(val id: String, val name: String, val hex: String) {
    val color: Color get() = AccentPreferences.colorFromHex(hex) ?: AccentPreferences.CyanColor
}

/** Mirrors iOS `AccentPreferences`. [ZelefinCyan] reads [color], so Compose redraws when it changes. */
object AccentPreferences {
    const val DEFAULT_ID = "cyan"
    const val CUSTOM_ID = "custom"
    const val DEFAULT_CUSTOM_HEX = "#2AD4FC"
    internal val CyanColor = Color(0xFF2AD4FC)

    val presets = listOf(
        AccentPreset("cyan", "Cyan", "#2AD4FC"),
        AccentPreset("red", "Red", "#FA2D48"),
        AccentPreset("pink", "Pink", "#FF3778"),
        AccentPreset("orange", "Orange", "#FF9500"),
        AccentPreset("yellow", "Yellow", "#FFD60A"),
        AccentPreset("green", "Green", "#34C759"),
        AccentPreset("teal", "Teal", "#30B0C7"),
        AccentPreset("blue", "Blue", "#0A84FF"),
        AccentPreset("indigo", "Indigo", "#5E5CE6"),
        AccentPreset("purple", "Purple", "#BF5AF2"),
        AccentPreset("lightgray", "Light Gray", "#ACACB0"),
    )

    var presetId by mutableStateOf(DEFAULT_ID)
        private set
    var customHex by mutableStateOf(DEFAULT_CUSTOM_HEX)
        private set

    val color: Color get() = preset(presetId, customHex).color

    val customColor: Color get() = colorFromHex(customHex) ?: CyanColor

    fun preset(id: String, custom: String = DEFAULT_CUSTOM_HEX): AccentPreset {
        if (id == CUSTOM_ID) return AccentPreset(CUSTOM_ID, "Custom", normalizedHex(custom) ?: DEFAULT_CUSTOM_HEX)
        return presets.firstOrNull { it.id == id } ?: presets.first()
    }

    fun load(context: Context) {
        val prefs = prefs(context)
        presetId = prefs.getString(PRESET_KEY, null) ?: prefs.getString(LEGACY_PRESET_KEY, null) ?: DEFAULT_ID
        customHex = normalizedHex(prefs.getString(CUSTOM_KEY, null).orEmpty()) ?: DEFAULT_CUSTOM_HEX
    }

    fun select(context: Context, id: String) {
        presetId = id
        prefs(context).edit().putString(PRESET_KEY, id).apply()
    }

    /** The Custom swatch starts from the current preset, like iOS. */
    fun selectCustom(context: Context) {
        if (presetId != CUSTOM_ID) setCustomHex(context, preset(presetId).hex, select = false)
        select(context, CUSTOM_ID)
    }

    fun setCustomHex(context: Context, hex: String, select: Boolean = true) {
        val normalized = normalizedHex(hex) ?: return
        customHex = normalized
        prefs(context).edit().putString(CUSTOM_KEY, normalized).apply()
        if (select && presetId != CUSTOM_ID) select(context, CUSTOM_ID)
    }

    fun normalizedHex(raw: String): String? {
        var value = raw.trim().uppercase()
        if (value.startsWith("#")) value = value.drop(1)
        if (value.length != 6 || !value.all { it in '0'..'9' || it in 'A'..'F' }) return null
        return "#$value"
    }

    fun colorFromHex(hex: String): Color? {
        val normalized = normalizedHex(hex) ?: return null
        val value = normalized.drop(1).toLong(16)
        return Color(0xFF000000 or value)
    }

    fun hexFrom(color: Color): String {
        fun channel(value: Float) = (value.coerceIn(0f, 1f) * 255f).roundToInt()
        return "#%02X%02X%02X".format(channel(color.red), channel(color.green), channel(color.blue))
    }

    private const val PRESET_KEY = "zelefin.accent-preset-id"
    private const val CUSTOM_KEY = "zelefin.custom-accent-hex"
    private const val LEGACY_PRESET_KEY = "accent-preset"
}

/** Same raw values and order as iOS `HomeRowKind`. */
enum class HomeRowKind(val raw: String, val title: String) {
    Featured("featured", "Featured"),
    ContinueWatching("continueWatching", "Continue Watching"),
    NextUp("nextUp", "Next Up"),
    Upcoming("upcoming", "Upcoming Episodes"),
    Recommendations("recommendations", "Recommendations"),
    RecentlyAddedMovies("recentlyAddedMovies", "Recently Added Movies"),
    RecentlyAddedShows("recentlyAddedShows", "Recently Added Shows"),
    Collections("collections", "Collections"),
    Genres("genres", "Genres"),
    RecentlyWatched("recentlyWatched", "Recently Watched");

    companion object {
        val defaultOrderRaw: String = entries.joinToString(",") { it.raw }

        fun ordered(raw: String): List<HomeRowKind> {
            val seen = LinkedHashSet<HomeRowKind>()
            raw.split(',').forEach { token -> entries.firstOrNull { it.raw == token.trim() }?.let(seen::add) }
            entries.forEach(seen::add)
            return seen.toList()
        }

        fun rawOrder(order: List<HomeRowKind>): String = order.distinct().joinToString(",") { it.raw }

        fun hidden(raw: String): Set<HomeRowKind> =
            raw.split(',').mapNotNull { token -> entries.firstOrNull { it.raw == token.trim() } }.toSet()

        fun rawHidden(hidden: Set<HomeRowKind>): String = hidden.map { it.raw }.sorted().joinToString(",")
    }
}

/** Same raw values as iOS `FeaturedHeroContent`. */
enum class FeaturedHeroContent(val raw: String, val title: String) {
    RecentlyAdded("recentlyAdded", "Recently Added"),
    Random("random", "Random"),
    ContinueWatching("continueWatching", "Continue Watching"),
    NextUp("nextUp", "Next Up"),
    Recommendations("recommendations", "Recommendations"),
    RecentlyWatched("recentlyWatched", "Recently Watched"),
    Favorites("favorites", "Favorites");

    companion object {
        fun from(raw: String?): FeaturedHeroContent = entries.firstOrNull { it.raw == raw } ?: RecentlyAdded
    }
}

/** Home layout choices from Interface settings. Home reads these directly, so changes show right away. */
object HomeLayoutPreferences {
    var order by mutableStateOf(HomeRowKind.entries.toList())
        private set
    var hidden by mutableStateOf(emptySet<HomeRowKind>())
        private set
    var mergeContinueAndNextUp by mutableStateOf(false)
        private set
    var heroContent by mutableStateOf(FeaturedHeroContent.RecentlyAdded)
        private set

    fun isVisible(row: HomeRowKind): Boolean =
        row !in hidden && !(mergeContinueAndNextUp && row == HomeRowKind.NextUp)

    fun load(context: Context) {
        val prefs = prefs(context)
        migrateLegacy(prefs)
        order = HomeRowKind.ordered(prefs.getString(ORDER, null) ?: HomeRowKind.defaultOrderRaw)
        hidden = HomeRowKind.hidden(prefs.getString(HIDDEN, "").orEmpty())
        mergeContinueAndNextUp = prefs.getBoolean(MERGE, false)
        heroContent = FeaturedHeroContent.from(prefs.getString(HERO, null))
    }

    fun setOrder(context: Context, next: List<HomeRowKind>) {
        order = HomeRowKind.ordered(HomeRowKind.rawOrder(next))
        prefs(context).edit().putString(ORDER, HomeRowKind.rawOrder(order)).apply()
    }

    fun setVisible(context: Context, row: HomeRowKind, visible: Boolean) {
        hidden = if (visible) hidden - row else hidden + row
        prefs(context).edit().putString(HIDDEN, HomeRowKind.rawHidden(hidden)).apply()
    }

    fun setMergeContinueAndNextUp(context: Context, on: Boolean) {
        mergeContinueAndNextUp = on
        prefs(context).edit().putBoolean(MERGE, on).apply()
    }

    fun setHeroContent(context: Context, content: FeaturedHeroContent) {
        heroContent = content
        prefs(context).edit().putString(HERO, content.raw).apply()
    }

    /** iOS "Reset Home Rows": default order, nothing hidden, Recently Added hero. */
    fun reset(context: Context) {
        prefs(context).edit().remove(ORDER).remove(HIDDEN).remove(HERO).apply()
        load(context)
    }

    internal fun applySynced(context: Context, orderRaw: String?, hiddenRaw: String?, merge: Boolean?, hero: String?) {
        val edit = prefs(context).edit()
        orderRaw?.trim()?.takeIf { it.isNotEmpty() }?.let {
            order = HomeRowKind.ordered(it)
            edit.putString(ORDER, HomeRowKind.rawOrder(order))
        }
        hiddenRaw?.let {
            hidden = HomeRowKind.hidden(it)
            edit.putString(HIDDEN, HomeRowKind.rawHidden(hidden))
        }
        merge?.let {
            mergeContinueAndNextUp = it
            edit.putBoolean(MERGE, it)
        }
        hero?.let { raw ->
            FeaturedHeroContent.entries.firstOrNull { it.raw == raw }?.let {
                heroContent = it
                edit.putString(HERO, it.raw)
            }
        }
        edit.apply()
    }

    /** Carries choices over from the first Android Interface screen (four rows plus a featured switch). */
    private fun migrateLegacy(prefs: SharedPreferences) {
        if (prefs.contains(ORDER) || prefs.contains(HIDDEN) || prefs.contains(MERGE)) return
        val legacy = mapOf(
            "ContinueWatching" to HomeRowKind.ContinueWatching,
            "NextUp" to HomeRowKind.NextUp,
            "RecentMovies" to HomeRowKind.RecentlyAddedMovies,
            "RecentShows" to HomeRowKind.RecentlyAddedShows,
        )
        val hasLegacy = listOf(LEGACY_ORDER, LEGACY_HIDDEN, LEGACY_FEATURED, LEGACY_MERGE).any(prefs::contains)
        if (!hasLegacy) return
        val edit = prefs.edit()
        prefs.getString(LEGACY_ORDER, null)?.split(',')?.mapNotNull { legacy[it] }?.distinct()?.let { legacyOrder ->
            val defaults = HomeRowKind.entries.toMutableList()
            val slots = defaults.indices.filter { defaults[it] in legacyOrder }
            slots.zip(legacyOrder).forEach { (slot, kind) -> defaults[slot] = kind }
            edit.putString(ORDER, HomeRowKind.rawOrder(defaults))
        }
        val legacyHidden = prefs.getString(LEGACY_HIDDEN, "").orEmpty().split(',').mapNotNull { legacy[it] }.toMutableSet()
        if (!prefs.getBoolean(LEGACY_FEATURED, true)) legacyHidden += HomeRowKind.Featured
        edit.putString(HIDDEN, HomeRowKind.rawHidden(legacyHidden))
        edit.putBoolean(MERGE, prefs.getBoolean(LEGACY_MERGE, false))
        edit.remove(LEGACY_ORDER).remove(LEGACY_HIDDEN).remove(LEGACY_FEATURED).remove(LEGACY_MERGE).apply()
    }

    private const val ORDER = "zelefin.home-row-order"
    private const val HIDDEN = "zelefin.home-row-hidden"
    private const val MERGE = "zelefin.merge-continue-next-up"
    private const val HERO = "zelefin.home-hero-content"
    private const val LEGACY_ORDER = "home-row-order"
    private const val LEGACY_HIDDEN = "home-row-hidden"
    private const val LEGACY_FEATURED = "home-featured"
    private const val LEGACY_MERGE = "home-merge-continue-next-up"
}

/** Same raw values and default order as iOS `AppTab`. Live TV stays in the order so it syncs with iOS. */
enum class DockTab(val raw: String, val title: String, val appTab: AppTab?) {
    Home("home", "Home", AppTab.Home),
    Movies("movies", "Movies", AppTab.Movies),
    Shows("shows", "Shows", AppTab.Shows),
    LiveTV("liveTV", "Live TV", null),
    Collections("collections", "Collections", AppTab.Collections),
    Library("library", "Library", AppTab.Library),
    Favorites("favorites", "Favorites", AppTab.Favorites);

    val canHide: Boolean get() = this != Home

    /** Android has no Live TV guide yet. */
    val availableOnAndroid: Boolean get() = appTab != null

    companion object {
        const val defaultOrderRaw = "home,movies,shows,liveTV,collections,library,favorites"
        val hiddenByDefault = setOf(LiveTV, Collections, Favorites)

        fun ordered(raw: String): List<DockTab> {
            val seen = LinkedHashSet<DockTab>()
            raw.split(',').forEach { token -> entries.firstOrNull { it.raw == token.trim() }?.let(seen::add) }
            entries.forEach(seen::add)
            return seen.toList()
        }

        fun rawOrder(order: List<DockTab>): String = order.distinct().joinToString(",") { it.raw }
    }
}

/** One slot in the floating dock: a tab, a pinned custom library, or Search. */
data class DockEntry(val tab: AppTab, val title: String, val room: LibraryRoom? = null)

/** Mirrors iOS `PhoneDockLimit`: five slots in one bar. Search always takes the last one. */
object PhoneDockLimit {
    const val CAPACITY = 5

    fun canEnableAnother(enabledTabs: Int, enabledLibraries: Int): Boolean = enabledTabs + enabledLibraries + 1 < CAPACITY
}

/** Tab order, visibility, names, and pinned libraries from Interface settings. The dock reads these directly. */
object TabPreferences {
    var order by mutableStateOf(DockTab.ordered(DockTab.defaultOrderRaw))
        private set
    var hidden by mutableStateOf(DockTab.hiddenByDefault)
        private set
    var showsNames by mutableStateOf(true)
        private set
    var dockLibraryIds by mutableStateOf(emptySet<String>())
        private set

    fun isShown(tab: DockTab): Boolean = !tab.canHide || tab !in hidden

    fun load(context: Context) {
        val prefs = prefs(context)
        order = DockTab.ordered(prefs.getString(ORDER, null) ?: DockTab.defaultOrderRaw)
        hidden = prefs.getString(HIDDEN, null)?.let { raw ->
            raw.split(',').mapNotNull { token -> DockTab.entries.firstOrNull { it.raw == token } }.toSet()
        } ?: DockTab.hiddenByDefault
        showsNames = prefs.getBoolean(NAMES, true)
        dockLibraryIds = prefs.getString(LIBRARIES, "").orEmpty().split(',').filter { it.isNotEmpty() }.toSet()
    }

    fun setOrder(context: Context, next: List<DockTab>) {
        order = DockTab.ordered(DockTab.rawOrder(next))
        prefs(context).edit().putString(ORDER, DockTab.rawOrder(order)).apply()
    }

    fun setShown(context: Context, tab: DockTab, shown: Boolean) {
        if (!tab.canHide) return
        hidden = if (shown) hidden - tab else hidden + tab
        prefs(context).edit().putString(HIDDEN, hidden.map { it.raw }.sorted().joinToString(",")).apply()
    }

    fun setShowsNames(context: Context, on: Boolean) {
        showsNames = on
        prefs(context).edit().putBoolean(NAMES, on).apply()
    }

    fun setLibraryPinned(context: Context, id: String, pinned: Boolean) {
        dockLibraryIds = if (pinned) dockLibraryIds + id else dockLibraryIds - id
        prefs(context).edit().putString(LIBRARIES, dockLibraryIds.sorted().joinToString(",")).apply()
    }

    /** iOS "Reset Tabs": default order and default visibility. */
    fun reset(context: Context) {
        prefs(context).edit().remove(ORDER).remove(HIDDEN).apply()
        load(context)
    }

    internal fun applySyncedOrder(context: Context, raw: String?) {
        val value = raw?.trim()?.takeIf { it.isNotEmpty() } ?: return
        order = DockTab.ordered(value)
        prefs(context).edit().putString(ORDER, DockTab.rawOrder(order)).apply()
    }

    fun pinnable(rooms: List<LibraryRoom>): List<LibraryRoom> =
        rooms.filter { it.kind in setOf(LibraryKind.Other, LibraryKind.YouTube, LibraryKind.HomeVideos, LibraryKind.Photos) }

    fun enabledTabCount(isSiloServer: Boolean): Int = order.count { tab -> tab.availableOnAndroid && isShown(tab) && !(isSiloServer && tab == DockTab.LiveTV) }

    fun enabledLibraryCount(rooms: List<LibraryRoom>): Int = pinnable(rooms).count { it.id in dockLibraryIds }

    /** Enabled tabs in order, then pinned libraries, trimmed to the phone dock. */
    fun dockEntries(rooms: List<LibraryRoom>): List<DockEntry> {
        var room = PhoneDockLimit.CAPACITY - 1
        val result = mutableListOf<DockEntry>()
        order.filter { it.availableOnAndroid && isShown(it) }.forEach { tab ->
            if (room <= 0) return@forEach
            result += DockEntry(tab.appTab ?: return@forEach, tab.title)
            room -= 1
        }
        pinnable(rooms).filter { it.id in dockLibraryIds }.forEach { library ->
            if (room <= 0) return@forEach
            result += DockEntry(AppTab.Room, library.name, library)
            room -= 1
        }
        result += DockEntry(AppTab.Search, "Search")
        return result
    }

    private const val ORDER = "zelefin.tab-order"
    private const val HIDDEN = "zelefin.tab-hidden"
    private const val NAMES = "zelefin.tab-bar-shows-titles"
    private const val LIBRARIES = "zelefin.dock-library-ids"
}

/** Which of the four main pages Zelefin opens to on launch. Local to this device; mirrors iOS `AppTab.startTab`. */
object StartPagePreferences {
    /** The always-available content pages a user can choose as the launch destination. */
    val choices = listOf(DockTab.Home, DockTab.Movies, DockTab.Shows, DockTab.Library)

    var tab by mutableStateOf(DockTab.Home)
        private set

    fun load(context: Context) {
        val raw = prefs(context).getString(KEY, null)
        tab = choices.firstOrNull { it.raw == raw } ?: DockTab.Home
    }

    fun setTab(context: Context, value: DockTab) {
        val next = if (value in choices) value else DockTab.Home
        tab = next
        prefs(context).edit().putString(KEY, next.raw).apply()
    }

    private const val KEY = "zelefin.start-tab"
}

/** Picks the Home hero the same way iOS `HomeLayoutPreferences.hero` does. */
object HomeHero {
    const val LIMIT = 8

    fun ranked(items: List<MediaItem>): List<MediaItem> {
        val withArt = items.filter { it.hasHeroBackdrop }
        val source = withArt.ifEmpty { items }
        return source.filter { !it.isWatched } + source.filter { it.isWatched }
    }

    fun recentlyAdded(movies: List<MediaItem>, shows: List<MediaItem>): List<MediaItem> =
        FeaturedHero.interleave(ranked(movies), ranked(shows), LIMIT)

    fun fromPool(pool: List<MediaItem>): List<MediaItem> = ranked(pool.distinctBy { it.id }).take(LIMIT)
}

fun loadInterfacePreferences(context: Context) {
    AccentPreferences.load(context)
    HomeLayoutPreferences.load(context)
    TabPreferences.load(context)
    StartPagePreferences.load(context)
    GlassPreferences.load(context)
}

private fun prefs(context: Context) = context.getSharedPreferences("zelefin.interface", Context.MODE_PRIVATE)
