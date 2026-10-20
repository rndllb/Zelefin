import SwiftUI

enum YouTubeVideoSort: String, CaseIterable, Identifiable {
    case latest
    case oldest
    case unwatched

    var id: String { rawValue }

    var label: String {
        switch self {
        case .latest: "Latest"
        case .oldest: "Oldest"
        case .unwatched: "Unwatched"
        }
    }
}

enum YouTubeText {
    static let red = Color(red: 1, green: 0, blue: 51 / 255)
    static let chipFill = Color.white.opacity(0.12)
    static let muted = Color.white.opacity(0.62)

    static func videoCountLabel(_ count: Int) -> String {
        count == 1 ? "1 video" : "\(count) videos"
    }

    static func videoLengthLabel(_ runtime: TimeInterval?) -> String? {
        guard let runtime, runtime > 0 else { return nil }
        let total = Int(runtime.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func publishedAgo(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        if days < 1 { return "Today" }
        if days < 7 { return unit(days, "day") }
        if days < 30 { return unit(max(1, days / 7), "week") }
        let months = max(1, calendar.dateComponents([.month], from: date, to: now).month ?? 0)
        if days < 365 { return unit(months, "month") }
        return unit(max(1, calendar.dateComponents([.year], from: date, to: now).year ?? 0), "year")
    }

    static func plainDescription(_ html: String) -> String? {
        var text = html
        for tag in ["<br>", "<br/>", "<br />", "<BR>", "<BR/>", "<BR />", "</p>", "</P>", "</div>", "</DIV>"] {
            text = text.replacingOccurrences(of: tag, with: "\n")
        }
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: .caseInsensitive) {
            text = regex.stringByReplacingMatches(
                in: text,
                options: [],
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
        }
        let decoded = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        let collapsed = decoded
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? nil : collapsed
    }

    private static func unit(_ value: Int, _ name: String) -> String {
        "\(value) \(name)\(value == 1 ? "" : "s") ago"
    }
}

struct YouTubeDetailPage: View {
    let item: MediaItem
    var channel: MediaItem?
    var videos: [MediaItem]
    var onPlay: (MediaItem) -> Void
    var onChangeItem: (MediaItem) -> Void
    var onChangeChannel: (MediaItem) -> Void
    var onChangeVideos: ([MediaItem]) -> Void
    @Binding var chromeVisible: Bool

    @State private var sort: YouTubeVideoSort = .latest

    private var contentTopInset: CGFloat {
        ScreenInsets.top + RootPageChrome.headerRowHeight + 8
    }

    var body: some View {
        ScrollView {
            Group {
                if item.kind == .series {
                    YouTubeChannelPage(
                        channel: item,
                        videos: videos,
                        sort: $sort,
                        onPlay: onPlay,
                        onChangeChannel: onChangeItem,
                        onChangeVideos: onChangeVideos
                    )
                } else {
                    YouTubeVideoPage(
                        video: item,
                        channel: channel,
                        videos: videos,
                        onPlay: onPlay,
                        onChangeVideo: onChangeItem,
                        onChangeChannel: onChangeChannel,
                        onChangeVideos: onChangeVideos
                    )
                }
            }
            .padding(.top, contentTopInset)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .zelefinScrollEdgeHidden()
        .zelefinPinnedBottomEdge()
        .zelefinHeaderScrollVisibility($chromeVisible)
    }
}

private struct YouTubeChannelPage: View {
    let channel: MediaItem
    var videos: [MediaItem]
    @Binding var sort: YouTubeVideoSort
    var onPlay: (MediaItem) -> Void
    var onChangeChannel: (MediaItem) -> Void
    var onChangeVideos: ([MediaItem]) -> Void

    @Environment(SessionStore.self) private var session

    private var sorted: [MediaItem] {
        switch sort {
        case .latest: videos
        case .oldest: videos.reversed()
        case .unwatched: videos.filter { !$0.isWatched }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if sorted.isEmpty {
                Text(sort == .unwatched ? "You’ve watched every video." : "No videos yet.")
                    .font(.subheadline)
                    .foregroundStyle(YouTubeText.muted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 32)
            } else {
                ForEach(sorted) { video in
                    YouTubeVideoRow(
                        video: video,
                        channel: channel,
                        onPlay: { onPlay(video) },
                        onChangeVideo: { updated in
                            onChangeVideos(videos.map { $0.id == updated.id ? updated : $0 })
                        },
                        onChangeChannel: onChangeChannel
                    )
                }
            }
        }
        .padding(.bottom, 40)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let banner = session.library?.bannerURL(for: channel) {
                PosterImage(url: banner, aspectRatio: 6.2, contentMode: .fill)
                    .aspectRatio(6.2, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            HStack(alignment: .center, spacing: 16) {
                YouTubeChannelAvatar(channel: channel, size: 80)
                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(YouTubeText.videoCountLabel(videos.count))
                        .font(.subheadline)
                        .foregroundStyle(YouTubeText.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)

            if let about = channel.overview.flatMap(YouTubeText.plainDescription) {
                YouTubeExpandableText(about, collapsedLines: 2)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }

            HStack(spacing: 10) {
                let resume = videos.first(where: \.showsResumeProgress)
                let target = resume ?? videos.first
                if let target {
                    YouTubePill(
                        label: resume != nil ? "Resume" : "Play latest",
                        systemImage: "play.fill",
                        style: .filled
                    ) { onPlay(target) }
                }
                YouTubePill(
                    label: channel.isFavorite ? "Favorited" : "Favorite",
                    systemImage: channel.isFavorite ? "heart.fill" : "heart",
                    style: channel.isFavorite ? .outline : .red
                ) {
                    Task { await toggleFavorite(channel, onChange: onChangeChannel) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(YouTubeVideoSort.allCases) { option in
                        YouTubeSortChip(label: option.label, selected: option == sort) {
                            sort = option
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 20)
            .padding(.bottom, 8)
        }
    }

    private func toggleFavorite(_ item: MediaItem, onChange: (MediaItem) -> Void) async {
        guard let updated = try? await session.toggleFavorite(item) else { return }
        onChange(updated)
    }
}

private struct YouTubeVideoPage: View {
    let video: MediaItem
    var channel: MediaItem?
    var videos: [MediaItem]
    var onPlay: (MediaItem) -> Void
    var onChangeVideo: (MediaItem) -> Void
    var onChangeChannel: (MediaItem) -> Void
    var onChangeVideos: ([MediaItem]) -> Void

    @Environment(SessionStore.self) private var session
    @State private var descriptionExpanded = false

    private var others: [MediaItem] {
        videos.filter { $0.id != video.id }
    }

    private var metaLine: String {
        [
            YouTubeText.publishedAgo(video.premiereDate),
            video.runtimeLabel,
            video.isWatched ? "Watched" : nil
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                onPlay(video)
            } label: {
                ZStack {
                    Color(red: 15 / 255, green: 15 / 255, blue: 15 / 255)
                    PosterImage(
                        url: session.library?.primaryURL(for: video, maxHeight: 720)
                            ?? session.library?.artworkURL(for: video, style: .landscape),
                        aspectRatio: 16 / 9,
                        contentMode: .fill
                    )
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 68, height: 68)
                        .overlay {
                            Image(systemName: "play.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.white)
                                .offset(x: 2)
                        }
                    VStack {
                        Spacer()
                        if video.showsResumeProgress {
                            YouTubeProgressBar(progress: video.progress)
                        }
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 0) {
                Text(video.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.top, 14)
                if !metaLine.isEmpty {
                    Text(metaLine)
                        .font(.footnote)
                        .foregroundStyle(YouTubeText.muted)
                        .padding(.top, 6)
                }

                if let channel {
                    NavigationLink {
                        ItemDetailView(item: channel)
                    } label: {
                        HStack(spacing: 12) {
                            YouTubeChannelAvatar(channel: channel, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(channel.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(YouTubeText.videoCountLabel(videos.count))
                                    .font(.caption)
                                    .foregroundStyle(YouTubeText.muted)
                            }
                            Spacer(minLength: 8)
                            YouTubePill(
                                label: channel.isFavorite ? "Favorited" : "Favorite",
                                systemImage: channel.isFavorite ? "heart.fill" : "heart",
                                style: channel.isFavorite ? .outline : .red,
                                compact: true
                            ) {
                                Task { await toggleFavorite(channel, onChange: onChangeChannel) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        YouTubePill(
                            label: video.showsResumeProgress ? "Resume" : "Play",
                            systemImage: "play.fill",
                            style: .filled,
                            compact: true
                        ) { onPlay(video) }
                        YouTubePill(
                            label: video.isWatched ? "Watched" : "Mark watched",
                            systemImage: video.isWatched ? "checkmark.circle.fill" : "checkmark.circle",
                            style: .outline,
                            compact: true
                        ) {
                            Task { await toggleWatched() }
                        }
                        YouTubePill(
                            label: video.isFavorite ? "Favorited" : "Favorite",
                            systemImage: video.isFavorite ? "heart.fill" : "heart",
                            style: .outline,
                            compact: true
                        ) {
                            Task { await toggleFavorite(video, onChange: onChangeVideo) }
                        }
                    }
                }
                .padding(.top, 14)

                if let about = video.overview.flatMap(YouTubeText.plainDescription) {
                    Button {
                        descriptionExpanded.toggle()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(about)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.88))
                                .lineLimit(descriptionExpanded ? nil : 3)
                                .multilineTextAlignment(.leading)
                            Text(descriptionExpanded ? "Show less" : "more")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(YouTubeText.chipFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 14)
                }
            }
            .padding(.horizontal, 16)

            if let channel, !others.isEmpty {
                Text("More from \(channel.name)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 8)
                ForEach(others) { other in
                    YouTubeVideoRow(
                        video: other,
                        channel: channel,
                        onPlay: { onPlay(other) },
                        onChangeVideo: { updated in
                            onChangeVideos(videos.map { $0.id == updated.id ? updated : $0 })
                        },
                        onChangeChannel: onChangeChannel
                    )
                }
            }
        }
        .padding(.bottom, 40)
    }

    private func toggleFavorite(_ item: MediaItem, onChange: (MediaItem) -> Void) async {
        guard let updated = try? await session.toggleFavorite(item) else { return }
        onChange(updated)
    }

    private func toggleWatched() async {
        do {
            if video.isWatched {
                try await session.markUnwatched(video)
            } else {
                try await session.markWatched(video)
            }
            if let updated = try? await session.library?.item(id: video.id) {
                onChangeVideo(updated)
                onChangeVideos(videos.map { $0.id == updated.id ? updated : $0 })
            }
        } catch {}
    }
}

private struct YouTubeVideoRow: View {
    let video: MediaItem
    let channel: MediaItem
    var onPlay: () -> Void
    var onChangeVideo: (MediaItem) -> Void
    var onChangeChannel: (MediaItem) -> Void

    @Environment(SessionStore.self) private var session

    private var caption: String {
        [channel.name, YouTubeText.publishedAgo(video.premiereDate)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                ItemDetailView(item: video)
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    PosterImage(
                        url: session.library?.primaryURL(for: video, maxHeight: 720)
                            ?? session.library?.artworkURL(for: video, style: .landscape),
                        aspectRatio: 16 / 9,
                        contentMode: .fill,
                        fill: Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
                    )
                    .aspectRatio(16 / 9, contentMode: .fit)
                    if let length = YouTubeText.videoLengthLabel(video.runtime) {
                        Text(length)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .padding(8)
                    }
                    VStack {
                        Spacer()
                        if video.showsResumeProgress {
                            YouTubeProgressBar(progress: video.progress)
                        } else if video.isWatched {
                            YouTubeProgressBar(progress: 1)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)

            HStack(alignment: .top, spacing: 12) {
                YouTubeChannelAvatar(channel: channel, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(video.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if !caption.isEmpty {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(YouTubeText.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Menu {
                    YouTubeUserActions(
                        item: video,
                        channel: channel,
                        onPlay: onPlay,
                        onChange: onChangeVideo
                    )
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 12)
            .padding(.top, 12)
        }
        .padding(.bottom, 20)
    }
}

struct YouTubeUserActions: View {
    let item: MediaItem
    var channel: MediaItem? = nil
    var onPlay: (() -> Void)? = nil
    var onChange: (MediaItem) -> Void
    var onPlayElsewhere: (() -> Void)? = nil
    var onSyncPlay: (() -> Void)? = nil
    var onRefreshMetadata: (() -> Void)? = nil

    @Environment(SessionStore.self) private var session
    @Environment(DownloadStore.self) private var downloads
    @Environment(\.openURL) private var openURL

    private var isChannel: Bool { item.kind == .series }

    var body: some View {
        if let onPlay {
            Button(
                playTitle,
                systemImage: "play.fill",
                action: onPlay
            )
        }
        if !isChannel, let channel {
            NavigationLink {
                ItemDetailView(item: channel)
            } label: {
                Label("Go to Channel", systemImage: "person.crop.circle")
            }
        }
        Button(watchedTitle, systemImage: item.isWatched ? "eye.slash" : "checkmark.circle") {
            Task { await toggleWatched() }
        }
        if !isChannel, session.downloadsAvailable {
            Button(downloadTitle, systemImage: downloadSymbol) {
                Task { await toggleDownload() }
            }
        }
        Button {
            Task { await toggleFavorite() }
        } label: {
            Label(
                item.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: item.isFavorite ? "heart.fill" : "heart"
            )
        }
        if !isChannel, !session.usesSilo {
            Button {
                Task { await toggleWatchLater() }
            } label: {
                Label(
                    item.isWatchlisted ? "Remove from Watch Later" : "Save to Watch Later",
                    systemImage: "clock"
                )
            }
        }
        if let url = item.youTubeURL {
            Button("Open in YouTube", systemImage: "arrow.up.right.square") {
                openURL(url)
            }
        }
        if !isChannel, let onPlayElsewhere, !session.usesSilo {
            Button("Play on Another Device…", systemImage: "tv.badge.wifi", action: onPlayElsewhere)
        }
        if !isChannel, let onSyncPlay, !session.usesSilo {
            Button("Watch Together…", systemImage: "person.2.wave.2", action: onSyncPlay)
        }
        if let onRefreshMetadata {
            Divider()
            Button("Refresh from TubeArchivist", systemImage: "arrow.clockwise", action: onRefreshMetadata)
        }
    }

    private var playTitle: String {
        if isChannel { return "Play Latest" }
        return item.showsResumeProgress ? "Resume" : "Play"
    }

    private var watchedTitle: String {
        switch (isChannel, item.isWatched) {
        case (true, true): "Mark Channel as Unwatched"
        case (true, false): "Mark Channel as Watched"
        case (false, true): "Mark as Unwatched"
        case (false, false): "Mark as Watched"
        }
    }

    private var downloadTitle: String {
        switch downloads.control(for: item, account: session.session) {
        case .idle: "Download Video"
        case let state: DownloadControlCopy.title(for: state)
        }
    }

    private var downloadSymbol: String {
        DownloadControlCopy.symbol(for: downloads.control(for: item, account: session.session))
    }

    private func toggleFavorite() async {
        guard let updated = try? await session.toggleFavorite(item) else { return }
        onChange(updated)
    }

    private func toggleWatchLater() async {
        guard let updated = try? await session.toggleWatchlist(item) else { return }
        onChange(updated)
    }

    private func toggleWatched() async {
        do {
            if item.isWatched {
                try await session.markUnwatched(item)
            } else {
                try await session.markWatched(item)
            }
            if let updated = try? await session.library?.item(id: item.id) {
                onChange(updated)
            }
        } catch {}
    }

    private func toggleDownload() async {
        _ = try? await downloads.toggle(item: item, library: session.library, account: session.session)
    }
}

private struct YouTubeChannelAvatar: View {
    let channel: MediaItem
    let size: CGFloat

    @Environment(SessionStore.self) private var session

    var body: some View {
        ZStack {
            Circle().fill(Color(red: 42 / 255, green: 42 / 255, blue: 46 / 255))
            if session.library?.primaryURL(for: channel, maxHeight: 240) != nil {
                PosterImage(
                    url: session.library?.primaryURL(for: channel, maxHeight: 240),
                    aspectRatio: 1,
                    contentMode: .fill,
                    fill: .clear
                )
            } else if let letter = channel.name.first {
                Text(String(letter).uppercased())
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

private struct YouTubePill: View {
    enum Style {
        case filled
        case outline
        case red
    }

    let label: String
    var systemImage: String? = nil
    var style: Style
    var compact: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: compact ? 13 : 16, weight: .semibold))
                }
                Text(label)
                    .font(compact ? .subheadline.weight(.semibold) : .body.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, compact ? 14 : 18)
            .frame(height: compact ? 36 : 42)
            .frame(maxWidth: style == .filled || style == .red ? .infinity : nil)
            .background(fill, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var tint: Color {
        style == .filled ? .black : .white
    }

    private var fill: Color {
        switch style {
        case .filled: .white
        case .outline: YouTubeText.chipFill
        case .red: YouTubeText.red
        }
    }
}

private struct YouTubeSortChip: View {
    let label: String
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? .black : .white)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(selected ? Color.white : YouTubeText.chipFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct YouTubeProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.white.opacity(0.35)
                YouTubeText.red
                    .frame(width: geo.size.width * progress.clamped(to: 0...1))
            }
        }
        .frame(height: 4)
    }
}

private struct YouTubeExpandableText: View {
    let text: String
    var collapsedLines: Int
    @State private var expanded = false

    init(_ text: String, collapsedLines: Int) {
        self.text = text
        self.collapsedLines = collapsedLines
    }

    var body: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(alignment: .bottom, spacing: 6) {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(YouTubeText.muted)
                    .lineLimit(expanded ? nil : collapsedLines)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(expanded ? "less" : "more")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
    }
}
