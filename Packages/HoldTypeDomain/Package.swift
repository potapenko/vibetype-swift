// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "HoldTypeDomain",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "HoldTypeDomain",
            targets: ["HoldTypeDomain"]
        ),
    ],
    targets: [
        .target(name: "HoldTypeDomain"),
        .testTarget(
            name: "HoldTypeDomainTests",
            dependencies: ["HoldTypeDomain"]
        ),
    ]
)
