import SwiftUI

struct ItemDetailView: View {
    @Environment(SessionStore.self) private var session
    let itemID: String

    @State private var item: MediaItem?
    @State private var overview: String?
    @State private var seasons: [MediaItem] = []
    @State private var episodes: [MediaItem] = []
    @State private var selectedSeasonID: String?
    @State private var isLoading = true
    @State private var playbackPlan: PlaybackPlan?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView().tint(.white)
            } else if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        backdrop(for: item)

                        VStack(alignment: .leading, spacing: 12) {
                            TitleLogo(
                                item: item,
                                maxHeight: 72,
                                fallbackFont: .largeTitle.bold(),
                                alignment: .leading
                            )

                            metadata(for: item)

                            playButton(for: item)

                            if let overview, !overview.isEmpty {
                                Text(overview)
                                    .font(.body)
                                    .foregroundStyle(.white.opacity(0.78))
                            }

                            if !seasons.isEmpty {
                                seasonPicker
                            }

                            if !episodes.isEmpty {
                                episodeList
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 40)
                    }
                }
            } else {
                ContentUnavailableView("Title Unavailable", systemImage: "film")
            }
        }
        .background(Color.black.ignoresSafeArea())
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .fullScreenCover(item: $playbackPlan) { plan in
            PlayerView(plan: plan)
        }
        .alert("Playback", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func backdrop(for item: MediaItem) -> some View {
        PosterImage(url: session.library?.backdropURL(for: item), aspectRatio: 16 / 9)
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 80)
            }
    }

    private func metadata(for item: MediaItem) -> some View {
        HStack(spacing: 10) {
            if let year = item.year {
                Text(String(year))
            }
            if item.videoRange != .sdr {
                Text(item.videoRange.displayName)
            }
            if item.audioFormat == .atmos || item.audioFormat == .surround {
                Text(item.audioFormat.displayName)
            }
            if let rating = item.officialRating, !rating.isEmpty {
                RatingBadge(rating: rating)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.7))
    }

    private func playButton(for item: MediaItem) -> some View {
        Button {
            Task { await play(item) }
        } label: {
            Label(item.playbackPosition > 5 ? "Resume" : "Play", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: 280)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(.white)
        .foregroundStyle(.black)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var seasonPicker: some View {
        Picker("Season", selection: $selectedSeasonID) {
            ForEach(seasons) { season in
                Text(season.name).tag(Optional(season.id))
            }
        }
        #if os(iOS)
        .pickerStyle(.menu)
        #endif
        .onChange(of: selectedSeasonID) { _, newValue in
            guard let newValue, let seriesID = item?.id else { return }
            Task { await loadEpisodes(seriesID: seriesID, seasonID: newValue) }
        }
    }

    private var episodeList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Episodes")
                .font(.title3.weight(.semibold))
            ForEach(episodes) { episode in
                Button {
                    Task { await play(episode) }
                } label: {
                    HStack(spacing: 12) {
                        PosterImage(
                            url: session.library?.artworkURL(for: episode, style: .landscape),
                            aspectRatio: 16 / 9
                        )
                        .frame(width: 140, height: 80)
                        .posterCard(cornerRadius: 8)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(episode.name)
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            if let label = episode.episodeLabel {
                                Text(label)
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        guard let library = session.library else { return }
        do {
            let (loaded, dto) = try await library.item(id: itemID)
            item = loaded
            overview = dto.overview
            if loaded.kind == .series {
                seasons = try await library.seasons(seriesID: loaded.id)
                selectedSeasonID = seasons.first?.id
                if let seasonID = selectedSeasonID {
                    episodes = try await library.episodes(seriesID: loaded.id, seasonID: seasonID)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadEpisodes(seriesID: String, seasonID: String) async {
        episodes = (try? await session.library?.episodes(seriesID: seriesID, seasonID: seasonID)) ?? []
    }

    private func play(_ item: MediaItem) async {
        guard let library = session.library else { return }
        do {
            playbackPlan = try await library.playbackPlan(for: item)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension PlaybackPlan: Identifiable {
    var id: String { item.id }
}
