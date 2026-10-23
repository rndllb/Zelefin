import Foundation

enum SiloProfileAvatars {
    struct Style: Identifiable, Hashable, Sendable {
        var id: String
        var label: String
        var summary: String
    }

    struct Preset: Identifiable, Hashable, Sendable {
        var id: String
        var label: String
        var styleID: String
        var previewURL: URL
    }

    static let styles: [Style] = [
        Style(id: "identicon", label: "Identicon", summary: "Geometric patterns"),
        Style(id: "initials", label: "Initials", summary: "Letter marks"),
        Style(id: "bottts-neutral", label: "Robots", summary: "Modular robot faces"),
        Style(id: "fun-emoji", label: "Emoji", summary: "Colorful faces"),
        Style(id: "pixel-art-neutral", label: "Pixel", summary: "Retro pixel faces")
    ]

    private static let adjectives = [
        "cosmic", "jelly", "starlight", "mango", "bubble", "neon", "marble", "comet",
        "snappy", "pepper", "glimmer", "ripple", "pocket", "candy", "ember", "mochi",
        "sprout", "twinkle", "whiz", "plasma", "mint", "velvet", "crunchy", "sunbeam",
        "toffee", "splash", "boomer", "lunar", "fizzy", "biscuit", "rocket", "cobalt"
    ]

    private static let nouns = [
        "otter", "rocket", "fox", "cookie", "gecko", "bunny", "penguin", "puffin",
        "tiger", "panda", "saturn", "wizard", "skater", "nebula", "robot", "pirate",
        "meteor", "sprite", "pebble", "nova", "dragon", "donut", "parrot", "panther",
        "goblin", "muffin", "laser", "pickle", "falcon", "sunset", "toaster", "bandit"
    ]

    static let batchSize = 18

    static func presetRef(_ id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return trimmed }
        if trimmed.hasPrefix("preset:") { return trimmed }
        return "preset:\(trimmed)"
    }

    static func presetID(from ref: String?) -> String? {
        let trimmed = ref?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("preset:") {
            let value = String(trimmed.dropFirst("preset:".count))
            return value.isEmpty ? nil : value
        }
        return trimmed
    }

    static func parseDiceBear(_ presetID: String) -> (styleID: String, seed: String)? {
        let parts = presetID.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == "dicebear" else { return nil }
        let styleID = parts[1]
        let seed = parts[2]
        guard styles.contains(where: { $0.id == styleID }), !seed.isEmpty else { return nil }
        return (styleID, seed)
    }

    static func batch(styleID: String, batch: Int) -> [Preset] {
        let style = styles.contains(where: { $0.id == styleID }) ? styleID : styles[0].id
        return (0..<batchSize).compactMap { index in
            let adjective = adjectives[(batch * 7 + index * 3 + style.count) % adjectives.count]
            let noun = nouns[(batch * 11 + index * 5 + style.count * 2) % nouns.count]
            return preset(styleID: style, seed: "\(adjective)-\(noun)")
        }
    }

    static func preset(styleID: String, seed: String) -> Preset? {
        let id = "dicebear:\(styleID):\(seed)"
        guard let url = diceBearPNGURL(styleID: styleID, seed: seed) else { return nil }
        let label = seed.replacingOccurrences(of: "-", with: " ").localizedCapitalized
        return Preset(id: id, label: label, styleID: styleID, previewURL: url)
    }

    static func previewURL(forPreset ref: String) -> URL? {
        guard let id = presetID(from: ref), let parsed = parseDiceBear(id) else { return nil }
        return diceBearPNGURL(styleID: parsed.styleID, seed: parsed.seed)
    }

    static func displayURL(baseURL: URL, raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let absolute = URL(string: trimmed),
           let scheme = absolute.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           absolute.host != nil {
            return pngFriendly(absolute)
        }
        guard var origin = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        origin.percentEncodedQuery = nil
        origin.fragment = nil
        if let relative = URL(string: trimmed.hasPrefix("/") ? trimmed : "/" + trimmed) {
            origin.percentEncodedPath = relative.path
            origin.percentEncodedQuery = relative.query
        } else {
            origin.path = trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
        }
        guard let url = origin.url else { return nil }
        return pngFriendly(url)
    }

    static func diceBearPNGURL(styleID: String, seed: String, size: Int = 256) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.dicebear.com"
        components.path = "/9.x/\(styleID)/png"
        components.queryItems = [
            URLQueryItem(name: "seed", value: seed),
            URLQueryItem(name: "size", value: String(size)),
            URLQueryItem(name: "radius", value: "24"),
            URLQueryItem(name: "backgroundType", value: "gradientLinear")
        ]
        return components.url
    }

    private static func pngFriendly(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        let host = (components.host ?? "").lowercased()
        if host.contains("dicebear.com"), components.path.contains("/svg") {
            components.path = components.path.replacingOccurrences(of: "/svg", with: "/png")
        } else if components.path.hasSuffix(".svg") {
            components.path = String(components.path.dropLast(4)) + ".png"
        }
        return components.url ?? url
    }
}
