// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BitwardenQuickAccess",
    platforms: [
        .macOS(.v15),
    ],
    targets: [
        .target(name: "QuickAccessCore"),
        .executableTarget(
            name: "BitwardenQuickAccess",
            dependencies: ["QuickAccessCore"]
        ),
        .testTarget(
            name: "QuickAccessCoreTests",
            dependencies: ["QuickAccessCore"]
        ),
    ]
)
