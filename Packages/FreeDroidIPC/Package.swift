// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FreeDroidIPC",
    platforms: [.macOS(.v15)],
    products: [.library(name: "FreeDroidIPC", targets: ["FreeDroidIPC"])],
    dependencies: [.package(path: "../FreeDroidDomain")],
    targets: [
        .target(
            name: "FreeDroidIPC",
            dependencies: ["FreeDroidDomain"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
