import Foundation

/// Which Apple-facing decoder path should open a planned stream.
enum PlaybackPipeline: Equatable, Sendable {
    /// AVPlayer opens server HLS (remux / transcode).
    case appleNative
    /// Zelefin Direct Play: FFmpeg demuxes the container, VideoToolbox decodes, and a sample-buffer layer paints.
    case directDecode
}

enum PlaybackPipelineResolver {
    static func pipeline(for plan: PlaybackPlan) -> PlaybackPipeline {
        pipeline(url: plan.streamURL, method: plan.method)
    }

    static func pipeline(
        url: URL,
        method: PlaybackMethod,
        container _: String? = nil,
        videoCodec _: String? = nil
    ) -> PlaybackPipeline {
        if method != .directPlay {
            return .appleNative
        }
        if isHLS(url) {
            return .appleNative
        }
        // Direct Play files go through Aether. AVPlayer on a mislabeled MP4/MKV, or on
        // MPEG-4 ASP / 4:2:2 H.264, plays audio into a black picture.
        return .directDecode
    }

    private static func isHLS(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.hasSuffix(".m3u8") || path.contains(".m3u8")
    }
}

/// Direct Play MKV often has Cues at EOF. A long automatic resume seek at load can
/// time out and black the screen. User skip / scrub is still offered so the chrome
/// matches AVPlayer; resume-at-load stays on the native path only.
enum DirectPlaySeekPolicy {
    static func allowsAutomaticResumeSeek(_ pipeline: PlaybackPipeline) -> Bool {
        pipeline == .appleNative
    }
}

/// Latest-wins queue for Direct Play seeks. Rapid scrubs must not stack `engine.seek`
/// calls: a superseded seek can tear down the session (`noActiveSession`) and reload
/// from t=0.
enum DirectPlaySeekCoalesce {
    /// Stores `latest` as the pending target. Returns true when the caller should
    /// start a drain loop; false when a drain is already in flight.
    static func enqueue(
        pending: inout TimeInterval?,
        latest: TimeInterval,
        isDraining: Bool
    ) -> Bool {
        pending = latest
        return !isDraining
    }
}

/// Jellyfin progress follows the on-screen frame. Direct Play jumps its clock to the
/// scrub target before video lands; reporting that makes the server think the skip
/// worked while the iPad is still on the previous picture.
enum DirectPlayProgressPolicy {
    static func shouldReport(playheadTrusted: Bool) -> Bool {
        playheadTrusted
    }

    static func playheadTrusted(after outcome: DirectPlaySeekEvent.Outcome) -> Bool {
        switch outcome {
        case .landed, .rejected:
            true
        case .began, .stalled, .superseded:
            false
        }
    }
}
