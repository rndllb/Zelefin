import SwiftUI

/// A Discover title's page, laid out like a library title's: artwork, the request button where Play
/// would be, then trailers, cast, similar titles, and the facts Seerr or Ombi has.
struct RequestTitleDetailView: View {
    let title: SeerrTitle
    var onRequested: (SeerrTitle) -> Void = { _ in }

    @Environment(SessionStore.self) private var session
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    @Environment(\.openURL) private var openURL
    @State private var current: SeerrTitle
    @State private var details: RequestTitleDetails?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var canManageRequests = false
    @State private var heroLock = HeroHeightLock()
    @State private var pageWidth: CGFloat = 0
    @State private var showsRequest = false
    @State private var showsOverview = false
    @State private var playingVideo: RequestVideo?
    @State private var showsLibraryItem = false

    init(title: SeerrTitle, onRequested: @escaping (SeerrTitle) -> Void = { _ in }) {
        self.title = title
        self.onRequested = onRequested
        _current = State(initialValue: title)
    }

    private var client: (any RequestServiceClient)? { PluginSettings.seerrClient }

    private var isFullyOnServer: Bool {
        current.availability == .available || (current.kind == .movie && current.isInJellyfin(catalog: session.tmdbCatalog))
    }

    /// The title's own library page, when the library has it.
    private var libraryItemID: String? {
        session.tmdbCatalog.itemID(for: current)
    }

