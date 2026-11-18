// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuickAccessForBitwarden",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .target(name: "QuickAccessCore"),
        .executableTarget(
            name: "QuickAccessForBitwarden",
            dependencies: ["QuickAccessCore"]
        ),
        // Test vectors and builders shared by both test targets.
        .target(
            name: "QuickAccessTestSupport",
            dependencies: ["QuickAccessCore"],
            path: "Tests/TestSupport"
        ),
        .testTarget(
            name: "QuickAccessCoreTests",
            dependencies: ["QuickAccessCore", "QuickAccessTestSupport"]
        ),
        .testTarget(
            name: "QuickAccessForBitwardenTests",
            dependencies: ["QuickAccessForBitwarden", "QuickAccessCore", "QuickAccessTestSupport"]
        ),
    ]
)
