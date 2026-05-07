// swift-tools-version: 5.9
// This file exists ONLY so SourceKit / IDEs treat the launcher/ directory as a
// Swift module instead of a collection of standalone scripts. The actual
// production build is build_app.sh, which compiles directly via swiftc into a
// macOS .app bundle. Running `swift build` here will not produce a usable .app.
import PackageDescription

let package = Package(
    name: "CatWatchPR",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CatWatchPR",
            path: "launcher"
        )
    ]
)
