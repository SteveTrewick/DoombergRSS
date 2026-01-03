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
        .package(url: "https://github.com/SteveTrewick/DoomModels.git", from: "0.1.0"),
        .package(url: "https://github.com/SteveTrewick/DoomLogs.git", from: "0.1.1")
    ],
    targets: [
        .target(
            name: "DoombergRSS",
            dependencies: [
                .product(name: "DoomModels", package: "DoomModels"),
                .product(name: "DoomLogs", package: "DoomLogs")
            ]
        ),
        .testTarget(
            name: "DoombergRSSTests",
            dependencies: [
                "DoombergRSS",
                .product(name: "DoomModels", package: "DoomModels")
            ],
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
