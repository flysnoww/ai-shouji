// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIQuickNote",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "QuickNoteCore", targets: ["QuickNoteCore"])],
    targets: [
        .target(name: "QuickNoteCore", path: "QuickNoteCore"),
        .testTarget(name: "QuickNoteCoreTests", dependencies: ["QuickNoteCore"], path: "QuickNoteCoreTests")
    ]
)
