// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftEarcut",
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
