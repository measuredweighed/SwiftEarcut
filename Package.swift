// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftEarcut",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
        .macCatalyst(.v13),
    ],
    products: [
        .library(
            name: "SwiftEarcut",
            targets: ["SwiftEarcut"]),
    ],
    targets: [
        .target(
            name: "SwiftEarcut",
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(
            name: "SwiftEarcutBench",
            dependencies: ["SwiftEarcut"],
            path: "Benchmarks/SwiftEarcutBench",
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "SwiftEarcutTests",
            dependencies: ["SwiftEarcut"],
            // Read from the source tree via #filePath rather than Bundle.module, so they
            // are excluded rather than copied into the test bundle on every build.
            exclude: [
                "fixtures",
                "expected.json",
            ]
        ),
    ]
)
