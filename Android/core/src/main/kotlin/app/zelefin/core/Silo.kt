package app.zelefin.core

import java.net.URI
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put

object SiloJson {
    val parser: Json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    fun parse(text: String): JsonElement = parser.parseToJsonElement(text)

    fun objectOrNull(text: String): JsonObject? = runCatching { parse(text).jsonObject }.getOrNull()
}

fun JsonObject.str(key: String): String? {
    val value = this[key] ?: return null
    val primitive = value as? JsonPrimitive ?: return null
    if (primitive.isString) return primitive.content.trim().ifEmpty { null }
    return primitive.contentOrNull?.trim()?.ifEmpty { null }
}

fun JsonObject.int(key: String): Int? {
    val value = this[key] as? JsonPrimitive ?: return null
    return value.intOrNull ?: value.longOrNull?.toInt() ?: value.contentOrNull?.trim()?.toIntOrNull()
}

fun JsonObject.dbl(key: String): Double? {
    val value = this[key] as? JsonPrimitive ?: return null
    return value.doubleOrNull ?: value.contentOrNull?.trim()?.toDoubleOrNull()
}

fun JsonObject.bool(key: String): Boolean? {
    val value = this[key] as? JsonPrimitive ?: return null
    value.booleanOrNull?.let { return it }
    return when (value.contentOrNull?.trim()?.lowercase()) {
        "true", "yes", "1" -> true
        "false", "no", "0" -> false
        else -> value.intOrNull?.let { it != 0 }
    }
}

fun JsonObject.obj(key: String): JsonObject? = this[key] as? JsonObject

fun JsonObject.arr(key: String): JsonArray? = this[key] as? JsonArray

fun JsonObject.objects(key: String): List<JsonObject> =
    (this[key] as? JsonArray)?.mapNotNull { it as? JsonObject }.orEmpty()

object SiloMediaUrl {
    fun resolve(base: String, raw: String): String? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty() || trimmed.startsWith("//")) return null
        if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
            val rewritten = ServerUrl.rewriteIfNeeded(trimmed, base)
            return pinStream(rewritten, base)
        }
        var relative = if (trimmed.startsWith("/")) trimmed else "/$trimmed"
        if (relative.startsWith("/stream/v3/")) {
            relative = "/api/v1/stream/" + relative.removePrefix("/stream/v3/")
        } else if (!relative.startsWith("/api/")) {
            relative = "/api/v1$relative"
        }
        return ServerUrl.join(base, relative)
    }

    fun pinStream(url: String, apiBase: String): String {
        val remote = runCatching { URI(url) }.getOrNull() ?: return url
        val base = runCatching { URI(apiBase) }.getOrNull() ?: return url
        val host = remote.host ?: return url
        val apiHost = base.host ?: return url
        if (!host.equals(apiHost, ignoreCase = true)) return url
        val prefix = "/stream/v3/"
        if (!remote.path.startsWith(prefix)) return url
        val rest = remote.path.removePrefix(prefix)
        var apiPath = base.path.orEmpty()
        while (apiPath.length > 1 && apiPath.endsWith("/")) apiPath = apiPath.dropLast(1)
        if (apiPath == "/") apiPath = ""
        val port = if (base.port != -1) ":${base.port}" else ""
        val query = if (remote.rawQuery.isNullOrEmpty()) "" else "?${remote.rawQuery}"
        return "${base.scheme}://$apiHost$port$apiPath/api/v1/stream/$rest$query"
    }
}

object SiloMapper {
    fun health(json: JsonObject): Pair<Boolean, String>? {
        val status = json.str("status")?.lowercase() ?: return null
        val ready = status == "ok" || status == "healthy" || status == "ready"
        if (!ready) return null
        val name = json.str("server_name")?.ifEmpty { null } ?: "Silo"
        val version = json.str("version") ?: "Silo"
        return true to "$name|$version"
    }

    fun serverName(json: JsonObject): String = json.str("server_name")?.ifEmpty { null } ?: "Silo"

    fun version(json: JsonObject): String = json.str("version") ?: "Silo"

