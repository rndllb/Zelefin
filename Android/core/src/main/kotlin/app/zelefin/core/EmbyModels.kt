package app.zelefin.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Emby's own API. Item ids are integer strings ("1093"), which the Jellyfin SDK cannot parse, and
 * a media source id ("mediasource_1093") is not the item id. Some ids (studios, genres, tags)
 * arrive as JSON numbers, hence the lenient parser.
 */
object EmbyJson {
    val parser: Json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
        isLenient = true
        explicitNulls = false
    }
}

@Serializable
data class EmbyPublicInfo(
    @SerialName("ServerName") val serverName: String? = null,
    @SerialName("Version") val version: String? = null,
    @SerialName("ProductName") val productName: String? = null,
    @SerialName("Id") val id: String? = null,
)

object EmbyDetection {
    /** Jellyfin always names itself in `ProductName` and is on 10.x; Emby leaves it out and is on 4.x. */
    fun isEmby(info: EmbyPublicInfo): Boolean {
        if (!info.productName.isNullOrBlank()) return false
        val major = info.version?.trim()?.substringBefore('.')?.toIntOrNull() ?: return false
        return major in 4..9
    }

    fun isEmby(publicInfoJson: String): Boolean =
        runCatching { EmbyJson.parser.decodeFromString(EmbyPublicInfo.serializer(), publicInfoJson) }
            .map(::isEmby)
            .getOrDefault(false)
}

@Serializable
data class EmbyUserData(
    @SerialName("PlaybackPositionTicks") val playbackPositionTicks: Long = 0,
    @SerialName("UnplayedItemCount") val unplayedItemCount: Int? = null,
    @SerialName("Played") val played: Boolean = false,
    @SerialName("IsFavorite") val isFavorite: Boolean = false,
)

@Serializable
data class EmbyNameId(
    @SerialName("Name") val name: String? = null,
    @SerialName("Id") val id: String? = null,
)

@Serializable
data class EmbyLink(
    @SerialName("Name") val name: String? = null,
    @SerialName("Url") val url: String? = null,
)

@Serializable
data class EmbyPerson(
    @SerialName("Name") val name: String? = null,
    @SerialName("Id") val id: String? = null,
    @SerialName("Role") val role: String? = null,
    @SerialName("Type") val type: String? = null,
    @SerialName("PrimaryImageTag") val primaryImageTag: String? = null,
)

/** `MarkerType` is `Chapter`, or `IntroStart` / `IntroEnd` / `CreditsStart` for detected segments. */
@Serializable
data class EmbyChapter(
    @SerialName("StartPositionTicks") val startPositionTicks: Long = 0,
    @SerialName("Name") val name: String? = null,
    @SerialName("MarkerType") val markerType: String? = null,
) {
    val isMarker: Boolean get() = markerType != null && !markerType.equals("Chapter", ignoreCase = true)
}

@Serializable
data class EmbyMediaStream(
    @SerialName("Index") val index: Int = 0,
    @SerialName("Type") val type: String? = null,
    @SerialName("Codec") val codec: String? = null,
    @SerialName("Language") val language: String? = null,
    @SerialName("Title") val title: String? = null,
    @SerialName("DisplayTitle") val displayTitle: String? = null,
    @SerialName("IsDefault") val isDefault: Boolean = false,
    @SerialName("IsForced") val isForced: Boolean = false,
    @SerialName("IsHearingImpaired") val isHearingImpaired: Boolean = false,
    @SerialName("IsExternal") val isExternal: Boolean = false,
    @SerialName("Channels") val channels: Int? = null,
    @SerialName("ChannelLayout") val channelLayout: String? = null,
    @SerialName("Width") val width: Int? = null,
    @SerialName("Height") val height: Int? = null,
    @SerialName("BitRate") val bitRate: Int? = null,
    @SerialName("VideoRange") val videoRange: String? = null,
    @SerialName("ExtendedVideoType") val extendedVideoType: String? = null,
    @SerialName("DeliveryMethod") val deliveryMethod: String? = null,
    @SerialName("DeliveryUrl") val deliveryUrl: String? = null,
) {
    val isVideo: Boolean get() = type.equals("Video", ignoreCase = true)
    val isAudio: Boolean get() = type.equals("Audio", ignoreCase = true)
    val isSubtitle: Boolean get() = type.equals("Subtitle", ignoreCase = true)
    val isExternalDelivery: Boolean get() = deliveryMethod.equals("External", ignoreCase = true)

    /** Emby flags HDR in `ExtendedVideoType`; spelled the way [ItemMapper] reads Jellyfin's range types. */
    val rangeLabel: String?
        get() = when (extendedVideoType?.lowercase()) {
            "dolbyvision" -> "DOVI"
            "hdr10plus" -> "HDR10Plus"
            "hyperloggamma" -> "HLG"
            "hdr10" -> "HDR10"
            else -> videoRange
        }
}

