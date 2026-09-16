// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Witt Kung <witt.w.kung@gmail.com>. All rights reserved.

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
