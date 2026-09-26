package app.zelefin.core

data class JellyfinStreamSnapshot(
    val type: String,
    val videoRange: String? = null,
    val codec: String? = null,
    val channels: Int? = null,
    val width: Int? = null,
    val height: Int? = null,
    val isDefault: Boolean = false,
    val title: String? = null,
    val displayTitle: String? = null,
    val channelLayout: String? = null,
)

data class JellyfinItemSnapshot(
    val id: String? = null,
    val name: String? = null,
    val type: String? = null,
    val overview: String? = null,
    val productionYear: Int? = null,
    val runTimeTicks: Long? = null,
    val officialRating: String? = null,
    val genres: List<String> = emptyList(),
    val seriesName: String? = null,
    val seriesId: String? = null,
    val indexNumber: Int? = null,
    val parentIndexNumber: Int? = null,
    val playbackPositionTicks: Long = 0,
    val unplayedItemCount: Int? = null,
    val played: Boolean = false,
    val favorite: Boolean = false,
    val primaryImageTag: String? = null,
    val imageTags: Map<String, String> = emptyMap(),
    val backdropImageTags: List<String> = emptyList(),
    val parentBackdropItemId: String? = null,
    val parentThumbItemId: String? = null,
    val parentThumbImageTag: String? = null,
    val parentLogoItemId: String? = null,
    val parentLogoImageTag: String? = null,
    val seriesThumbImageTag: String? = null,
    val parentPrimaryImageItemId: String? = null,
    val parentPrimaryImageTag: String? = null,
    val seriesPrimaryImageTag: String? = null,
    val communityRating: Double? = null,
    val criticRating: Double? = null,
    val providerIds: Map<String, String> = emptyMap(),
    val people: List<CreditPerson> = emptyList(),
    val streams: List<JellyfinStreamSnapshot> = emptyList(),
    val width: Int? = null,
    val height: Int? = null,
)

object ItemMapper {
    fun mediaItem(snapshot: JellyfinItemSnapshot, queueKind: PlaybackQueueKind = PlaybackQueueKind.Resume): MediaItem? {
        val id = snapshot.id ?: return null
        val name = snapshot.name ?: return null
        val kind = kind(snapshot.type) ?: return null
        val ownPrimary = snapshot.primaryImageTag ?: snapshot.imageTags["Primary"] ?: snapshot.imageTags["primary"]
        val borrowedStill = kind == MediaKind.LiveTV && ownPrimary == null
        val stillItemId = if (borrowedStill) snapshot.parentPrimaryImageItemId ?: snapshot.seriesId else null
        val stillTag = ownPrimary ?: if (borrowedStill) {
            snapshot.parentPrimaryImageTag ?: snapshot.seriesPrimaryImageTag
        } else {
            null
        }
        val width = snapshot.width ?: snapshot.streams.firstOrNull { it.type.equals("Video", true) }?.width
        val height = snapshot.height ?: snapshot.streams.firstOrNull { it.type.equals("Video", true) }?.height
        return MediaItem(
            id = id,
            name = name,
            kind = kind,
            overview = snapshot.overview?.trim()?.ifEmpty { null },
            year = snapshot.productionYear,
            runtime = snapshot.runTimeTicks?.let(TickClock::seconds),
            officialRating = snapshot.officialRating,
            genres = snapshot.genres,
            seriesName = snapshot.seriesName,
            seasonIndex = if (kind == MediaKind.Season) snapshot.indexNumber else snapshot.parentIndexNumber,
            episodeIndex = if (kind == MediaKind.Episode) snapshot.indexNumber else null,
            playbackPosition = TickClock.seconds(snapshot.playbackPositionTicks),
            unplayedCount = snapshot.unplayedItemCount,
            isPlayed = snapshot.played,
            primaryImageTag = stillTag,
            thumbImageTag = snapshot.imageTags["Thumb"] ?: snapshot.imageTags["Screenshot"],
            backdropImageTag = snapshot.backdropImageTags.firstOrNull(),
            backdropImageTags = snapshot.backdropImageTags,
            logoImageTag = snapshot.imageTags["Logo"],
            parentBackdropItemId = snapshot.parentBackdropItemId,
            parentThumbItemId = snapshot.parentThumbItemId,
            parentThumbImageTag = snapshot.parentThumbImageTag,
            parentLogoItemId = snapshot.parentLogoItemId,
            parentLogoImageTag = snapshot.parentLogoImageTag,
            seriesThumbImageTag = snapshot.seriesThumbImageTag,
            seriesId = snapshot.seriesId,
            imageItemId = stillItemId,
            queueKind = queueKind,
            videoRange = videoRange(snapshot.streams),
            audioFormat = audioFormat(snapshot.streams),
            communityRating = snapshot.communityRating,
            tmdbId = tmdbId(snapshot.providerIds),
            criticRating = snapshot.criticRating,
            videoResolution = videoResolution(width, height),
            hasClosedCaptions = snapshot.streams.any { it.type.equals("Subtitle", true) },
            hasAudioDescription = hasAudioDescription(snapshot.streams),
            isFavorite = snapshot.favorite,
            people = snapshot.people,
        )
    }