    private var awaitsReview: Bool {
        canManageRequests && current.review == .pendingApproval && current.requestID != nil
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero(width: geo.size.width, height: heroLock.height(for: geo.size))

                    if let details {
                        if !details.trailers.isEmpty {
                            trailersSection(details.trailers)
                                .padding(.top, 4)
                                .padding(.bottom, 20)
                        }
                        if !details.cast.isEmpty {
                            castSection(details.cast)
                                .padding(.bottom, 20)
                        }
                        if !details.related.isEmpty {
                            relatedSection(details.related)
                                .padding(.bottom, 20)
                        }
                        if !details.facts.isEmpty {
                            TitleFactsSection(title: "Information", rows: details.facts)
                                .padding(.bottom, 20)
                        }
                    } else if isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .zelefinScrollEdgeHidden()
            .zelefinPinnedBottomEdge()
            .onAppear { heroLock.lock(geo.size) }
            .onChange(of: geo.size.width) { heroLock.lock(geo.size) }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
        .background(Color.zelefinPage.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .zelefinPushedChrome(contentIgnoresTopSafeArea: true, hidesToolbarBackground: true) {
            moreMenu
        }
        .tint(.white)
        .task { await load() }
        .sheet(isPresented: $showsRequest) {
            NavigationStack {
                SeerrRequestView(title: current) {
                    current.availability = .pending
                    onRequested(current)
                    Task { await refreshStatus() }
                }
            }
        }
        .sheet(isPresented: $showsOverview) {
            RequestOverviewSheet(name: current.name, tagline: details?.tagline, overview: overview ?? "")
                .presentationBackground(TitleMoreInfoView.sheetBackground)
        }
        .navigationDestination(isPresented: $showsLibraryItem) {
            if let libraryItemID {
                ItemDetailView(itemID: libraryItemID)
            }
        }
        .fullScreenCover(item: $playingVideo) { video in
            if let url = video.watchURL {
                TrailerSafariView(url: url)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: Hero

    private var overview: String? {
        let text = details?.overview ?? current.overview ?? title.overview
        return text?.isEmpty == false ? text : nil
    }

    private var metadataLine: String {
        var parts = [current.kind == .movie ? "Movie" : "Show"]
        if let year = current.year ?? title.year {
            parts.append("\(year)")
        }
        parts.append(contentsOf: (details?.genres ?? []).prefix(2))
        return parts.joined(separator: " · ")
    }

    private func hero(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 14) {
            Text(current.name)
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.7), radius: 10, y: 1)

            Text(metadataLine)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            requestButton

            if let requester = current.requestedByName {
                Text("Requested by \(requester)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }

            if let overview {
                overviewBlock(overview)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
        .frame(width: width, height: height, alignment: .bottom)
        .background {
            ZStack {
                HeroArtwork(
                    url: details?.backdropURL ?? details?.posterURL ?? title.posterURL,
                    placeholderURL: title.posterURL,
                    size: CGSize(width: width, height: height)
                )

                LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .center)

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.28),
                        .init(color: Color.zelefinPage.opacity(0.55), location: 0.58),
                        .init(color: Color.zelefinPage.opacity(0.94), location: 0.86),
                        .init(color: Color.zelefinPage, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .zelefinHeroBackgroundExtension()
        }
    }

    @ViewBuilder
    private var requestButton: some View {
        if isFullyOnServer, libraryItemID != nil {
            Button { showsLibraryItem = true } label: {
                actionLabel("View in Library", systemImage: "play.rectangle", enabled: true)
            }
            .buttonStyle(.plain)
        } else if isFullyOnServer {
            actionLabel("In Library", systemImage: "checkmark", enabled: false)
        } else if awaitsReview {
            Button { showsRequest = true } label: {
                actionLabel("Review", systemImage: "checkmark.seal", enabled: true)
            }
            .buttonStyle(.plain)
        } else if current.canRequest && current.review != .pendingApproval {
            Button { showsRequest = true } label: {
                actionLabel(current.availability.buttonTitle, systemImage: "plus", enabled: true)
            }
            .buttonStyle(.plain)
        } else {
            actionLabel(current.review == .approved || current.availability == .processing ? "Approved" : "Requested", systemImage: "clock", enabled: false)
        }
    }

    private func actionLabel(_ text: String, systemImage: String, enabled: Bool) -> some View {
        Label(text, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(enabled ? Color.black : Color.white.opacity(0.8))
            .frame(minWidth: 175)
            .frame(height: 45)
            .padding(.horizontal, 12)
            .background(enabled ? Color.white : Color.white.opacity(0.18), in: Capsule())
            .accessibilityAddTraits(enabled ? .isButton : [])
    }

    private func overviewBlock(_ overview: String) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Text(overview)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, overview.count > 90 ? 56 : 0)

            if overview.count > 90 {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, Color.zelefinPage.opacity(0.92)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 28, height: 22)
                    Button { showsOverview = true } label: {
                        Text("MORE")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Full description")
                }
            }
        }
    }

    // MARK: More menu

    private var moreMenu: some View {
        Menu {
            if libraryItemID != nil, !isFullyOnServer {
                Button("View in Library", systemImage: "play.rectangle") { showsLibraryItem = true }
            }
            if let trailer = details?.trailers.first {
                Button("Watch Trailer", systemImage: "play.rectangle") { playingVideo = trailer }
            }
            if let client, let url = client.webURL(for: current) {
                Button("Open in \(client.service.name)", systemImage: "safari") { openURL(url) }
            }
            if let imdb = details?.imdbID, let url = URL(string: "https://www.imdb.com/title/\(imdb)") {
                Button("Open in IMDb", systemImage: "film") { openURL(url) }
            }
            if let homepage = details?.homepage {
                Button("Official Website", systemImage: "globe") { openURL(homepage) }
            }
            if let url = tmdbURL {
                Divider()
                ShareLink(item: url, subject: Text(current.name)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: ZelefinPillMetrics.height, height: ZelefinPillMetrics.height)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .zelefinLiquidGlassCircle()
        .accessibilityLabel("More")
    }

    private var tmdbURL: URL? {
        URL(string: "https://www.themoviedb.org/\(current.kind.rawValue)/\(current.tmdbID)")
    }

    // MARK: Rows

    private var rowWidth: CGFloat {
        pageWidth > 1 ? pageWidth : sidebarLayout.contentWidth
    }

    private var wideCardWidth: CGFloat? {
        DetailRowLayout.cardWidth(fitting: 5, in: rowWidth)
    }

    private var landscapeCardHeight: CGFloat {
        wideCardWidth.map { ($0 * 9 / 16).rounded() } ?? PosterMetrics.landscapeSize.height * sidebarLayout.scale
    }

    private var rowPosterSize: CGSize? {
        DetailRowLayout.cardWidth(fitting: 8, in: rowWidth).map { CGSize(width: $0, height: ($0 * 1.5).rounded()) }
    }

    private func trailersSection(_ videos: [RequestVideo]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Trailers", showsChevron: false)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DetailRowLayout.spacing) {
                    ForEach(videos) { video in
                        Button { playingVideo = video } label: {
                            TrailerLandscapeCard(
                                title: video.name,
                                caption: video.type ?? "Video",
                                imageURL: video.thumbnailURL,
                                width: wideCardWidth
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: landscapeCardHeight)
        }
    }

    private func castSection(_ cast: [RequestCastMember]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Cast", showsChevron: false)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DetailRowLayout.spacing) {
                    ForEach(cast) { member in
                        CastMemberCard(
                            person: member.creditPerson,
                            imageURL: member.imageURL,
                            width: DetailRowLayout.cardWidth(fitting: 10, in: rowWidth)
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func relatedSection(_ titles: [SeerrTitle]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "More Like This", showsChevron: false)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DetailRowLayout.spacing) {
                    ForEach(titles) { related in
                        NavigationLink {
                            RequestTitleDetailView(title: related, onRequested: onRequested)
                        } label: {
                            SeerrPoster(title: related, size: rowPosterSize)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: Loading

    private func load() async {
        guard let client else {
            errorMessage = "Sign in to \(PluginSettings.requestService.name) in Settings."
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        async let status = try? client.requestStatus(for: title)
        async let user = try? client.currentUser()
        do {
            details = try await client.titleDetails(for: title)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        if let refreshed = await status {
            apply(refreshed)
        }
        canManageRequests = await user?.canManageRequests ?? false
    }

    private func refreshStatus() async {
        guard let refreshed = try? await client?.requestStatus(for: title) else { return }
        apply(refreshed)
    }

    private func apply(_ refreshed: SeerrTitle) {
        var copy = refreshed
        copy.posterURL = refreshed.posterURL ?? title.posterURL
        copy.year = refreshed.year ?? title.year
        current = copy
    }
}

/// The whole description, which the hero cuts to two lines.
private struct RequestOverviewSheet: View {
    let name: String
    let tagline: String?
    let overview: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let tagline, !tagline.isEmpty {
                        Text(tagline)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    Text(overview)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
