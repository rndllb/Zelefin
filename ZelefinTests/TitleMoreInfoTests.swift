import JellyfinAPI
import XCTest
@testable import Zelefin

final class TitleMoreInfoTests: XCTestCase {
    func testMapsStudioRatingAndOrigin() {
        let item = movie(name: "Batman Begins", year: 2005, runtime: 8_400, rating: "PG-13")
        let dto = BaseItemDto(
            officialRating: "PG-13",
            productionLocations: ["United States", "United Kingdom"],
            productionYear: 2005,
            runTimeTicks: TickClock.intTicks(from: 8_400),
            studios: [NameGuidPair(name: "Warner Bros.")],
            tags: ["Violence", "Language"]
        )

        let info = TitleMoreInfoMapper.info(from: dto, item: item)
        XCTAssertEqual(info.information.first { $0.label == "Studio" }?.value, "Warner Bros.")
        XCTAssertEqual(info.information.first { $0.label == "Released" }?.value, "2005")
        XCTAssertEqual(info.information.first { $0.label == "Run Time" }?.value, "2h 20m")
        XCTAssertEqual(info.information.first { $0.label == "Rated" }?.value, "PG-13")
        XCTAssertEqual(info.information.first { $0.label == "Content Advisories" }?.value, "Violence, Language")
        XCTAssertEqual(
            info.information.first { $0.label == "Regions of Origin" }?.value,
            "United States, United Kingdom"
        )
    }

    func testGroupsAudioByLanguageAndFormat() {
        let streams = [
            MediaStream(
                audioSpatialFormat: .dolbyAtmos,
                channelLayout: "5.1",
                codec: "truehd",
                language: "eng",
                type: .audio
            ),
            MediaStream(codec: "aac", language: "eng", type: .audio),
            MediaStream(
                codec: "aac",
                comment: "Audio Description",
                language: "eng",
                title: "English AD",
                type: .audio
            ),
            MediaStream(codec: "aac", language: "fra", type: .audio),
        ]

        let dto = BaseItemDto(mediaStreams: streams)
        let info = TitleMoreInfoMapper.info(from: dto, item: movie())
        let english = TitleMoreInfoMapper.languageName(from: "eng")
        let french = TitleMoreInfoMapper.languageName(from: "fra")
        XCTAssertEqual(
            info.languages.first { $0.label == "Original Audio" }?.value,
            "\(english), \(french)"
        )
        let audio = info.languages.first { $0.label == "Audio" }?.value
        XCTAssertEqual(
            audio,
            "\(english) (Dolby Atmos, AAC, AD), \(french) (AAC)"
        )
    }

    func testSubtitleMarksClosedCaptions() {
        let streams = [
            MediaStream(isHearingImpaired: true, language: "eng", type: .subtitle),
            MediaStream(language: "jpn", type: .subtitle),
            MediaStream(isForced: true, language: "eng", type: .subtitle),
        ]
        let dto = BaseItemDto(mediaStreams: streams)
        let info = TitleMoreInfoMapper.info(from: dto, item: movie())
        let english = TitleMoreInfoMapper.languageName(from: "eng")
        let japanese = TitleMoreInfoMapper.languageName(from: "jpn")
        XCTAssertEqual(
            info.languages.first { $0.label == "Subtitles" }?.value,
            "\(english) (CC), \(japanese), \(english) (Forced)"
        )
        XCTAssertNotNil(info.accessibilityNote)
    }

    func testFileVersionIncludesContainerSizeAndVideo() {
        let video = MediaStream(
            codec: "hevc",
            height: 2160,
            type: .video,
            videoRangeType: .dovi,
            width: 3840
        )
        let source = MediaSourceInfo(
            bitrate: 45_000_000,
            container: "mkv",
            mediaStreams: [video],
            size: 16_540_000_000
        )
        let dto = BaseItemDto(mediaSources: [source])
        let info = TitleMoreInfoMapper.info(from: dto, item: movie())
        let file = info.file.first { $0.label == "File" }?.value
        XCTAssertTrue(file?.contains("4K") == true)
        XCTAssertTrue(file?.contains("MKV") == true)
        XCTAssertTrue(file?.contains("GB") == true)
        XCTAssertEqual(info.file.first { $0.label == "Video" }?.value, "3840×2160 · HEVC · Dolby Vision")
        XCTAssertEqual(info.file.first { $0.label == "Bitrate" }?.value, "45 Mbps")
    }

    func testSeriesWithoutStreamsNeedsEpisodeMedia() {
        let show = movie(name: "Silo", year: 2023, runtime: 0, rating: "TV-MA")
        let dto = BaseItemDto(studios: [NameGuidPair(name: "Apple")], type: .series)
        let info = TitleMoreInfoMapper.info(from: dto, item: show)
        XCTAssertTrue(info.needsEpisodeMedia)
        XCTAssertEqual(info.information.first { $0.label == "Studio" }?.value, "Apple")

        let episode = BaseItemDto(
            mediaSources: [
                MediaSourceInfo(container: "mkv", size: 4_000_000_000)
            ]
        )
        let merged = info.mergingMedia(from: episode)
        XCTAssertFalse(merged.needsEpisodeMedia)
        XCTAssertEqual(merged.information.first { $0.label == "Studio" }?.value, "Apple")
        XCTAssertTrue(merged.file.first { $0.label == "File" }?.value.contains("MKV") == true)
    }

    func testAudioCodecNames() {
        XCTAssertEqual(
            TitleMoreInfoMapper.audioFormatName(
                codec: "ac3",
                channelLayout: "5.1",
                spatial: nil,
                isAudioDescription: false
            ),
            "Dolby Digital 5.1"
        )
        XCTAssertEqual(
            TitleMoreInfoMapper.audioFormatName(
                codec: "truehd",
                channelLayout: "7.1",
                spatial: .dolbyAtmos,
                isAudioDescription: false
            ),
            "Dolby Atmos"
        )
        XCTAssertEqual(TitleMoreInfoMapper.bitrateLabel(1_500_000), "1.5 Mbps")
        XCTAssertEqual(TitleMoreInfoMapper.containerLabel("mkv,webm"), "MKV")
    }

    private func movie(
        name: String = "Batman Begins",
        year: Int = 2005,
        runtime: TimeInterval = 8_400,
        rating: String = "PG-13"
    ) -> MediaItem {
        MediaItem(
            id: "1",
            name: name,
            kind: .movie,
            overview: "As a young boy, Bruce Wayne watched in horror.",
            year: year,
            runtime: runtime,
            officialRating: rating,
            genres: ["Action"],
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
            videoRange: .dolbyVision,
            audioFormat: .atmos
        )
    }
}
