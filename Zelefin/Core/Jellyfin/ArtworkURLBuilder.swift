import Foundation
import JellyfinAPI

struct ArtworkURLBuilder: Sendable {
    let client: JellyfinClient

    func primary(for item: MediaItem, maxHeight: Int) -> URL? {
        image(itemID: item.artworkItemID, type: "Primary", tag: item.primaryImageTag, maxHeight: maxHeight)
    }

    func thumb(for item: MediaItem, maxWidth: Int) -> URL? {
        if let tag = item.thumbImageTag {
            return image(itemID: item.artworkItemID, type: "Thumb", tag: tag, maxWidth: maxWidth)
        }
        if let parent = item.parentThumbItemID {
            return image(itemID: parent, type: "Thumb", tag: item.parentThumbImageTag, maxWidth: maxWidth)
        }
        if let seriesID = item.seriesID, let tag = item.seriesThumbImageTag {
            return image(itemID: seriesID, type: "Thumb", tag: tag, maxWidth: maxWidth)
        }
        return image(itemID: item.artworkItemID, type: "Thumb", tag: nil, maxWidth: maxWidth)
    }

    func backdrop(for item: MediaItem, maxWidth: Int, allowPosterFallback: Bool = true) -> URL? {
        if let tag = item.backdropImageTag {
            return image(itemID: item.artworkItemID, type: "Backdrop", tag: tag, maxWidth: maxWidth)
        }
        if let parent = item.parentBackdropItemID {
            return image(itemID: parent, type: "Backdrop", tag: nil, maxWidth: maxWidth)
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
            return image(itemID: item.artworkItemID, type: "Thumb", tag: tag, maxWidth: maxWidth)
        }
        return primary(for: item, maxHeight: maxWidth)
    }

    func logo(for item: MediaItem, maxHeight: Int = 240) -> URL? {
        if let tag = item.logoImageTag {
            return image(itemID: item.id, type: "Logo", tag: tag, maxHeight: maxHeight)
        }
        if let parent = item.parentLogoItemID {
            return image(itemID: parent, type: "Logo", tag: item.parentLogoImageTag, maxHeight: maxHeight)
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

    func image(itemID: String, type: String, tag: String?, maxHeight: Int? = nil, maxWidth: Int? = nil) -> URL? {
        var query: [String] = ["quality=90"]
        if let maxHeight { query.append("maxHeight=\(maxHeight)") }
        if let maxWidth { query.append("maxWidth=\(maxWidth)") }
        if let tag {
            query.append("tag=\(tag)")
        }
        if let token = client.accessToken {
            query.append("api_key=\(token)")
        }
        let path = "/Items/\(itemID)/Images/\(type)?\(query.joined(separator: "&"))"
        return ServerURL.resolve(base: client.configuration.url, path: path)
    }
}
