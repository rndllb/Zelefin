import SwiftUI

struct SeerrDiscoverHomeView: View {
    @Binding var home: SeerrDiscoverHome
    var isLoading: Bool
    var onSelect: (SeerrTitle) -> Void
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    @State private var rowWidth: CGFloat = 0

    /// Eight posters across the Mac's visible width, as on Home; nil keeps the phone sizes.
    private var fittedPosterSize: CGSize? {
        DetailRowLayout.cardWidth(fitting: 8, in: rowWidth).map { CGSize(width: $0, height: ($0 * 1.5).rounded()) }
    }

    /// Five wide cards across the Mac's visible width, as on Home.
    private var fittedCardWidth: CGFloat? {
        DetailRowLayout.cardWidth(fitting: 5, in: rowWidth)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if isLoading && home.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            }

            titleRow("Recent Requests", titles: home.recentRequests, query: .requests)
            titleRow("Trending", titles: home.trending, query: .trending)
            titleRow("Popular Movies", titles: home.popularMovies, query: .popularMovies)
            genreRow("Movie Genres", genres: home.movieGenres, kind: .movie)
            titleRow("Upcoming Movies", titles: home.upcomingMovies, query: .upcomingMovies)
            companyRow("Studios", companies: home.studios)
            titleRow("Popular TV", titles: home.popularTV, query: .popularTV)
            genreRow("TV Genres", genres: home.tvGenres, kind: .tv)
            titleRow("Upcoming TV", titles: home.upcomingTV, query: .upcomingTV)
            companyRow("Networks", companies: home.networks)
        }
        .padding(.top, 8)
        .padding(.bottom, 32)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
    }

    @ViewBuilder
    private func titleRow(_ title: String, titles: [SeerrTitle], query: SeerrDiscoverQuery) -> some View {
        if !titles.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink {
                    SeerrDiscoverGridView(query: query) { title in
                        home.markRequested(title)
                    }
                } label: {
                    SectionHeader(title: title)
                }
                .buttonStyle(.plain)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: DetailRowLayout.spacing) {
                        ForEach(titles) { item in
                            SeerrRequestPosterButton(title: item, size: fittedPosterSize) { item in
                                onSelect(item)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    @ViewBuilder
    private func genreRow(_ title: String, genres: [SeerrGenreSliderItem], kind _: SeerrTitle.Kind) -> some View {
        if !genres.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: title, showsChevron: false)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: DetailRowLayout.spacing) {
                        ForEach(GenreOrder.shuffled(genres, name: \.name)) { genre in
                            NavigationLink {
                                SeerrDiscoverGridView(query: genre.discoverQuery) { title in
                                    home.markRequested(title)
                                }
                            } label: {
                                GenrePosterCard(title: genre.name, width: fittedPosterSize?.width, height: fittedPosterSize?.height)
                            }
                            .buttonStyle(.plain)
                            .frame(width: fittedPosterSize?.width ?? PosterMetrics.portraitSize.width * sidebarLayout.scale, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    @ViewBuilder
    private func companyRow(_ title: String, companies: [SeerrCompany]) -> some View {
        if !companies.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: title, showsChevron: false)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: DetailRowLayout.spacing) {
                        ForEach(companies) { company in
                            NavigationLink {
                                SeerrDiscoverGridView(query: company.query) { title in
                                    home.markRequested(title)
                                }
                            } label: {
                                SeerrCompanyCard(company: company, width: fittedCardWidth)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

struct SeerrDiscoverGridView: View {
    let query: SeerrDiscoverQuery
    var onRequested: (SeerrTitle) -> Void = { _ in }
    @Environment(SessionStore.self) private var session
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout

    @State private var titles: [SeerrTitle] = []
    @State private var page = 1
    @State private var totalPages = 1
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var requestTitle: SeerrTitle?

    private var columns: [GridItem] {
        PosterGridLayout.columns(for: sidebarLayout)
    }

    var body: some View {
        ScrollView {
            if isLoading && titles.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else if let errorMessage, titles.isEmpty {
                ContentUnavailableView(
                    "Couldn’t Load \(query.title)",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                .padding(.top, 24)
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(Array(titles.enumerated()), id: \.element.id) { index, title in
                        gridCell(title, index: index)
                    }
                }
                .padding(16)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(query.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load(page: 1, replace: true) }
        .sheet(item: $requestTitle) { title in
            NavigationStack {
                SeerrRequestView(title: title) {
                    markRequested(title)
                    onRequested(title)
                }
            }
        }
    }

    private func gridCell(_ title: SeerrTitle, index: Int) -> some View {
        SeerrRequestPosterButton(title: title, fillsCell: true) { title in
            handleRequest(title)
        }
        .onAppear {
            if index >= titles.count - 4 {
                Task { await loadMore() }
            }
        }
    }

    private func loadMore() async {
        guard !isLoading, page < totalPages else { return }
        await load(page: page + 1, replace: false)
    }

    private func load(page nextPage: Int, replace: Bool) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let payload: SeerrDiscoverPage
            guard let client = PluginSettings.seerrClient else {
                errorMessage = "Sign in to \(PluginSettings.requestService.name) in Settings."
                return
            }
            payload = try await client.discover(query, page: nextPage)
            if replace {
                titles = payload.titles
            } else {
                let existing = Set(titles.map(\.id))
                titles.append(contentsOf: payload.titles.filter { !existing.contains($0.id) })
            }
            page = payload.page
            totalPages = max(payload.totalPages, 1)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleRequest(_ title: SeerrTitle) {
        guard !title.isInJellyfin(catalog: session.tmdbCatalog) else { return }
        requestTitle = title
    }

    private func markRequested(_ title: SeerrTitle) {
        if let index = titles.firstIndex(where: { $0.id == title.id }) {
            titles[index].availability = .pending
        }
    }
}

private struct SeerrRequestPosterButton: View {
    @Environment(SessionStore.self) private var session
    let title: SeerrTitle
    var fillsCell = false
    var size: CGSize? = nil
    var onSelect: (SeerrTitle) -> Void

    private var locked: Bool {
        title.isInJellyfin(catalog: session.tmdbCatalog)
    }

    var body: some View {
        Group {
            if locked {
                poster
                    .allowsHitTesting(false)
            } else {
                Button {
                    onSelect(title)
                } label: {
                    poster
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var poster: some View {
        if fillsCell {
            FillingPosterCell { size in
                SeerrPoster(title: title, size: size, libraryMarkOnly: locked)
            }
        } else {
            SeerrPoster(title: title, size: size, libraryMarkOnly: locked)
        }
    }
}

private struct SeerrPoster: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    let title: SeerrTitle
    var size: CGSize? = nil
    var libraryMarkOnly = false

    private var fittedSize: CGSize {
        size ?? PosterMetrics.portraitSize.scaled(by: sidebarLayout.scale)
    }

    private var isInJellyfin: Bool {
        title.isInJellyfin(catalog: session.tmdbCatalog)
    }

    var body: some View {
        PosterImage(url: title.posterURL)
            .frame(width: fittedSize.width, height: fittedSize.height)
            .overlay(alignment: .topLeading) {
                if !libraryMarkOnly {
                    SeerrKindMark(kind: title.kind)
                        .padding(6)
                }
            }
            .overlay(alignment: .topTrailing) {
                if libraryMarkOnly || isInJellyfin {
                    JellyfinLibraryMark()
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if !libraryMarkOnly, let requester = title.requestedByName {
                    Text(requester)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LoginPalette.actionLabel)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.tint, in: Capsule(style: .continuous))
                        .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
                        .frame(maxWidth: max(0, fittedSize.width - 12), alignment: .leading)
                        .padding(6)
                }
            }
            .posterCard()
            .frame(width: fittedSize.width, alignment: .leading)
            .accessibilityLabel(accessibilityName)
    }

    private var accessibilityName: String {
        var parts = [title.name, title.kind.accessibilityName]
        if let requester = title.requestedByName {
            parts.append("requested by \(requester)")
        }
        if isInJellyfin {
            parts.append("on Jellyfin")
        }
        return parts.joined(separator: ", ")
    }
}

struct SeerrKindMark: View {
    let kind: SeerrTitle.Kind

    var body: some View {
        Image(systemName: kind.symbolName)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: 24, height: 24)
            .background(Color.white, in: Circle())
            .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
            .accessibilityHidden(true)
    }
}

struct JellyfinLibraryMark: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.black, Color.white)
            .font(.system(size: 20, weight: .bold))
            .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
            .accessibilityHidden(true)
    }
}

private struct SeerrCompanyCard: View {
    let company: SeerrCompany
    var width: CGFloat? = nil
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout

    /// Grey used by TMDB’s studio/network duotone (`#2e2e2e`).
    private static let logoBackdrop = Color(red: 46 / 255, green: 46 / 255, blue: 46 / 255)

    private var size: CGSize {
        let base = CGSize(
            width: PosterMetrics.landscapeSize.width * 0.62,
            height: PosterMetrics.landscapeSize.height * 0.72
        )
        guard let width else { return base.scaled(by: sidebarLayout.scale) }
        return CGSize(width: width, height: (width * base.height / base.width).rounded())
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PosterMetrics.cornerRadius, style: .continuous)
                .fill(Self.logoBackdrop)
            PosterImage(
                url: company.imageURL,
                aspectRatio: 2.2,
                contentMode: .fit,
                fill: Self.logoBackdrop,
                progressTint: Color.white.opacity(0.45)
            )
            .padding(18)
        }
        .frame(width: size.width, height: size.height)
        .posterCard()
        .accessibilityLabel(company.name)
    }
}
