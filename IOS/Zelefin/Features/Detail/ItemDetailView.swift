import AVFoundation
import Combine
import SwiftUI
import SafariServices

struct ItemDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(DownloadStore.self) private var downloads
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    /// The page's own width: a pushed page doesn't always get the measured layout from its column.
    @State private var pageWidth: CGFloat = 0
    @Environment(\.scenePhase) private var scenePhase
    let itemID: String
    let focusEpisodeID: String?

    @State private var item: MediaItem?
    @State private var seasons: [MediaItem] = []
    @State private var episodes: [MediaItem] = []
    @State private var channel: MediaItem?
    @State private var youtubeChromeVisible = true
    @State private var heroLock = HeroHeightLock()
    @State private var trailers: [TitleTrailer] = []
    @State private var extras: [TitleExtra] = []
    @State private var additionalParts: [MediaItem] = []
    @State private var showsIdentify = false
    @State private var showsEditMetadata = false
    @State private var related: [MediaItem] = []
    @State private var credits: [CreditPerson] = []
    @State private var collections: [ItemCollectionMembership] = []
    @State private var collectionMembers: [MediaItem] = []
    @State private var selectedSeasonID: String?
    @State private var scrolledEpisodeID: EpisodeCarouselCard.ID?
    @State private var isJumpingSeason = false
    @State private var isLoading = true
    @State private var hasLoadedDetail = false
    @State private var showsMoreInfo = false
    @State private var showsAboutPage = false
    @State private var moreInfo = TitleMoreInfo()
    @State private var playingItem: MediaItem?
    @State private var playingWebTrailer: TitleTrailer?
    @State private var theme = ThemeMediaController()
    @State private var loadedTheme: ThemeMedia?
    @State private var isOnScreen = false
    @State private var showsCollectionEditor = false
    @State private var showsPlayOnDevice = false
    @State private var showsSyncPlay = false
    @State private var showsRemoteImages = false
    @State private var showsDeleteConfirm = false
    @State private var viewingPhoto: MediaItem?
    @State private var errorMessage: String?
    @State private var downloadRemovalPrompt: DownloadRemovalPrompt?
    @State private var downloadRemovalItem: MediaItem?
    @State private var subtitleSearchItem: MediaItem?
    @State private var mediaStreamRevision = 0
    @State private var audioTracks: [MediaTrack]?
    @State private var subtitleTracks: [MediaTrack]?

    init(itemID: String, preview: MediaItem? = nil, focusEpisodeID: String? = nil) {
        self.itemID = itemID
        self.focusEpisodeID = focusEpisodeID
        _item = State(initialValue: preview)
        _isLoading = State(initialValue: preview == nil)
    }

    init(item: MediaItem) {
        if item.isYouTube {
            self.init(itemID: item.id, preview: item)
        } else if let seriesID = item.seriesDetailItemID {
            self.init(
                itemID: seriesID,
                preview: item.seriesShowcasePreview(),
                focusEpisodeID: item.kind == .episode ? item.id : nil
            )
        } else {
            self.init(itemID: item.id, preview: item)
        }
    }

    /// The theme waits while something else plays or the app is in the background.
    private var themeIsPaused: Bool {
        session.pendingPlayerItem != nil || playingWebTrailer != nil || scenePhase != .active
    }

    var body: some View {
        page
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
            .presentsPlayerFromRoot($playingItem) {
                Task { await refreshPlaybackProgress() }
            }
            .onAppear {
                isOnScreen = true
                if let loadedTheme, !themeIsPaused {
                    theme.start(loadedTheme)
                }
            }
            .onDisappear {
                isOnScreen = false
                theme.stop()
            }
            .onChange(of: themeIsPaused) { _, paused in
                if paused {
                    theme.suspend()
                } else {
                    theme.resume()
                }
            }
            .fullScreenCover(item: $playingWebTrailer) { trailer in
                if let url = trailer.externalWatchURL {
                    TrailerSafariView(url: url)
                        .ignoresSafeArea()
                }
            }
            .sheet(isPresented: $showsCollectionEditor) {
                if let item {
                    CollectionEditSheet(item: item) {
                        showsCollectionEditor = false
                        Task { await refreshCollections() }
                    }
                }
            }
            .sheet(isPresented: $showsPlayOnDevice) {
                if let item {
                    PlayOnDeviceSheet(item: item) {
                        showsPlayOnDevice = false
                    }
                }
            }
            .sheet(isPresented: $showsSyncPlay) {
                if let item {
                    SyncPlayPlaySheet(item: item) {
                        showsSyncPlay = false
                    }
                }
            }
            .sheet(isPresented: $showsRemoteImages, onDismiss: {
                Task { await refreshFromServer() }
            }) {
                if let item {
                    RemoteImagePickerView(item: item) {
                        showsRemoteImages = false
                    }
                }
            }
            .sheet(isPresented: $showsIdentify, onDismiss: {
                Task { await refreshFromServer() }
            }) {
                if let item {
                    IdentifySheet(item: item) { showsIdentify = false }
                }
            }
            .sheet(isPresented: $showsEditMetadata, onDismiss: {
                Task { await refreshFromServer() }
            }) {
                if let item {
                    EditMetadataSheet(item: item) { showsEditMetadata = false }
                }
            }
            .fullScreenCover(item: $viewingPhoto) { photo in
                NavigationStack {
                    PhotoViewerView(item: photo)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { viewingPhoto = nil }
                            }
                        }
                }
            }
            .alert(
                "Delete this title from the library?",
                isPresented: $showsDeleteConfirm
            ) {
                Button("Delete Files", role: .destructive) {
                    Task { await deleteFromLibrary() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Jellyfin will remove this item and its files from the server. This cannot be undone.")
            }
            .sheet(isPresented: $showsMoreInfo) {
                if let item {
                    TitleMoreInfoView(item: item, info: moreInfo) {
                        showsMoreInfo = false
                    }
                    .presentationBackground(TitleMoreInfoView.sheetBackground)
                }
            }
            .sheet(isPresented: $showsAboutPage) {
                if let item {
                    TitleAboutPage(item: item) {
                        showsAboutPage = false
                    }
                    .presentationBackground(TitleMoreInfoView.sheetBackground)
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
            .openSubtitlesSearch(item: $subtitleSearchItem)
            .onReceive(NotificationCenter.default.publisher(for: .zelefinSubtitlesSaved)) { notification in
                guard let savedID = notification.userInfo?[SubtitleCatalogRefresh.itemIDKey] as? String else {
                    return
                }
                Task { await refreshAfterSubtitleSave(savedItemID: savedID) }
            }
    }

    private var page: some View {
        GeometryReader { geo in
            Group {
                if isLoading {
                    ProgressView().tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let item, item.isYouTube {
                    YouTubeDetailPage(
                        item: item,
                        channel: channel,
                        videos: episodes,
                        onPlay: { playingItem = $0 },
                        onChangeItem: { self.item = $0 },
                        onChangeChannel: { channel = $0 },
                        onChangeVideos: { episodes = $0 },
                        chromeVisible: $youtubeChromeVisible
                    )
                } else if let item {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            hero(for: item, width: geo.size.width, height: heroLock.height(for: geo.size))

                            if item.kind == .collection {
                                collectionMemberSections(for: item)
                            }

                            if item.kind == .series, !seasons.isEmpty {
                                seasonsSection
                                    .padding(.top, 4)
                                    .padding(.bottom, 20)
                            }

                            if !additionalParts.isEmpty {
                                additionalPartsSection
                                    .padding(.bottom, 20)
                            }

                            if !trailers.isEmpty {
                                trailersSection(for: item)
                                    .padding(.top, item.kind == .series ? 0 : 4)
                                    .padding(.bottom, 20)
                            }

                            if !extras.isEmpty {
                                extrasSection(for: item)
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

                            if !TitleAboutCards.cards(for: item).isEmpty {
                                TitleAboutRow(item: item) {
                                    showsAboutPage = true
                                }
                                .padding(.bottom, 20)
                            }

                            TitleEnhancedExtras(item: item)

                            if !moreInfo.information.isEmpty {
                                TitleFactsSection(title: "Information", rows: moreInfo.information)
                                    .padding(.bottom, 20)
                            }

                            if !moreInfo.languages.isEmpty {
                                TitleFactsSection(title: "Languages", rows: moreInfo.languages)
                                    .padding(.bottom, 20)
                            }

                            if !moreInfo.file.isEmpty {
                                TitleFactsSection(title: "File", rows: moreInfo.file)
                                    .padding(.bottom, 20)
                            }
                        }
                        .padding(.bottom, 40)
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                    .zelefinScrollEdgeHidden()
                    .zelefinPinnedBottomEdge()
                } else {
                    ContentUnavailableView("Title Unavailable", systemImage: "film")
                }
            }
            .onAppear { heroLock.lock(geo.size) }
            .onChange(of: geo.size.width) { heroLock.lock(geo.size) }
        }
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .zelefinPushedChrome(
            contentIgnoresTopSafeArea: true,
            hidesToolbarBackground: true,
            chromeVisible: item?.isYouTube != true || youtubeChromeVisible
        ) {
            if let item {
                detailTrailingChrome(for: item)
            }
        }
        .tint(.white)
        .onChange(of: itemID) { _, _ in
            youtubeChromeVisible = true
        }
        .task { await load() }
    }

    private func detailTrailingChrome(for item: MediaItem) -> some View {
        HStack(spacing: 8) {
            Menu {
                if item.isYouTube {
                    YouTubeUserActions(
                        item: item,
                        channel: channel,
                        onPlay: { playYouTube(item) },
                        onChange: { self.item = $0 },
                        onPlayElsewhere: session.isSiloServer ? nil : { showsPlayOnDevice = true },
                        onSyncPlay: session.lacksJellyfinOnlyFeatures || !item.kind.usesVideoPlayer
                            ? nil
                            : { showsSyncPlay = true },
                        onRefreshMetadata: session.isAdministrator
                            ? { Task { await refreshMetadata() } }
                            : nil
                    )
                } else {
                    TitleUserActions(
                        item: item,
                        onChange: { self.item = $0 },
                        onCollections: session.isSiloServer || item.kind == .collection ? nil : { showsCollectionEditor = true },
                        onPlayElsewhere: session.isSiloServer ? nil : { showsPlayOnDevice = true },
                        onSyncPlay: session.lacksJellyfinOnlyFeatures || !item.kind.usesVideoPlayer
                            ? nil
                            : { showsSyncPlay = true },
                        onRefreshMetadata: session.isAdministrator
                            ? { Task { await refreshMetadata() } }
                            : nil,
                        onRemoteImage: session.isAdministrator
                            ? { showsRemoteImages = true }
                            : nil,
                        onDelete: session.isAdministrator && item.kind != .collection
                            ? { showsDeleteConfirm = true }
                            : nil,
                        onIdentify: session.isAdministrator
                            ? { showsIdentify = true }
                            : nil,
                        onEditMetadata: session.isAdministrator
                            ? { showsEditMetadata = true }
                            : nil
                    )
                    if item.kind == .movie || item.kind == .episode {
                        Divider()
                        TitlePlaybackMenus(
                            item: item,
                            audioTracks: audioTracks,
                            subtitleTracks: subtitleTracks,
                            streamRevision: mediaStreamRevision,
                            onAddSubtitles: { subtitleSearchItem = item }
                        )
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
            DetailDownloadSharePill(item: item, seasons: seasons, episodes: episodes)
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

            playProgressRow(for: heroPlaybackItem(for: item))

            if let overview = item.overview, !overview.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    overviewBlock(overview)
                    TitleSpecsRow(item: item)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    TitleSpecsRow(item: item)
                    if moreInfo.hasDetails {
                        moreInfoButton
                    }
                }
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

                if let player = theme.videoPlayer {
                    ThemeVideoView(player: player) { theme.videoIsReady = true }
                        .frame(width: width, height: height)
                        .clipped()
                        .opacity(theme.videoIsReady ? 1 : 0)
                        .animation(.easeInOut(duration: 0.6), value: theme.videoIsReady)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

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

    /// What Play starts: the next episode for a show, the next unwatched title for a collection.
    private func heroPlaybackItem(for item: MediaItem) -> MediaItem {
        guard item.kind == .collection else {
            return MediaItem.heroPlaybackItem(title: item, episodes: episodes)
        }
        let playable = collectionMembers.filter { [.movie, .episode, .unknown].contains($0.kind) }
        return MediaItem.preferredEpisode(in: playable) ?? item
    }

    private func detailMetadataLine(for item: MediaItem) -> String {
        if item.kind == .collection {
            return CollectionMemberGroup.metadataLine(for: item, members: collectionMembers)
        }
        var parts = [item.kindLabel]
        parts.append(contentsOf: Array(item.genres.prefix(2)))
        return parts.joined(separator: " · ")
    }

    private func playProgressRow(for playbackItem: MediaItem) -> some View {
        let title = item ?? playbackItem
        return VStack(spacing: 10) {
            if title.kind == .book || playbackItem.kind == .collection {
                EmptyView()
            } else if title.kind == .photo {
                Button {
                    viewingPhoto = title
                } label: {
                    Label("View", systemImage: "photo")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(width: 175, height: 45)
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                playProgressButton(for: playbackItem, allowRelatedDownload: true)
            }
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

                CapsuleProgressBar(
                    progress: item.progress,
                    width: PlayButtonLayout.progressWidth,
                    height: PlayButtonLayout.progressHeight
                )

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

    private func overviewBlock(_ overview: String) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Text(overview)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.leading)
                .lineLimit(2)
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

                    moreInfoButton
                }
            }
        }
    }

    private var moreInfoButton: some View {
        Button {
            showsMoreInfo = true
        } label: {
            Text("MORE")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More information")
    }

    private func showsOverviewMore(_ overview: String) -> Bool {
        overview.count > 90 || moreInfo.hasDetails
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

            if !episodeStrip.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: DetailRowLayout.spacing) {
                        ForEach(episodeStrip) { card in
                            ZStack(alignment: .bottomTrailing) {
                                Button {
                                    play(card.episode)
                                } label: {
                                    EpisodeShowcaseCard(
                                        item: card.episode,
                                        imageURL: session.library?.primaryURL(for: card.episode, maxHeight: 480),
                                        showsOverflowIcon: false,
                                        width: wideCardWidth
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
                            .frame(width: episodeCardSize.width, height: episodeCardSize.height)
                            .accessibilityHidden(card.copy != EpisodeCarousel.homeCopy)
                        }
                    }
                    .scrollTargetLayout()
                }
                .frame(height: episodeCardSize.height)
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
                    if scrolledEpisodeID == nil {
                        syncCarouselPosition(forceSeasonStart: true)
                    }
                }
            }
        }
    }

    private var additionalPartsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Additional Parts", showsChevron: false)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DetailRowLayout.spacing) {
                    ForEach(additionalParts) { part in
                        Button {
                            play(part)
                        } label: {
                            TrailerLandscapeCard(
                                title: part.name,
                                caption: "Part",
                                imageURL: session.library?.artworkURL(for: part, style: .replayLandscape)
                                    ?? session.library?.backdropURL(for: part),
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
                LazyHStack(spacing: DetailRowLayout.spacing) {
                    ForEach(trailers) { trailer in
                        Button {
                            playTrailer(trailer)
                        } label: {
                            TrailerLandscapeCard(
                                title: trailer.title,
                                caption: trailer.caption,
                                imageURL: thumbnailURL(for: trailer, title: item),
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

    private func extrasSection(for item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Extras", showsChevron: false)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DetailRowLayout.spacing) {
                    ForEach(extras) { extra in
                        Button {
                            play(extra.item)
                        } label: {
                            TrailerLandscapeCard(
                                title: extra.title,
                                caption: extra.caption,
                                imageURL: session.library?.artworkURL(for: extra.item, style: .replayLandscape)
                                    ?? session.library?.backdropURL(for: extra.item)
                                    ?? session.library?.backdropURL(for: item),
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
                LazyHStack(alignment: .top, spacing: DetailRowLayout.spacing) {
                    ForEach(credits) { person in
                        NavigationLink {
                            PersonDetailView(
                                personID: person.id,
                                name: person.name,
                                imageTag: person.imageTag,
                                imageURL: person.imageURL
                            )
                        } label: {
                            CastMemberCard(
                                person: person,
                                imageURL: person.imageURL ?? session.library?.personImageURL(id: person.id, tag: person.imageTag),
                                width: DetailRowLayout.cardWidth(fitting: 10, in: rowWidth)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    /// A collection's titles in release order, one row per kind. Each header opens the full grid
    /// with sorting and filters.
    private func collectionMemberSections(for collection: MediaItem) -> some View {
        ForEach(CollectionMemberGroup.groups(from: collectionMembers)) { group in
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink {
                    CatalogGridView(title: collection.browsingCardTitle, query: .parent(collection.id))
                } label: {
                    SectionHeader(title: group.title)
                }
                .buttonStyle(.plain)

                posterScroller(group.items)
            }
            .padding(.top, 4)
            .padding(.bottom, 20)
        }
    }

    private func collectionSection(_ membership: ItemCollectionMembership) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                LibraryItemRoute(item: membership.collection)
            } label: {
                SectionHeader(title: collections.count > 1 ? membership.collection.browsingCardTitle : "Collection")
            }
            .buttonStyle(.plain)

            posterScroller(membership.items)
        }
    }

    private func posterScroller(_ items: [MediaItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: DetailRowLayout.spacing) {
                ForEach(items) { item in
                    NavigationLink {
                        LibraryItemRoute(item: item)
                    } label: {
                        PortraitPoster(
                            item: item,
                            imageURL: session.library?.primaryURL(for: item),
                            size: rowPosterSize
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: rowPosterSize?.height ?? PosterMetrics.portraitSize.height * sidebarLayout.scale)
    }

    /// Five episode, trailer or extra cards across the Mac's visible width; nil keeps the phone sizes.
    private var wideCardWidth: CGFloat? {
        DetailRowLayout.cardWidth(fitting: 5, in: rowWidth)
    }

    private var rowWidth: CGFloat {
        pageWidth > 1 ? pageWidth : sidebarLayout.contentWidth
    }

    private var episodeCardSize: CGSize {
        wideCardWidth.map(PosterMetrics.episodeCardSize(width:))
            ?? PosterMetrics.episodeCardSize.scaled(by: sidebarLayout.scale)
    }

    private var landscapeCardHeight: CGFloat {
        wideCardWidth.map { ($0 * 9 / 16).rounded() } ?? PosterMetrics.landscapeSize.height * sidebarLayout.scale
    }

    /// Eight related posters across the Mac's visible width.
    private var rowPosterSize: CGSize? {
        DetailRowLayout.cardWidth(fitting: 8, in: rowWidth).map { CGSize(width: $0, height: ($0 * 1.5).rounded()) }
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

    private func loadStreamTracks(for item: MediaItem) async {
        let fetched = await session.library?.streamTracks(for: item.id)
        audioTracks = fetched?.audio ?? []
        subtitleTracks = fetched?.subtitles ?? []
    }

    private func load() async {
        guard session.library != nil else { return }
        if hasLoadedDetail { return }

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
        extras = snapshot.extras
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
            extras: extras,
            related: related,
            credits: credits,
            collections: collections,
            seasons: seasons,
            episodes: episodes,
            selectedSeasonID: selectedSeasonID
        )
    }

    /// A fresh title read drops person tags the cached copy already learned; keep those so
    /// the cast row never blanks between loads.
    private static func keepingCastPhotos(_ fresh: [CreditPerson], from cached: [CreditPerson]) -> [CreditPerson] {
        let known = Dictionary(
            cached.filter { !($0.imageTag ?? "").isEmpty }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard !known.isEmpty else { return fresh }
        return fresh.map { person in
            guard (person.imageTag ?? "").isEmpty, let hit = known[person.id] else { return person }
            return Self.person(person, withPhotoFrom: hit)
        }
    }

    /// A title lists a person without a Primary tag until Jellyfin has refreshed that person.
    /// Reading the person item is what makes Jellyfin fetch the portrait on demand, so this does
    /// what tapping each cast member used to do and fills the row in as each batch lands.
    private func fillCastPhotos(library: any LibraryServing, for titleID: String) async {
        let missing = credits.filter { ($0.imageTag ?? "").isEmpty && $0.imageURL == nil && !$0.id.isEmpty }
        guard !missing.isEmpty else { return }
        var found: [String: CreditPerson] = [:]
        let ids = missing.map(\.id)
        var start = 0
        while start < ids.count, itemID == titleID {
            let batch = ids[start ..< min(start + 6, ids.count)]
            start += batch.count
            var changed = false
            await withTaskGroup(of: CreditPerson?.self) { group in
                for id in batch {
                    group.addTask { await library.person(id: id) }
                }
                for await profile in group {
                    guard let profile, !(profile.imageTag ?? "").isEmpty else { continue }
                    found[profile.id] = profile
                    changed = true
                }
            }
            guard changed, itemID == titleID else { continue }
            credits = credits.map { person in
                guard (person.imageTag ?? "").isEmpty, let hit = found[person.id] else { return person }
                return Self.person(person, withPhotoFrom: hit)
            }
            persistSnapshot()
        }
    }

    private static func person(_ person: CreditPerson, withPhotoFrom profile: CreditPerson) -> CreditPerson {
        CreditPerson(
            id: person.id,
            name: person.name,
            roleLabel: person.roleLabel,
            imageTag: profile.imageTag,
            rank: person.rank,
            overview: person.overview ?? profile.overview,
            birthYear: person.birthYear ?? profile.birthYear,
            imageURL: person.imageURL
        )
    }

    /// Theme song and video, when the user turned them on in Settings → Playback and Jellyfin has them.
    private func loadTheme(library: any LibraryServing, for loaded: MediaItem) async {
        guard PlaybackPreferences.themeSongsEnabled || PlaybackPreferences.themeVideosEnabled else { return }
        let media = await library.themeMedia(for: loaded.id)
        guard !media.isEmpty, media != loadedTheme else { return }
        loadedTheme = media
        guard isOnScreen, !themeIsPaused else { return }
        theme.start(media)
    }

    private func refreshFromServer() async {
        guard let library = session.library else { return }
        do {
            let loaded = try await library.item(id: itemID)
            item = loaded
            moreInfo = await library.titleMoreInfo(for: loaded)
            isLoading = false

            if loaded.kind == .collection {
                Task { await loadTheme(library: library, for: loaded) }
                await loadCollection(library: library, collection: loaded)
                return
            }

            await loadStreamTracks(for: loaded)

            if loaded.isYouTube {
                await loadYouTubeDetail(library: library, loaded: loaded)
                persistSnapshot()
                return
            }

            Task { await loadTheme(library: library, for: loaded) }
            async let fetchedTrailers = library.trailers(for: loaded)
            async let fetchedExtras = library.specialFeatures(for: loaded.id)
            async let fetchedThemes = library.themeVideos(for: loaded.id)
            async let fetchedRelated = library.similarItems(for: loaded)
            async let fetchedCredits = library.credits(for: loaded)

            if loaded.kind == .series {
                async let fetchedSeasons = library.seasons(seriesID: loaded.id)
                async let fetchedEpisodes = library.episodes(seriesID: loaded.id)
                let loadedSeasons = MediaItem.orderedSeasons((try? await fetchedSeasons) ?? [])
                let loadedEpisodes = MediaItem.orderedShowEpisodes(
                    (try? await fetchedEpisodes) ?? [],
                    seasons: loadedSeasons
                )
                seasons = loadedSeasons
                if selectedSeasonID == nil || !loadedSeasons.contains(where: { $0.id == selectedSeasonID }) {
                    selectedSeasonID = loadedSeasons.first?.id
                }
                episodes = loadedEpisodes
                applyFocusedEpisode()
                syncCarouselPosition(forceSeasonStart: scrolledEpisodeID == nil)
                persistSnapshot()
                await fillSeriesMedia(library: library, title: loaded)
            } else {
                seasons = []
                episodes = []
                selectedSeasonID = nil
                scrolledEpisodeID = nil
            }

            related = await fetchedRelated
            credits = Self.keepingCastPhotos(await fetchedCredits, from: credits)
            persistSnapshot()
            Task { await fillCastPhotos(library: library, for: loaded.id) }

            trailers = await fetchedTrailers
            persistSnapshot()

            var extrasList = await fetchedExtras
            // With Theme Videos on they play as the backdrop, so they are not listed again here.
            let themes = PlaybackPreferences.themeVideosEnabled ? [] : await fetchedThemes
            if PlaybackPreferences.themeVideosEnabled {
                extrasList.removeAll { $0.caption == ItemMapper.themeVideoCaption }
            }
            let extraIDs = Set(extrasList.map(\.id))
            extrasList.append(contentsOf: themes.filter { !extraIDs.contains($0.id) })
            extras = extrasList
            persistSnapshot()

            additionalParts = await library.additionalParts(for: loaded.id)
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

    private func fillSeriesMedia(library: any LibraryServing, title: MediaItem) async {
        guard moreInfo.needsEpisodeMedia else { return }
        let hero = MediaItem.heroPlaybackItem(title: title, episodes: episodes)
        guard hero.kind == .episode, hero.id != title.id else { return }
        guard let episode = try? await library.item(id: hero.id) else { return }
        moreInfo = moreInfo.mergingMedia(from: episode)
    }

    private func refreshPlaybackProgress() async {
        guard let library = session.library else { return }
        guard let loaded = try? await library.item(id: itemID) else { return }
        item = loaded
        if loaded.kind == .collection {
            collectionMembers = await Self.members(of: loaded, library: library) ?? collectionMembers
        } else if loaded.isYouTube {
            await loadYouTubeVideos(library: library, loaded: loaded)
        } else if loaded.kind == .series {
            let fetched = (try? await library.episodes(seriesID: loaded.id)) ?? []
            episodes = MediaItem.orderedShowEpisodes(fetched, seasons: seasons)
        }
        persistSnapshot()
    }

    /// Jellyfin's BoxSet item gives the hero; its children, in release order, fill the rows.
    private func loadCollection(library: any LibraryServing, collection: MediaItem) async {
        collectionMembers = await Self.members(of: collection, library: library) ?? collectionMembers
        credits = Self.keepingCastPhotos(await library.credits(for: collection), from: credits)
        persistSnapshot()
    }

    private static func members(of collection: MediaItem, library: any LibraryServing) async -> [MediaItem]? {
        var query = CatalogBrowseQuery.default
        query.sort = .releaseDate
        return try? await library.items(parentID: collection.id, query: query, onPage: nil)
    }

    private func loadYouTubeDetail(library: any LibraryServing, loaded: MediaItem) async {
        let channelID = loaded.kind == .series ? loaded.id : loaded.seriesID
        if loaded.kind == .series {
            channel = loaded
        } else if let channelID {
            channel = try? await library.item(id: channelID)
        } else {
            channel = nil
        }
        await loadYouTubeVideos(library: library, loaded: loaded)
        seasons = []
        selectedSeasonID = nil
        scrolledEpisodeID = nil
        trailers = []
        extras = []
        related = []
        credits = []
        additionalParts = []
        collections = []
    }

    private func loadYouTubeVideos(library: any LibraryServing, loaded: MediaItem) async {
        let channelID = loaded.kind == .series ? loaded.id : loaded.seriesID
        guard let channelID else {
            episodes = []
            return
        }
        let fetched = (try? await library.episodes(seriesID: channelID)) ?? []
        episodes = MediaItem.orderedYouTubeVideos(fetched)
    }

    private func playYouTube(_ item: MediaItem) {
        if item.kind == .series {
            let resume = episodes.first(where: \.showsResumeProgress)
            playingItem = resume ?? episodes.first ?? item
            return
        }
        playingItem = item
    }

    private func refreshCollections() async {
        guard let library = session.library else { return }
        collections = await library.collections(containing: itemID)
        persistSnapshot()
    }

    private func refreshAfterSubtitleSave(savedItemID: String) async {
        guard SubtitleCatalogRefresh.shouldRefreshDetail(
            detailItemID: itemID,
            episodeIDs: episodes.map(\.id),
            savedItemID: savedItemID
        ) else { return }
        guard let library = session.library else { return }

        if savedItemID == itemID {
            if let loaded = try? await library.item(id: itemID) {
                item = loaded
            }
        } else if let index = episodes.firstIndex(where: { $0.id == savedItemID }) {
            if let loaded = try? await library.item(id: savedItemID) {
                episodes[index] = loaded
            }
        }
        mediaStreamRevision += 1
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
        if item.kind == .photo {
            viewingPhoto = item
            return
        }
        if session.playIfSyncPlay(item) { return }
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

    private func refreshMetadata() async {
        guard let item else { return }
        do {
            try await session.library?.refreshItemMetadata(itemID: item.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteFromLibrary() async {
        guard let item else { return }
        do {
            try await session.library?.deleteLibraryItem(itemID: item.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
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
                        PersonDetailView(
                            personID: person.id,
                            name: person.name,
                            imageTag: person.imageTag,
                            imageURL: person.imageURL
                        )
                    } label: {
                        HStack(spacing: 14) {
                            PosterImage(
                                url: person.imageURL ?? session.library?.personImageURL(id: person.id, tag: person.imageTag),
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

/// A collection's titles split into rows by kind, with the hero's summary line.
private struct CollectionMemberGroup: Identifiable {
    let title: String
    let items: [MediaItem]
    var id: String { title }

    static func groups(from members: [MediaItem]) -> [CollectionMemberGroup] {
        let movies = members.filter { $0.kind == .movie }
        let shows = members.filter { $0.kind == .series || $0.kind == .season }
        let episodes = members.filter { $0.kind == .episode }
        let other = members.filter { ![.movie, .series, .season, .episode].contains($0.kind) }
        return [
            CollectionMemberGroup(title: "Movies", items: movies),
            CollectionMemberGroup(title: "Shows", items: shows),
            CollectionMemberGroup(title: "Episodes", items: episodes),
            CollectionMemberGroup(title: other.count == members.count ? "Titles" : "More", items: other)
        ].filter { !$0.items.isEmpty }
    }

    /// "Collection · 3 Movies · 1985–1990"
    static func metadataLine(for collection: MediaItem, members: [MediaItem]) -> String {
        var parts = [collection.kindLabel]
        if !members.isEmpty {
            let allMovies = members.allSatisfy { $0.kind == .movie }
            let noun = allMovies ? (members.count == 1 ? "Movie" : "Movies") : (members.count == 1 ? "Title" : "Titles")
            parts.append("\(members.count) \(noun)")
        }
        let years = members.compactMap(\.year)
        if let first = years.min(), let last = years.max() {
            parts.append(first == last ? "\(first)" : "\(first)–\(last)")
        } else {
            parts.append(contentsOf: collection.genres.prefix(2))
        }
        return parts.joined(separator: " · ")
    }
}

/// Plays a title's Jellyfin theme video, looping and muted unless Theme Video Sound is on, or else its
/// theme song. As in Jellyfin, a theme video is preferred and the song does not play alongside it.
@MainActor
@Observable
final class ThemeMediaController {
    private(set) var videoPlayer: AVPlayer?
    var videoIsReady = false
    /// Whichever player is heard: the theme song, or the video when its sound is on.
    private var soundPlayer: AVPlayer?
    private var media: ThemeMedia?
    private var isSuspended = false
    private var fadeTask: Task<Void, Never>?
    private var loopObserver: NSObjectProtocol?

    func start(_ next: ThemeMedia) {
        stop()
        media = next
        isSuspended = false
        let videoURL = PlaybackPreferences.themeVideosEnabled ? next.videoURL : nil
        let songURL = videoURL == nil && PlaybackPreferences.themeSongsEnabled ? next.songURL : nil
        if songURL != nil || (videoURL != nil && PlaybackPreferences.themeVideoSoundEnabled) {
            PlaybackAudioSession.activateForThemeMedia()
        }
        if let url = songURL {
            let player = AVPlayer(playerItem: Self.item(for: url))
            player.volume = 0
            soundPlayer = player
            player.play()
            fade(player, to: 1, over: 1.2)
        }
        if let url = videoURL {
            let item = Self.item(for: url)
            let player = AVPlayer(playerItem: item)
            player.actionAtItemEnd = .none
            loopObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification,
                object: item,
                queue: .main
            ) { [weak player] _ in
                MainActor.assumeIsolated {
                    player?.seek(to: .zero)
                    player?.play()
                }
            }
            videoPlayer = player
            if PlaybackPreferences.themeVideoSoundEnabled {
                player.volume = 0
                soundPlayer = player
                player.play()
                fade(player, to: 1, over: 1.2)
            } else {
                player.isMuted = true
                player.play()
            }
        }
    }

    func suspend() {
        guard media != nil, !isSuspended else { return }
        isSuspended = true
        fadeTask?.cancel()
        soundPlayer?.pause()
        videoPlayer?.pause()
    }

    func resume() {
        guard media != nil, isSuspended else { return }
        isSuspended = false
        videoPlayer?.play()
        if let soundPlayer {
            PlaybackAudioSession.activateForThemeMedia()
            soundPlayer.play()
            fade(soundPlayer, to: 1, over: 0.6)
        }
    }

    /// Fades the sound out rather than cutting it when the page goes away.
    func stop() {
        fadeTask?.cancel()
        if let soundPlayer {
            let fading = soundPlayer
            Task { @MainActor in
                let steps = 8
                let start = fading.volume
                for step in 1...steps {
                    try? await Task.sleep(for: .milliseconds(40))
                    fading.volume = start * Float(steps - step) / Float(steps)
                }
                fading.pause()
            }
        }
        if videoPlayer !== soundPlayer {
            videoPlayer?.pause()
        }
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
        loopObserver = nil
        soundPlayer = nil
        videoPlayer = nil
        videoIsReady = false
        media = nil
    }

    private func fade(_ player: AVPlayer, to target: Float, over seconds: Double) {
        fadeTask?.cancel()
        fadeTask = Task { @MainActor in
            let steps = 20
            let start = player.volume
            for step in 1...steps {
                try? await Task.sleep(for: .milliseconds(Int(seconds * 1_000) / steps))
                if Task.isCancelled { return }
                player.volume = start + (target - start) * Float(step) / Float(steps)
            }
        }
    }

    private static func item(for url: URL) -> AVPlayerItem {
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": PlaybackHTTPHeaders.fields(for: url)])
        return AVPlayerItem(asset: asset)
    }
}

/// The theme video filling the hero. Reports once its first frame can show, so the backdrop
/// stays until then instead of flashing black.
private struct ThemeVideoView: UIViewRepresentable {
    let player: AVPlayer
    var onReady: () -> Void

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.isUserInteractionEnabled = false
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        view.onReady = onReady
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
        view.onReady = onReady
    }

    final class PlayerLayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var onReady: (() -> Void)?
        private var readiness: AnyCancellable?

        override init(frame: CGRect) {
            super.init(frame: frame)
            readiness = playerLayer.publisher(for: \.isReadyForDisplay)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] ready in
                    if ready { self?.onReady?() }
                }
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
