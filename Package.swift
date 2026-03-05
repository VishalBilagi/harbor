// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Harbor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // The shared core used by both CLI and the menubar app
        .library(
            name: "PortKit",
            targets: ["PortKit"]
        ),
        // The CLI tool
        .executable(
            name: "harbor",
            targets: ["harbor"]
        )
    ],
    targets: [
        .target(
            name: "PortKit",
            path: "Sources/PortKit"
        ),
        .target(
            name: "HarborMenuCore",
            dependencies: ["PortKit"],
            path: "Harbor",
            exclude: [
                "Assets.xcassets",
                "AppSettings.swift",
                "ContentView.swift",
                "HarborApp.swift",
                "HarborMenuModel.swift",
                "HarborSettingsView.swift",
            ],
            sources: ["ListenerRow.swift"]
        ),
        .executableTarget(
            name: "harbor",
            dependencies: ["PortKit"],
            path: "Sources/harbor"
        ),
        .testTarget(
            name: "PortKitTests",
            dependencies: ["PortKit"],
            path: "Tests/PortKitTests",
            resources: [.copy("Fixtures/lsof")]
        ),
        .testTarget(
            name: "HarborCLITests",
            dependencies: ["harbor", "PortKit"],
            path: "Tests/HarborCLITests"
        ),
        .testTarget(
            name: "HarborMenuCoreTests",
            dependencies: ["HarborMenuCore", "PortKit"],
            path: "Tests/HarborMenuCoreTests"
        ),
    ]
)
