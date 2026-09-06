import Foundation
import JellyfinAPI

enum StreamContainer {
    /// File extension Jellyfin expects on `/Videos/{id}/stream.{ext}` for Direct Play.
    static func pathExtension(from source: MediaSourceInfo) -> String {
        pathExtension(fromContainer: source.container)
    }

    static func pathExtension(fromContainer container: String?) -> String {
        let raw = container?
            .split(separator: ",")
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "mp4"
        switch raw {
        case "matroska":
            return "mkv"
        case "mpegts", "mpegtsraw":
            return "ts"
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
        case "":
            nil
        default:
            url.pathExtension.lowercased()
        }
    }
}
