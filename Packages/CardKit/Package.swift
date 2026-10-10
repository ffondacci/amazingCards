// swift-tools-version: 6.2

import PackageDescription

/// Settings shared by every target: Swift 6 strict concurrency plus the
/// "approachable concurrency" upcoming features.
let strictSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "CardKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        // Umbrella product: everything.
        .library(name: "CardKit", targets: ["CardCore", "CardFX", "CardUI", "CardPack"]),
        // Granular products for apps that only need a subset.
        .library(name: "CardCore", targets: ["CardCore"]),
        .library(name: "CardFX", targets: ["CardFX"]),
        .library(name: "CardUI", targets: ["CardUI"]),
        .library(name: "CardPack", targets: ["CardPack"]),
    ],
    targets: [
        .target(
            name: "CardCore",
            swiftSettings: strictSettings
        ),
        .target(
            name: "CardFX",
            dependencies: ["CardCore"],
            resources: [.process("Shaders")],
            swiftSettings: strictSettings
        ),
        .target(
            name: "CardUI",
            dependencies: ["CardCore", "CardFX"],
            swiftSettings: strictSettings
        ),
        .target(
            name: "CardPack",
            dependencies: ["CardCore", "CardFX", "CardUI"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "CardCoreTests",
            dependencies: ["CardCore"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "CardFXTests",
            dependencies: ["CardFX"],
            swiftSettings: strictSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
