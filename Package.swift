// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SyncWebSocketClient",
    platforms: [.macOS(.v11), .iOS(.v14), .watchOS(.v6), .tvOS(.v14)],
    products: [
        .library(
            name: "SyncWebSocketClient",
            targets: ["SyncWebSocketClient"]),
    ],
    dependencies: [
        .package(name: "Sync", url: "https://github.com/nerdsupremacist/Sync.git", branch: "main"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "SyncWebSocketClient",
            dependencies: ["Sync"]),
        .testTarget(
            name: "SyncWebSocketClientTests",
            dependencies: ["SyncWebSocketClient"]),
    ]
)
