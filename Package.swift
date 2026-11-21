// swift-tools-version: 6.0
// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Doug C. Hardester

import PackageDescription

let package = Package(
    name: "Savage",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "Savage", targets: ["Savage"]),
    ],
    targets: [
        .target(name: "Savage"),
        .testTarget(name: "SavageTests", dependencies: ["Savage"]),
        // The README's code examples, compiled against the public API only.
        .testTarget(name: "SavageReadmeTests", dependencies: ["Savage"]),
    ],
    swiftLanguageModes: [.v6]
)
