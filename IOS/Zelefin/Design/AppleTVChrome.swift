import SwiftUI
import UIKit

extension CGSize {
    func scaled(by factor: CGFloat) -> CGSize {
        CGSize(width: width * factor, height: height * factor)
    }
}

/// Horizontal pill that keeps circular end caps. Scaling a capsule in X flattens the
/// leading radius, so the fill is sized by width instead.
struct CapsuleProgressBar: View {
    var progress: Double
    var width: CGFloat
    var height: CGFloat
    var track: Color = Color.black.opacity(0.28)
    var fill: Color = Color.black.opacity(0.82)

    var body: some View {
        let clamped = min(1, max(0, progress))
        Capsule()
            .fill(track)
            .overlay(alignment: .leading) {
                if clamped > 0 {
                    Capsule()
                        .fill(fill)
                        .frame(width: max(height, width * clamped), height: height)
                }
            }
            .clipShape(Capsule())
            .frame(width: width, height: height)
    }
}

enum PosterMetrics {
    static var landscapeSize: CGSize {
        CGSize(width: 280, height: 158)
    }

    /// Episode still width; text stacks tightly under the image.
    static var episodeCardWidth: CGFloat {
        252
    }

    static var episodeCardSize: CGSize {
        let width = episodeCardWidth
        let textHeight: CGFloat = 132
        return CGSize(width: width, height: (width * 9 / 16) + textHeight)
    }

    static var portraitSize: CGSize {
        CGSize(width: 124, height: 186)
    }

    static var aboutCardHeight: CGFloat {
        164
    }

    static var aboutSynopsisCardSize: CGSize {
        CGSize(width: 304, height: aboutCardHeight)
    }

    static var aboutRatingCardSize: CGSize {
        CGSize(width: 152, height: aboutCardHeight)
    }

    static var aboutCardCornerRadius: CGFloat {
        16
    }

    static var cornerRadius: CGFloat {
        10
    }

    static var rowSpacing: CGFloat {
        10
    }

    static var heroHeight: CGFloat {
        heroHeight(for: CGSize(width: 390, height: 844))
    }

    static func heroHeight(for size: CGSize) -> CGFloat {
        max(680, size.height * 0.82)
    }

}

/// Holds the hero height measured when a page first appears. The tab bar and mini player
/// change the available height as they collapse on scroll; re-measuring made the hero resize.
struct HeroHeightLock: Equatable {
    private var width: CGFloat = 0
    private var locked: CGFloat?

    func height(for size: CGSize) -> CGFloat {
        if let locked, width == size.width { return locked }
        return PosterMetrics.heroHeight(for: size)
    }

    mutating func lock(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        guard locked == nil || width != size.width else { return }
        width = size.width
        locked = PosterMetrics.heroHeight(for: size)
    }
}

enum PosterChrome {
    /// Hairline around cover art — same overlay as Vellum’s `AlbumArtworkView`.
    static let outlineWidth: CGFloat = 1

    static func outline(for colorScheme: ColorScheme) -> Color {
        Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.07)
    }
}

private struct PosterCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    PosterChrome.outline(for: colorScheme),
                    lineWidth: PosterChrome.outlineWidth
                )
            }
    }
}

extension View {
    /// Clips artwork and draws Vellum’s cover-art hairline on top.
    func posterCard(cornerRadius: CGFloat = PosterMetrics.cornerRadius) -> some View {
        modifier(PosterCardModifier(cornerRadius: cornerRadius))
    }
}

struct PosterImage: View {
    let url: URL?
    var aspectRatio: CGFloat = 2 / 3
    var contentMode: ContentMode = .fill
    var fill: Color?
    var progressTint: Color = Color.white.opacity(0.6)
    @Environment(\.libraryArtworkRevision) private var artworkRevision
    @Environment(\.zelefinSurfaces) private var surfaces
    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Rectangle()
                .fill(fill ?? surfaces.raised)
            if let shown = image ?? url.flatMap({ ArtworkCache.shared.image(for: $0) }) {
                Image(uiImage: shown)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoading {
                ProgressView()
                    .tint(progressTint)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: "\(url?.absoluteString ?? "")-\(artworkRevision)") { await load() }
    }

    private func load() async {
        guard let url else {
            image = nil
            isLoading = false
            return
        }
        if let cached = ArtworkCache.shared.image(for: url) {
            image = cached
            isLoading = false
            return
        }
        image = nil
        isLoading = true
        if let loaded = await ArtworkCache.shared.load(from: url) {
            guard !Task.isCancelled else { return }
            image = loaded
        }
        isLoading = false
    }
}

/// Lives in the scroll content under the header so it stays at the top of the page
/// and leaves the screen when you scroll.
struct CatalogIndexBar: View {
    var progress: CatalogIndexProgress?

    var body: some View {
        if let progress {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(progress.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Spacer(minLength: 8)
                    Text(progress.countLabel)
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
                CatalogIndexTrack(fraction: progress.fraction, isDeterminate: progress.isDeterminate)
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(progress.label)
            .accessibilityValue(progress.countLabel)
        }
    }
}

private struct CatalogIndexTrack: View {
    var fraction: CGFloat
    var isDeterminate: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(Color.white.opacity(isDeterminate ? 0.7 : 0.28))
                    .frame(width: max(10, geo.size.width * (isDeterminate ? fraction : 0.32)))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.2), value: fraction)
    }
}

/// UIImageView fills its SwiftUI frame; resizable Image often letterboxes instead.
private final class FillingUIImageView: UIImageView {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
}

private struct FillingImageView: UIViewRepresentable {
    var image: UIImage?

    func makeUIView(context: Context) -> FillingUIImageView {
        let view = FillingUIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.backgroundColor = .clear
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: FillingUIImageView, context: Context) {
        view.image = image
    }
}

struct SectionHeader: View {
    let title: String
    var showsChevron = true

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }
}

struct LandscapeCard: View {
    let item: MediaItem
    let imageURL: URL?
    var showsOverflowIcon = true
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    @Environment(DownloadStore.self) private var downloads
    @Environment(SessionStore.self) private var session

    private var size: CGSize {
        PosterMetrics.landscapeSize.scaled(by: sidebarLayout.scale)
    }

    var body: some View {
        PosterImage(url: downloads.posterURL(for: item, account: session.session, remote: imageURL), aspectRatio: 16 / 9)
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .bottom) {
                footer
            }
            .overlay {
                DownloadCoverBadge(item: item)
            }
            .posterCard()
            .overlay(alignment: .topLeading) {
                PosterQualityBadgeStack(item: item, compact: true)
            }
            .frame(width: size.width, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityCaption)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 44)
            .overlay(alignment: .bottom) {
                HStack(spacing: 6) {
                    if item.showsResumeProgress {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                        resumeBar
                    }
                    if let caption = item.continueWatchingCaption {
                        Text(caption)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 4)
                    if showsOverflowIcon {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .bold))
                    } else {
                        Color.clear
                            .frame(width: 18, height: 18)
                    }
                }
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
        .allowsHitTesting(false)
    }

    private var resumeBar: some View {
        CapsuleProgressBar(
            progress: item.progress,
            width: 22,
            height: 3.5,
            track: .white.opacity(0.32),
            fill: .white.opacity(0.75)
        )
    }

    private var accessibilityCaption: String {
        var parts = [item.name, item.continueWatchingCaption].compactMap { $0 }
        if let download = downloads.coverMark(for: item, account: session.session).accessibilityCaption {
            parts.append(download)
        }
        let quality = PosterQualityBadges.badges(for: item).map(\.accessibilityLabel)
        if !quality.isEmpty {
            parts.append(contentsOf: quality)
        }
        return parts.joined(separator: ", ")
    }
}

struct ReplayLandscapeCard: View {
    let item: MediaItem
    let imageURL: URL?
    var showsOverflowIcon = true
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    @Environment(DownloadStore.self) private var downloads
    @Environment(SessionStore.self) private var session

