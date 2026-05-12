// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DiskWave2",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DiskWave2", targets: ["DiskWave2"])
    ],
    targets: [
        .executableTarget(
            name: "DiskWave2",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("QuickLookUI")
            ]
        )
    ]
)
