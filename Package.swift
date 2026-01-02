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
        .package(path: "../DoomLogs")
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