    private var size: CGSize {
        PosterMetrics.landscapeSize.scaled(by: sidebarLayout.scale)
    }

    var body: some View {
        PosterImage(url: downloads.posterURL(for: item, account: session.session, remote: imageURL), aspectRatio: 16 / 9)
            .frame(width: size.width, height: size.height)
            .overlay {
                DownloadCoverBadge(item: item)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 62 * sidebarLayout.scale)
                .overlay(alignment: .bottom) {
                    HStack(alignment: .bottom, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.continueWatchingTitle)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 10, weight: .bold))
                                if let caption = item.recentlyWatchedCaption {
                                    Text(caption)
                                        .font(.caption2.weight(.semibold))
                                        .lineLimit(1)
                                }
                            }
                            .opacity(0.78)
                        }
                        Spacer(minLength: 4)
                        if showsOverflowIcon {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 18, weight: .bold))
                                .padding(.bottom, 2)
                        } else {
                            Color.clear
                                .frame(width: 18, height: 18)
                                .padding(.bottom, 2)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
            }
            .posterCard()
            .overlay(alignment: .topLeading) {
                PosterQualityBadgeStack(item: item, compact: true)
            }
            .frame(width: size.width, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityCaption)
    }

    private var accessibilityCaption: String {
        var parts = [item.continueWatchingTitle, item.recentlyWatchedCaption].compactMap { $0 }
        if let download = downloads.coverMark(for: item, account: session.session).accessibilityCaption {
            parts.append(download)
        }
        let quality = PosterQualityBadges.badges(for: item).map(\.accessibilityLabel)
        if !quality.isEmpty {
            parts.append(contentsOf: quality)
        }
        return parts.joined(separator: ", ")
    }
}

struct TrailerLandscapeCard: View {
    let title: String
    let caption: String
    let imageURL: URL?
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout

    private var size: CGSize {
        PosterMetrics.landscapeSize.scaled(by: sidebarLayout.scale)
    }

    var body: some View {
        PosterImage(url: imageURL, aspectRatio: 16 / 9)
            .frame(width: size.width, height: size.height)
            .overlay {
                Image(systemName: "play.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.48), in: Circle())
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.55), lineWidth: 0.8)
                    }
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 62 * sidebarLayout.scale)
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(caption)
                            .font(.caption2.weight(.semibold))
                            .opacity(0.78)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
            }
            .posterCard()
            .frame(width: size.width, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(caption)")
            .accessibilityAddTraits(.isButton)
    }
}

struct EpisodeShowcaseCard: View {
    @Environment(\.zelefinSurfaces) private var surfaces
    let item: MediaItem
    let imageURL: URL?
    var showsOverflowIcon = true
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    @Environment(DownloadStore.self) private var downloads
    @Environment(SessionStore.self) private var session

    private var size: CGSize {
        PosterMetrics.episodeCardSize.scaled(by: sidebarLayout.scale)
    }
    private var imageHeight: CGFloat { size.width * 9 / 16 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PosterImage(
                url: downloads.posterURL(for: item, account: session.session, remote: imageURL),
                aspectRatio: 16 / 9
            )
                .frame(width: size.width, height: imageHeight)
                .clipped()
                .overlay {
                    DownloadCoverBadge(item: item, padded: false)
                }
                .overlay(alignment: .topTrailing) {
                    if item.isWatched {
                        PosterWatchedMark(size: markSize)
                            .padding(markPadding)
                    }
                }

            VStack(alignment: .leading, spacing: 0) {
                Text(item.episodeOrdinalLabel ?? " ")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.55))
                    .opacity(item.episodeOrdinalLabel == nil ? 0 : 1)
                    .lineLimit(1)
                    .padding(.bottom, 3)

                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.bottom, 4)

                Text(item.overview ?? " ")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48, alignment: .topLeading)
                    .padding(.bottom, 8)

                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                    if let runtime = item.runtimeLabel {
                        Text(runtime)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                    Spacer(minLength: 4)
                    if showsOverflowIcon {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white.opacity(0.72))
                    } else {
                        Color.clear
                            .frame(width: 16, height: 16)
                    }
                }
                .foregroundStyle(.white.opacity(0.84))
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(width: size.width, height: size.height - imageHeight, alignment: .topLeading)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(surfaces.raised)
        .posterCard()
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityCaption)
        .accessibilityAddTraits(.isButton)
    }

    private var markSize: CGFloat {
        22
    }

    private var markPadding: CGFloat {
        8
    }

    private var accessibilityCaption: String {
        var parts = [item.episodeOrdinalLabel, item.name, item.runtimeLabel].compactMap { $0 }
        if item.isWatched {
            parts.append("Watched")
        }
        if let download = downloads.coverMark(for: item, account: session.session).accessibilityCaption {
            parts.append(download)
        }
        return parts.joined(separator: ", ")
    }
}

struct LabeledPortraitCard: View {
    let title: String
    let imageURL: URL?
    var collection: MediaItem? = nil
    var washColor: Color? = nil
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    var cornerRadius: CGFloat = PosterMetrics.cornerRadius
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout

    private var fittedWidth: CGFloat {
        width ?? PosterMetrics.portraitSize.width * sidebarLayout.scale
    }

    private var fittedHeight: CGFloat {
        height ?? PosterMetrics.portraitSize.height * sidebarLayout.scale
    }

    static func genreWash(for title: String) -> Color {
        let palette: [(hue: Double, saturation: Double, brightness: Double)] = [
            (0.00, 0.98, 0.96),
            (0.07, 1.00, 1.00),
            (0.13, 1.00, 1.00),
            (0.32, 0.95, 0.88),
            (0.47, 1.00, 0.92),
            (0.54, 1.00, 1.00),
            (0.60, 0.95, 1.00),
            (0.72, 0.88, 1.00),
            (0.83, 0.92, 1.00),
            (0.92, 0.90, 1.00)
        ]
        let hash = title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) &* 37 }
        let swatch = palette[abs(hash) % palette.count]
        return Color(hue: swatch.hue, saturation: swatch.saturation, brightness: swatch.brightness)
    }

    var body: some View {
        Color.clear
            .frame(width: fittedWidth, height: fittedHeight)
            .background {
                ZStack {
                    fallbackFill
                    if let collection, collection.usesGeneratedCollage {
                        CollectionCover(item: collection, width: fittedWidth, height: fittedHeight)
                    } else {
                        PosterImage(url: imageURL)
                            .frame(width: fittedWidth, height: fittedHeight)
                    }
                }
            }
            .overlay {
                if let washColor {
                    washColor.opacity(0.70)
                }
            }
            .overlay {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.82)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 1)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: max(0, fittedWidth - 16), alignment: .leading)
                    .padding(.leading, 8)
                    .padding(.bottom, 8)
            }
            .clipped()
            .posterCard(cornerRadius: cornerRadius)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityLabel(title)
    }

    private var fallbackFill: some View {
        Rectangle()
            .fill(Self.genreWash(for: title))
    }
}

extension MediaItem {
    /// Jellyfin draws an untagged box-set Primary as a 2×2 collage and leaves a grey cell
    /// when a child has no poster.
    var usesGeneratedCollage: Bool {
        kind == .collection && primaryImageTag == nil && posterURL == nil
    }
}

private struct CollectionCover: View {
    @Environment(SessionStore.self) private var session
    let item: MediaItem
    let width: CGFloat
    let height: CGFloat
    @State private var members: [MediaItem]?

    var body: some View {
        Group {
            if let members {
                let posters = Array(members.prefix(4))
                if posters.isEmpty {
                    PosterImage(url: session.library?.primaryURL(for: item))
                } else {
                    CollectionCollage(posters: posters)
                }
            } else {
                Color(red: 0.11, green: 0.11, blue: 0.11)
            }
        }
        .frame(width: width, height: height)
        .task(id: item.id) {
            guard let client = session.library as? JellyfinLibraryClient else {
                members = []
                return
            }
            let loaded = await client.collectionPosterMembers(parentID: item.id)
            guard !Task.isCancelled else { return }
            members = loaded
        }
    }
}

