import Foundation
import JellyfinAPI

struct StreamURLBuilder: Sendable {
    let client: JellyfinClient

    func url(itemID: String, source: MediaSourceInfo) throws -> URL {
        let method = ItemMapper.playbackMethod(from: source)
        if method != .directPlay, let transcodingPath = source.transcodingURL {
            guard let url = ServerURL.resolve(base: client.configuration.url, path: transcodingPath, token: client.accessToken) else {
                throw ZelefinError.missingStreamURL
            }
            return url
        }

        let container = StreamContainer.pathExtension(from: source)
        var query = "static=true"
        if let sourceID = source.id {
            query += "&mediaSourceId=\(sourceID)"
        }
        if let token = client.accessToken {
            query += "&api_key=\(token)"
        }

        guard let url = ServerURL.resolve(
            base: client.configuration.url,
            path: "/Videos/\(itemID)/stream.\(container)?\(query)"
        ) else {
            throw ZelefinError.missingStreamURL
        }
        return url
    }

    func externalSubtitles(itemID: String, source: MediaSourceInfo) -> [ExternalSubtitleSidecar] {
        guard let sourceID = source.id, !sourceID.isEmpty else { return [] }
        return (source.mediaStreams ?? []).compactMap { stream in
            Self.sidecar(from: stream, itemID: itemID, mediaSourceID: sourceID, client: client)
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
        client: JellyfinClient
    ) -> ExternalSubtitleSidecar? {
        guard isExternalSubtitle(stream), let index = stream.index else { return nil }
        let format = subtitleExtension(codec: stream.codec)
        guard let url = subtitleURL(
            itemID: itemID,
            mediaSourceID: mediaSourceID,
            index: index,
            format: format,
            deliveryPath: stream.deliveryURL,
            client: client
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
        client: JellyfinClient
    ) -> URL? {
        if let deliveryPath, !deliveryPath.isEmpty {
            return ServerURL.resolve(base: client.configuration.url, path: deliveryPath, token: client.accessToken)
        }
        var path = "/Videos/\(itemID)/\(mediaSourceID)/Subtitles/\(index)/Stream.\(format)"
        if let token = client.accessToken, !token.isEmpty {
            path += "?api_key=\(token)"
        }
        return ServerURL.resolve(base: client.configuration.url, path: path)
    }
}
