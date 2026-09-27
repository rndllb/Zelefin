package app.zelefin.core

object PlaybackResumePolicy {
    const val THRESHOLD: Double = 5.0

    fun clientStartPosition(
        method: PlaybackMethod,
        startTime: Double,
        clientOwnsPlayhead: Boolean = false,
    ): Double? {
        if (startTime <= THRESHOLD) return null
        if (method != PlaybackMethod.DirectPlay && !clientOwnsPlayhead) return null
        return startTime
    }

    fun reportStartPosition(playhead: Double, plannedStart: Double): Double =
        if (plannedStart > THRESHOLD) maxOf(playhead, plannedStart) else playhead

    fun needsDeferredSeek(
        method: PlaybackMethod,
        playhead: Double,
        plannedStart: Double,
        clientOwnsPlayhead: Boolean = false,
    ): Boolean = (method == PlaybackMethod.DirectPlay || clientOwnsPlayhead) &&
        plannedStart > THRESHOLD &&
        playhead <= THRESHOLD
}

object StreamResumeUrl {
    /**
     * Jellyfin 12.1 copies `StartTimeTicks` from the playlist URL onto the fMP4 init and every
     * segment URL, then rejects those segments with 400 ("StartTimeTicks is not allowed").
     * HLS must open at t=0 and let the player seek to the resume point.
     */
    fun strippingStartTimeTicks(url: String): String {
        if (!url.contains('?')) return url
        val path = url.substringBefore('?')
        val params = url.substringAfter('?').split("&")
        val kept = params.filterNot { it.substringBefore("=").equals("StartTimeTicks", ignoreCase = true) }
        if (kept.size == params.size) return url
        return if (kept.isEmpty()) path else "$path?${kept.joinToString("&")}"
    }
}

object StreamUrlBuilder {
    fun directPlayQuery(sourceId: String?, token: String?, liveStreamId: String? = null): String {
        val parts = mutableListOf("static=true")
        if (!sourceId.isNullOrEmpty()) parts += "mediaSourceId=$sourceId"
        if (!liveStreamId.isNullOrEmpty()) parts += "liveStreamId=$liveStreamId"
        if (!token.isNullOrEmpty()) parts += "api_key=$token"
        return parts.joinToString("&")
    }

    fun directPlay(base: String, itemId: String, sourceId: String?, token: String?, container: String): String? {
        val query = directPlayQuery(sourceId, token)
        return ServerUrl.resolve(base, "/Videos/$itemId/stream.$container?$query")
    }

    fun transcode(base: String, transcodingPath: String, token: String?): String? =
        ServerUrl.resolve(base, transcodingPath, token)
}

object PlaybackEpisodeAdvance {
    fun next(after: MediaItem, episodes: List<MediaItem>): MediaItem? {
        if (after.kind != MediaKind.Episode) return null
        val index = episodes.indexOfFirst { it.id == after.id }
        if (index >= 0) return episodes.getOrNull(index + 1)
        val season = after.seasonIndex ?: return null
        val episode = after.episodeIndex ?: return null
        return episodes.firstOrNull { candidate ->
            val candidateSeason = candidate.seasonIndex ?: Int.MIN_VALUE
            val candidateEpisode = candidate.episodeIndex ?: Int.MIN_VALUE
            candidateSeason > season || (candidateSeason == season && candidateEpisode > episode)
        }
    }
}

object FeaturedHero {
    fun interleave(movies: List<MediaItem>, shows: List<MediaItem>, limit: Int = 8): List<MediaItem> {
        val picked = mutableListOf<MediaItem>()
        var movieIndex = 0
        var showIndex = 0
        while (picked.size < limit && (movieIndex < movies.size || showIndex < shows.size)) {
            if (movieIndex < movies.size) picked += movies[movieIndex++]
            if (picked.size >= limit) break
            if (showIndex < shows.size) picked += shows[showIndex++]
        }
        return picked
    }
}
