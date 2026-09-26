import Foundation

struct EpisodeCarouselCard: Identifiable, Hashable {
    struct ID: Hashable {
        var copy: Int
        var episodeID: String
    }

    let copy: Int
    let seasonID: String
    let episode: MediaItem

    var id: ID { ID(copy: copy, episodeID: episode.id) }
}

enum EpisodeCarousel {
    static let loopCopies = 3
    static let homeCopy = 1

    static func cards(seasons: [MediaItem], episodes: [MediaItem]) -> [EpisodeCarouselCard] {
        let ordered = MediaItem.orderedShowEpisodes(episodes, seasons: seasons)
        guard !ordered.isEmpty else { return [] }

        let base: [(seasonID: String, episode: MediaItem)] = ordered.map { episode in
            let seasonID = seasons.first(where: { $0.resolvedSeasonNumber == episode.seasonIndex })?.id
                ?? seasons.first?.id
                ?? ""
            return (seasonID, episode)
        }

        return (0..<loopCopies).flatMap { copy in
            base.map { EpisodeCarouselCard(copy: copy, seasonID: $0.seasonID, episode: $0.episode) }
        }
    }

    static func homePosition(
        seasonID: String?,
        seasons: [MediaItem],
        episodes: [MediaItem]
    ) -> EpisodeCarouselCard.ID? {
        let ordered = MediaItem.orderedShowEpisodes(episodes, seasons: seasons)
        let episode: MediaItem?
        if let seasonID, let season = seasons.first(where: { $0.id == seasonID }) {
            episode = ordered.first(where: { $0.seasonIndex == season.resolvedSeasonNumber }) ?? ordered.first
        } else {
            episode = ordered.first
        }
        guard let episode else { return nil }
        return position(episodeID: episode.id)
    }

    static func position(episodeID: String) -> EpisodeCarouselCard.ID {
        EpisodeCarouselCard.ID(copy: homeCopy, episodeID: episodeID)
    }

    static func recentered(_ id: EpisodeCarouselCard.ID) -> EpisodeCarouselCard.ID? {
        guard id.copy != homeCopy else { return nil }
        return EpisodeCarouselCard.ID(copy: homeCopy, episodeID: id.episodeID)
    }

    static func seasonID(for episodeID: String, in cards: [EpisodeCarouselCard]) -> String? {
        cards.first(where: { $0.episode.id == episodeID })?.seasonID
    }
}
