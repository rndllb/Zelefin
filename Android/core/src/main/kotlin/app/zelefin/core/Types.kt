package app.zelefin.core

class ZelefinException(val code: Code, message: String = code.defaultMessage) : Exception(message) {
    enum class Code(val defaultMessage: String) {
        InvalidServerUrl("Enter a server address that starts with http:// or https://"),
        MissingItemId("This title is missing an identifier."),
        MissingUser("Sign in again to continue."),
        MissingStreamUrl("Zelefin could not build a playback URL."),
        AccessGateway(
            "This server is behind an access gateway such as Cloudflare Zero Trust or Pangolin. Add the gateway client ID and token, then try again.",
        ),
        QuickConnectDisabled("Quick Connect is turned off on this server."),
        QuickConnectExpired("This Quick Connect code expired. Try again."),
        QuickConnectUnavailable("Jellyfin did not return a Quick Connect code."),
        Server(""),
    }

    companion object {
        fun invalidServerUrl() = ZelefinException(Code.InvalidServerUrl)
        fun missingUser() = ZelefinException(Code.MissingUser)
        fun missingStreamUrl() = ZelefinException(Code.MissingStreamUrl)
        fun accessGateway() = ZelefinException(Code.AccessGateway)
        fun quickConnectDisabled() = ZelefinException(Code.QuickConnectDisabled)
        fun quickConnectExpired() = ZelefinException(Code.QuickConnectExpired)
        fun quickConnectUnavailable() = ZelefinException(Code.QuickConnectUnavailable)
        fun server(message: String) = ZelefinException(Code.Server, message)
    }
}

enum class MediaBackend {
    Jellyfin,
    Silo,
    ;

    val usesHouseholdProfiles: Boolean get() = this == Silo
}

enum class MediaKind {
    Movie,
    Series,
    Season,
    Episode,
    Collection,
    Genre,
    Playlist,
    LiveTV,
    Book,
    Photo,
    Unknown,
    ;

    val usesVideoPlayer: Boolean
        get() = this == Movie || this == Series || this == Season || this == Episode || this == LiveTV || this == Unknown
}

enum class VideoRange { Sdr, Hdr10, Hdr10Plus, DolbyVision, Hlg }

enum class AudioFormat { Stereo, Surround, Atmos, Unknown }

enum class VideoResolution { Sd, Hd, FourK, Unknown }

enum class PlaybackQueueKind { Resume, NextUp }

enum class PlaybackMethod { DirectPlay, Remux, Transcode }

enum class HomeRowStyle { Portrait, Landscape }
