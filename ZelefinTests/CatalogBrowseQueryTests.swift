import XCTest
@testable import Zelefin
import JellyfinAPI

final class CatalogBrowseQueryTests: XCTestCase {
    func testDefaultQueryHasNoFiltersAndSortsByNameAscending() {
        let query = CatalogBrowseQuery.default
        XCTAssertTrue(query.isDefault)
        XCTAssertEqual(query.activeFilterCount, 0)
        XCTAssertEqual(query.sort, .name)
        XCTAssertTrue(query.sortAscending)
        XCTAssertEqual(query.itemFilters, [])
        XCTAssertEqual(query.videoTypes, [])
        XCTAssertNil(query.is3D)
        XCTAssertEqual(query.resolutionPasses.count, 1)
        XCTAssertNil(query.resolutionPasses[0].isHd)
        XCTAssertNil(query.resolutionPasses[0].is4K)
    }

    func testPlayedAndUnplayedTogetherDoNotFilterStatus() {
        var query = CatalogBrowseQuery.default
        query.statuses = [.played, .unplayed, .favorite]
        XCTAssertEqual(query.itemFilters, [.isFavorite])
        XCTAssertFalse(query.isDefault)
        XCTAssertEqual(query.activeFilterCount, 3)
    }

    func testContinueWatchingUsesResumableFilter() {
        var query = CatalogBrowseQuery.default
        query.statuses = [.continueWatching]
        XCTAssertEqual(query.itemFilters, [.isResumable])
    }

    func testVideoKindsMapToJellyfinFlags() {
        var query = CatalogBrowseQuery.default
        query.videoKinds = [.dvd, .bluRay, .iso, .threeD]
        XCTAssertEqual(Set(query.videoTypes), [.dvd, .bluRay, .iso])
        XCTAssertEqual(query.is3D, true)

        query.videoKinds = [.sd]
        XCTAssertEqual(query.resolutionPasses.count, 1)
        XCTAssertEqual(query.resolutionPasses[0].isHd, false)

        query.videoKinds = [.fourK]
        XCTAssertEqual(query.resolutionPasses[0].is4K, true)

        query.videoKinds = [.hd, .fourK]
        XCTAssertEqual(query.resolutionPasses[0].isHd, true)
        XCTAssertNil(query.resolutionPasses[0].is4K)

        query.videoKinds = [.sd, .hd]
        XCTAssertEqual(query.resolutionPasses.count, 1)
        XCTAssertNil(query.resolutionPasses[0].isHd)

        query.videoKinds = [.sd, .fourK]
        XCTAssertEqual(query.resolutionPasses.count, 2)
    }

    func testApplySetsFeatureAndSortParameters() {
        var query = CatalogBrowseQuery.default
        query.features = [.subtitles, .extras, .themeSongs]
        query.sort = .runtime
        query.sortAscending = false
        query.genres = ["Action"]
        query.years = [2024]
        var parameters = Paths.GetItemsParameters()
        query.apply(to: &parameters, isHd: true, is4K: nil)
        XCTAssertEqual(parameters.hasSubtitles, true)
        XCTAssertEqual(parameters.hasSpecialFeature, true)
        XCTAssertEqual(parameters.hasThemeSong, true)
        XCTAssertNil(parameters.hasTrailer)
        XCTAssertEqual(parameters.isHd, true)
        XCTAssertEqual(parameters.sortBy, [.runtime])
        XCTAssertEqual(parameters.sortOrder, [.descending])
        XCTAssertEqual(parameters.genres, ["Action"])
        XCTAssertEqual(parameters.years, [2024])
    }

    func testRandomSortOmitsDirection() {
        var query = CatalogBrowseQuery.default
        query.sort = .random
        var parameters = Paths.GetItemsParameters()
        query.apply(to: &parameters, isHd: nil, is4K: nil)
        XCTAssertEqual(parameters.sortBy, [.random])
        XCTAssertNil(parameters.sortOrder)
        XCTAssertFalse(CatalogSortField.random.allowsDirection)
    }

    func testClearFiltersKeepsSort() {
        var query = CatalogBrowseQuery.default
        query.statuses = [.played]
        query.sort = .dateAdded
        query.sortAscending = false
        query.clearFilters()
        XCTAssertTrue(query.statuses.isEmpty)
        XCTAssertEqual(query.sort, .dateAdded)
        XCTAssertFalse(query.sortAscending)
        XCTAssertFalse(query.isDefault)
    }

    func testLanguageChoicesPreferThreeLetterCodesAndSkipDuplicates() {
        let choices = CatalogFilterLists.languageChoices(from: [
            CultureDto(displayName: "English", threeLetterISOLanguageName: "eng", twoLetterISOLanguageName: "en"),
            CultureDto(displayName: "English (US)", threeLetterISOLanguageName: "eng", twoLetterISOLanguageName: "en"),
            CultureDto(displayName: "Spanish", threeLetterISOLanguageName: "spa", twoLetterISOLanguageName: "es")
        ])
        XCTAssertEqual(choices.map(\.id), ["eng", "spa"])
        XCTAssertEqual(choices.map(\.name), ["English", "Spanish"])
    }

    func testClientSortOrdersByRuntime() {
        var query = CatalogBrowseQuery.default
        query.sort = .runtime
        query.sortAscending = true
        let short = item(id: "a", runtime: 60)
        let long = item(id: "b", runtime: 180)
        XCTAssertEqual(query.sorted([long, short]).map(\.id), ["a", "b"])
        query.sortAscending = false
        XCTAssertEqual(query.sorted([short, long]).map(\.id), ["b", "a"])
    }

    private func item(id: String, runtime: TimeInterval) -> MediaItem {
        MediaItem(
            id: id,
            name: id,
            kind: .movie,
            overview: nil,
            year: 2024,
            runtime: runtime,
            officialRating: nil,
            genres: [],
            seriesName: nil,
            seasonIndex: nil,
            episodeIndex: nil,
            playbackPosition: 0,
            unplayedCount: nil,
            isPlayed: false,
            primaryImageTag: nil,
            thumbImageTag: nil,
            backdropImageTag: nil,
            backdropImageTags: [],
            logoImageTag: nil,
            parentBackdropItemID: nil,
            parentThumbItemID: nil,
            parentThumbImageTag: nil,
            parentLogoItemID: nil,
            parentLogoImageTag: nil,
            seriesThumbImageTag: nil,
            seriesID: nil,
            imageItemID: nil,
            queueKind: .resume,
            videoRange: .sdr,
            audioFormat: .stereo
        )
    }
}
