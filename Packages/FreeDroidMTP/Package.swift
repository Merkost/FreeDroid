// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FreeDroidMTP",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FreeDroidMTP", targets: ["FreeDroidMTP"])
    ],
    dependencies: [
        .package(path: "../FreeDroidDomain")
    ],
    targets: [
        .binaryTarget(
            name: "libmtp",
            path: "../../Vendor/libmtp.xcframework"
        ),
        .target(
            name: "CLibmtp",
            dependencies: ["libmtp"],
            path: "Sources/CLibmtp",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("../../Vendor/libmtp.xcframework/macos-arm64_x86_64/Headers")
            ],
            linkerSettings: [
                .linkedLibrary("mtp")
            ]
        ),
        .target(
            name: "FreeDroidMTP",
            dependencies: [
                "FreeDroidDomain",
                "CLibmtp"
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "FreeDroidMTPTests",
            dependencies: ["FreeDroidMTP"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
