import SwiftUI
import SafariServices

struct ItemDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(DownloadStore.self) private var downloads
    @Environment(\.openURL) private var openURL
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    let itemID: String
    let focusEpisodeID: String?

    @State private var item: MediaItem?
    @State private var seasons: [MediaItem] = []
    @State private var episodes: [MediaItem] = []
    @State private var trailers: [TitleTrailer] = []
    @State private var related: [MediaItem] = []
    @State private var credits: [CreditPerson] = []
    @State private var collections: [ItemCollectionMembership] = []
    @State private var selectedSeasonID: String?
    @State private var scrolledEpisodeID: EpisodeCarouselCard.ID?
    @State private var isJumpingSeason = false
    @State private var isLoading = true
    @State private var hasLoadedDetail = false
    @State private var isOverviewExpanded = false
    @State private var playingItem: MediaItem?
    @State private var playingWebTrailer: TitleTrailer?
    @State private var errorMessage: String?
    @State private var downloadRemovalPrompt: DownloadRemovalPrompt?
    @State private var downloadRemovalItem: MediaItem?

    init(itemID: String, preview: MediaItem? = nil, focusEpisodeID: String? = nil) {
        self.itemID = itemID
        self.focusEpisodeID = focusEpisodeID
        _item = State(initialValue: preview)
        _isLoading = State(initialValue: preview == nil)
    }

    init(item: MediaItem) {
        if let seriesID = item.seriesDetailItemID {
            self.init(
                itemID: seriesID,
                preview: item.seriesShowcasePreview(),
                focusEpisodeID: item.kind == .episode ? item.id : nil
            )
        } else {
            self.init(itemID: item.id, preview: item)
        }
    }

    var body: some View {
        GeometryReader { geo in
            Group {
                if isLoading {
                    ProgressView().tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let item {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            hero(for: item, width: geo.size.width, height: PosterMetrics.heroHeight(for: geo.size))

                            if item.kind == .series, !seasons.isEmpty {
                                seasonsSection
                                    .padding(.top, 4)
                                    .padding(.bottom, 20)
                            }

                            if !trailers.isEmpty {
                                trailersSection(for: item)
                                    .padding(.top, item.kind == .series ? 0 : 4)
                                    .padding(.bottom, 20)
                            }

                            if !related.isEmpty {
                                relatedSection
                                    .padding(.bottom, 20)
                            }

                            if !credits.isEmpty {
                                castSection
                                    .padding(.bottom, 20)
                            }

                            ForEach(collections) { membership in
                                collectionSection(membership)
                                    .padding(.bottom, 20)
                            }
                        }
                        .padding(.bottom, 40)
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                    .zelefinScrollEdgeHidden()
                } else {
                    ContentUnavailableView("Title Unavailable", systemImage: "film")
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let item {
                    DetailDownloadSharePill(item: item, episodes: episodes)
                }
            }
            .catalogToolbarHidesSystemBackground()
        }
        .tint(.white)
        .task { await load() }
        .fullScreenCover(item: $playingItem, onDismiss: {
            Task { await refreshPlaybackProgress() }
        }) { item in
            PlayerView(item: item)
        }
        .fullScreenCover(item: $playingWebTrailer) { trailer in
            if let url = trailer.externalWatchURL {
                TrailerSafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .alert("Playback", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .downloadRemovalConfirmation($downloadRemovalPrompt) {
            if let downloadRemovalItem {
                downloads.removeDownloaded(item: downloadRemovalItem, account: session.session)
            }
            downloadRemovalItem = nil
        }
    }

    private func hero(for item: MediaItem, width: CGFloat, height: CGFloat) -> some View {
        return VStack(spacing: 14) {
            TitleLogo(
                item: item,
                maxHeight: 72,
                fallbackFont: .largeTitle.bold(),
                alignment: .center
            )
            .frame(minHeight: 44)
            .shadow(color: .black.opacity(0.7), radius: 10, y: 1)

            Text(detailMetadataLine(for: item))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            playProgressRow(for: MediaItem.heroPlaybackItem(title: item, episodes: episodes))

            if let overview = item.overview, !overview.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    overviewBlock(overview)
                    technicalSpecsRow(for: item)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                technicalSpecsRow(for: item)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
        .frame(width: width, height: height, alignment: .bottom)
        .background {
            ZStack {
                HeroArtwork(
                    url: session.library?.backdropURL(for: item),
                    placeholderURL: session.library?.primaryURL(for: item),
                    size: CGSize(width: width, height: height)
                )

                LinearGradient(
                    colors: [.black.opacity(0.5), .clear],
                    startPoint: .top,
                    endPoint: .center
                )

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.28),
                        .init(color: .black.opacity(0.55), location: 0.58),
                        .init(color: .black.opacity(0.94), location: 0.86),
                        .init(color: .black, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .zelefinHeroBackgroundExtension()
        }
    }

    private func detailMetadataLine(for item: MediaItem) -> String {
        var parts = [item.kindLabel]
        parts.append(contentsOf: Array(item.genres.prefix(2)))
        return parts.joined(separator: " · ")
    }

    private func playProgressRow(for playbackItem: MediaItem) -> some View {
        let title = item ?? playbackItem
        return VStack(spacing: 10) {
            playProgressButton(for: playbackItem, allowRelatedDownload: true)
            DownloadStatusBanner(item: title)
        }
    }

    private func playProgressButton(for item: MediaItem, allowRelatedDownload: Bool = false) -> some View {
        Button {
            play(item, allowRelatedDownload: allowRelatedDownload)
        } label: {
            HStack(spacing: PlayButtonLayout.spacing) {
                Image(systemName: "play.fill")
                    .font(PlayButtonLayout.iconFont)
                    .frame(width: PlayButtonLayout.iconWidth)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.28))
                    Capsule()
                        .fill(Color.black.opacity(0.82))
                        .scaleEffect(x: item.progress, y: 1, anchor: .leading)
                }
                .frame(width: PlayButtonLayout.progressWidth, height: PlayButtonLayout.progressHeight)

                playButtonLabel(for: item)
            }
            .foregroundStyle(.black)
            .padding(.horizontal, PlayButtonLayout.horizontalPadding)
            .frame(width: 175, height: 45)
            .background(Color.white, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.playbackPosition > 5 ? "Resume" : "Play")
        .accessibilityValue(item.playActionDurationLabel ?? "")
    }

    @ViewBuilder
    private func playButtonLabel(for item: MediaItem) -> some View {
        Text(item.playActionDurationLabel ?? "Play")
            .font(PlayButtonLayout.labelFont)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }

    private enum PlayButtonLayout {
        static let spacing: CGFloat = 8
        static let iconFont: Font = .body.weight(.bold)
        static let iconWidth: CGFloat = 10
        static let progressWidth: CGFloat = 55
        static let progressHeight: CGFloat = 7
        static let labelFont: Font = .subheadline.weight(.semibold)
        static let horizontalPadding: CGFloat = 12
        static let minWidth: CGFloat = 175
        static let height: CGFloat = 45
    }

    private func technicalSpecsRow(for item: MediaItem) -> some View {
        ViewThatFits(in: .horizontal) {
            specsContent(for: item, spacing: 5)
            specsContent(for: item, spacing: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Title details")
    }

    @ViewBuilder
    private func specsContent(for item: MediaItem, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            if let year = item.year, let runtime = item.runtimeLabel {
                specText("\(year) · \(runtime)")
            } else if let year = item.year {
                specText("\(year)")
            } else if let runtime = item.runtimeLabel {
                specText(runtime)
            }
            if let score = item.criticRating, score > 0 {
                HStack(spacing: 3) {
                    Image(score >= 60 ? "TomatometerFresh" : "TomatometerSplat")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                    Text("\(Int(score.rounded()))%")
                }
                .fixedSize()
                .accessibilityLabel("Rotten Tomatoes \(Int(score.rounded())) percent")
            }
            if let age = item.ageGateLabel {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.35))
                    Text(age)
                }
                .fixedSize()
                .accessibilityLabel(age)
            }
            if let rating = item.officialRating, !rating.isEmpty {
                specBadge(rating)
            }
            if let resolution = item.videoResolution.displayName {
                specBadge(resolution)
            }
            if item.videoRange == .dolbyVision {
                Image("DolbyVisionLogo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 11)
                    .accessibilityLabel("Dolby Vision")
            } else if item.videoRange != .sdr {
                specBadge(item.videoRange.displayName)
            }
            if item.audioFormat == .atmos {
                Image("DolbyAtmosLogo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 11)
                    .accessibilityLabel("Dolby Atmos")
            }
            if item.hasClosedCaptions {
                specBadge("CC")
            }
            if item.hasAudioDescription {
                specBadge("AD")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.88))
        .fixedSize(horizontal: true, vertical: false)
    }

    private func specText(_ value: String) -> some View {
        Text(value)
            .fixedSize()
            .layoutPriority(1)
    }

    private func specBadge(_ value: String) -> some View {
        Text(value)
            .font(.caption)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(.white.opacity(0.85), lineWidth: 1)
            }
            .accessibilityLabel(value)
    }

    private func overviewBlock(_ overview: String) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Text(overview)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.leading)
                .lineLimit(isOverviewExpanded ? nil : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, showsOverviewMore(overview) ? 56 : 0)

            if showsOverviewMore(overview) {
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.92)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 28, height: 22)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isOverviewExpanded = true
                        }
                    } label: {
                        Text("MORE")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("More")
                }
            }
        }
    }

    private func showsOverviewMore(_ overview: String) -> Bool {
        !isOverviewExpanded && overview.count > 90
    }

    private var selectedSeasonTitle: String {
        seasons.first(where: { $0.id == selectedSeasonID })?.seasonMenuTitle ?? "Season"
    }

    private var episodeStrip: [EpisodeCarouselCard] {
        EpisodeCarousel.cards(seasons: seasons, episodes: episodes)
    }

    private var seasonsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Menu {
                ForEach(seasons) { season in
                    Button(season.seasonMenuTitle) {
                        selectSeason(season)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedSeasonTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(selectedSeasonTitle)
            .accessibilityHint("Choose a season")

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: PosterMetrics.rowSpacing) {
                    ForEach(episodeStrip) { card in
                        ZStack(alignment: .bottomTrailing) {
                            Button {
                                play(card.episode)
                            } label: {
                                EpisodeShowcaseCard(
                                    item: card.episode,
                                    imageURL: session.library?.primaryURL(for: card.episode, maxHeight: 480),
                                    showsOverflowIcon: false
                                )
                            }
                            .buttonStyle(.plain)

                            PlaybackQueueOverflowButton(
                                item: card.episode,
                                context: .episode,
                                onPlay: { play(card.episode) },
                                onDidChange: { Task { await refreshPlaybackProgress() } },
                                labelOpacity: 0.72,
                                usesCardChrome: false
                            )
                            .padding(.trailing, 2)
                            .padding(.bottom, 2)
                        }
                        .frame(
                            width: PosterMetrics.episodeCardSize.width * sidebarLayout.scale,
                            height: PosterMetrics.episodeCardSize.height * sidebarLayout.scale
                        )
                        .accessibilityHidden(card.copy != EpisodeCarousel.homeCopy)
                    }
                }
                .scrollTargetLayout()
            }
            .frame(height: PosterMetrics.episodeCardSize.height * sidebarLayout.scale)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrolledEpisodeID)
            .onChange(of: scrolledEpisodeID) { _, newValue in
                handleEpisodeScroll(newValue)
            }
            .onScrollPhaseChange { _, phase in
                guard phase == .idle else { return }
                isJumpingSeason = false
                recenterLoopIfNeeded()
            }
            .onAppear {
                if scrolledEpisodeID == nil, !episodeStrip.isEmpty {
                    syncCarouselPosition(forceSeasonStart: true)
                }
            }
        }
    }

    private func trailersSection(for item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                TrailerListView(
                    trailers: trailers,
                    thumbnailURL: { thumbnailURL(for: $0, title: item) },
                    onPlay: playTrailer
                )
            } label: {
                SectionHeader(title: "Trailers")
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: PosterMetrics.rowSpacing) {
                    ForEach(trailers) { trailer in
                        Button {
                            playTrailer(trailer)
                        } label: {
                            TrailerLandscapeCard(
                                title: trailer.title,
                                caption: trailer.caption,
                                imageURL: thumbnailURL(for: trailer, title: item)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: PosterMetrics.landscapeSize.height * sidebarLayout.scale)
        }
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                SectionGridView(
                    section: HomeSection(id: "related", title: "Related", style: .portrait, items: related)
                )
            } label: {
                SectionHeader(title: "Related")
            }
            .buttonStyle(.plain)

            posterScroller(related)
        }
    }

    private var castSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                CastCrewListView(people: credits)
            } label: {
                SectionHeader(title: "Cast & Crew")
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: PosterMetrics.rowSpacing) {
                    ForEach(credits) { person in
                        NavigationLink {
                            CatalogGridView(title: person.name, query: .person(person.id))
                        } label: {
                            CastMemberCard(
                                person: person,
                                imageURL: session.library?.personImageURL(id: person.id, tag: person.imageTag)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func collectionSection(_ membership: ItemCollectionMembership) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                CatalogGridView(title: membership.collection.browsingCardTitle, query: .parent(membership.collection.id))
            } label: {
                SectionHeader(title: collections.count > 1 ? membership.collection.browsingCardTitle : "Collection")
            }
            .buttonStyle(.plain)

            posterScroller(membership.items)
        }
    }

    private func posterScroller(_ items: [MediaItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: PosterMetrics.rowSpacing) {
                ForEach(items) { item in
                    NavigationLink {
                        if item.kind == .collection {
                            CatalogGridView(title: item.name, query: .parent(item.id))
                        } else {
                            ItemDetailView(item: item)
                        }
                    } label: {
                        PortraitPoster(
                            item: item,
                            imageURL: session.library?.primaryURL(for: item)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: PosterMetrics.portraitSize.height * sidebarLayout.scale)
    }

    private func thumbnailURL(for trailer: TitleTrailer, title: MediaItem) -> URL? {
        if let url = trailer.thumbnailURL {
            return url
        }
        if let local = trailer.jellyfinItem {
            return session.library?.artworkURL(for: local, style: .replayLandscape)
                ?? session.library?.backdropURL(for: local)
        }
        return session.library?.backdropURL(for: title)
    }

    private func playTrailer(_ trailer: TitleTrailer) {
        if let local = trailer.jellyfinItem {
            play(local)
            return
        }
        playingWebTrailer = trailer
    }

    private func load() async {
        guard session.library != nil else { return }
        if hasLoadedDetail { return }

        isOverviewExpanded = false
        if let snapshot = session.cachedItemDetail(itemID: itemID) {
            apply(snapshot)
            applyFocusedEpisode()
            isLoading = false
        } else if item != nil {
            isLoading = false
        }
        await refreshFromServer()
        hasLoadedDetail = true
    }

    private func apply(_ snapshot: ItemDetailSnapshot) {
        item = snapshot.item
        trailers = snapshot.trailers
        related = snapshot.related
        credits = snapshot.credits
        collections = snapshot.collections
        seasons = MediaItem.orderedSeasons(snapshot.seasons)
        episodes = MediaItem.orderedShowEpisodes(snapshot.episodes, seasons: seasons)
        selectedSeasonID = snapshot.selectedSeasonID
        if scrolledEpisodeID == nil {
            scrolledEpisodeID = EpisodeCarousel.homePosition(
                seasonID: selectedSeasonID,
                seasons: seasons,
                episodes: episodes
            )
        }
    }

    private func persistSnapshot() {
        guard let item else { return }
        session.persistItemDetail(
            item: item,
            trailers: trailers,
            related: related,
            credits: credits,
            collections: collections,
            seasons: seasons,
            episodes: episodes,
            selectedSeasonID: selectedSeasonID
        )
    }

    private func refreshFromServer() async {
        guard let library = session.library else { return }
        do {
            let (loaded, dto) = try await library.item(id: itemID)
            item = loaded
            isLoading = false

            async let fetchedTrailers = library.trailers(for: dto)
            async let fetchedRelated = library.similarItems(for: loaded)
            async let fetchedCredits = library.credits(for: loaded.id, from: dto)

            if loaded.kind == .series {
                async let fetchedSeasons = library.seasons(seriesID: loaded.id)
                async let fetchedEpisodes = library.episodes(seriesID: loaded.id)
                seasons = MediaItem.orderedSeasons((try? await fetchedSeasons) ?? [])
                if selectedSeasonID == nil || !seasons.contains(where: { $0.id == selectedSeasonID }) {
                    selectedSeasonID = seasons.first?.id
                }
                episodes = MediaItem.orderedShowEpisodes(
                    (try? await fetchedEpisodes) ?? [],
                    seasons: seasons
                )
                applyFocusedEpisode()
                syncCarouselPosition(forceSeasonStart: scrolledEpisodeID == nil)
                persistSnapshot()
            } else {
                seasons = []
                episodes = []
                selectedSeasonID = nil
                scrolledEpisodeID = nil
            }

            related = await fetchedRelated
            credits = await fetchedCredits
            persistSnapshot()

            trailers = await fetchedTrailers
            persistSnapshot()

            collections = await library.collections(containing: loaded.id)
            persistSnapshot()
        } catch {
            if item == nil {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    private func refreshPlaybackProgress() async {
        guard let library = session.library else { return }
        guard let (loaded, _) = try? await library.item(id: itemID) else { return }
        item = loaded
        if loaded.kind == .series {
            let fetched = (try? await library.episodes(seriesID: loaded.id)) ?? []
            episodes = MediaItem.orderedShowEpisodes(fetched, seasons: seasons)
        }
        persistSnapshot()
    }

    private func applyFocusedEpisode() {
        guard let focusEpisodeID, episodes.contains(where: { $0.id == focusEpisodeID }) else { return }
        if let seasonID = EpisodeCarousel.seasonID(for: focusEpisodeID, in: episodeStrip) {
            selectedSeasonID = seasonID
        }
        scrolledEpisodeID = EpisodeCarousel.position(episodeID: focusEpisodeID)
    }

    private func selectSeason(_ season: MediaItem) {
        selectedSeasonID = season.id
        guard let position = EpisodeCarousel.homePosition(
            seasonID: season.id,
            seasons: seasons,
            episodes: episodes
        ) else { return }
        isJumpingSeason = true
        withAnimation(.smooth(duration: 0.5)) {
            scrolledEpisodeID = position
        }
        persistSnapshot()
    }

    private func jumpToSeasonStart(_ seasonID: String) {
        guard let position = EpisodeCarousel.homePosition(
            seasonID: seasonID,
            seasons: seasons,
            episodes: episodes
        ) else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrolledEpisodeID = position
        }
    }

    private func syncCarouselPosition(forceSeasonStart: Bool) {
        let strip = episodeStrip
        if forceSeasonStart {
            jumpToSeasonStart(selectedSeasonID ?? seasons.first?.id ?? "")
            return
        }
        if let scrolledEpisodeID, strip.contains(where: { $0.id == scrolledEpisodeID }) {
            return
        }
        if let scrolledEpisodeID,
           strip.contains(where: { $0.copy == EpisodeCarousel.homeCopy && $0.episode.id == scrolledEpisodeID.episodeID }) {
            self.scrolledEpisodeID = EpisodeCarouselCard.ID(
                copy: EpisodeCarousel.homeCopy,
                episodeID: scrolledEpisodeID.episodeID
            )
            return
        }
        jumpToSeasonStart(selectedSeasonID ?? seasons.first?.id ?? "")
    }

    private func handleEpisodeScroll(_ id: EpisodeCarouselCard.ID?) {
        guard let id else { return }
        if let seasonID = EpisodeCarousel.seasonID(for: id.episodeID, in: episodeStrip),
           selectedSeasonID != seasonID {
            selectedSeasonID = seasonID
        }
    }

    private func recenterLoopIfNeeded() {
        guard !isJumpingSeason, let id = scrolledEpisodeID,
              let recentered = EpisodeCarousel.recentered(id)
        else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrolledEpisodeID = recentered
        }
        persistSnapshot()
    }

    private func play(_ item: MediaItem, allowRelatedDownload: Bool = false) {
        if let local = downloads.playableItem(
            for: item,
            allowRelated: allowRelatedDownload,
            account: session.session
        ) {
            playingItem = local
            return
        }
        playingItem = item
    }

}

extension PlaybackPlan: Identifiable {
    var id: String { item.id }
}

private struct TrailerListView: View {
    let trailers: [TitleTrailer]
    let thumbnailURL: (TitleTrailer) -> URL?
    let onPlay: (TitleTrailer) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(trailers) { trailer in
                    Button {
                        onPlay(trailer)
                    } label: {
                        TrailerLandscapeCard(
                            title: trailer.title,
                            caption: trailer.caption,
                            imageURL: thumbnailURL(trailer)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Trailers")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private struct CastCrewListView: View {
    @Environment(SessionStore.self) private var session
    let people: [CreditPerson]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(people) { person in
                    NavigationLink {
                        CatalogGridView(title: person.name, query: .person(person.id))
                    } label: {
                        HStack(spacing: 14) {
                            PosterImage(
                                url: session.library?.personImageURL(id: person.id, tag: person.imageTag),
                                aspectRatio: 1
                            )
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text(person.roleLabel)
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Cast & Crew")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private struct TrailerSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.barCollapsingEnabled = true
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.dismissButtonStyle = .close
        controller.preferredBarTintColor = .black
        controller.preferredControlTintColor = .white
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
