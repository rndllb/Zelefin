import SwiftUI
import UIKit

extension CGSize {
    func scaled(by factor: CGFloat) -> CGSize {
        CGSize(width: width * factor, height: height * factor)
    }
}

enum PosterMetrics {
    static var landscapeSize: CGSize {
        #if os(tvOS)
        CGSize(width: 440, height: 248)
        #else
        CGSize(width: 280, height: 158)
        #endif
    }

    /// Episode still width; text stacks tightly under the image.
    static var episodeCardWidth: CGFloat {
        #if os(tvOS)
        400
        #else
        252
        #endif
    }

    static var episodeCardSize: CGSize {
        let width = episodeCardWidth
        #if os(tvOS)
        let textHeight: CGFloat = 148
        #else
        let textHeight: CGFloat = 132
        #endif
        return CGSize(width: width, height: (width * 9 / 16) + textHeight)
    }

    static var portraitSize: CGSize {
        #if os(tvOS)
        CGSize(width: 200, height: 300)
        #else
        CGSize(width: 124, height: 186)
        #endif
    }

    static var cornerRadius: CGFloat {
        #if os(tvOS)
        14
        #else
        10
        #endif
    }

    static var rowSpacing: CGFloat {
        #if os(tvOS)
        22
        #else
        10
        #endif
    }

    static var heroHeight: CGFloat {
        heroHeight(for: CGSize(width: 390, height: 844))
    }

    static func heroHeight(for size: CGSize) -> CGFloat {
        #if os(tvOS)
        max(760, size.height * 0.72)
        #else
        max(680, size.height * 0.82)
        #endif
    }
}

enum PosterChrome {
    /// Hairline around cover art — same overlay as Vellum’s `AlbumArtworkView`.
    static let outlineWidth: CGFloat = 0.75

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
    var fill: Color = Color.white.opacity(0.08)
    var progressTint: Color = Color.white.opacity(0.6)
    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Rectangle()
                .fill(fill)
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
        .task(id: url) { await load() }
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
        let width: CGFloat = 22
        return Capsule()
            .fill(.white.opacity(0.32))
            .frame(width: width, height: 3.5)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.75))
                    .frame(width: max(2, width * item.progress), height: 3.5)
            }
            .frame(width: width, height: 3.5)
            .clipped()
    }

    private var accessibilityCaption: String {
        var parts = [item.name, item.continueWatchingCaption].compactMap { $0 }
        if let download = downloads.coverMark(for: item, account: session.session).accessibilityCaption {
            parts.append(download)
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
            .frame(width: size.width, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                ([item.continueWatchingTitle, item.recentlyWatchedCaption]
                    .compactMap { $0 }
                    + [downloads.coverMark(for: item, account: session.session).accessibilityCaption].compactMap { $0 }
                )
                .joined(separator: ", ")
            )
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
                        watchedMark
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
        .background(Color.white.opacity(0.08))
        .posterCard()
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityCaption)
        .accessibilityAddTraits(.isButton)
    }

    private var watchedMark: some View {
        Image(systemName: "checkmark.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color.black.opacity(0.78))
            .font(.system(size: markSize, weight: .semibold))
            .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
            .accessibilityHidden(true)
    }

    private var markSize: CGFloat {
        #if os(tvOS)
        28
        #else
        22
        #endif
    }

    private var markPadding: CGFloat {
        #if os(tvOS)
        10
        #else
        8
        #endif
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
                    PosterImage(url: imageURL)
                        .frame(width: fittedWidth, height: fittedHeight)
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
        if let download = downloads.coverMark(for: item, account: session.session).accessibilityCaption {
            parts.append(download)
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
        .task(id: item.id) { await load() }
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
        .task(id: url) { await load() }
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
    @ViewBuilder
    func zelefinHeroBackgroundExtension() -> some View {
        if #available(iOS 26, tvOS 26, *) {
            backgroundExtensionEffect()
        } else {
            self
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
        .contentShape(Rectangle())
        .simultaneousGesture(turnPageGesture)
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
        .fullScreenCover(item: $playingItem) { item in
            PlayerView(item: item)
        }
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

    private var turnPageGesture: some Gesture {
        DragGesture(minimumDistance: 50)
            .onEnded { value in
                guard slides.count > 1 else { return }
                if value.translation.width < -50 {
                    moveSelection(by: 1)
                } else if value.translation.width > 50 {
                    moveSelection(by: -1)
                }
            }
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
        playingItem = item
    }
}

extension View {
    /// Circular Liquid Glass bezel so content (the avatar) sits inside the ring, not over it.
    @ViewBuilder
    func zelefinLiquidGlassCircle(interactive: Bool = true) -> some View {
        if #available(iOS 26, tvOS 26, *) {
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
        if #available(iOS 26, tvOS 26, *) {
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PageHeaderProfileButton()
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
    }

    @ViewBuilder
    func zelefinScrollEdgeBlur() -> some View {
        #if os(iOS)
        if #available(iOS 26, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func zelefinScrollEdgeHidden() -> some View {
        #if os(iOS)
        if #available(iOS 26, *) {
            self.scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
        }
        #else
        self
        #endif
    }

    func zelefinHeaderScrollVisibility(_ isVisible: Binding<Bool>) -> some View {
        #if os(iOS)
        modifier(HeaderScrollVisibilityModifier(isVisible: isVisible))
        #else
        self
        #endif
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

enum RootPageChrome {
    static let hideAfter: CGFloat = 20
    static let headerRowHeight: CGFloat = 59
    /// Space the iPad floating top tab bar occupies below the status bar.
    static let padTopTabBarClearance: CGFloat = 62

    static func showsTitle(idiom: UIUserInterfaceIdiom) -> Bool {
        #if os(iOS)
        idiom == .phone
        #else
        false
        #endif
    }

    @MainActor
    static var showsTitle: Bool {
        #if os(iOS)
        showsTitle(idiom: UIDevice.current.userInterfaceIdiom)
        #else
        false
        #endif
    }

    static func headerVisible(offset: CGFloat, previousOffset: CGFloat, wasVisible: Bool) -> Bool {
        if offset <= hideAfter { return true }
        let delta = offset - previousOffset
        if delta > 2 { return false }
        if delta < -2 { return true }
        return wasVisible
    }

    /// Lift a safe-area overlay into the iPad top tab bar row, matching Home.
    static func padTabBarLift(usesPadTopChrome: Bool, isSidebarVisible: Bool) -> CGFloat {
        guard usesPadTopChrome, !isSidebarVisible else { return 0 }
        return -padTopTabBarClearance
    }
}

#if os(iOS)
private struct HeaderScrollVisibilityModifier: ViewModifier {
    @Binding var isVisible: Bool

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self, of: { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            }) { oldValue, newValue in
                let next = RootPageChrome.headerVisible(
                    offset: max(0, newValue),
                    previousOffset: max(0, oldValue),
                    wasVisible: isVisible
                )
                guard next != isVisible else { return }
                withAnimation(.smooth(duration: 0.22)) {
                    isVisible = next
                }
            }
    }
}
#endif

#if os(iOS)
private struct PageHeaderProfileButton: View {
    @Environment(\.tabBarPlacement) private var tabBarPlacement

    var body: some View {
        if tabBarPlacement != .sidebar {
            ProfileMenu()
        }
    }
}
#endif

enum ScreenInsets {
    @MainActor
    static var top: CGFloat {
        #if os(iOS)
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if let window = windowScene.windows.first(where: \.isKeyWindow) ?? windowScene.windows.first {
                return window.safeAreaInsets.top
            }
        }
        return 59
        #else
        0
        #endif
    }
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
        let width = layout.expandedWidth > 1 ? layout.expandedWidth : max(layout.contentWidth, 390)
        let count = columnCount(expandedWidth: width)
        return Array(repeating: GridItem(.flexible(), spacing: PosterMetrics.rowSpacing), count: count)
    }
}

