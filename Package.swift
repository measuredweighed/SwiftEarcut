// swift-tools-version: 5.6
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
            name: "Earcut",
            targets: ["Earcut"]),
    ],
    targets: [
        .target(
            name: "Earcut"),
        .testTarget(
            name: "EarcutTests",
            dependencies: ["Earcut"],
            resources: [
                .copy("fixtures/")
            ]
        ),
    ]
)