private struct CollectionCollage: View {
    @Environment(SessionStore.self) private var session
    let posters: [MediaItem]

    var body: some View {
        let rows: [[MediaItem]] = posters.count <= 2
            ? [posters]
            : [Array(posters.prefix(2)), Array(posters.dropFirst(2).prefix(2))]
        GeometryReader { geo in
            let gaps = CGFloat(max(rows.count - 1, 0))
            let rowHeight = max(0, (geo.size.height - gaps) / CGFloat(rows.count))
            VStack(spacing: 1) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 1) {
                        ForEach(row) { poster in
                            PosterImage(
                                url: session.library?.primaryURL(for: poster),
                                contentMode: .fill,
                                fill: Color(red: 0.11, green: 0.11, blue: 0.11)
                            )
                        }
                    }
                    .frame(height: rowHeight)
                }
            }
        }
    }
}

/// Accent-tinted card with the genre mark and name in Outfit Bold, like Android's `GenreCard`.
struct GenrePosterCard: View {
    let title: String
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    var cornerRadius: CGFloat = PosterMetrics.cornerRadius
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    @Environment(\.zelefinSurfaces) private var surfaces

    var body: some View {
        let fittedWidth = width ?? PosterMetrics.portraitSize.width * sidebarLayout.scale
        let fittedHeight = height ?? PosterMetrics.portraitSize.height * sidebarLayout.scale
        let size = CGSize(width: fittedWidth, height: fittedHeight)
        ZStack(alignment: .bottomLeading) {
            GenreCardBackdrop(base: surfaces.genreBase, glow: surfaces.genreGlow)
                .overlay(alignment: .topTrailing) { monogram(in: size) }
                .clipped()
            VStack(alignment: .leading, spacing: size.width * 0.05) {
                Capsule(style: .continuous)
                    .fill(surfaces.content.opacity(0.85))
                    .frame(width: size.width * 0.16, height: max(2, size.width * 0.02))
                Text(title)
                    .font(.custom("Outfit", size: size.width * 0.17).weight(.black))
                    .foregroundStyle(surfaces.content)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                    .lineLimit(3)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(size.width * 0.08)
        }
        .frame(width: fittedWidth, height: fittedHeight)
        .posterCard(cornerRadius: cornerRadius)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityLabel(title)
    }

    /// The genre's initial, oversized and bleeding off the top corner, fading out before the title.
    @ViewBuilder
    private func monogram(in size: CGSize) -> some View {
        if let initial = title.first {
            Text(String(initial).uppercased())
                .font(.custom("Outfit", size: size.height * 0.72).weight(.black))
                .foregroundStyle(
                    LinearGradient(
                        colors: [surfaces.genreGlow.opacity(0.75), surfaces.genreGlow.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .fixedSize()
                .offset(x: size.width * 0.12, y: -size.height * 0.22)
                .accessibilityHidden(true)
        }
    }
}
/// Dot grid under an off-centre elliptical glow, both in the accent hue. Same layers as the CSS
/// `radial-gradient(#ffffff33 1px, transparent 1px)` at 16px, then
/// `radial-gradient(150% 80% at 25% 75%, glow/0.5 35%, base 100%)` over a `base` fill.
struct GenreCardBackdrop: View {
    let base: Color
    let glow: Color
    /// A touch above the CSS 0.5 so the accent reads through on small cards.
    static let glowOpacity = 0.6

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            context.fill(Path(bounds), with: .color(base))

            let spacing: CGFloat = 16
            var dots = Path()
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                    x += spacing
                }
                y += spacing
            }
            context.fill(dots, with: .color(.white.opacity(0.2)))

            // A radial gradient is circular, so squash the context to make the 150% x 80% ellipse.
            let radiusX = size.width * 1.5
            let radiusY = size.height * 0.8
            guard radiusX > 0, radiusY > 0 else { return }
            let squash = radiusY / radiusX
            var glowContext = context
            glowContext.scaleBy(x: 1, y: squash)
            glowContext.fill(
                Path(CGRect(x: 0, y: 0, width: size.width, height: size.height / squash)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: glow.opacity(GenreCardBackdrop.glowOpacity), location: 0),
                        .init(color: glow.opacity(GenreCardBackdrop.glowOpacity), location: 0.35),
                        .init(color: base, location: 1)
                    ]),
                    center: CGPoint(x: size.width * 0.25, y: size.height * 0.75 / squash),
                    startRadius: 0,
                    endRadius: radiusX
                )
            )
        }
        .accessibilityHidden(true)
    }
}

struct PosterWatchedMark: View {
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color.black.opacity(0.78))
            .font(.system(size: size, weight: .semibold))
            .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
            .accessibilityHidden(true)
    }
}

/// A compact IMDb-style community-rating badge (★ 7.5) for a poster corner,
/// shown only when a title carries a rating on the 0–10 scale. Same visual
/// language as the quality badges.
struct PosterRatingBadge: View {
    let rating: Double

    /// The rating is only meaningful as a star score on the 0–10 scale; RT-style
    /// percentages (which can land in `communityRating`) are skipped rather than
    /// shown as a misleading "85.0".
    static func starScore(from rating: Double?) -> Double? {
        guard let rating, rating > 0, rating <= 10 else { return nil }
        return rating
    }

    private var text: String { String(format: "%.1f", rating) }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.yellow)
            Text(text)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2.5)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
        .accessibilityElement()
        .accessibilityLabel("Rated \(text) out of 10")
    }
}

struct PortraitPoster: View {
    let item: MediaItem
    let imageURL: URL?
    var rank: Int?
    var size: CGSize? = nil
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    @Environment(DownloadStore.self) private var downloads
    @Environment(SessionStore.self) private var session

    private var fittedSize: CGSize {
        size ?? PosterMetrics.portraitSize.scaled(by: sidebarLayout.scale)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            PosterImage(url: downloads.posterURL(for: item, account: session.session, remote: imageURL))
                .frame(width: fittedSize.width, height: fittedSize.height)
                .overlay {
                    DownloadCoverBadge(item: item)
                }
                .posterCard()
                .overlay(alignment: .bottomLeading) {
                    PosterQualityBadgeStack(item: item)
                }
                .overlay(alignment: .topLeading) {
                    if rank == nil, let score = PosterRatingBadge.starScore(from: item.communityRating) {
                        PosterRatingBadge(rating: score)
                            .padding(6)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        if item.isWatched {
                            PosterWatchedMark()
                        }
                        if rank != nil, let score = PosterRatingBadge.starScore(from: item.communityRating) {
                            PosterRatingBadge(rating: score)
                        }
                    }
                    .padding(6)
                }

            if let rank {
                Text("\(rank)")
                    .font(.system(size: 44 * sidebarLayout.scale, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.leading, 8)
                    .padding(.top, 4)
            }
        }
        .frame(width: fittedSize.width, alignment: .leading)
        .accessibilityLabel(accessibilityCaption)
    }

    private var accessibilityCaption: String {
        var parts = [item.name]
        if item.isWatched {
            parts.append("Watched")
        }
        if let score = PosterRatingBadge.starScore(from: item.communityRating) {
            parts.append("Rated \(String(format: "%.1f", score)) out of 10")
        }
        if let download = downloads.coverMark(for: item, account: session.session).accessibilityCaption {
            parts.append(download)
        }
        let quality = PosterQualityBadges.badges(for: item).map(\.accessibilityLabel)
        if !quality.isEmpty {
            parts.append(contentsOf: quality)
        }
        return parts.joined(separator: ", ")
    }
}

struct FillingPortraitPoster: View {
    let item: MediaItem
    let imageURL: URL?
    var rank: Int? = nil

