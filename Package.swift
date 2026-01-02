// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DoombergRSS",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "DoombergRSS",
            targets: ["DoombergRSS"]
        )
    ],
    targets: [
        .target(
            name: "DoombergRSS"
        ),
        .testTarget(
            name: "DoombergRSSTests",
            dependencies: ["DoombergRSS"],
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