private struct ZelefinSidebarLayoutKey: EnvironmentKey {
    static let defaultValue = ZelefinSidebarLayout.identity
}

extension EnvironmentValues {
    var zelefinSidebarLayout: ZelefinSidebarLayout {
        get { self[ZelefinSidebarLayoutKey.self] }
        set { self[ZelefinSidebarLayoutKey.self] = newValue }
    }
}

extension View {
    func zelefinSidebarLayout() -> some View {
        #if os(iOS)
        modifier(SidebarLayoutModifier())
        #else
        self
        #endif
    }
}

#if os(iOS)
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
#endif

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
    }
}

/// Trailing profile control for root tabs. iPhone also shows the tab title on this row.
struct FloatingPageHeader<Accessory: View>: View {
    var title: String = ""
    var isVisible: Bool = true
    /// Home draws from the screen top. Other tabs sit in the content safe area and
    /// need this lift so the profile lands in the iPad top tab bar row.
    var liftsIntoPadTabBar: Bool = false
    var accessory: Accessory
    #if os(iOS)
    @Environment(\.tabBarPlacement) private var tabBarPlacement
    #endif

    init(
        title: String = "",
        isVisible: Bool = true,
        liftsIntoPadTabBar: Bool = false,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.isVisible = isVisible
        self.liftsIntoPadTabBar = liftsIntoPadTabBar
        self.accessory = accessory()
    }

    private var showsTitle: Bool {
        RootPageChrome.showsTitle && !title.isEmpty
    }

    private var showsProfile: Bool {
        #if os(iOS)
        tabBarPlacement != .sidebar
        #else
        true
        #endif
    }

    private var padTabBarLift: CGFloat {
        #if os(iOS)
        RootPageChrome.padTabBarLift(
            usesPadTopChrome: liftsIntoPadTabBar && UIDevice.current.userInterfaceIdiom == .pad,
            isSidebarVisible: tabBarPlacement == .sidebar
        )
        #else
        0
        #endif
    }

    var body: some View {
        if showsTitle || showsProfile || Accessory.self != EmptyView.self {
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
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 10)
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? padTabBarLift : padTabBarLift - 18)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
            .transition(.opacity.combined(with: .scale(scale: 0.86)))
            #if os(iOS)
            .animation(ZelefinMotion.sidebarChrome, value: tabBarPlacement)
            #endif
        }
    }
}

extension FloatingPageHeader where Accessory == EmptyView {
    init(title: String = "", isVisible: Bool = true, liftsIntoPadTabBar: Bool = false) {
        self.init(title: title, isVisible: isVisible, liftsIntoPadTabBar: liftsIntoPadTabBar) {
            EmptyView()
        }
    }
}