@Serializable
data class EmbyMediaSource(
    @SerialName("Id") val id: String? = null,
    @SerialName("ItemId") val itemId: String? = null,
    @SerialName("Name") val name: String? = null,
    @SerialName("Container") val container: String? = null,
    @SerialName("Size") val size: Long? = null,
    @SerialName("Bitrate") val bitrate: Int? = null,
    @SerialName("RunTimeTicks") val runTimeTicks: Long? = null,
    @SerialName("SupportsDirectPlay") val supportsDirectPlay: Boolean = false,
    @SerialName("SupportsDirectStream") val supportsDirectStream: Boolean = false,
    @SerialName("SupportsTranscoding") val supportsTranscoding: Boolean = false,
    @SerialName("DirectStreamUrl") val directStreamUrl: String? = null,
    @SerialName("TranscodingUrl") val transcodingUrl: String? = null,
    @SerialName("LiveStreamId") val liveStreamId: String? = null,
    @SerialName("DefaultAudioStreamIndex") val defaultAudioStreamIndex: Int? = null,
    @SerialName("DefaultSubtitleStreamIndex") val defaultSubtitleStreamIndex: Int? = null,
    @SerialName("MediaStreams") val mediaStreams: List<EmbyMediaStream> = emptyList(),
    @SerialName("Chapters") val chapters: List<EmbyChapter> = emptyList(),
)

@Serializable
data class EmbyItem(
    @SerialName("Id") val id: String? = null,
    @SerialName("Name") val name: String? = null,
    @SerialName("Type") val type: String? = null,
    @SerialName("CollectionType") val collectionType: String? = null,
    @SerialName("OriginalTitle") val originalTitle: String? = null,
    @SerialName("Overview") val overview: String? = null,
    @SerialName("ProductionYear") val productionYear: Int? = null,
    @SerialName("PremiereDate") val premiereDate: String? = null,
    @SerialName("RunTimeTicks") val runTimeTicks: Long? = null,
    @SerialName("OfficialRating") val officialRating: String? = null,
    @SerialName("CommunityRating") val communityRating: Double? = null,
    @SerialName("CriticRating") val criticRating: Double? = null,
    @SerialName("Genres") val genres: List<String> = emptyList(),
    @SerialName("SeriesName") val seriesName: String? = null,
    @SerialName("SeriesId") val seriesId: String? = null,
    @SerialName("IndexNumber") val indexNumber: Int? = null,
    @SerialName("ParentIndexNumber") val parentIndexNumber: Int? = null,
    @SerialName("UserData") val userData: EmbyUserData? = null,
    @SerialName("ImageTags") val imageTags: Map<String, String> = emptyMap(),
    @SerialName("BackdropImageTags") val backdropImageTags: List<String> = emptyList(),
    @SerialName("ParentBackdropItemId") val parentBackdropItemId: String? = null,
    @SerialName("ParentThumbItemId") val parentThumbItemId: String? = null,
    @SerialName("ParentThumbImageTag") val parentThumbImageTag: String? = null,
    @SerialName("ParentLogoItemId") val parentLogoItemId: String? = null,
    @SerialName("ParentLogoImageTag") val parentLogoImageTag: String? = null,
    @SerialName("SeriesPrimaryImageTag") val seriesPrimaryImageTag: String? = null,
    @SerialName("SeriesThumbImageTag") val seriesThumbImageTag: String? = null,
    @SerialName("ProviderIds") val providerIds: Map<String, String> = emptyMap(),
    @SerialName("People") val people: List<EmbyPerson> = emptyList(),
    @SerialName("Studios") val studios: List<EmbyNameId> = emptyList(),
    @SerialName("TagItems") val tagItems: List<EmbyNameId> = emptyList(),
    @SerialName("ExternalUrls") val externalUrls: List<EmbyLink> = emptyList(),
    @SerialName("RemoteTrailers") val remoteTrailers: List<EmbyLink> = emptyList(),
    @SerialName("ProductionLocations") val productionLocations: List<String> = emptyList(),
    @SerialName("Status") val status: String? = null,
    @SerialName("AirTime") val airTime: String? = null,
    @SerialName("Container") val container: String? = null,
    @SerialName("Width") val width: Int? = null,
    @SerialName("Height") val height: Int? = null,
    @SerialName("MediaStreams") val mediaStreams: List<EmbyMediaStream> = emptyList(),
    @SerialName("MediaSources") val mediaSources: List<EmbyMediaSource> = emptyList(),
    @SerialName("Chapters") val chapters: List<EmbyChapter> = emptyList(),
    @SerialName("RecursiveItemCount") val recursiveItemCount: Int? = null,
    @SerialName("ChildCount") val childCount: Int? = null,
    @SerialName("LocalTrailerCount") val localTrailerCount: Int? = null,
) {
    /** List endpoints often carry streams only on the media source. */
    val streams: List<EmbyMediaStream>
        get() = mediaStreams.ifEmpty { mediaSources.firstOrNull()?.mediaStreams.orEmpty() }

    val allChapters: List<EmbyChapter>
        get() = chapters.ifEmpty { mediaSources.firstOrNull()?.chapters.orEmpty() }

    fun toSnapshot(): JellyfinItemSnapshot = JellyfinItemSnapshot(
        id = id,
        name = name,
        type = type,
        overview = overview,
        productionYear = productionYear,
        runTimeTicks = runTimeTicks,
        officialRating = officialRating,
        genres = genres,
        seriesName = seriesName,
        seriesId = seriesId,
        indexNumber = indexNumber,
        parentIndexNumber = parentIndexNumber,
        playbackPositionTicks = userData?.playbackPositionTicks ?: 0,
        unplayedItemCount = userData?.unplayedItemCount,
        played = userData?.played == true,
        favorite = userData?.isFavorite == true,
        primaryImageTag = imageTags["Primary"],
        imageTags = imageTags,
        backdropImageTags = backdropImageTags,
        parentBackdropItemId = parentBackdropItemId,
        parentThumbItemId = parentThumbItemId,
        parentThumbImageTag = parentThumbImageTag,
        parentLogoItemId = parentLogoItemId,
        parentLogoImageTag = parentLogoImageTag,
        seriesThumbImageTag = seriesThumbImageTag,
        seriesPrimaryImageTag = seriesPrimaryImageTag,
        communityRating = communityRating,
        criticRating = criticRating,
        providerIds = providerIds,
        premiereDate = premiereDate,
        people = people
            .sortedBy { CreditRoles.rank(it.type.orEmpty()) }
            .mapNotNull { person ->
                val personName = person.name?.trim().orEmpty()
                val personId = person.id?.trim().orEmpty()
                if (personName.isEmpty() || personId.isEmpty()) return@mapNotNull null
                CreditPerson(
                    id = personId,
                    name = personName,
                    roleLabel = person.role?.trim()?.ifEmpty { null } ?: CreditRoles.label(person.type.orEmpty()),
                    imageTag = person.primaryImageTag,
                )
            }
            .distinctBy { it.id },
        streams = streams.map { stream ->
            JellyfinStreamSnapshot(
                type = stream.type.orEmpty(),
                videoRange = stream.rangeLabel,
                codec = stream.codec,
                channels = stream.channels,
                width = stream.width,
                height = stream.height,
                isDefault = stream.isDefault,
                title = stream.title,
                displayTitle = stream.displayTitle,
                channelLayout = stream.channelLayout,
            )
        },
        width = width,
        height = height,
        mediaSourceId = mediaSources.firstOrNull()?.id?.takeIf { it.isNotBlank() },
    )
}

