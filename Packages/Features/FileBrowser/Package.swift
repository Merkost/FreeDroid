// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FileBrowser",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FileBrowser", targets: ["FileBrowser"])
    ],
    dependencies: [
        .package(path: "../../FreeDroidDomain"),
        .package(path: "../../FreeDroidUI")
    ],
    targets: [
        .target(
            name: "FileBrowser",
            dependencies: ["FreeDroidDomain", "FreeDroidUI"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "FileBrowserTests",
            dependencies: ["FileBrowser"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
