// swift-tools-version: 6.0
import PackageDescription

let strictConcurrency: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("StrictConcurrency")
]

let package = Package(
    name: "FreeDroidPackages",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FreeDroidDomain", targets: ["FreeDroidDomain"]),
        .library(name: "FreeDroidUI", targets: ["FreeDroidUI"]),
        .library(name: "FreeDroidADB", targets: ["FreeDroidADB"]),
        .library(name: "FreeDroidMTP", targets: ["FreeDroidMTP"]),
        .library(name: "FreeDroidData", targets: ["FreeDroidData"]),
        .library(name: "FreeDroidIPC", targets: ["FreeDroidIPC"]),
        .library(name: "DeviceManagement", targets: ["DeviceManagement"]),
        .library(name: "FileBrowser", targets: ["FileBrowser"]),
        .library(name: "Gallery", targets: ["Gallery"]),
        .library(name: "Transfer", targets: ["Transfer"]),
        .library(name: "FreeDroidProviderShared", targets: ["FreeDroidProviderShared"]),
        .library(name: "FreeDroidContentCache", targets: ["FreeDroidContentCache"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.4"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.4.0")
    ],
    targets: [
        .target(
            name: "FreeDroidDomain",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
            ],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "FreeDroidDomainTests",
            dependencies: ["FreeDroidDomain"],
            swiftSettings: strictConcurrency
        ),

        .target(
            name: "FreeDroidUI",
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "FreeDroidUITests",
            dependencies: [
                "FreeDroidUI",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            swiftSettings: strictConcurrency
        ),

        .target(
            name: "FreeDroidADB",
            dependencies: [
                "FreeDroidDomain",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
            ],
            resources: [.copy("adb")],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "FreeDroidADBTests",
            dependencies: ["FreeDroidADB"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "FreeDroidADBWireTests",
            dependencies: ["FreeDroidADB"],
            swiftSettings: strictConcurrency
        ),

        .binaryTarget(
            name: "libmtp",
            path: "Vendor/libmtp.xcframework"
        ),
        .binaryTarget(
            name: "libusb",
            path: "Vendor/libusb.xcframework"
        ),
        .target(
            name: "CLibmtp",
            dependencies: ["libmtp", "libusb"],
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("."),
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
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "FreeDroidMTPTests",
            dependencies: ["FreeDroidMTP"],
            swiftSettings: strictConcurrency
        ),

        .target(
            name: "FreeDroidData",
            dependencies: [
                "FreeDroidDomain",
                "FreeDroidADB",
                "FreeDroidMTP",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "Dependencies", package: "swift-dependencies")
            ],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "FreeDroidDataTests",
            dependencies: ["FreeDroidData"],
            swiftSettings: strictConcurrency
        ),

        .target(
            name: "FreeDroidIPC",
            dependencies: ["FreeDroidDomain"],
            swiftSettings: strictConcurrency
        ),

        .target(
            name: "FreeDroidProviderShared",
            dependencies: ["FreeDroidDomain", "FreeDroidIPC"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "FreeDroidProviderSharedTests",
            dependencies: ["FreeDroidProviderShared"],
            swiftSettings: strictConcurrency
        ),

        .target(
            name: "FreeDroidContentCache",
            dependencies: ["FreeDroidDomain"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "FreeDroidContentCacheTests",
            dependencies: ["FreeDroidContentCache"],
            swiftSettings: strictConcurrency
        ),

        .target(
            name: "DeviceManagement",
            dependencies: ["FreeDroidDomain", "FreeDroidUI"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "DeviceManagementTests",
            dependencies: ["DeviceManagement"],
            swiftSettings: strictConcurrency
        ),

        .target(
            name: "FileBrowser",
            dependencies: ["FreeDroidDomain", "FreeDroidUI"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "FileBrowserTests",
            dependencies: ["FileBrowser"],
            swiftSettings: strictConcurrency
        ),

        .target(
            name: "Gallery",
            dependencies: ["FreeDroidDomain", "FreeDroidUI"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "GalleryTests",
            dependencies: ["Gallery"],
            swiftSettings: strictConcurrency
        ),

        .target(
            name: "Transfer",
            dependencies: ["FreeDroidDomain", "FreeDroidUI"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "TransferTests",
            dependencies: ["Transfer"],
            swiftSettings: strictConcurrency
        )
    ]
)
