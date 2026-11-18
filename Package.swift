// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BitwardenQuickAccess",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .target(name: "QuickAccessCore"),
        .executableTarget(
            name: "BitwardenQuickAccess",
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
            name: "BitwardenQuickAccessTests",
            dependencies: ["BitwardenQuickAccess", "QuickAccessCore", "QuickAccessTestSupport"]
        ),
    ]
)
