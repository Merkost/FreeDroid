// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DeviceManagement",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DeviceManagement", targets: ["DeviceManagement"])
    ],
    dependencies: [
        .package(path: "../../FreeDroidDomain"),
        .package(path: "../../FreeDroidUI")
    ],
    targets: [
        .target(
            name: "DeviceManagement",
            dependencies: ["FreeDroidDomain", "FreeDroidUI"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "DeviceManagementTests",
            dependencies: ["DeviceManagement", "FreeDroidDomain", "FreeDroidUI"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
