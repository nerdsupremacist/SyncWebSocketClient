// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SyncWebSocketClient",
    platforms: [.macOS(.v12), .iOS(.v15), .watchOS(.v8), .tvOS(.v15)],
    products: [
        .library(
            name: "SyncWebSocketClient",
            targets: ["SyncWebSocketClient"]),
    ],
    dependencies: [
        .package(name: "Sync", url: "https://github.com/nerdsupremacist/Sync.git", from: "1.0.0"),
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", .upToNextMinor(from: "0.12.0")),
    ],
    targets: [
        .target(
            name: "SyncWebSocketClient",
            dependencies: [
                "Sync",
                .product(
                    name: "JavaScriptKit",
                    package: "JavaScriptKit",
                    condition: .when(platforms: [.wasi])
                ),
            ]),
        .testTarget(
            name: "SyncWebSocketClientTests",
            dependencies: ["SyncWebSocketClient"]),
    ]
)