    fun auth(json: JsonObject): SiloAuth? {
        val token = json.str("access_token") ?: return null
        val user = json.obj("user") ?: return null
        val id = user.int("id")?.toString() ?: user.str("id") ?: return null
        val name = user.str("username") ?: return null
        return SiloAuth(
            accessToken = token,
            refreshToken = json.str("refresh_token"),
            userId = id,
            userName = name,
            role = user.str("role"),
        )
    }

    fun profiles(json: JsonElement, base: String): List<HouseholdProfile> {
        val array = when (json) {
            is JsonArray -> json
            is JsonObject -> json.arr("profiles") ?: json.arr("items") ?: return emptyList()
            else -> return emptyList()
        }
        return array.mapNotNull { element ->
            val obj = element as? JsonObject ?: return@mapNotNull null
            val id = obj.str("id") ?: obj.int("id")?.toString() ?: return@mapNotNull null
            val name = obj.str("name") ?: "Profile"
            val rawAvatar = obj.str("avatar_url")
            HouseholdProfile(
                id = id,
                name = name,
                avatarUrl = rawAvatar?.let { SiloMediaUrl.resolve(base, it) },
                hasPin = obj.bool("has_pin") == true,
                isChild = obj.bool("is_child") == true,
                isPrimary = obj.bool("is_primary") == true,
            )
        }
    }

    fun catalogItems(json: JsonElement, base: String): List<MediaItem> {
        val array = when (json) {
            is JsonArray -> json
            is JsonObject -> json.arr("items") ?: json.arr("results") ?: json.arr("entries") ?: return emptyList()
            else -> return emptyList()
        }
        return array.mapNotNull { (it as? JsonObject)?.let { obj -> mediaItem(obj, base) } }
    }