@Serializable
data class EmbyItemsResult(
    @SerialName("Items") val items: List<EmbyItem> = emptyList(),
    @SerialName("TotalRecordCount") val totalRecordCount: Int = 0,
)

@Serializable
data class EmbyItemCounts(
    @SerialName("MovieCount") val movieCount: Int = 0,
    @SerialName("SeriesCount") val seriesCount: Int = 0,
    @SerialName("EpisodeCount") val episodeCount: Int = 0,
)

@Serializable
data class EmbyUserPolicy(
    @SerialName("IsAdministrator") val isAdministrator: Boolean = false,
)

@Serializable
data class EmbyUser(
    @SerialName("Id") val id: String? = null,
    @SerialName("Name") val name: String? = null,
    @SerialName("PrimaryImageTag") val primaryImageTag: String? = null,
    @SerialName("Policy") val policy: EmbyUserPolicy? = null,
)

@Serializable
data class EmbyAuthResult(
    @SerialName("AccessToken") val accessToken: String? = null,
    @SerialName("User") val user: EmbyUser? = null,
    @SerialName("ServerId") val serverId: String? = null,
)

@Serializable
data class EmbyPlaybackInfo(
    @SerialName("MediaSources") val mediaSources: List<EmbyMediaSource> = emptyList(),
    @SerialName("PlaySessionId") val playSessionId: String? = null,
    @SerialName("ErrorCode") val errorCode: String? = null,
)

@Serializable
data class EmbyThemeResult(
    @SerialName("Items") val items: List<EmbyItem> = emptyList(),
)

@Serializable
data class EmbyThemeMedia(
    @SerialName("ThemeVideosResult") val themeVideos: EmbyThemeResult? = null,
    @SerialName("ThemeSongsResult") val themeSongs: EmbyThemeResult? = null,
)

@Serializable
data class EmbyRecommendation(
    @SerialName("Items") val items: List<EmbyItem> = emptyList(),
    @SerialName("RecommendationType") val recommendationType: String? = null,
    @SerialName("BaselineItemName") val baselineItemName: String? = null,
    @SerialName("CategoryId") val categoryId: String? = null,
)