    var body: some View {
        FillingPosterCell { size in
            PortraitPoster(item: item, imageURL: imageURL, rank: rank, size: size)
        }
    }
}

struct CastMemberCard: View {
    let person: CreditPerson
    let imageURL: URL?
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout

    private var photoSize: CGFloat { 110 * sidebarLayout.scale }

    var body: some View {
        VStack(spacing: 8) {
            PosterImage(url: imageURL, aspectRatio: 1)
                .frame(width: photoSize, height: photoSize)
                .clipShape(Circle())

            VStack(spacing: 2) {
                Text(person.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(person.roleLabel)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .frame(width: photoSize + 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(person.name), \(person.roleLabel)")
    }
}

struct TitleLogo: View {
    @Environment(SessionStore.self) private var session
    let item: MediaItem
    var maxHeight: CGFloat = 88
    var fallbackFont: Font = .title.weight(.bold)
    var alignment: Alignment = .center

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        let shown = image ?? session.library?.logoURL(for: item).flatMap { ArtworkCache.shared.image(for: $0) }
        Group {
            if let shown {
                Image(uiImage: shown)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: maxHeight)
            } else {
                Text(item.name)
                    .font(fallbackFont)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(alignment == .leading ? .leading : .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .accessibilityLabel(item.name)
        .task(id: "\(item.id)-\(item.logoImageTag ?? "")-\(session.artworkRevision)") { await load() }
    }

    private func load() async {
        failed = false
        guard let url = session.library?.logoURL(for: item) else {
            image = nil
            return
        }
        if let cached = ArtworkCache.shared.image(for: url) {
            image = cached
            return
        }
        if let loaded = await ArtworkCache.shared.load(from: url) {
            guard !Task.isCancelled else { return }
            image = loaded
        } else {
            failed = true
        }
    }
}

struct RatingBadge: View {
    let rating: String

    var body: some View {
        Text(rating)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(.white, lineWidth: 1)
            }
            .accessibilityLabel(rating)
    }
}


/// Sharp hero art that fills its frame.
struct HeroArtwork: View {
    let url: URL?
    var placeholderURL: URL? = nil
    var size: CGSize? = nil
    @Environment(\.libraryArtworkRevision) private var artworkRevision
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let size, size.width > 1, size.height > 1 {
                layers(in: size)
            } else {
                GeometryReader { geo in
                    layers(in: geo.size)
                }
            }
        }
        .task(id: "\(url?.absoluteString ?? "")-\(placeholderURL?.absoluteString ?? "")-\(artworkRevision)") { await load() }
    }

    @ViewBuilder
    private func layers(in size: CGSize) -> some View {
        let shown = image
            ?? url.flatMap { ArtworkCache.shared.image(for: $0) }
            ?? placeholderURL.flatMap { ArtworkCache.shared.image(for: $0) }
        ZStack {
            if let shown {
                FillingImageView(image: shown)
                    .frame(width: size.width, height: size.height)
            } else {
                Color.black
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .allowsHitTesting(false)
    }

    private func load() async {
        image = url.flatMap { ArtworkCache.shared.image(for: $0) }
        if image != nil { return }
        image = placeholderURL.flatMap { ArtworkCache.shared.image(for: $0) }
        guard let url else { return }
        if let loaded = await ArtworkCache.shared.load(from: url) {
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}

extension View {
    /// Mirrors the hero under the sidebar frost — Apple's split-view / Liquid Glass treatment.
    /// iPhone has no sidebar; applying this there pulls the backdrop out of layout and
    /// stacks the Play control on the Home title.
    func zelefinHeroBackgroundExtension() -> some View {
        modifier(HeroBackgroundExtensionModifier())
    }
}

private struct HeroBackgroundExtensionModifier: ViewModifier {
    @Environment(\.tabBarPlacement) private var tabBarPlacement

    func body(content: Content) -> some View {
        if #available(iOS 26, *), tabBarPlacement == .sidebar {
            content.backgroundExtensionEffect()
        } else {
            content
        }
    }
}

private struct FeaturedHeroPagePan: UIGestureRecognizerRepresentable {
    var isEnabled: Bool
    var onPage: (Int) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(isEnabled: isEnabled, onPage: onPage)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.isEnabled = isEnabled
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onPage = onPage
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        guard recognizer.state == .ended else { return }
        let translation = recognizer.translation(in: recognizer.view)
        if let delta = FeaturedHeroPaging.selectionDelta(
            translation: CGSize(width: translation.x, height: translation.y)
        ) {
            context.coordinator.onPage(delta)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled: Bool
        var onPage: (Int) -> Void

        init(isEnabled: Bool, onPage: @escaping (Int) -> Void) {
            self.isEnabled = isEnabled
            self.onPage = onPage
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isEnabled, let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return FeaturedHeroPaging.shouldClaimPan(
                velocity: CGSize(width: velocity.x, height: velocity.y)
            )
        }
    }
}

struct FeaturedHero: View {
    let items: [MediaItem]
    let size: CGSize
    let imageURL: (MediaItem) -> URL?

    @Environment(SessionStore.self) private var session
    @State private var selection: String?
    @State private var slideStartedAt = Date()
    @State private var playingItem: MediaItem?
    @State private var playbackError: String?
    @State private var pauseDwell = false
    @State private var detailItem: MediaItem?

    private static let dwell: TimeInterval = 6
    private static let dotSize: CGFloat = 7
    private static let pillWidth: CGFloat = 24

    private var slides: [MediaItem] {
        Array(items.prefix(8))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let item = currentSlide {
                slide(item)
            }

            if slides.count > 1 {
                TimelineView(.periodic(from: .now, by: 1 / 30)) { context in
                    heroPageDots(progress: slideProgress(at: context.date))
                }
                .padding(.bottom, 14)
            }
        }
        .frame(width: size.width, height: size.height)
        .onAppear {
            if selection == nil {
                selection = slides.first?.id
            }
        }
        .task(id: "\(currentSlide?.id ?? "")-\(pauseDwell)") {
            guard !pauseDwell else { return }
            await dwellThenAdvance()
        }
        .onChange(of: currentSlide?.id) { _, _ in
            slideStartedAt = Date()
        }
        .navigationDestination(item: $detailItem) { item in
            ItemDetailView(item: item)
        }
        .presentsPlayerFromRoot($playingItem)
        .alert("Playback", isPresented: Binding(
            get: { playbackError != nil },
            set: { if !$0 { playbackError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playbackError ?? "")
        }
    }

    private var currentSlide: MediaItem? {
        slides.first(where: { $0.id == selection }) ?? slides.first
    }

    private func slideProgress(at date: Date) -> CGFloat {
        let elapsed = date.timeIntervalSince(slideStartedAt)
        return min(1, max(0, elapsed / Self.dwell))
    }

    private func heroPageDots(progress: CGFloat) -> some View {
        HStack(spacing: 6) {
            ForEach(slides) { item in
                let isActive = item.id == currentSlide?.id
                Capsule()
                    .fill(Color.white.opacity(0.38))
                    .frame(width: isActive ? Self.pillWidth : Self.dotSize, height: Self.dotSize)
                    .overlay(alignment: .leading) {
                        if isActive {
                            Capsule()
                                .fill(Color.white)
                                .frame(width: max(0, Self.pillWidth * progress), height: Self.dotSize)
                        }
                    }
                    .clipShape(Capsule())
                    .accessibilityHidden(true)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: currentSlide?.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Featured titles")
        .accessibilityValue(pageAccessibilityValue)
    }

    private var pageAccessibilityValue: String {
        guard let current = currentSlide, let index = slides.firstIndex(of: current) else { return "" }
        return "Slide \(index + 1) of \(slides.count)"
    }

    private func slide(_ item: MediaItem) -> some View {
        ZStack(alignment: .bottom) {
            ZStack {
                HeroArtwork(
                    url: imageURL(item),
                    placeholderURL: session.library?.primaryURL(for: item),
                    size: size
                )

                LinearGradient(
                    colors: [.black.opacity(0.55), .clear],
                    startPoint: .top,
                    endPoint: .center
                )

                LinearGradient(
                    colors: [.clear, .black.opacity(0.55), .black.opacity(0.96)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .zelefinHeroBackgroundExtension()
            .contentShape(Rectangle())
            .onTapGesture {
                detailItem = item
            }
            .gesture(
                FeaturedHeroPagePan(isEnabled: slides.count > 1) { delta in
                    moveSelection(by: delta)
                }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(item.name)
            .accessibilityHint("Opens details")
            .accessibilityAction(.default) {
                detailItem = item
            }

            VStack(spacing: 16) {
                VStack(spacing: 5) {
                    TitleLogo(item: item, maxHeight: 92)
                        .frame(maxWidth: 300)

                    HStack(spacing: 8) {
                        Text(item.heroMetadataLine)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.86))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        if let rating = item.officialRating, !rating.isEmpty {
                            RatingBadge(rating: rating)
                        }
                    }
                }
                .allowsHitTesting(false)

                HStack(spacing: 12) {
                    Button {
                        play(item)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.headline.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 36)
                            .padding(.vertical, 13)
                            .background(Color.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play")

                    PlaybackQueueOverflowButton(
                        item: item,
                        context: .featured,
                        onPlay: { play(item) },
                        usesHeroChrome: true,
                        onMenuVisibilityChange: { pauseDwell = $0 }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 56)
        }
        .frame(width: size.width, height: size.height)
    }

    private func moveSelection(by delta: Int) {
        let ids = slides.map(\.id)
        guard ids.count > 1 else { return }
        let current = selection ?? ids[0]
        let index = ids.firstIndex(of: current) ?? 0
        let next = ids[(index + delta + ids.count) % ids.count]
        withAnimation(.easeInOut(duration: 0.35)) {
            selection = next
        }
    }

    private func dwellThenAdvance() async {
        guard slides.count > 1 else { return }
        if selection == nil {
            selection = slides.first?.id
        }
        slideStartedAt = Date()
        try? await Task.sleep(for: .seconds(Self.dwell))
        guard !Task.isCancelled else { return }
        moveSelection(by: 1)
    }

    private func play(_ item: MediaItem) {
        if session.playIfSyncPlay(item) { return }
        playingItem = item
    }
}

extension View {
    /// Circular Liquid Glass bezel so content (the avatar) sits inside the ring, not over it.
    @ViewBuilder
    func zelefinLiquidGlassCircle(interactive: Bool = true) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: Circle())
        } else {
            self
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.32), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
        }
    }

    @ViewBuilder
    func zelefinLiquidGlassCapsule(interactive: Bool = true) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: Capsule(style: .continuous))
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
                }
        }
    }

    func zelefinPageChrome(_ title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PageHeaderProfileButton()
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
    }

    @ViewBuilder
    func zelefinScrollEdgeBlur() -> some View {
        if #available(iOS 26, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }

    @ViewBuilder
    func zelefinScrollEdgeHidden() -> some View {
        if #available(iOS 26, *) {
            self.scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
        }
    }

    /// Stops the rubber band at the bottom edge only. `tabBarMinimizeBehavior(.onScrollDown)`
    /// reads the bounce back from the bottom as an upward scroll and re-expands the dock.
    /// The top edge keeps its bounce so pull to refresh still works.
    func zelefinPinnedBottomEdge() -> some View {
        background(BottomEdgePin().allowsHitTesting(false))
    }

    func zelefinHeaderScrollVisibility(_ isVisible: Binding<Bool>) -> some View {
        modifier(HeaderScrollVisibilityModifier(isVisible: isVisible))
    }

    func zelefinLibraryListRow() -> some View {
        self
            .listRowBackground(Color.black)
            .listRowSeparatorTint(Color.white.opacity(0.16))
    }
}

enum ZelefinPillMetrics {
    static let height: CGFloat = 45
    static let iconSegmentWidth: CGFloat = 46
    static let dividerHeight: CGFloat = 20
    static let iconPointSize: CGFloat = 17
    static let iconFrame: CGFloat = 22
}

struct ZelefinGlassPillCluster<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) {
            content
        }
        .frame(height: ZelefinPillMetrics.height)
        .background {
            Color.clear
                .zelefinLiquidGlassCapsule(interactive: false)
        }
        .imageScale(.medium)
        .controlSize(.regular)
        .tint(.white)
        .accessibilityElement(children: .contain)
    }
}

struct ZelefinGlassPillDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.28))
            .frame(width: 1, height: ZelefinPillMetrics.dividerHeight)
            .allowsHitTesting(false)
    }
}

