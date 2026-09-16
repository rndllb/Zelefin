import Foundation
import JellyfinAPI

struct ArtworkURLBuilder: Sendable {
    /// Height requested for grid and row posters. Matches on-screen portrait cards at 2–3x
    /// without pulling original files. Swiftfin uses `maxWidth`/`maxHeight` (not `fillWidth`);
    /// fill boxes crop and can request a larger image than this cap.
    static let posterMaxHeight = 420

    let client: JellyfinClient

    func primary(for item: MediaItem, maxHeight: Int = posterMaxHeight) -> URL? {
        guard Self.requestsPrimary(kind: item.kind, tag: item.primaryImageTag) else { return nil }
        return image(
            itemID: item.artworkItemID,
            type: "Primary",
            tag: item.primaryImageTag,
            maxHeight: maxHeight,
            format: "jpg"
        )
    }

    /// Movies and shows without a Primary tag have no poster. Collections still request
    /// untagged covers because Jellyfin often serves collages without a tag.
    static func requestsPrimary(kind: MediaKind, tag: String?) -> Bool {
        tag != nil || kind == .collection || kind == .photo || kind == .playlist || kind == .liveTV
    }

    func splashscreenURL() -> URL? {
        ServerURL.resolve(base: client.configuration.url, path: "/Branding/Splashscreen")
    }

    func thumb(for item: MediaItem, maxWidth: Int) -> URL? {
        if let tag = item.thumbImageTag {
            return image(itemID: item.artworkItemID, type: "Thumb", tag: tag, maxWidth: maxWidth, format: "jpg")
        }
        if let parent = item.parentThumbItemID {
            return image(itemID: parent, type: "Thumb", tag: item.parentThumbImageTag, maxWidth: maxWidth, format: "jpg")
        }
        if let seriesID = item.seriesID, let tag = item.seriesThumbImageTag {
            return image(itemID: seriesID, type: "Thumb", tag: tag, maxWidth: maxWidth, format: "jpg")
        }
        // Live TV programs almost never have a Thumb; requesting one 404s and
        // hides the Primary still that the guide actually shipped.
        if item.kind == .liveTV {
            return nil
        }
        return image(itemID: item.artworkItemID, type: "Thumb", tag: nil, maxWidth: maxWidth, format: "jpg")
    }

    func backdrop(for item: MediaItem, maxWidth: Int, allowPosterFallback: Bool = true) -> URL? {
        if let tag = item.backdropImageTag {
            return image(itemID: item.artworkItemID, type: "Backdrop", tag: tag, maxWidth: maxWidth, format: "jpg")
        }
        if let parent = item.parentBackdropItemID {
            return image(itemID: parent, type: "Backdrop", tag: nil, maxWidth: maxWidth, format: "jpg")
        }
        if allowPosterFallback {
            return primary(for: item, maxHeight: maxWidth)
        }
        return nil
    }

    func genreCover(for item: MediaItem, maxWidth: Int) -> URL? {
        if let url = backdrop(for: item, maxWidth: maxWidth, allowPosterFallback: false) {
            return url
        }
        if let tag = item.thumbImageTag {
            return image(itemID: item.artworkItemID, type: "Thumb", tag: tag, maxWidth: maxWidth, format: "jpg")
        }
        return primary(for: item, maxHeight: maxWidth)
    }

    func logo(for item: MediaItem, maxHeight: Int = 240) -> URL? {
        if let tag = item.logoImageTag {
            return image(itemID: item.id, type: "Logo", tag: tag, maxHeight: maxHeight, format: "png")
        }
        if let parent = item.parentLogoItemID {
            return image(
                itemID: parent,
                type: "Logo",
                tag: item.parentLogoImageTag,
                maxHeight: maxHeight,
                format: "png"
            )
        }
        return nil
    }

    func userAvatar(userID: String, tag: String?, maxHeight: Int = 180, revision: Int = 0) -> URL? {
        var query: [String] = ["quality=90", "maxHeight=\(maxHeight)"]
        if let tag {
            query.append("tag=\(tag)")
        }
        if revision > 0 {
            query.append("v=\(revision)")
        }
        if let token = client.accessToken {
            query.append("api_key=\(token)")
        }
        let path = "/Users/\(userID)/Images/Primary?\(query.joined(separator: "&"))"
        return ServerURL.resolve(base: client.configuration.url, path: path)
    }

    func image(
        itemID: String,
        type: String,
        tag: String?,
        maxHeight: Int? = nil,
        maxWidth: Int? = nil,
        format: String? = nil
    ) -> URL? {
        let query = Self.queryItems(
            quality: 90,
            format: format,
            maxHeight: maxHeight,
            maxWidth: maxWidth,
            tag: tag,
            token: client.accessToken
        )
        let path = "/Items/\(itemID)/Images/\(type)?\(query.joined(separator: "&"))"
        return ServerURL.resolve(base: client.configuration.url, path: path)
    }

    static func queryItems(
        quality: Int,
        format: String?,
        maxHeight: Int?,
        maxWidth: Int?,
        tag: String?,
        token: String?
    ) -> [String] {
        var query = ["quality=\(quality)"]
        if let format { query.append("format=\(format)") }
        if let maxHeight { query.append("maxHeight=\(maxHeight)") }
        if let maxWidth { query.append("maxWidth=\(maxWidth)") }
        if let tag { query.append("tag=\(tag)") }
        if let token { query.append("api_key=\(token)") }
        return query
    }

    func trickplayTile(itemID: String, width: Int, index: Int, mediaSourceID: String?) -> URL? {
        var query = ["quality=90"]
        if let mediaSourceID { query.append("mediaSourceId=\(mediaSourceID)") }
        if let token = client.accessToken { query.append("api_key=\(token)") }
        let path = "/Videos/\(itemID)/Trickplay/\(width)/\(index).jpg?\(query.joined(separator: "&"))"
        return ServerURL.resolve(base: client.configuration.url, path: path)
    }
}
