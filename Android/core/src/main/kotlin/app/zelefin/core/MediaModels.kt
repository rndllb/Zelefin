package app.zelefin.core

import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.round
import kotlinx.serialization.Serializable

object TickClock {
    const val TICKS_PER_SECOND: Long = 10_000_000L

    fun seconds(ticks: Long): Double = ticks.toDouble() / TICKS_PER_SECOND.toDouble()

    fun ticks(seconds: Double): Long = round(seconds * TICKS_PER_SECOND.toDouble()).toLong()
}

@Serializable
data class MediaItem(
    val id: String,
    val name: String,
    val kind: MediaKind,
    val overview: String? = null,
    val year: Int? = null,
    val runtime: Double? = null,
    val officialRating: String? = null,
    val genres: List<String> = emptyList(),
    val seriesName: String? = null,
    val seasonIndex: Int? = null,
    val episodeIndex: Int? = null,
    val playbackPosition: Double = 0.0,
    val unplayedCount: Int? = null,
    val isPlayed: Boolean = false,
    val primaryImageTag: String? = null,
    val thumbImageTag: String? = null,
    val backdropImageTag: String? = null,
    val backdropImageTags: List<String> = emptyList(),
    val logoImageTag: String? = null,
    val parentBackdropItemId: String? = null,
    val parentThumbItemId: String? = null,
    val parentThumbImageTag: String? = null,
    val parentLogoItemId: String? = null,
    val parentLogoImageTag: String? = null,
    val seriesThumbImageTag: String? = null,
    val seriesId: String? = null,
    val imageItemId: String? = null,
    val queueKind: PlaybackQueueKind = PlaybackQueueKind.Resume,
    val videoRange: VideoRange = VideoRange.Sdr,
    val audioFormat: AudioFormat = AudioFormat.Unknown,
    val communityRating: Double? = null,
    val tmdbId: Int? = null,
    val criticRating: Double? = null,
    val videoResolution: VideoResolution = VideoResolution.Unknown,
    val hasClosedCaptions: Boolean = false,
    val hasAudioDescription: Boolean = false,
    val isFavorite: Boolean = false,
    val posterUrl: String? = null,
    val backdropUrl: String? = null,
    val logoUrl: String? = null,
    val mediaSourceId: String? = null,
    val people: List<CreditPerson> = emptyList(),
) {
    val progress: Double
        get() {
            val length = runtime ?: return 0.0
            if (length <= 0) return 0.0
            return min(1.0, max(0.0, playbackPosition / length))
        }

    val isWatched: Boolean get() = isPlayed || progress >= 0.98

    val artworkItemId: String get() = imageItemId ?: id

    val hasHeroBackdrop: Boolean
        get() = backdropUrl != null || backdropImageTag != null || backdropImageTags.isNotEmpty() || parentBackdropItemId != null

    val heroMetadataLine: String
        get() = (listOf(kindLabel) + genres.take(2)).joinToString("  ·  ")

    val showsResumeProgress: Boolean
        get() = progress > 0.02 && progress < 0.98

    val continueWatchingTitle: String
        get() = if (kind == MediaKind.Episode) seriesName ?: name else name

    val episodeLabel: String?
        get() {
            if (kind != MediaKind.Episode) return null
            if (seasonIndex == null || episodeIndex == null) return seriesName
            val remaining = runtime?.let { " · ${minutesLabel(max(0.0, it - playbackPosition), floor = true)}" }.orEmpty()
            return "S$seasonIndex, E$episodeIndex$remaining"
        }

    val continueWatchingCaption: String?
        get() {
            val remaining = runtime?.let { minutesLabel(max(0.0, it - playbackPosition), floor = true) }
            if (kind == MediaKind.Episode && seasonIndex != null && episodeIndex != null) {
                return if (remaining != null) "S$seasonIndex, E$episodeIndex · $remaining" else "S$seasonIndex, E$episodeIndex"
            }
            return remaining
        }

    val runtimeLabel: String? get() = runtime?.takeIf { it > 0 }?.let { minutesLabel(it) }

    val playActionDurationLabel: String?
        get() {
            if (playbackPosition > 5) {
                val length = runtime
                if (length != null && length > 0) {
                    val remaining = max(0.0, length - playbackPosition)
                    if (remaining > 0) return minutesLabel(remaining, floor = true)
                }
            }
            val length = runtime ?: return null
            if (length <= 0) return null
            return minutesLabel(length)
        }

    val ageGateLabel: String?
        get() {
            val rating = officialRating ?: return null
            val compact = rating.uppercase().filter { !it.isWhitespace() }
            return when {
                compact.contains("NC-17") || compact == "X" -> "18+"
                compact == "R" || compact.contains("TV-MA") -> "17+"
                compact.contains("PG-13") || compact.contains("TV-14") -> "13+"
                compact.contains("TV-Y7") || compact == "PG" || compact.contains("TV-PG") -> "7+"
                compact == "G" || compact.startsWith("TV-Y") || compact.contains("TV-G") -> "All"
                compact.endsWith("+") -> rating
                else -> null
            }
        }

    val kindLabel: String
        get() = when (kind) {
            MediaKind.Movie -> "Movie"
            MediaKind.Series, MediaKind.Season, MediaKind.Episode -> "Show"
            MediaKind.Collection -> "Collection"
            MediaKind.Genre -> "Genre"
            MediaKind.Playlist -> "Playlist"
            MediaKind.LiveTV -> "Live TV"
            MediaKind.Book -> "Book"
            MediaKind.Photo -> "Photo"
            MediaKind.Unknown -> "Title"
        }

    val seriesDetailItemId: String?
        get() {
            if (kind != MediaKind.Episode && kind != MediaKind.Season) return null
            val show = seriesId ?: return null
            return show.ifEmpty { null }
        }

    val seasonMenuTitle: String
        get() {
            val number = if (kind == MediaKind.Season) seasonIndex ?: episodeIndex else seasonIndex
            return when (number) {
                null -> name
                0 -> "Specials"
                else -> "Season $number"
            }
        }

    companion object {
        fun heroPlaybackItem(title: MediaItem, episodes: List<MediaItem>): MediaItem {
            if (title.kind != MediaKind.Series) return title
            episodes.firstOrNull { !it.isWatched && it.playbackPosition > 5 }?.let { return it }
            episodes.firstOrNull { !it.isWatched }?.let { return it }
            return episodes.firstOrNull() ?: title
        }

        fun minutesLabel(interval: Double, floor: Boolean = false): String {
            val divided = interval / 60.0
            val rounded = if (floor) floor(divided) else round(divided)
            val totalMinutes = max(0, rounded.toInt())
            if (totalMinutes < 60) return "${max(1, totalMinutes)}m"
            val hours = totalMinutes / 60
            val minutes = totalMinutes % 60
            return if (minutes == 0) "${hours}h" else "${hours}h ${minutes}m"
        }

        fun orderedEpisodes(episodes: List<MediaItem>): List<MediaItem> =
            episodes.sortedWith(compareBy({ it.seasonIndex ?: Int.MAX_VALUE }, { it.episodeIndex ?: Int.MAX_VALUE }))
    }
}

