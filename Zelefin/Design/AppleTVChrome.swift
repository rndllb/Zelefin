import SwiftUI
import UIKit

enum PosterMetrics {
    static var landscapeSize: CGSize {
        #if os(tvOS)
        CGSize(width: 440, height: 248)
        #else
        CGSize(width: 280, height: 158)
        #endif
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
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if isLoading {
                ProgressView()
                    .tint(progressTint)
            }
        }
        .clipped()
        .task(id: url) { await load() }
    }

    private func load() async {
        image = nil
        isLoading = true
        guard let url else {
            isLoading = false
            return
        }
        if let cached = ArtworkCache.shared.image(for: url) {
            image = cached
            isLoading = false
            return
        }
        do {
            let (data, response) = try await JellyfinNetworking.data(from: url)
            guard !Task.isCancelled else { return }
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
                  let loaded = UIImage(data: data)
            else {
                isLoading = false
                return
            }
            ArtworkCache.shared.store(loaded, for: url)
            image = loaded
        } catch is CancellationError {
            return
        } catch {
            isLoading = false
            return
        }
        isLoading = false
    }
}

private final class ArtworkCache: @unchecked Sendable {
    static let shared = ArtworkCache()
    private let cache = NSCache<NSURL, UIImage>()

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
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

    var body: some View {
        PosterImage(url: imageURL, aspectRatio: 16 / 9)
            .frame(width: PosterMetrics.landscapeSize.width, height: PosterMetrics.landscapeSize.height)
            .overlay(alignment: .bottom) {
                footer
            }
            .posterCard()
            .frame(width: PosterMetrics.landscapeSize.width, alignment: .leading)
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
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .bold))
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
        [item.name, item.continueWatchingCaption]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

struct ReplayLandscapeCard: View {
    let item: MediaItem
    let imageURL: URL?

    var body: some View {
        PosterImage(url: imageURL, aspectRatio: 16 / 9)
            .frame(width: PosterMetrics.landscapeSize.width, height: PosterMetrics.landscapeSize.height)
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 62)
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
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .bold))
                            .padding(.bottom, 2)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
            }
            .posterCard()
            .frame(width: PosterMetrics.landscapeSize.width, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                [item.continueWatchingTitle, item.recentlyWatchedCaption]
                    .compactMap { $0 }
                    .joined(separator: ", ")
            )
    }
}

struct LabeledPortraitCard: View {
    let title: String
    let imageURL: URL?
    var washColor: Color? = nil
    var width: CGFloat = PosterMetrics.portraitSize.width
    var height: CGFloat = PosterMetrics.portraitSize.height
    var cornerRadius: CGFloat = PosterMetrics.cornerRadius

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
            .frame(width: width, height: height)
            .background {
                ZStack {
                    fallbackFill
                    PosterImage(url: imageURL)
                        .frame(width: width, height: height)
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
                    .frame(width: width - 16, alignment: .leading)
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

    var body: some View {
        ZStack(alignment: .topLeading) {
            PosterImage(url: imageURL)
                .frame(width: PosterMetrics.portraitSize.width, height: PosterMetrics.portraitSize.height)
                .posterCard()

            if let rank {
                Text("\(rank)")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.leading, 8)
                    .padding(.top, 4)
            }
        }
        .frame(width: PosterMetrics.portraitSize.width, alignment: .leading)
        .accessibilityLabel(item.name)
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
        Group {
            if let image {
                Image(uiImage: image)
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
        image = nil
        failed = false
        guard let url = session.library?.logoURL(for: item) else { return }
        if let cached = ArtworkCache.shared.image(for: url) {
            image = cached
            return
        }
        do {
            let (data, response) = try await JellyfinNetworking.data(from: url)
            guard !Task.isCancelled else { return }
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
                  let loaded = UIImage(data: data)
            else {
                failed = true
                return
            }
            ArtworkCache.shared.store(loaded, for: url)
            image = loaded
        } catch is CancellationError {
            return
        } catch {
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

struct FeaturedHero: View {
    let items: [MediaItem]
    let imageURL: (MediaItem) -> URL?

    @Environment(SessionStore.self) private var session
    @State private var selection: String?
    @State private var playbackPlan: PlaybackPlan?
    @State private var playbackError: String?

    private var slides: [MediaItem] {
        Array(items.prefix(8))
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(slides) { item in
                slide(item)
                    .tag(Optional(item.id))
            }
        }
        #if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        #endif
        .ignoresSafeArea(edges: .top)
        .onAppear {
            if selection == nil {
                selection = slides.first?.id
            }
        }
        .task(id: slides.map(\.id)) {
            await autoAdvance()
        }
        .fullScreenCover(item: $playbackPlan) { plan in
            PlayerView(plan: plan)
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

    private func slide(_ item: MediaItem) -> some View {
        ZStack(alignment: .bottom) {
            PosterImage(url: imageURL(item), aspectRatio: 16 / 9)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                        Task { await play(item) }
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

                    NavigationLink {
                        ItemDetailView(itemID: item.id)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .zelefinLiquidGlassCircle()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("More")
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 56)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func autoAdvance() async {
        let ids = slides.map(\.id)
        guard ids.count > 1 else { return }
        if selection == nil {
            selection = ids.first
        }

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            let current = selection ?? ids[0]
            let index = ids.firstIndex(of: current) ?? 0
            let next = ids[(index + 1) % ids.count]
            withAnimation(.easeInOut(duration: 0.55)) {
                selection = next
            }
        }
    }

    private func play(_ item: MediaItem) async {
        guard let library = session.library else { return }
        do {
            playbackPlan = try await library.playbackPlan(for: item)
        } catch {
            playbackError = error.localizedDescription
        }
    }
}

extension View {
    /// Circular Liquid Glass bezel so content (the avatar) sits inside the ring, not over it.
    @ViewBuilder
    func zelefinLiquidGlassCircle() -> some View {
        if #available(iOS 26, tvOS 26, *) {
            self.glassEffect(.regular.interactive(), in: Circle())
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
    func zelefinLiquidGlassCapsule() -> some View {
        if #available(iOS 26, tvOS 26, *) {
            self.glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
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
                    ProfileMenu()
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
    }
}

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

struct FloatingPageHeader: View {
    let title: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            ProfileMenu(diameter: 45)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}
