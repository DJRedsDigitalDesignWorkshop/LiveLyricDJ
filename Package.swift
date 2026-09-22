// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SeratoLyrics",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SeratoLyrics",
            path: "Sources/SeratoLyrics"
        )
    ]
)