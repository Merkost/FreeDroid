// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Gallery",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Gallery", targets: ["Gallery"])
    ],
    dependencies: [
        .package(path: "../../FreeDroidDomain"),
        .package(path: "../../FreeDroidUI")
    ],
    targets: [
        .target(
            name: "Gallery",
            dependencies: ["FreeDroidDomain", "FreeDroidUI"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "GalleryTests",
            dependencies: ["Gallery"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
