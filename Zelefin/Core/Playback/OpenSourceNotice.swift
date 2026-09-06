import Foundation

struct OpenSourceWork: Identifiable, Hashable, Sendable {
    struct BundledLicense: Hashable, Sendable {
        let name: String
        let fileName: String
    }

    let name: String
    let sourceURL: String
    let fileName: String
    var bundledLicenses: [BundledLicense] = []

    var id: String { fileName }
}

enum OpenSourceNotice {
    static let works: [OpenSourceWork] = [
        OpenSourceWork(
            name: "AetherEngine",
            sourceURL: "https://github.com/superuser404notfound/AetherEngine",
            fileName: "AetherEngine"
        ),
        OpenSourceWork(
            name: "FFmpeg",
            sourceURL: "https://github.com/superuser404notfound/FFmpegBuild",
            fileName: "FFmpeg-LGPL-2.1",
            bundledLicenses: [
                .init(name: "dav1d", fileName: "dav1d-BSD-2-Clause"),
                .init(name: "libdovi", fileName: "libdovi-MIT"),
                .init(name: "libzvbi", fileName: "libzvbi-MIT"),
                .init(name: "zimg", fileName: "zimg-WTFPL")
            ]
        )
    ]

    static let summary = "Direct Play demuxes with FFmpeg (dynamically linked) and presents through AetherEngine. The FFmpeg build also contains dav1d, libdovi, libzvbi, and zimg; their licenses are in the FFmpeg notice."

    static func text(for work: OpenSourceWork) -> String {
        var sections = [licenseText(fileName: work.fileName, fallbackURL: work.sourceURL)]
        for bundled in work.bundledLicenses {
            sections.append(
                """

                ——— \(bundled.name) ———

                \(licenseText(fileName: bundled.fileName, fallbackURL: work.sourceURL))
                """
            )
        }
        return sections.joined(separator: "\n")
    }

    private static func licenseText(fileName: String, fallbackURL: String) -> String {
        let urls = [
            Bundle.main.url(forResource: fileName, withExtension: "txt", subdirectory: "Licenses"),
            Bundle.main.url(forResource: fileName, withExtension: "txt", subdirectory: "Resources/Licenses"),
            Bundle.main.url(forResource: fileName, withExtension: "txt")
        ]
        guard let url = urls.compactMap({ $0 }).first else {
            return "License text is missing. Source: \(fallbackURL)"
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            return "License text could not be read. Source: \(fallbackURL)"
        }
    }
}