    fun kind(type: String?): MediaKind? = when (type?.lowercase()) {
        "movie" -> MediaKind.Movie
        "series" -> MediaKind.Series
        "season" -> MediaKind.Season
        "episode" -> MediaKind.Episode
        "boxset" -> MediaKind.Collection
        "genre" -> MediaKind.Genre
        "playlist" -> MediaKind.Playlist
        "tvchannel", "livetvprogram", "tvprogram" -> MediaKind.LiveTV
        "recording", "video" -> MediaKind.Movie
        "book" -> MediaKind.Book
        "photo" -> MediaKind.Photo
        "photoalbum" -> MediaKind.Collection
        "collectionfolder", "userview", "userrootfolder", "aggregatefolder", "basepluginfolder" -> null
        null -> null
        else -> MediaKind.Unknown
    }

    fun tmdbId(providerIds: Map<String, String>): Int? {
        val raw = providerIds.entries.firstOrNull { it.key.equals("Tmdb", true) }?.value ?: return null
        return raw.trim().toIntOrNull()
    }

    private fun videoRange(streams: List<JellyfinStreamSnapshot>): VideoRange {
        val raw = streams.firstOrNull { it.type.equals("Video", true) }?.videoRange?.lowercase().orEmpty()
        return when {
            raw.contains("dolbyvision") || raw.contains("dovi") -> VideoRange.DolbyVision
            raw.contains("hdr10+") || raw.contains("hdr10plus") -> VideoRange.Hdr10Plus
            raw.contains("hlg") -> VideoRange.Hlg
            raw.contains("hdr") -> VideoRange.Hdr10
            else -> VideoRange.Sdr
        }
    }

    private fun audioFormat(streams: List<JellyfinStreamSnapshot>): AudioFormat {
        val audio = streams.filter { it.type.equals("Audio", true) }
        val joined = audio.joinToString(" ") { stream ->
            listOfNotNull(stream.codec, stream.channelLayout, stream.title, stream.displayTitle).joinToString(" ")
        }.lowercase()
        if (joined.contains("atmos") || joined.contains("joc")) return AudioFormat.Atmos
        if (audio.any { (it.channels ?: 0) >= 6 }) return AudioFormat.Surround
        if (audio.isEmpty()) return AudioFormat.Unknown
        return AudioFormat.Stereo
    }

    private fun hasAudioDescription(streams: List<JellyfinStreamSnapshot>): Boolean =
        streams.any { stream ->
            stream.type.equals("Audio", true) &&
                listOfNotNull(stream.title, stream.displayTitle).joinToString(" ").lowercase().let { blob ->
                    blob.contains("audio description") || blob.contains("described") ||
                        blob.contains("ad -") || blob.startsWith("ad ") || blob.contains(" visually")
                }
        }