struct InteractivePopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {}

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enablePopGesture()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            enablePopGesture()
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }

        private func enablePopGesture() {
            guard let navigationController, let pop = navigationController.interactivePopGestureRecognizer else { return }
            pop.isEnabled = navigationController.viewControllers.count > 1
            pop.delegate = self
        }
    }
}

enum RootPageChrome {
    static let hideAfter: CGFloat = 20
    static let headerRowHeight: CGFloat = 59
    /// Space the iPad floating top tab bar occupies below the status bar.
    static let padTopTabBarClearance: CGFloat = 62
    /// Where the floating tab bar's centre line sits below the status bar, when it can't be measured.
    static let padTabBarCenterBelowStatusBar: CGFloat = 30

    static func showsTitle(idiom: UIUserInterfaceIdiom) -> Bool {
        idiom == .phone
    }

    @MainActor
    static var showsTitle: Bool {
        showsTitle(idiom: UIDevice.current.userInterfaceIdiom)
    }

    static func headerVisible(
        offset: CGFloat,
        previousOffset: CGFloat,
        wasVisible: Bool,
        distanceFromBottom: CGFloat = .greatestFiniteMagnitude
    ) -> Bool {
        if offset <= hideAfter { return true }
        let delta = offset - previousOffset
        if delta > 2 { return false }
        // A bottom bounce moves the offset upward without the user scrolling up.
        if delta < -2, distanceFromBottom > 24 { return true }
        return wasVisible
    }

    static func distanceFromBottom(_ geometry: ScrollGeometry) -> CGFloat {
        let visibleBottom = geometry.contentOffset.y + geometry.containerSize.height - geometry.contentInsets.bottom
        return geometry.contentSize.height - visibleBottom
    }

    /// Lift a safe-area overlay into the iPad top tab bar row, matching Home.
    static func padTabBarLift(usesPadTopChrome: Bool, isSidebarVisible: Bool) -> CGFloat {
        guard usesPadTopChrome, !isSidebarVisible else { return 0 }
        return -padTopTabBarClearance
    }

    /// iPad's floating tab bar and UINavigationBar wrap leading/trailing items onto a
    /// second row when a pushed page shows the system bar. Overlay those controls instead.
    @MainActor
    static var usesOverlayPushedBar: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    static func pushedOverlayTopPadding(
        contentIgnoresTopSafeArea: Bool,
        statusBarHeight: CGFloat
    ) -> CGFloat {
        contentIgnoresTopSafeArea ? statusBarHeight + 4 : 4
    }

    static func pushedOverlayLift(
        contentIgnoresTopSafeArea: Bool,
        usesPadTopChrome: Bool,
        isSidebarVisible: Bool
    ) -> CGFloat {
        guard !contentIgnoresTopSafeArea else { return 0 }
        return padTabBarLift(usesPadTopChrome: usesPadTopChrome, isSidebarVisible: isSidebarVisible)
    }
}

