// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FreeDroidData",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FreeDroidData", targets: ["FreeDroidData"])
    ],
    dependencies: [
        .package(path: "../FreeDroidDomain"),
        .package(path: "../FreeDroidADB"),
        .package(path: "../FreeDroidMTP"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.4"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.4.0")
    ],
    targets: [
        .target(
            name: "FreeDroidData",
            dependencies: [
                "FreeDroidDomain",
                "FreeDroidADB",
                "FreeDroidMTP",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "Dependencies", package: "swift-dependencies")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "FreeDroidDataTests",
            dependencies: ["FreeDroidData"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
