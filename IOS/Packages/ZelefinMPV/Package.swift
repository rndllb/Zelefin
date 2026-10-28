// swift-tools-version:6.0
import PackageDescription

// libmpv for the iOS and Mac Catalyst player. The xcframework is built by IOS/scripts/build-mpv.sh and is not in git.
let package = Package(
    name: "ZelefinMPV",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "ZelefinMPV", targets: ["ZelefinMPV"])
    ],
    targets: [
        .binaryTarget(name: "ZelefinMPV", path: "ZelefinMPV.xcframework")
    ]
)