enum BottomEdgeClamp {
    /// Bounce stays on in the top half of the page (pull to refresh) and turns off in the
    /// bottom half, so UIKit stops at the bottom edge itself. Snapping the offset back after an
    /// overscroll still showed the tab bar an upward scroll and re-expanded it.
    static func shouldBounce(
        offsetY: CGFloat,
        contentHeight: CGFloat,
        viewportHeight: CGFloat,
        insetTop: CGFloat,
        insetBottom: CGFloat
    ) -> Bool {
        let minOffset = -insetTop
        let maxOffset = contentHeight + insetBottom - viewportHeight
        guard maxOffset > minOffset else { return true }
        return offsetY < (minOffset + maxOffset) / 2
    }
}

/// Finds the vertical scroll view it sits behind (same frame) and pins its bottom edge.
private struct BottomEdgePin: UIViewRepresentable {
    func makeUIView(context: Context) -> BottomEdgePinView {
        BottomEdgePinView()
    }

    func updateUIView(_ uiView: BottomEdgePinView, context: Context) {}
}

final class BottomEdgePinView: UIView {
    private weak var scrollView: UIScrollView?
    private var observation: NSKeyValueObservation?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            observation = nil
            scrollView = nil
        } else {
            DispatchQueue.main.async { [weak self] in self?.attachIfNeeded() }
        }
    }

    private func attachIfNeeded(retriesLeft: Int = 6) {
        guard scrollView == nil, let window, bounds.width > 1, bounds.height > 1 else { return }
        let target = convert(bounds, to: window)
        var ancestor = superview
        while let view = ancestor {
            if let match = Self.scrollView(in: view, matching: target, window: window) {
                attach(match)
                return
            }
            ancestor = view.superview
        }
        // The scroll view can appear after this view does, once a loading state clears.
        guard retriesLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.attachIfNeeded(retriesLeft: retriesLeft - 1)
        }
    }

    private func attach(_ scrollView: UIScrollView) {
        self.scrollView = scrollView
        observation = scrollView.observe(\.contentOffset, options: [.initial, .new]) { scrollView, _ in
            MainActor.assumeIsolated {
                let bounce = BottomEdgeClamp.shouldBounce(
                    offsetY: scrollView.contentOffset.y,
                    contentHeight: scrollView.contentSize.height,
                    viewportHeight: scrollView.bounds.height,
                    insetTop: scrollView.adjustedContentInset.top,
                    insetBottom: scrollView.adjustedContentInset.bottom
                )
                if scrollView.bounces != bounce {
                    scrollView.bounces = bounce
                }
            }
        }
    }

    private static func scrollView(in root: UIView, matching target: CGRect, window: UIWindow) -> UIScrollView? {
        for subview in root.subviews {
            if let scroll = subview as? UIScrollView,
               Self.matches(scroll.convert(scroll.bounds, to: window), target) {
                return scroll
            }
            if let nested = scrollView(in: subview, matching: target, window: window) {
                return nested
            }
        }
        return nil
    }

    private static func matches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 2 && abs(lhs.width - rhs.width) < 2
            && abs(lhs.minY - rhs.minY) < 2 && abs(lhs.height - rhs.height) < 2
    }
}

private struct HeaderScrollVisibilityModifier: ViewModifier {
    @Binding var isVisible: Bool

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: ScrollSample.self, of: { geometry in
                ScrollSample(
                    offset: geometry.contentOffset.y + geometry.contentInsets.top,
                    distanceFromBottom: RootPageChrome.distanceFromBottom(geometry)
                )
            }) { oldValue, newValue in
                let next = RootPageChrome.headerVisible(
                    offset: max(0, newValue.offset),
                    previousOffset: max(0, oldValue.offset),
                    wasVisible: isVisible,
                    distanceFromBottom: newValue.distanceFromBottom
                )
                guard next != isVisible else { return }
                withAnimation(.smooth(duration: 0.22)) {
                    isVisible = next
                }
            }
    }
}

private struct PageHeaderProfileButton: View {
    @Environment(\.tabBarPlacement) private var tabBarPlacement

    var body: some View {
        if tabBarPlacement != .sidebar {
            ProfileMenu()
        }
    }
}

enum ScreenInsets {
    /// Live status bar height from the scene; 24 (iPad) before a scene is attached.
    @MainActor
    static var statusBar: CGFloat {
        for scene in UIApplication.shared.connectedScenes {
            if let height = (scene as? UIWindowScene)?.statusBarManager?.statusBarFrame.height, height > 0 {
                return height
            }
        }
        return 24
    }

    @MainActor
    static var top: CGFloat {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if let window = windowScene.windows.first(where: \.isKeyWindow) ?? windowScene.windows.first {
                return window.safeAreaInsets.top
            }
        }
        return 59
    }
}

struct ScrollSample: Equatable {
    var offset: CGFloat
    var distanceFromBottom: CGFloat
}

enum ZelefinMotion {
    static let sidebarChrome: Animation = .smooth(duration: 0.38)
}

struct ZelefinSidebarLayout: Equatable {
    var scale: CGFloat
    var contentWidth: CGFloat
    var expandedWidth: CGFloat

    static let identity = ZelefinSidebarLayout(scale: 1, contentWidth: 0, expandedWidth: 0)

    /// Extra width the sidebar stole from the content column.
    var leadingBleed: CGFloat {
        guard expandedWidth > 1, contentWidth > 1 else { return 0 }
        return max(0, expandedWidth - contentWidth)
    }
}

enum SidebarLayoutMetrics {
    static func scale(contentWidth: CGFloat, expandedWidth: CGFloat) -> CGFloat {
        guard expandedWidth > 1, contentWidth > 1 else { return 1 }
        let raw = contentWidth / expandedWidth
        if raw > 0.98 { return 1 }
        return min(1, max(0.55, raw))
    }

    static func expandedWidth(
        currentWidth: CGFloat,
        previousExpandedWidth: CGFloat,
        isSidebarVisible: Bool
    ) -> CGFloat {
        if currentWidth < 1 { return previousExpandedWidth }
        if !isSidebarVisible { return currentWidth }
        if previousExpandedWidth < 1 { return currentWidth }
        return previousExpandedWidth
    }
}

enum PosterGridLayout {
    static let horizontalInset: CGFloat = 16

    static func columnCount(expandedWidth: CGFloat) -> Int {
        let inner = max(expandedWidth - horizontalInset * 2, PosterMetrics.portraitSize.width)
        let cell = PosterMetrics.portraitSize.width + PosterMetrics.rowSpacing
        return max(3, Int((inner + PosterMetrics.rowSpacing) / cell))
    }

    static func columns(for layout: ZelefinSidebarLayout) -> [GridItem] {
        let width: CGFloat
        if layout.expandedWidth > 1 {
            width = layout.expandedWidth
        } else if layout.contentWidth > 1 {
            width = layout.contentWidth
        } else {
            width = 390
        }
        let count = columnCount(expandedWidth: width)
        return Array(repeating: GridItem(.flexible(), spacing: PosterMetrics.rowSpacing), count: count)
    }

    static func landscapeColumnCount(expandedWidth: CGFloat) -> Int {
        let inner = max(expandedWidth - horizontalInset * 2, PosterMetrics.landscapeSize.width)
        let cell = PosterMetrics.landscapeSize.width + PosterMetrics.rowSpacing
        return max(1, Int((inner + PosterMetrics.rowSpacing) / cell))
    }

    static func landscapeColumns(for layout: ZelefinSidebarLayout) -> [GridItem] {
        let width: CGFloat
        if layout.expandedWidth > 1 {
            width = layout.expandedWidth
        } else if layout.contentWidth > 1 {
            width = layout.contentWidth
        } else {
            width = 390
        }
        let count = landscapeColumnCount(expandedWidth: width)
        return Array(repeating: GridItem(.flexible(), spacing: PosterMetrics.rowSpacing), count: count)
    }

    static func squareColumnCount(expandedWidth: CGFloat) -> Int {
        let size: CGFloat = 152
        let inner = max(expandedWidth - horizontalInset * 2, size)
        let cell = size + PosterMetrics.rowSpacing
        return max(2, Int((inner + PosterMetrics.rowSpacing) / cell))
    }

