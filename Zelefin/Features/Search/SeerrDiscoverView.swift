import SwiftUI

struct SeerrDiscoverHomeView: View {
    @Binding var home: SeerrDiscoverHome
    var isLoading: Bool
    var onSelect: (SeerrTitle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if isLoading && home.isEmpty {
                ProgressView()
                    .tint(.white)
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
                    LazyHStack(spacing: PosterMetrics.rowSpacing) {
                        ForEach(titles) { item in
                            Button {
                                onSelect(item)
                            } label: {
                                SeerrPoster(title: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    @ViewBuilder
    private func genreRow(_ title: String, genres: [SeerrGenreSliderItem], kind: SeerrTitle.Kind) -> some View {
        if !genres.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: title, showsChevron: false)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: PosterMetrics.rowSpacing) {
                        ForEach(genres) { genre in
                            NavigationLink {
                                SeerrDiscoverGridView(
                                    query: kind == .movie
                                        ? .movieGenre(id: genre.id, name: genre.name)
                                        : .tvGenre(id: genre.id, name: genre.name)
                                ) { title in
                                    home.markRequested(title)
                                }
                            } label: {
                                LabeledPortraitCard(
                                    title: genre.name,
                                    imageURL: genre.imageURL,
                                    washColor: LabeledPortraitCard.genreWash(for: genre.name)
                                )
                            }
                            .buttonStyle(.plain)
                            .frame(width: PosterMetrics.portraitSize.width, alignment: .leading)
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
                    LazyHStack(spacing: PosterMetrics.rowSpacing) {
                        ForEach(companies) { company in
                            NavigationLink {
                                SeerrDiscoverGridView(query: company.query) { title in
                                    home.markRequested(title)
                                }
                            } label: {
                                SeerrCompanyCard(company: company)
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

    @State private var titles: [SeerrTitle] = []
    @State private var page = 1
    @State private var totalPages = 1
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var requestTitle: SeerrTitle?

    private let columns = [
        GridItem(.adaptive(minimum: PosterMetrics.portraitSize.width), spacing: PosterMetrics.rowSpacing)
    ]

    var body: some View {
        ScrollView {
            if isLoading && titles.isEmpty {
                ProgressView()
                    .tint(.white)
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
                        Button {
                            requestTitle = title
                        } label: {
                            SeerrPoster(title: title)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if index >= titles.count - 4 {
                                Task { await loadMore() }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(query.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        .task { await load(page: 1, replace: true) }
        .sheet(item: $requestTitle) { title in
            NavigationStack {
                SeerrRequestView(title: title) {
                    if let index = titles.firstIndex(where: { $0.id == title.id }) {
                        titles[index].availability = .pending
                    }
                    onRequested(title)
                }
            }
        }
    }

    private func loadMore() async {
        guard !isLoading, page < totalPages else { return }
        await load(page: page + 1, replace: false)
    }

    private func load(page nextPage: Int, replace: Bool) async {
        guard let client = PluginSettings.seerrClient else {
            errorMessage = "Sign in to Seerr in Settings."
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let payload = try await client.discover(query, page: nextPage)
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
}

private struct SeerrPoster: View {
    @Environment(SessionStore.self) private var session
    let title: SeerrTitle

    private var isInJellyfin: Bool {
        title.isInJellyfin(catalog: session.tmdbCatalog)
    }

    var body: some View {
        PosterImage(url: title.posterURL)
            .frame(width: PosterMetrics.portraitSize.width, height: PosterMetrics.portraitSize.height)
            .overlay(alignment: .topLeading) {
                SeerrKindMark(kind: title.kind)
                    .padding(6)
            }
            .overlay(alignment: .topTrailing) {
                if isInJellyfin {
                    JellyfinLibraryMark()
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let requester = title.requestedByName {
                    Text(requester)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white, in: Capsule(style: .continuous))
                        .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
                        .frame(maxWidth: PosterMetrics.portraitSize.width - 12, alignment: .leading)
                        .padding(6)
                }
            }
            .posterCard()
            .frame(width: PosterMetrics.portraitSize.width, alignment: .leading)
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

    /// Grey used by TMDB’s studio/network duotone (`#2e2e2e`).
    private static let logoBackdrop = Color(red: 46 / 255, green: 46 / 255, blue: 46 / 255)

    private var size: CGSize {
        CGSize(width: PosterMetrics.landscapeSize.width * 0.62, height: PosterMetrics.landscapeSize.height * 0.72)
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
