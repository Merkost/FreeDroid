// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Transfer",
    platforms: [.macOS(.v15)],
    products: [.library(name: "Transfer", targets: ["Transfer"])],
    dependencies: [
        .package(path: "../../FreeDroidDomain"),
        .package(path: "../../FreeDroidUI")
    ],
    targets: [
        .target(
            name: "Transfer",
            dependencies: ["FreeDroidDomain", "FreeDroidUI"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "TransferTests",
            dependencies: ["Transfer"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