    private fun videoResolution(width: Int?, height: Int?): VideoResolution {
        val edge = maxOf(width ?: 0, height ?: 0)
        return when {
            edge >= 3800 -> VideoResolution.FourK
            edge >= 1200 -> VideoResolution.Hd
            edge > 0 -> VideoResolution.Sd
            else -> VideoResolution.Unknown
        }
    }
}

object ArtworkUrls {
    const val POSTER_MAX_HEIGHT = 420

    fun requestsPrimary(kind: MediaKind, tag: String?): Boolean =
        tag != null || kind == MediaKind.Collection || kind == MediaKind.Photo ||
            kind == MediaKind.Playlist || kind == MediaKind.LiveTV

    fun primary(base: String, item: MediaItem, token: String?, maxHeight: Int = POSTER_MAX_HEIGHT): String? {
        if (!requestsPrimary(item.kind, item.primaryImageTag)) return null
        return image(base, item.artworkItemId, "Primary", item.primaryImageTag, token, maxHeight = maxHeight, format = "jpg")
    }

    fun backdrop(base: String, item: MediaItem, token: String?, maxWidth: Int, allowPosterFallback: Boolean = true): String? {
        if (item.backdropUrl != null) return item.backdropUrl
        if (item.backdropImageTag != null) {
            return image(base, item.artworkItemId, "Backdrop", item.backdropImageTag, token, maxWidth = maxWidth, format = "jpg")
        }
        if (item.parentBackdropItemId != null) {
            return image(base, item.parentBackdropItemId, "Backdrop", null, token, maxWidth = maxWidth, format = "jpg")
        }
        if (allowPosterFallback) return item.posterUrl ?: primary(base, item, token, maxHeight = maxWidth)
        return null
    }

    fun thumb(base: String, item: MediaItem, token: String?, maxWidth: Int): String? {
        if (item.thumbImageTag != null) {
            return image(base, item.artworkItemId, "Thumb", item.thumbImageTag, token, maxWidth = maxWidth, format = "jpg")
        }
        if (item.parentThumbItemId != null) {
            return image(base, item.parentThumbItemId, "Thumb", item.parentThumbImageTag, token, maxWidth = maxWidth, format = "jpg")
        }
        if (item.seriesId != null && item.seriesThumbImageTag != null) {
            return image(base, item.seriesId, "Thumb", item.seriesThumbImageTag, token, maxWidth = maxWidth, format = "jpg")
        }
        // An untagged Thumb 404s for most episodes and series, and a failed request
        // hides the backdrop or poster that does exist.
        return null
    }

    fun person(base: String, person: CreditPerson, token: String?): String? {
        person.imageUrl?.let { return it }
        val tag = person.imageTag ?: return null
        return image(base, person.id, "Primary", tag, token, maxHeight = 360, format = "jpg")
    }

    fun logo(base: String, item: MediaItem, token: String?, maxHeight: Int = 240): String? {
        if (item.logoUrl != null) return item.logoUrl
        if (item.logoImageTag != null) {
            return image(base, item.id, "Logo", item.logoImageTag, token, maxHeight = maxHeight, format = "png")
        }
        if (item.parentLogoItemId != null) {
            return image(base, item.parentLogoItemId, "Logo", item.parentLogoImageTag, token, maxHeight = maxHeight, format = "png")
        }
        return null
    }

    fun image(
        base: String,
        itemId: String,
        type: String,
        tag: String?,
        token: String?,
        maxHeight: Int? = null,
        maxWidth: Int? = null,
        format: String? = null,
    ): String? {
        val query = mutableListOf("quality=90")
        if (format != null) query += "format=$format"
        if (maxHeight != null) query += "maxHeight=$maxHeight"
        if (maxWidth != null) query += "maxWidth=$maxWidth"
        if (!tag.isNullOrEmpty()) query += "tag=$tag"
        if (!token.isNullOrEmpty()) query += "api_key=$token"
        return ServerUrl.resolve(base, "/Items/$itemId/Images/$type?${query.joinToString("&")}")
    }
}
