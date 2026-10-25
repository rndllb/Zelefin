import Foundation
import JellyfinAPI

struct StreamURLBuilder: Sendable {
    private let endpoint: @Sendable () -> (url: URL, token: String?)

    init(client: JellyfinClient) {
        endpoint = { (client.configuration.url, client.accessToken) }
    }

    /// Emby serves subtitle sidecars at the same paths.
    init(serverURL: URL, accessToken: String?) {
        endpoint = { (serverURL, accessToken) }
    }

    private var serverURL: URL { endpoint().url }
    private var accessToken: String? { endpoint().token }

    func url(itemID: String, source: MediaSourceInfo) throws -> URL {
        let method = ItemMapper.playbackMethod(from: source)
        if method != .directPlay, let transcodingPath = source.transcodingURL {
            guard let url = ServerURL.resolve(base: serverURL, path: transcodingPath, token: accessToken) else {
                throw ZelefinError.missingStreamURL
            }
            return url
        }

        let container = StreamContainer.pathExtension(from: source)
        let query = Self.directPlayQuery(
            sourceID: source.id,
            token: accessToken,
            liveStreamID: source.liveStreamID
        )

        guard let url = ServerURL.resolve(
            base: serverURL,
            path: "/Videos/\(itemID)/stream.\(container)?\(query)"
        ) else {
            throw ZelefinError.missingStreamURL
        }
        return url
    }

    static func directPlayQuery(sourceID: String?, token: String?, liveStreamID: String?) -> String {
        var query = "static=true"
        if let sourceID, !sourceID.isEmpty {
            query += "&mediaSourceId=\(sourceID)"
        }
        if let liveStreamID, !liveStreamID.isEmpty {
            let encoded = liveStreamID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? liveStreamID
            query += "&liveStreamId=\(encoded)"
        }
        if let token, !token.isEmpty {
            query += "&api_key=\(token)"
        }
        return query
    }

    func externalSubtitles(itemID: String, source: MediaSourceInfo) -> [ExternalSubtitleSidecar] {
        guard let sourceID = source.id, !sourceID.isEmpty else { return [] }
        let base = serverURL
        let token = accessToken
        return (source.mediaStreams ?? []).compactMap { stream in
            Self.sidecar(from: stream, itemID: itemID, mediaSourceID: sourceID, base: base, token: token)
        }
    }

    static func subtitleExtension(codec: String?) -> String {
        switch (codec ?? "").lowercased() {
        case "vtt", "webvtt": "vtt"
        case "ass": "ass"
        case "ssa": "ssa"
        default: "srt"
        }
    }

    static func isExternalSubtitle(_ stream: MediaStream) -> Bool {
        guard stream.type == .subtitle, stream.index != nil else { return false }
        return stream.isExternal == true || stream.isExternalURL == true
    }

    private static func sidecar(
        from stream: MediaStream,
        itemID: String,
        mediaSourceID: String,
        base: URL,
        token: String?
    ) -> ExternalSubtitleSidecar? {
        guard isExternalSubtitle(stream), let index = stream.index else { return nil }
        let format = subtitleExtension(codec: stream.codec)
        guard let url = subtitleURL(
            itemID: itemID,
            mediaSourceID: mediaSourceID,
            index: index,
            format: format,
            deliveryPath: stream.deliveryURL,
            base: base,
            token: token
        ) else {
            return nil
        }
        let name = stream.displayTitle ?? stream.title ?? stream.language ?? "Subtitle"
        return ExternalSubtitleSidecar(
            url: url,
            name: name,
            language: stream.language,
            formatHint: format,
            isForced: stream.isForced == true,
            isHearingImpaired: stream.isHearingImpaired == true
        )
    }

    private static func subtitleURL(
        itemID: String,
        mediaSourceID: String,
        index: Int,
        format: String,
        deliveryPath: String?,
        base: URL,
        token: String?
    ) -> URL? {
        if let deliveryPath, !deliveryPath.isEmpty {
            return ServerURL.resolve(base: base, path: deliveryPath, token: token)
        }
        var path = "/Videos/\(itemID)/\(mediaSourceID)/Subtitles/\(index)/Stream.\(format)"
        if let token, !token.isEmpty {
            path += "?api_key=\(token)"
        }
        return ServerURL.resolve(base: base, path: path)
    }
}
