// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LiveLyricDJ",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "LiveLyricDJ",
            path: "Sources/LiveLyricDJ"
        ),
        .testTarget(
            name: "LiveLyricDJTests",
            dependencies: ["LiveLyricDJ"],
            path: "Tests/LiveLyricDJTests"
        )
    ]
)
