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
    dependencies: [
        .package(url: "https://github.com/SteveTrewick/DoomLogs.git", from: "0.1.1")
    ],
    targets: [
        .target(
            name: "DoombergRSS",
            dependencies: [
                .product(name: "DoomLogs", package: "DoomLogs")
            ]
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
