// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FreeDroidUI",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FreeDroidUI", targets: ["FreeDroidUI"])
    ],
    targets: [
        .target(
            name: "FreeDroidUI",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