    static func squareColumns(for layout: ZelefinSidebarLayout) -> [GridItem] {
        let width: CGFloat
        if layout.expandedWidth > 1 {
            width = layout.expandedWidth
        } else if layout.contentWidth > 1 {
            width = layout.contentWidth
        } else {
            width = 390
        }
        let count = squareColumnCount(expandedWidth: width)
        return Array(repeating: GridItem(.flexible(), spacing: 18), count: count)
    }
}

private struct ZelefinSidebarLayoutKey: EnvironmentKey {
    static let defaultValue = ZelefinSidebarLayout.identity
}

private struct LibraryArtworkRevisionKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var zelefinSidebarLayout: ZelefinSidebarLayout {
        get { self[ZelefinSidebarLayoutKey.self] }
        set { self[ZelefinSidebarLayoutKey.self] = newValue }
    }

    var libraryArtworkRevision: Int {
        get { self[LibraryArtworkRevisionKey.self] }
        set { self[LibraryArtworkRevisionKey.self] = newValue }
    }
}

extension View {
    func zelefinSidebarLayout() -> some View {
        modifier(SidebarLayoutModifier())
    }
}

private struct SidebarLayoutModifier: ViewModifier {
    @Environment(\.tabBarPlacement) private var tabBarPlacement
    @State private var contentWidth: CGFloat = 0
    @State private var expandedWidth: CGFloat = 0

    private var isSidebarVisible: Bool {
        tabBarPlacement == .sidebar
    }

    private var layout: ZelefinSidebarLayout {
        ZelefinSidebarLayout(
            scale: SidebarLayoutMetrics.scale(contentWidth: contentWidth, expandedWidth: expandedWidth),
            contentWidth: contentWidth,
            expandedWidth: expandedWidth
        )
    }

    func body(content: Content) -> some View {
        content
            .environment(\.zelefinSidebarLayout, layout)
            .geometryGroup()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .animation(ZelefinMotion.sidebarChrome, value: layout)
            .animation(ZelefinMotion.sidebarChrome, value: tabBarPlacement)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                updateWidths(width)
            }
    }

    private func updateWidths(_ width: CGFloat) {
        let nextExpanded = SidebarLayoutMetrics.expandedWidth(
            currentWidth: width,
            previousExpandedWidth: expandedWidth,
            isSidebarVisible: isSidebarVisible
        )
        let shouldAnimate = expandedWidth > 1 && abs(width - contentWidth) > 2
        let apply = {
            contentWidth = width
            expandedWidth = nextExpanded
        }
        if shouldAnimate {
            withAnimation(ZelefinMotion.sidebarChrome, apply)
        } else {
            apply()
        }
    }
}

struct FillingPosterCell<Content: View>: View {
    var aspectRatio: CGFloat = 2 / 3
    @ViewBuilder var content: (CGSize) -> Content

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    content(geo.size)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            // The `Color.clear` base has no hit area, so without this only the opaque pixels of the
            // card are tappable (the label row, padding, and rounded-corner gaps are dead). Make the
            // whole cell tappable so a NavigationLink/Button wrapping it opens from anywhere on the card.
            .contentShape(Rectangle())
    }
}

/// Trailing profile control for root tabs. iPhone also shows the tab title on this row.
struct FloatingPageHeader<Accessory: View, Center: View>: View {
    var title: String = ""
    var isVisible: Bool = true
    /// Home draws from the screen top. Other tabs sit in the content safe area and
    /// need this lift so the profile lands in the iPad top tab bar row.
    var liftsIntoPadTabBar: Bool = false
    var accessory: Accessory
    var center: Center
    @Environment(\.tabBarPlacement) private var tabBarPlacement

    init(
        title: String = "",
        isVisible: Bool = true,
        liftsIntoPadTabBar: Bool = false,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder center: () -> Center
    ) {
        self.title = title
        self.isVisible = isVisible
        self.liftsIntoPadTabBar = liftsIntoPadTabBar
        self.accessory = accessory()
        self.center = center()
    }

    private var showsTitle: Bool {
        RootPageChrome.showsTitle && !title.isEmpty
    }

    private var showsProfile: Bool {
        tabBarPlacement != .sidebar
    }

    private var showsCenter: Bool {
        Center.self != EmptyView.self
    }

    private var padTabBarLift: CGFloat {
        if centersOnPadTabBar { return 0 }
        return RootPageChrome.padTabBarLift(
            usesPadTopChrome: liftsIntoPadTabBar && UIDevice.current.userInterfaceIdiom == .pad,
            isSidebarVisible: tabBarPlacement == .sidebar
        )
    }

    /// iPad sits the profile and page buttons on the floating tab bar itself rather than a fixed
    /// lift from the safe area, which landed the avatar too high when navigation shifted that inset.
    private var centersOnPadTabBar: Bool {
        RootPageChrome.usesOverlayPushedBar && tabBarPlacement != .sidebar
    }

    var body: some View {
        if showsTitle || showsProfile || Accessory.self != EmptyView.self || showsCenter {
            HStack(spacing: 12) {
                if showsTitle {
                    Text(title)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 0)
                accessory
                if showsProfile {
                    ProfileMenu(diameter: 45)
                }
            }
            .frame(minHeight: showsCenter ? 45 : nil)
            .overlay {
                center
            }
            .padding(.horizontal, 16)
            .padding(.top, centersOnPadTabBar ? 0 : 4)
            .padding(.bottom, 10)
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? padTabBarLift : padTabBarLift - 18)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
            .modifier(PadTabBarRowAlignment(isActive: centersOnPadTabBar))
            .transition(.opacity.combined(with: .scale(scale: 0.86)))
            .animation(ZelefinMotion.sidebarChrome, value: tabBarPlacement)
        }
    }
}

extension FloatingPageHeader where Center == EmptyView {
    init(
        title: String = "",
        isVisible: Bool = true,
        liftsIntoPadTabBar: Bool = false,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.init(
            title: title,
            isVisible: isVisible,
            liftsIntoPadTabBar: liftsIntoPadTabBar,
            accessory: accessory,
            center: { EmptyView() }
        )
    }
}

extension FloatingPageHeader where Accessory == EmptyView, Center == EmptyView {
    init(title: String = "", isVisible: Bool = true, liftsIntoPadTabBar: Bool = false) {
        self.init(title: title, isVisible: isVisible, liftsIntoPadTabBar: liftsIntoPadTabBar) {
            EmptyView()
        }
    }
}

struct ZelefinPadBackButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button(action: dismiss.callAsFunction) {
            Image(systemName: "chevron.backward")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: ZelefinPillMetrics.height, height: ZelefinPillMetrics.height)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .zelefinLiquidGlassCircle()
        .accessibilityLabel("Back")
    }
}

struct ZelefinPadPushedChrome<Trailing: View>: View {
    var contentIgnoresTopSafeArea: Bool
    var isVisible: Bool = true
    /// Changes whenever the page's layout does, so the row re-measures the tab bar.
    var layoutKey: CGSize = .zero
    @ViewBuilder var trailing: Trailing
    @Environment(\.tabBarPlacement) private var tabBarPlacement

    /// iPad sits the row on the floating tab bar's centre line. A pushed page's safe area does not
    /// carry the tab bar the way a root tab's does, and the window inset was read once and guessed
    /// before the window was key, so the row landed above or below the bar.
    private var centersOnPadTabBar: Bool {
        RootPageChrome.usesOverlayPushedBar && tabBarPlacement != .sidebar
    }

    private var topPadding: CGFloat {
        guard centersOnPadTabBar else {
            return RootPageChrome.pushedOverlayTopPadding(
                contentIgnoresTopSafeArea: contentIgnoresTopSafeArea,
                statusBarHeight: ScreenInsets.top
            )
        }
        return 0
    }

