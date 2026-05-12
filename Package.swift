// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DiskUsage",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DiskUsage", targets: ["DiskUsage"])
    ],
    targets: [
        .executableTarget(
            name: "DiskUsage",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("QuickLookUI")
            ]
        )
    ]
)