@Serializable
data class CreditPerson(
    val id: String,
    val name: String,
    val roleLabel: String,
    val imageTag: String? = null,
    val imageUrl: String? = null,
    val overview: String? = null,
    val birthYear: Int? = null,
)

@Serializable
data class HomeSection(
    val id: String,
    val title: String,
    val style: HomeRowStyle = HomeRowStyle.Portrait,
    val items: List<MediaItem> = emptyList(),
)

@Serializable
data class HomeFeed(
    val featured: List<MediaItem> = emptyList(),
    val continueWatching: List<MediaItem> = emptyList(),
    val nextUp: List<MediaItem> = emptyList(),
    val recentMovies: List<MediaItem> = emptyList(),
    val recentShows: List<MediaItem> = emptyList(),
    val upcoming: List<MediaItem> = emptyList(),
    val recommendations: List<HomeSection> = emptyList(),
    val collections: List<MediaItem> = emptyList(),
    val genres: List<MediaItem> = emptyList(),
    val recentlyWatched: List<MediaItem> = emptyList(),
)

@Serializable
data class TitleMoreRow(val label: String, val value: String)

@Serializable
data class TitleMoreLink(val name: String, val url: String)

@Serializable
data class TitleMoreInfo(
    val information: List<TitleMoreRow> = emptyList(),
    val languages: List<TitleMoreRow> = emptyList(),
    val file: List<TitleMoreRow> = emptyList(),
    val links: List<TitleMoreLink> = emptyList(),
    val accessibilityNote: String? = null,
) {
    val hasDetails: Boolean
        get() = information.isNotEmpty() || languages.isNotEmpty() || file.isNotEmpty() || links.isNotEmpty()

    companion object {
        fun fromItem(item: MediaItem): TitleMoreInfo {
            val rows = buildList {
                item.year?.let { add(TitleMoreRow("Released", it.toString())) }
                item.runtimeLabel?.let { add(TitleMoreRow("Run Time", it)) }
                item.officialRating?.takeIf { it.isNotBlank() }?.let { add(TitleMoreRow("Rated", it)) }
                if (item.genres.isNotEmpty()) add(TitleMoreRow("Genres", item.genres.joinToString(", ")))
            }
            return TitleMoreInfo(information = rows)
        }
    }
}

