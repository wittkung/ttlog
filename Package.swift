// swift-tools-version: 6.0
// Copyright 2026 MetastudyLine. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0

import PackageDescription

let package = Package(
    name: "TTLog",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .watchOS(.v9),
        .tvOS(.v16),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "TTLogKit", type: .dynamic, targets: ["TTLogKit"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "TTLogKit",
            dependencies: [],
            path: "Sources/TTLogKit",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "TTLogKitTests",
            dependencies: ["TTLogKit"],
            path: "Tests/TTLogKitTests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
