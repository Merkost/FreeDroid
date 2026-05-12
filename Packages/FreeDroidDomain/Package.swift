// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FreeDroidDomain",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FreeDroidDomain", targets: ["FreeDroidDomain"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.4")
    ],
    targets: [
        .target(
            name: "FreeDroidDomain",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "FreeDroidDomainTests",
            dependencies: ["FreeDroidDomain"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
