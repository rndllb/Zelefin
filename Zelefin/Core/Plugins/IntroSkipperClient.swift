import Foundation
import JellyfinAPI

struct IntroSkipperClient: Sendable {
    private let client: JellyfinClient

    init(client: JellyfinClient) {
        self.client = client
    }

    func isInstalled() async -> Bool {
        guard let plugins = try? await client.send(Paths.getPlugins).value else { return false }
        let activeNames = plugins.compactMap { plugin -> String? in
            switch plugin.status {
            case .disabled, .deleted, .malfunctioned:
                return nil
            default:
                return plugin.name
            }
        }
        return IntroSkipperPlugin.isInstalled(names: activeNames)
    }

    func segments(for itemID: String) async -> [SkipSegment] {
        if let core = try? await mediaSegments(for: itemID), !core.isEmpty {
            return core
        }
        if let plugin = await pluginSegments(for: itemID), !plugin.isEmpty {
            return plugin
        }
        return []
    }

    private func mediaSegments(for itemID: String) async throws -> [SkipSegment] {
        let result = try await client.send(
            Paths.getItemSegments(itemID: itemID, includeSegmentTypes: [.intro, .outro])
        ).value
        return (result.items ?? []).compactMap { dto in
            guard let startTicks = dto.startTicks, let endTicks = dto.endTicks else { return nil }
            let kind: SkipSegment.Kind
            switch dto.type {
            case .intro: kind = .intro
            case .outro: kind = .outro
            default: return nil
            }
            return SkipSegment(
                kind: kind,
                start: TickClock.seconds(from: startTicks),
                end: TickClock.seconds(from: endTicks)
            )
        }
        .filter { $0.end - $0.start >= 3 }
    }

    private func pluginSegments(for itemID: String) async -> [SkipSegment]? {
        let paths = [
            "/Episode/\(itemID)/IntroSkipperSegments",
            "/Episode/\(itemID)/Timestamps"
        ]
        for path in paths {
            if let segments = await decodePluginSegments(path: path), !segments.isEmpty {
                return segments
            }
        }
        if let intro = await getJSON(IntroTimestampPayload.self, path: "/Episode/\(itemID)/IntroTimestamps"),
           let segment = intro.segment(kind: .intro)
        {
            return [segment]
        }
        return nil
    }

    private func decodePluginSegments(path: String) async -> [SkipSegment]? {
        guard let data = await getData(path: path) else { return nil }
        let decoder = JSONDecoder()
        if let grouped = try? decoder.decode(IntroSkipperTimestampsResponse.self, from: data) {
            let segments = grouped.segments
            if !segments.isEmpty { return segments }
        }
        if let map = try? decoder.decode([String: IntroTimestampPayload].self, from: data) {
            let intro = map["Introduction"] ?? map["introduction"] ?? map["Intro"]
            let credits = map["Credits"] ?? map["credits"] ?? map["Outro"] ?? map["outro"]
            let segments = SkipSegment.fromPluginTimestamps(intro: intro, credits: credits)
            if !segments.isEmpty { return segments }
        }
        return nil
    }

    private func getJSON<T: Decodable>(_ type: T.Type, path: String) async -> T? {
        guard let data = await getData(path: path) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func getData(path: String) async -> Data? {
        guard let url = ServerURL.resolve(base: client.configuration.url, path: path, token: client.accessToken) else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = client.accessToken {
            request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "Authorization")
            request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        }
        do {
            let (data, response) = try await JellyfinNetworking.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }
}
