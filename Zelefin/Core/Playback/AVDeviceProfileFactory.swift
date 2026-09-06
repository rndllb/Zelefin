import Foundation
import JellyfinAPI

enum AVDeviceProfileFactory {
    static let maxBitrate = 200_000_000
    static let videoDirectPlayContainers = [
        "mp4", "m4v", "mov", "mkv", "matroska", "avi", "mpegts", "ts",
        "m2ts", "mts", "3gp", "3g2", "vob", "ogg", "webm", "flv"
    ]
    static let videoDirectPlayCodecs = [
        "h264", "hevc", "av1", "vp9", "vp8", "mpeg4", "mpeg2video", "vc1",
        "qtrle", "msmpeg4v1", "msmpeg4v2", "msmpeg4v3", "wmv1", "wmv2", "wmv3"
    ]
    static let audioDirectPlayCodecs = [
        "aac", "aac_latm", "ac3", "eac3", "mp3", "mp2", "flac", "opus", "vorbis",
        "alac", "truehd", "mlp", "dts", "dca", "dts-hd", "dtshd",
        "pcm_s16le", "pcm_s24le", "pcm_f32le", "pcm_bluray"
    ]

    static func make() -> DeviceProfile {
        DeviceProfile(
            codecProfiles: codecProfiles,
            directPlayProfiles: directPlayProfiles,
            maxStaticBitrate: maxBitrate,
            maxStaticMusicBitrate: maxBitrate,
            maxStreamingBitrate: maxBitrate,
            name: "Zelefin",
            subtitleProfiles: subtitleProfiles,
            transcodingProfiles: transcodingProfiles
        )
    }
}

private extension AVDeviceProfileFactory {
    /// Containers Zelefin Direct Play can demux. Apple-legal MP4/MOV still open in AVPlayer;
    /// MKV and friends use the sample-buffer engine.
    static var directPlayProfiles: [DirectPlayProfile] {
        [
            DirectPlayProfile(
                audioCodec: audioDirectPlayCodecs.joined(separator: ","),
                container: videoDirectPlayContainers.joined(separator: ","),
                type: .video,
                videoCodec: videoDirectPlayCodecs.joined(separator: ",")
            ),
            DirectPlayProfile(
                audioCodec: "aac,ac3,eac3,mp3,alac,flac,pcm,opus,vorbis",
                container: "mp4,m4v,mov,mp3,aac,m4a,m4b,flac,wav,opus,ogg",
                type: .audio
            )
        ]
    }

    /// Server remux/transcode when the file is outside the Direct Play set. HLS fMP4 keeps
    /// HEVC HDR and E-AC-3 Atmos for the native AVPlayer path.
    static var transcodingProfiles: [TranscodingProfile] {
        [
            TranscodingProfile(
                protocol: .hls,
                audioCodec: "aac,ac3,eac3",
                container: "mp4",
                context: .streaming,
                enableSubtitlesInManifest: true,
                maxAudioChannels: "8",
                minSegments: 2,
                segmentLength: 6,
                type: .video,
                videoCodec: "hevc,h264,av1"
            ),
            TranscodingProfile(
                protocol: .http,
                audioCodec: "aac",
                container: "mp4",
                context: .streaming,
                type: .audio
            )
        ]
    }

    /// External delivery so an unsupported subtitle codec never forces a video transcode.
    /// Embedded PGS/ASS in a Direct Play MKV are decoded from the file.
    static var subtitleProfiles: [SubtitleProfile] {
        [
            SubtitleProfile(format: "vtt", method: .hls),
            SubtitleProfile(format: "vtt", method: .external),
            SubtitleProfile(format: "webvtt", method: .external),
            SubtitleProfile(format: "srt", method: .external),
            SubtitleProfile(format: "subrip", method: .external),
            SubtitleProfile(format: "ttml", method: .external),
            SubtitleProfile(format: "mov_text", method: .embed),
            SubtitleProfile(format: "ass", method: .external),
            SubtitleProfile(format: "ssa", method: .external),
            SubtitleProfile(format: "pgssub", method: .external),
            SubtitleProfile(format: "pgs", method: .external),
            SubtitleProfile(format: "dvdsub", method: .external),
            SubtitleProfile(format: "dvbsub", method: .external)
        ]
    }

    static var codecProfiles: [CodecProfile] {
        [
            CodecProfile(
                applyConditions: [
                    ProfileCondition(
                        condition: .equalsAny,
                        isRequired: false,
                        property: .videoRangeType,
                        value: "SDR,HDR10,HDR10Plus,HLG,DOVI,DOVIWithHDR10,DOVIWithHLG"
                    )
                ],
                codec: "hevc",
                type: .video
            ),
            CodecProfile(
                applyConditions: [
                    ProfileCondition(
                        condition: .equalsAny,
                        isRequired: false,
                        property: .videoRangeType,
                        value: "DOVI,DOVIWithHDR10,DOVIWithHLG"
                    )
                ],
                codec: "h264",
                type: .video
            )
        ]
    }
}