    fun mediaItem(json: JsonObject, base: String, queueKind: PlaybackQueueKind = PlaybackQueueKind.Resume): MediaItem? {
        val id = json.str("content_id") ?: json.str("id") ?: return null
        val name = json.str("title") ?: json.str("name") ?: return null
        val type = json.str("type")
        val user = json.obj("user_state") ?: json.obj("userState")
        val position = user?.dbl("seconds") ?: user?.dbl("position") ?: json.dbl("position_seconds") ?: 0.0
        val poster = json.str("poster_url")?.let { SiloMediaUrl.resolve(base, it) }
        val backdrop = json.str("backdrop_url")?.let { SiloMediaUrl.resolve(base, it) }
        val logo = json.str("logo_url")?.let { SiloMediaUrl.resolve(base, it) }
        val fileId = fileIds(json).firstOrNull()
        val overlay = json.obj("overlay_summary")
        return MediaItem(
            id = id,
            name = name,
            kind = kind(type),
            overview = json.str("overview"),
            year = json.int("year"),
            runtime = json.int("runtime")?.times(60.0) ?: json.dbl("duration_seconds"),
            officialRating = json.str("content_rating"),
            genres = json.arr("genres")?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }.orEmpty(),
            seriesName = json.str("series_title"),
            seasonIndex = json.int("season_number"),
            episodeIndex = json.int("episode_number"),
            playbackPosition = position,
            isPlayed = user?.bool("watched") == true,
            seriesId = json.str("series_id"),
            queueKind = queueKind,
            videoRange = videoRange(overlay?.str("hdr")),
            audioFormat = audioFormat(overlay?.str("audio")),
            videoResolution = resolution(overlay?.str("resolution")),
            communityRating = json.dbl("rating_imdb") ?: json.dbl("rating_tmdb"),
            criticRating = json.dbl("rating_rt"),
            isFavorite = user?.bool("favorite") == true || user?.bool("is_favorite") == true,
            posterUrl = poster,
            backdropUrl = backdrop,
            logoUrl = logo,
            mediaSourceId = fileId?.toString(),
            people = credits(json),
        )
    }

    fun trailers(json: JsonObject): List<TitleTrailer> {
        val videos = json.arr("videos") ?: return emptyList()
        return videos.mapNotNull { element ->
            val video = element as? JsonObject ?: return@mapNotNull null
            val key = video.str("site_key")?.trim().orEmpty().ifEmpty { video.str("key")?.trim().orEmpty() }
            if (key.isEmpty()) return@mapNotNull null
            val site = video.str("site").orEmpty().lowercase()
            val title = video.str("name")?.trim()?.ifEmpty { null } ?: "Trailer"
            when {
                site.contains("youtube") -> TrailerLinks.youtube(key, title)
                site.contains("vimeo") -> TrailerLinks.remote("https://vimeo.com/$key", title)
                else -> TrailerLinks.remote(key, title)
            }
        }.sortedBy { trailerRank(it.title) }
    }

    private fun trailerRank(title: String): Int {
        val name = title.lowercase()
        return when {
            name.contains("official") && name.contains("trailer") -> 0
            name.contains("trailer") -> 1
            name.contains("teaser") -> 2
            else -> 3
        }
    }

    fun home(json: JsonElement, base: String): HomeFeed {
        val root = json as? JsonObject ?: return HomeFeed()
        val sections = root.arr("sections") ?: root.arr("items") ?: return HomeFeed()
        val featured = mutableListOf<MediaItem>()
        val resume = mutableListOf<MediaItem>()
        val nextUp = mutableListOf<MediaItem>()
        val movies = mutableListOf<MediaItem>()
        val shows = mutableListOf<MediaItem>()
        for (element in sections) {
            val section = element as? JsonObject ?: continue
            val type = (section.str("section_type") ?: section.str("id") ?: "").replace('-', '_').lowercase()
            val featuredFlag = section.bool("featured") == true
            val entries = (section.arr("items") ?: JsonArray(emptyList())).mapNotNull { item ->
                (item as? JsonObject)?.let { mediaItem(it, base, queueKind(type)) }
            }
            when {
                featuredFlag || type.contains("featured") || type.contains("hero") -> featured += entries
                type.contains("continue") -> resume += entries
                type.contains("next_up") || type.contains("nextup") || type.contains("on_deck") -> nextUp += entries
                type.contains("recently_added") || type.contains("recent") -> {
                    movies += entries.filter { it.kind == MediaKind.Movie }
                    shows += entries.filter { it.kind == MediaKind.Series }
                }
                else -> {
                    movies += entries.filter { it.kind == MediaKind.Movie }
                    shows += entries.filter { it.kind == MediaKind.Series }
                }
            }
        }
        return HomeFeed(
            featured = featured.distinctBy { it.id }.ifEmpty {
                FeaturedHero.interleave(movies, shows)
            },
            continueWatching = resume.distinctBy { it.id },
            nextUp = nextUp.distinctBy { it.id },
            recentMovies = movies.distinctBy { it.id },
            recentShows = shows.distinctBy { it.id },
        )
    }

    fun episodes(json: JsonElement, base: String, seriesId: String, seriesTitle: String?): List<MediaItem> {
        val array = when (json) {
            is JsonArray -> json
            is JsonObject -> json.arr("episodes") ?: json.arr("items") ?: json.arr("results") ?: return emptyList()
            else -> return emptyList()
        }
        return array.mapNotNull { element ->
            val obj = element as? JsonObject ?: return@mapNotNull null
            mediaItem(obj, base)?.copy(
                kind = MediaKind.Episode,
                seriesId = obj.str("series_id") ?: seriesId,
                seriesName = obj.str("series_title") ?: seriesTitle,
            )
        }
    }

    fun fileIds(json: JsonObject): List<Int> {
        val versions = json.arr("versions") ?: json.arr("files") ?: return emptyList()
        return versions.mapNotNull { element ->
            val obj = element as? JsonObject ?: return@mapNotNull null
            obj.int("file_id") ?: obj.int("media_file_id") ?: obj.int("id")
        }
    }

    fun streamPath(json: JsonObject): String? {
        val plan = json.obj("playback_plan")
        val stream = plan?.obj("stream")
        return stream?.str("url") ?: json.str("stream_url") ?: json.str("url")
    }

    fun playbackMethod(json: JsonObject): PlaybackMethod {
        val plan = json.obj("playback_plan")
        val kind = plan?.obj("stream")?.str("protocol").orEmpty().lowercase()
        val delivery = plan?.str("delivery").orEmpty().lowercase()
        if (kind.contains("hls") || delivery.contains("hls")) {
            return if (delivery.contains("transcode")) PlaybackMethod.Transcode else PlaybackMethod.Remux
        }
        if (delivery.contains("original")) return PlaybackMethod.DirectPlay
        return PlaybackMethod.Remux
    }

    fun clientOwnsPlayhead(json: JsonObject): Boolean {
        val plan = json.obj("playback_plan")
        val timeline = plan?.obj("timeline")
        if (timeline?.bool("can_seek_anywhere") == false) return false
        val kind = plan?.obj("stream")?.str("protocol").orEmpty().lowercase()
        val delivery = plan?.str("delivery").orEmpty().lowercase()
        if (kind.contains("hls") || delivery.contains("hls")) return false
        if (timeline?.bool("can_seek_anywhere") == true) return true
        return delivery.contains("original")
    }

    fun sessionId(json: JsonObject): String? =
        json.str("session_id") ?: json.str("play_session_id") ?: json.obj("playback_plan")?.str("session_id")

    fun playbackStart(
        fileId: Int,
        profileId: String,
        startPosition: Double,
        attemptId: String,
        appVersion: String,
        osVersion: String,
        model: String,
        formFactor: String,
        bandwidthCapKbps: Int? = null,
        audioIndex: Int? = null,
        subtitleIndex: Int? = null,
    ): String = buildJsonObject {
        put("protocol_version", 3)
        put("client_features", buildJsonArray {
            listOf(
                "playback_plan_v3",
                "playback_route_diagnostics",
                "direct_stream_resume_v1",
                "header_authenticated_media_v1",
                "embedded_subtitles_v1",
            ).forEach { add(JsonPrimitive(it)) }
        })
        put("file_id", fileId)
        put("profile_id", profileId)
        put("playback_attempt_id", attemptId)
        // A user-picked cap must not silently become "original".
        put("quality_preference", if (bandwidthCapKbps == null) "original" else "auto")
        put("subtitle_fidelity_preference", "preserve")
        put("start_position", startPosition)
        audioIndex?.let { put("audio_track_index", it) }
        subtitleIndex?.let { put("subtitle_track_index", it) }
        put("metered", false)
        bandwidthCapKbps?.let {
            put("bandwidth_estimate_kbps", it)
            put("bandwidth_cap_kbps", it)
        }
        put("client_capabilities", capabilities())
        put("client_playback_context", context(appVersion, osVersion, model, formFactor))
    }.toString()

    private fun capabilities() = buildJsonObject {
        put("video_evidence", "declared")
        put("audio_evidence", "declared")
        put("codecs_video", jsonStrings("h264", "hevc", "av1", "vp9"))
        put("codecs_video_hardware", jsonStrings("h264", "hevc"))
        put("codecs_audio", jsonStrings("aac", "ac3", "eac3", "mp3", "opus", "flac", "vorbis"))
        put("containers", jsonStrings("mp4", "m4v", "mov", "mkv", "matroska", "webm", "ts", "mpegts"))
        put("max_resolution", "2160p")
        put("hdr", true)
        put("hdr_details", hdr())
        put("video_decode", buildJsonArray {
            add(decode("h264", 8))
            add(decode("hevc", 10))
        })
    }

    private fun context(appVersion: String, osVersion: String, model: String, formFactor: String) = buildJsonObject {
        put("protocol_version", 3)
        put("form_factor", formFactor)
        put("app_version", appVersion)
        put("app_channel", "release")
        put("device", buildJsonObject {
            put("platform", "android")
            put("os_version", osVersion)
            put("manufacturer", "Android")
            put("model", model)
            put("platform_details", buildJsonObject { put("os_name", "android") })
        })
        put("output", buildJsonObject {
            put("hdr_details", hdr())
            put("current_sink", "internal")
            put("sink_type", "internal")
            put("output_context_id", "android-internal")
        })
        put("deliveries", buildJsonObject {
            put("original_http", delivery(listOf("mp4", "mkv", "matroska", "webm", "mov", "m4v"), listOf("h264", "hevc", "av1", "vp9")))
            put("progressive", delivery(listOf("mp4", "mov", "m4v"), listOf("h264", "hevc")))
            put("hls", delivery(listOf("hls", "fmp4", "mp4"), listOf("h264", "hevc")))
        })
    }

    private fun delivery(containers: List<String>, video: List<String>) = buildJsonObject {
        put("enabled", true)
        put("supported_on_device", true)
        put("containers", jsonStrings(*containers.toTypedArray()))
        put("video_codecs", jsonStrings(*video.toTypedArray()))
        put("audio_decode_codecs", jsonStrings("aac", "ac3", "eac3", "mp3", "opus"))
        put("audio_passthrough_codecs", buildJsonArray { })
        put("max_channels", 8)
        put("hdr_details", hdr())
        put("subtitles", buildJsonObject {
            put("embedded_text", true)
            put("sidecar_text", true)
            put("ass_styling", true)
            put("embedded_bitmap", true)
            put("sidecar_bitmap", false)
            put("font_attachments", true)
        })
        put("features", buildJsonArray { })
        put("auth_header_refresh", false)
        put("validated_claims", jsonStrings("authenticated_stream_headers", "client_subtitle_overlay"))
        put("transformations", buildJsonArray { })
    }

    private fun hdr() = buildJsonObject {
        put("hdr10", true)
        put("hdr10_plus", true)
        put("hlg", true)
        put("dolby_vision_profiles", buildJsonArray {
            add(JsonPrimitive(5))
            add(JsonPrimitive(8))
        })
    }

    private fun decode(codec: String, bitDepth: Int) = buildJsonObject {
        put("codec", codec)
        put("decoder_name", "MediaCodec")
        put("profiles", buildJsonArray { })
        put("levels", buildJsonArray { })
        put("bit_depths", buildJsonArray { add(JsonPrimitive(bitDepth)) })
        put("max_width", 3840)
        put("max_height", 2160)
        put("max_frame_rate", 60)
        put("max_bitrate_kbps", 120000)
        put("hardware", true)
    }

    private fun jsonStrings(vararg values: String) = buildJsonArray {
        values.forEach { add(JsonPrimitive(it)) }
    }

    private fun queueKind(type: String): PlaybackQueueKind =
        if (type.contains("next")) PlaybackQueueKind.NextUp else PlaybackQueueKind.Resume

    private fun kind(type: String?): MediaKind = when (type?.lowercase()) {
        "movie", "movies" -> MediaKind.Movie
        "series", "show", "shows", "tv" -> MediaKind.Series
        "season" -> MediaKind.Season
        "episode", "episodes" -> MediaKind.Episode
        "collection", "collections", "boxset" -> MediaKind.Collection
        else -> MediaKind.Unknown
    }

    private fun videoRange(raw: String?): VideoRange = when (raw?.lowercase()) {
        "dolby vision", "dolbyvision", "dv", "dovi" -> VideoRange.DolbyVision
        "hdr10+", "hdr10plus" -> VideoRange.Hdr10Plus
        "hlg" -> VideoRange.Hlg
        "hdr", "hdr10" -> VideoRange.Hdr10
        else -> VideoRange.Sdr
    }

    private fun audioFormat(raw: String?): AudioFormat = when (raw?.lowercase()) {
        "atmos", "dolby atmos" -> AudioFormat.Atmos
        "surround", "5.1", "7.1" -> AudioFormat.Surround
        "stereo", "2.0" -> AudioFormat.Stereo
        else -> AudioFormat.Unknown
    }

    private fun resolution(raw: String?): VideoResolution = when (raw?.lowercase()) {
        "4k", "2160p", "uhd" -> VideoResolution.FourK
        "1080p", "720p", "hd" -> VideoResolution.Hd
        "sd", "480p" -> VideoResolution.Sd
        else -> VideoResolution.Unknown
    }

    private fun credits(json: JsonObject): List<CreditPerson> {
        val cast = json.objects("cast") + json.objects("crew")
        return cast.mapNotNull { person ->
            val id = person.str("id") ?: person.str("person_id") ?: return@mapNotNull null
            val name = person.str("name") ?: return@mapNotNull null
            CreditPerson(
                id = id,
                name = name,
                roleLabel = person.str("role") ?: person.str("job") ?: "Cast",
                imageUrl = person.str("image_url") ?: person.str("profile_url") ?: person.str("photo_url"),
            )
        }.distinctBy { it.id }
    }
}

data class SiloAuth(
    val accessToken: String,
    val refreshToken: String?,
    val userId: String,
    val userName: String,
    val role: String?,
)
