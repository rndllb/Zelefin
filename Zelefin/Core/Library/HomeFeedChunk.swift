import Foundation

/// One Home row or catalog bundle, fetched in parallel so the screen can
/// paint as soon as the first chunk arrives.
enum HomeFeedChunk: Sendable {
    case continueWatching([MediaItem])
    case nextUp([MediaItem])
    case recentlyWatched([MediaItem])
    case featured([MediaItem])
    case collections(HomeSection?)
    case genres(HomeSection?)
    case libraryHome(libraries: [MediaLibrary], sections: [HomeSection])
    case recommendations([HomeSection])
    case upcoming([MediaItem])
}