@Serializable
data class TitleCollection(
    val collection: MediaItem,
    val items: List<MediaItem>,
)

@Serializable
data class TitleDetail(
    val item: MediaItem,
    val seasons: List<MediaItem> = emptyList(),
    val episodes: List<MediaItem> = emptyList(),
    val related: List<MediaItem> = emptyList(),
    val trailers: List<TitleTrailer> = emptyList(),
    val moreInfo: TitleMoreInfo = TitleMoreInfo(),
    val collections: List<TitleCollection> = emptyList(),
)

@Serializable
data class TitleTrailer(
    val id: String,
    val title: String,
    val caption: String,
    val watchUrl: String? = null,
    val thumbnailUrl: String? = null,
    val localItem: MediaItem? = null,
)

data class PlaybackPlan(
    val item: MediaItem,
    val streamUrl: String,
    val playSessionId: String?,
    val mediaSourceId: String?,
    val method: PlaybackMethod,
    val container: String?,
    val videoCodec: String?,
    val startTimeSeconds: Double,
    val headers: Map<String, String> = emptyMap(),
    val clientOwnsPlayhead: Boolean = false,
    val chapters: List<PlaybackChapter> = emptyList(),
    val externalSubtitles: List<ExternalSubtitle> = emptyList(),
    /** Bitrate cap this stream was requested at; null for local files. */
    val appliedBitrate: Int? = null,
    /** Source file bitrate when the server reports it. */
    val sourceBitrate: Int? = null,
    /** Audio stream Jellyfin chose for this user; null leaves it to the player. */
    val audioChoice: TrackChoice? = null,
    /** Subtitle stream Jellyfin chose for this user. */
    val subtitleChoice: TrackChoice? = null,
    /** True when the server resolved the user's subtitle settings to no subtitles at all. */
    val subtitlesOff: Boolean = false,
)

/**
 * A stream Jellyfin's user settings (preferred language, play default audio track, subtitle
 * mode) selected. The player cannot see Jellyfin's stream indices, so this carries the track's
 * position among streams of its type plus its language, and the sideload id for a subtitle file.
 */
data class TrackChoice(
    val ordinal: Int,
    val language: String?,
    val externalId: String? = null,
)

data class PlaybackChapter(val startSeconds: Double, val name: String)

/** A subtitle file the server delivers beside the stream (saved from Open Subtitles, or extracted for a transcode). */
data class ExternalSubtitle(
    val url: String,
    val mimeType: String,
    val language: String?,
    val title: String,
    /** Stable id handed to the player so the chosen file can be found among its text tracks. */
    val id: String? = null,
)
