package app.zelefin.client

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.UUID

/** Movies, shows, or both — new rows default to movies. */
enum class CustomHomeRowScope(val raw: String, val title: String) {
    Movies("movies", "Movies"),
    Shows("shows", "Shows"),
    Both("both", "Movies & Shows"),
    ;

    companion object {
        fun from(raw: String?): CustomHomeRowScope =
            entries.firstOrNull { it.raw == raw } ?: Movies
    }
}

/** A named Home shelf backed by [CatalogBrowseQuery] filters. */
@Serializable
data class CustomHomeRow(
    val id: String = UUID.randomUUID().toString(),
    val title: String = "Custom Row",
    val scope: String = CustomHomeRowScope.Movies.raw,
    val query: CatalogBrowseQueryDto = CatalogBrowseQueryDto(),
    val enabled: Boolean = true,
) {
    val resolvedScope: CustomHomeRowScope get() = CustomHomeRowScope.from(scope)
    val browseQuery: CatalogBrowseQuery get() = query.toQuery()

    fun withQuery(next: CatalogBrowseQuery): CustomHomeRow = copy(query = CatalogBrowseQueryDto.from(next))
}

/**
 * Serializable mirror of [CatalogBrowseQuery] for prefs / display-preference sync.
 * Kept separate so the live query type stays a plain data class for UI code.
 */
@Serializable
data class CatalogBrowseQueryDto(
    val statuses: List<String> = emptyList(),
    val features: List<String> = emptyList(),
    val videoKinds: List<String> = emptyList(),
    val genres: List<String> = emptyList(),
    val officialRatings: List<String> = emptyList(),
    val tags: List<String> = emptyList(),
    val years: List<Int> = emptyList(),
    val studios: List<String> = emptyList(),
    val audioLanguages: List<String> = emptyList(),
    val subtitleLanguages: List<String> = emptyList(),
    val sort: String = CatalogSortField.Name.name,
    val sortAscending: Boolean = true,
) {
    fun toQuery(): CatalogBrowseQuery = CatalogBrowseQuery(
        statuses = statuses.mapNotNull { raw -> CatalogStatusFilter.entries.firstOrNull { it.name == raw } }.toSet(),
        features = features.mapNotNull { raw -> CatalogFeatureFilter.entries.firstOrNull { it.name == raw } }.toSet(),
        videoKinds = videoKinds.mapNotNull { raw -> CatalogVideoKind.entries.firstOrNull { it.name == raw } }.toSet(),
        genres = genres.toSet(),
        officialRatings = officialRatings.toSet(),
        tags = tags.toSet(),
        years = years.toSet(),
        studios = studios.toSet(),
        audioLanguages = audioLanguages.toSet(),
        subtitleLanguages = subtitleLanguages.toSet(),
        sort = CatalogSortField.entries.firstOrNull { it.name == sort } ?: CatalogSortField.Name,
        sortAscending = sortAscending,
    )

    companion object {
        fun from(query: CatalogBrowseQuery) = CatalogBrowseQueryDto(
            statuses = query.statuses.map { it.name },
            features = query.features.map { it.name },
            videoKinds = query.videoKinds.map { it.name },
            genres = query.genres.toList(),
            officialRatings = query.officialRatings.toList(),
            tags = query.tags.toList(),
            years = query.years.toList(),
            studios = query.studios.toList(),
            audioLanguages = query.audioLanguages.toList(),
            subtitleLanguages = query.subtitleLanguages.toList(),
            sort = query.sort.name,
            sortAscending = query.sortAscending,
        )
    }
}

/** Built-in Home rows plus `custom:<id>` slots, for interleaved order. */
sealed class HomeRowSlot {
    data class BuiltIn(val kind: app.zelefin.client.ui.HomeRowKind) : HomeRowSlot()
    data class Custom(val id: String) : HomeRowSlot()

    val raw: String
        get() = when (this) {
            is BuiltIn -> kind.raw
            is Custom -> "$CUSTOM_PREFIX$id"
        }

    companion object {
        const val CUSTOM_PREFIX = "custom:"

        fun parse(token: String): HomeRowSlot? {
            val trimmed = token.trim()
            if (trimmed.startsWith(CUSTOM_PREFIX)) {
                val id = trimmed.removePrefix(CUSTOM_PREFIX)
                return if (id.isNotEmpty()) Custom(id) else null
            }
            return app.zelefin.client.ui.HomeRowKind.entries.firstOrNull { it.raw == trimmed }?.let(::BuiltIn)
        }

        fun ordered(raw: String, customIds: Set<String>): List<HomeRowSlot> {
            val seen = LinkedHashSet<HomeRowSlot>()
            raw.split(',').forEach { token ->
                val slot = parse(token) ?: return@forEach
                when (slot) {
                    is BuiltIn -> seen.add(slot)
                    is Custom -> if (slot.id in customIds) seen.add(slot)
                }
            }
            app.zelefin.client.ui.HomeRowKind.entries.forEach { seen.add(BuiltIn(it)) }
            customIds.forEach { id ->
                if (seen.none { it is Custom && it.id == id }) seen.add(Custom(id))
            }
            return seen.toList()
        }

        fun rawOrder(slots: List<HomeRowSlot>): String =
            slots.map { it.raw }.distinct().joinToString(",")
    }
}

/** Persists custom Home rows and exposes them to Interface / Home. */
object CustomHomeRows {
    private const val PREFS = "zelefin.interface"
    private const val KEY = "custom-home-rows"
    const val SYNC_KEY = "customHomeRows"

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    var rows by mutableStateOf<List<CustomHomeRow>>(emptyList())
        private set

    fun load(context: Context) {
        rows = decode(prefs(context).getString(KEY, null))
    }

    fun save(context: Context, next: List<CustomHomeRow>) {
        rows = next
        prefs(context).edit().putString(KEY, encode(next)).apply()
    }

    fun add(context: Context, row: CustomHomeRow = CustomHomeRow()): CustomHomeRow {
        save(context, rows + row)
        return row
    }

    fun update(context: Context, row: CustomHomeRow) {
        save(context, rows.map { if (it.id == row.id) row else it })
    }

    fun remove(context: Context, id: String) {
        save(context, rows.filterNot { it.id == id })
    }

    fun row(id: String): CustomHomeRow? = rows.firstOrNull { it.id == id }

    fun encode(list: List<CustomHomeRow> = rows): String = json.encodeToString(list)

    fun decode(raw: String?): List<CustomHomeRow> {
        if (raw.isNullOrBlank()) return emptyList()
        return runCatching { json.decodeFromString<List<CustomHomeRow>>(raw) }.getOrElse { emptyList() }
    }

    fun applySynced(context: Context, raw: String?) {
        if (raw == null) return
        save(context, decode(raw))
    }

    fun filterSummary(row: CustomHomeRow): String {
        val query = row.browseQuery
        val parts = buildList {
            add(row.resolvedScope.title)
            if (query.activeFilterCount > 0) add("${query.activeFilterCount} filters")
            if (query.sort != CatalogSortField.Name || !query.sortAscending) {
                add(query.sort.title + if (query.sortAscending) "" else " ↓")
            }
        }
        return parts.joinToString(" · ")
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
