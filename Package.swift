// swift-tools-version: 6.2

// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import PackageDescription

let package = Package(
    name: "swift-icecast-kit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "IcecastKit",
            targets: ["IcecastKit"]
        ),
        .executable(
            name: "icecast-cli",
            targets: ["IcecastKitCLI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin.git", from: "1.4.3")
    ],
    targets: [
        // Core library — swift-crypto only on Linux
        .target(
            name: "IcecastKit",
            dependencies: [
                .product(
                    name: "Crypto",
                    package: "swift-crypto",
                    condition: .when(platforms: [.linux])
                )
            ]
        ),

        // CLI commands library — testable independently
        .target(
            name: "IcecastKitCommands",
            dependencies: [
                "IcecastKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),

        // CLI executable — thin entry point only
        .executableTarget(
            name: "IcecastKitCLI",
            dependencies: ["IcecastKitCommands"]
        ),

        // Core library tests
        .testTarget(
            name: "IcecastKitTests",
            dependencies: ["IcecastKit"]
        ),

        // CLI command tests — SEPARATE from core tests
        .testTarget(
            name: "IcecastKitCommandsTests",
            dependencies: ["IcecastKitCommands"]
        )
    ]
)
