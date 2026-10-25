package app.zelefin.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class EmbyPlayState(
    @SerialName("PositionTicks") val positionTicks: Long? = null,
    @SerialName("CanSeek") val canSeek: Boolean = false,
    @SerialName("IsPaused") val isPaused: Boolean = false,
    @SerialName("IsMuted") val isMuted: Boolean = false,
    @SerialName("VolumeLevel") val volumeLevel: Int? = null,
    @SerialName("PlayMethod") val playMethod: String? = null,
)

@Serializable
data class EmbyTranscodingInfo(
    @SerialName("Container") val container: String? = null,
    @SerialName("VideoCodec") val videoCodec: String? = null,
    @SerialName("AudioCodec") val audioCodec: String? = null,
    @SerialName("IsVideoDirect") val isVideoDirect: Boolean = false,
    @SerialName("IsAudioDirect") val isAudioDirect: Boolean = false,
    @SerialName("AudioChannels") val audioChannels: Int? = null,
    @SerialName("Width") val width: Int? = null,
    @SerialName("Height") val height: Int? = null,
    @SerialName("Bitrate") val bitrate: Int? = null,
    @SerialName("CompletionPercentage") val completionPercentage: Double? = null,
    @SerialName("TranscodeReasons") val transcodeReasons: List<String> = emptyList(),
)

@Serializable
data class EmbySessionInfo(
    @SerialName("Id") val id: String? = null,
    @SerialName("UserId") val userId: String? = null,
    @SerialName("UserName") val userName: String? = null,
    @SerialName("UserPrimaryImageTag") val userPrimaryImageTag: String? = null,
    @SerialName("Client") val client: String? = null,
    @SerialName("DeviceName") val deviceName: String? = null,
    @SerialName("DeviceType") val deviceType: String? = null,
    @SerialName("DeviceId") val deviceId: String? = null,
    @SerialName("ApplicationVersion") val applicationVersion: String? = null,
    @SerialName("RemoteEndPoint") val remoteEndPoint: String? = null,
    @SerialName("LastActivityDate") val lastActivityDate: String? = null,
    @SerialName("SupportsRemoteControl") val supportsRemoteControl: Boolean = false,
    @SerialName("PlayableMediaTypes") val playableMediaTypes: List<String> = emptyList(),
    @SerialName("SupportedCommands") val supportedCommands: List<String> = emptyList(),
    @SerialName("NowPlayingItem") val nowPlayingItem: EmbyItem? = null,
    @SerialName("PlayState") val playState: EmbyPlayState? = null,
    @SerialName("TranscodingInfo") val transcodingInfo: EmbyTranscodingInfo? = null,
)

@Serializable
data class EmbyTaskResult(
    @SerialName("StartTimeUtc") val startTimeUtc: String? = null,
    @SerialName("EndTimeUtc") val endTimeUtc: String? = null,
    @SerialName("Status") val status: String? = null,
    @SerialName("ErrorMessage") val errorMessage: String? = null,
)

@Serializable
data class EmbyTaskInfo(
    @SerialName("Id") val id: String? = null,
    @SerialName("Name") val name: String? = null,
    @SerialName("Category") val category: String? = null,
    @SerialName("Description") val description: String? = null,
    @SerialName("State") val state: String? = null,
    @SerialName("CurrentProgressPercentage") val currentProgressPercentage: Double? = null,
    @SerialName("IsHidden") val isHidden: Boolean = false,
    @SerialName("LastExecutionResult") val lastExecutionResult: EmbyTaskResult? = null,
)

@Serializable
data class EmbyActivityEntry(
    @SerialName("Id") val id: String? = null,
    @SerialName("Name") val name: String? = null,
    @SerialName("Overview") val overview: String? = null,
    @SerialName("ShortOverview") val shortOverview: String? = null,
    @SerialName("Type") val type: String? = null,
    @SerialName("Date") val date: String? = null,
)

@Serializable
data class EmbyActivityResult(
    @SerialName("Items") val items: List<EmbyActivityEntry> = emptyList(),
)

@Serializable
data class EmbyRemoteImage(
    @SerialName("ProviderName") val providerName: String? = null,
    @SerialName("Url") val url: String? = null,
    @SerialName("ThumbnailUrl") val thumbnailUrl: String? = null,
    @SerialName("Width") val width: Int? = null,
    @SerialName("Height") val height: Int? = null,
)

@Serializable
data class EmbyRemoteImageResult(
    @SerialName("Images") val images: List<EmbyRemoteImage> = emptyList(),
)

@Serializable
data class EmbyParentalRating(
    @SerialName("Name") val name: String? = null,
    @SerialName("Value") val value: Int? = null,
)

@Serializable
data class EmbyLiveTvInfo(
    @SerialName("IsEnabled") val isEnabled: Boolean = false,
)

@Serializable
data class EmbyCreated(
    @SerialName("Id") val id: String? = null,
    @SerialName("Name") val name: String? = null,
)

@Serializable
data class EmbyPlaylistEntry(
    @SerialName("Id") val id: String? = null,
    @SerialName("PlaylistItemId") val playlistItemId: String? = null,
)

@Serializable
data class EmbyPlaylistEntries(
    @SerialName("Items") val items: List<EmbyPlaylistEntry> = emptyList(),
)
