// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FreeDroidADB",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FreeDroidADB", targets: ["FreeDroidADB"])
    ],
    dependencies: [
        .package(path: "../FreeDroidDomain"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.4")
    ],
    targets: [
        .target(
            name: "FreeDroidADB",
            dependencies: [
                "FreeDroidDomain",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
            ],
            resources: [.copy("../../Resources/adb")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "FreeDroidADBTests",
            dependencies: ["FreeDroidADB"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
