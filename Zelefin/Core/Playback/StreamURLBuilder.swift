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
}
