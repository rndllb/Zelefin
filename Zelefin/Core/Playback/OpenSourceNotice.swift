import Foundation

struct OpenSourceWork: Identifiable, Hashable, Sendable {
    let name: String
    let sourceURL: String
    let fileName: String

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
            fileName: "FFmpeg-LGPL-2.1"
        ),
        OpenSourceWork(
            name: "dav1d",
            sourceURL: "https://code.videolan.org/videolan/dav1d",
            fileName: "dav1d-BSD-2-Clause"
        ),
        OpenSourceWork(
            name: "libdovi",
            sourceURL: "https://github.com/quietvoid/dovi_tool",
            fileName: "libdovi-MIT"
        ),
        OpenSourceWork(
            name: "libzvbi",
            sourceURL: "https://github.com/superuser404notfound/FFmpegBuild",
            fileName: "libzvbi-MIT"
        ),
        OpenSourceWork(
            name: "zimg",
            sourceURL: "https://github.com/sekrit-twc/zimg",
            fileName: "zimg-WTFPL"
        )
    ]

    static let summary = "Zelefin Direct Play demuxes with FFmpeg, decodes with VideoToolbox, and presents on a sample-buffer layer. FFmpeg is dynamically linked. Each license includes a link to the source of the build Zelefin ships."

    static func text(for work: OpenSourceWork) -> String {
        let urls = [
            Bundle.main.url(forResource: work.fileName, withExtension: "txt", subdirectory: "Licenses"),
            Bundle.main.url(forResource: work.fileName, withExtension: "txt", subdirectory: "Resources/Licenses"),
            Bundle.main.url(forResource: work.fileName, withExtension: "txt")
        ]
        guard let url = urls.compactMap({ $0 }).first else {
            return "License text is missing. Source: \(work.sourceURL)"
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            return "License text could not be read. Source: \(work.sourceURL)"
        }
    }
}