    private var lift: CGFloat {
        if centersOnPadTabBar { return 0 }
        return RootPageChrome.pushedOverlayLift(
            contentIgnoresTopSafeArea: contentIgnoresTopSafeArea,
            usesPadTopChrome: RootPageChrome.usesOverlayPushedBar,
            isSidebarVisible: tabBarPlacement == .sidebar
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ZelefinPadBackButton()
            Spacer(minLength: 0)
                .allowsHitTesting(false)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.top, topPadding)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? lift : lift - 18)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
        .modifier(PadTabBarRowAlignment(isActive: centersOnPadTabBar, layoutKey: layoutKey))
    }
}

/// Moves a row of 45pt glass controls onto the floating iPad tab bar's centre line: the tab bar
/// is measured on screen, and so is where the row would sit, so no safe-area constant is assumed.
/// Pushed pages, root headers and full-bleed pages all line up the same way.
private struct PadTabBarRowAlignment: ViewModifier {
    var isActive: Bool
    /// Changes whenever the page's layout does, so the tab bar is measured again.
    var layoutKey: CGSize = .zero
    @Environment(\.tabBarPlacement) private var tabBarPlacement
    /// Nil until the marker reports, so the first frame does not jump.
    @State private var originY: CGFloat?
    @State private var tabBarMidY: CGFloat?

    private struct MeasureKey: Equatable {
        var isActive: Bool
        var layoutKey: CGSize
        var placement: String
    }

    private var offset: CGFloat {
        guard let originY else { return 0 }
        let statusBar = ScreenInsets.statusBar
        let midY = tabBarMidY ?? statusBar + RootPageChrome.padTabBarCenterBelowStatusBar
        // Never above the status bar, whatever a reading taken mid-transition said.
        let top = max(midY - ZelefinPillMetrics.height / 2, statusBar + 2)
        return top - originY
    }

    func body(content: Content) -> some View {
        content
            .offset(y: isActive ? offset : 0)
            // Measured off a marker the offset does not move. Reading the offset row itself fed each
            // new offset back into the next measurement and SwiftUI cycled until the app was killed.
            .background(alignment: .top) {
                Color.clear
                    .frame(height: 1)
                    .allowsHitTesting(false)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { origin in
                        // Recorded with the sidebar open too, so the row does not come back on a
                        // position left over from before the sidebar animation.
                        guard abs(origin - (originY ?? -1_000)) > 0.5 else { return }
                        originY = origin
                        measureTabBar()
                    }
            }
            .task(id: MeasureKey(isActive: isActive, layoutKey: layoutKey, placement: String(describing: tabBarPlacement))) {
                guard isActive else { return }
                // The floating bar slides in after a push, a tab switch or the sidebar closing. A
                // single early reading caught it mid-slide and parked the row above it, so follow it
                // until it holds still.
                var steady = 0
                for _ in 0..<20 where steady < 3 {
                    steady = measureTabBar() ? 0 : steady + 1
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
    }

    /// True when the reading moved the row.
    @discardableResult
    private func measureTabBar() -> Bool {
        guard isActive, let frame = PadTabBarLocator.frame() else { return false }
        guard abs(frame.midY - (tabBarMidY ?? -1)) > 0.5 else { return false }
        tabBarMidY = frame.midY
        return true
    }
}

/// The floating iPad tab bar's frame in window coordinates. Found by its public accessibility
/// trait, or by class name on releases that do not set it; nil when no top tab bar is showing.
enum PadTabBarLocator {
    @MainActor
    static func frame() -> CGRect? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            guard let window = windowScene.windows.first(where: \.isKeyWindow) ?? windowScene.windows.first else { continue }
            var candidates: [CGRect] = []
            collect(in: window, window: window, statusBar: ScreenInsets.statusBar, into: &candidates)
            // The floating bar is centred; a sidebar's leftover tab-bar views sit off to the side.
            return candidates.min { abs($0.midX - window.bounds.midX) < abs($1.midX - window.bounds.midX) }
        }
        return nil
    }

    @MainActor
    private static func collect(in view: UIView, window: UIWindow, statusBar: CGFloat, into candidates: inout [CGRect]) {
        for subview in view.subviews where !subview.isHidden && subview.alpha > 0.01 {
            let isTabBar = subview.accessibilityTraits.contains(.tabBar)
                || String(describing: type(of: subview)).contains("FloatingTabBar")
            if isTabBar {
                let frame = subview.convert(subview.bounds, to: window)
                // On screen, pill sized and below the status bar: a bar still sliding in from above,
                // or one parked off screen with the sidebar open, is not where the row should go.
                if frame.height > 20, frame.height < 120, frame.maxY < 200,
                   frame.minY >= statusBar - 2,
                   frame.minX >= 0, frame.maxX <= window.bounds.width,
                   frame.width < window.bounds.width * 0.95 {
                    candidates.append(frame)
                    continue
                }
            }
            collect(in: subview, window: window, statusBar: statusBar, into: &candidates)
        }
    }
}

private struct ZelefinPushedChromeModifier<Trailing: View>: ViewModifier {
    var title: String
    var contentIgnoresTopSafeArea: Bool
    var hidesToolbarBackground: Bool
    var chromeVisible: Bool
    var trailing: Trailing

    init(
        title: String,
        contentIgnoresTopSafeArea: Bool,
        hidesToolbarBackground: Bool,
        chromeVisible: Bool,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.contentIgnoresTopSafeArea = contentIgnoresTopSafeArea
        self.hidesToolbarBackground = hidesToolbarBackground
        self.chromeVisible = chromeVisible
        self.trailing = trailing()
    }

    func body(content: Content) -> some View {
        // Hero pages hide the system bar. Keep back and trailing pills on the
        // same overlay as iPad so iPhone does not shrink More in the toolbar.
        if RootPageChrome.usesOverlayPushedBar || hidesToolbarBackground {
            padChrome(content)
                .toolbar(.hidden, for: .navigationBar)
                .navigationBarBackButtonHidden(true)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .background(InteractivePopGestureEnabler())
        } else {
            iphoneChrome(content)
        }
    }

    @ViewBuilder
    private func padChrome(_ content: Content) -> some View {
        if contentIgnoresTopSafeArea {
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    content
                    ZelefinPadPushedChrome(
                        contentIgnoresTopSafeArea: true,
                        isVisible: chromeVisible,
                        layoutKey: geo.size
                    ) {
                        trailing
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
        } else {
            content.overlay(alignment: .top) {
                ZelefinPadPushedChrome(contentIgnoresTopSafeArea: false, isVisible: chromeVisible) {
                    trailing
                }
            }
        }
    }

    @ViewBuilder
    private func iphoneChrome(_ content: Content) -> some View {
        if hidesToolbarBackground {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(false)
                .toolbar(.visible, for: .navigationBar)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    if Trailing.self != EmptyView.self {
                        ToolbarItem(placement: .topBarTrailing) {
                            trailing
                        }
                        .catalogToolbarHidesSystemBackground()
                    }
                }
        } else {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(false)
                .toolbar(.visible, for: .navigationBar)
                .toolbarBackground(Color.black, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    if Trailing.self != EmptyView.self {
                        ToolbarItem(placement: .topBarTrailing) {
                            trailing
                        }
                        .catalogToolbarHidesSystemBackground()
                    }
                }
        }
    }
}

extension View {
    func zelefinPushedChrome<Trailing: View>(
        title: String = "",
        contentIgnoresTopSafeArea: Bool = false,
        hidesToolbarBackground: Bool = false,
        chromeVisible: Bool = true,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        modifier(
            ZelefinPushedChromeModifier(
                title: title,
                contentIgnoresTopSafeArea: contentIgnoresTopSafeArea,
                hidesToolbarBackground: hidesToolbarBackground,
                chromeVisible: chromeVisible,
                trailing: trailing
            )
        )
    }
}
