// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FreeDroidUI",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FreeDroidUI", targets: ["FreeDroidUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0")
    ],
    targets: [
        .target(
            name: "FreeDroidUI",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "FreeDroidUITests",
            dependencies: [
                "FreeDroidUI",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
