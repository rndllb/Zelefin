import Foundation
import JellyfinAPI

enum StreamContainer {
    /// File extension Jellyfin expects on `/Videos/{id}/stream.{ext}` for Direct Play.
    static func pathExtension(from source: MediaSourceInfo) -> String {
        pathExtension(container: source.container, path: source.path)
    }

    static func pathExtension(container: String?, path: String?) -> String {
        if let container = pathExtension(fromContainer: container) {
            return container
        }
        if let path, let ext = pathExtension(fromContainer: URL(fileURLWithPath: path).pathExtension) {
            return ext
        }
        return "mkv"
    }

    static func pathExtension(fromContainer container: String?) -> String? {
        let raw = container?
            .split(separator: ",")
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let raw, !raw.isEmpty else { return nil }
        switch raw {
        case "matroska":
            return "mkv"
        case "mpegts", "mpegtsraw":
            return "ts"
        case "mpegps", "mpeg", "mpg", "ps":
            return "mpg"
        default:
            return raw
        }
    }

    /// libavformat short name for a Direct Play URL, when the path has an extension.
    static func formatHint(from url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "mkv", "mka", "mks":
            "matroska"
        case "ts", "m2ts", "mts":
            "mpegts"
        case "mpg", "mpeg", "ps", "vob":
            "mpeg"
        case "":
            nil
        default:
            url.pathExtension.lowercased()
        }
    }
}
