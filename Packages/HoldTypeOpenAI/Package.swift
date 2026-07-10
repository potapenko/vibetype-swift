// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "HoldTypeOpenAI",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "HoldTypeOpenAI",
            targets: ["HoldTypeOpenAI"]
        ),
    ],
    dependencies: [
        .package(path: "../HoldTypeDomain"),
    ],
    targets: [
        .target(
            name: "HoldTypeOpenAI",
            dependencies: [
                .product(name: "HoldTypeDomain", package: "HoldTypeDomain"),
            ]
        ),
        .testTarget(
            name: "HoldTypeOpenAITests",
            dependencies: [
                "HoldTypeOpenAI",
                .product(name: "HoldTypeDomain", package: "HoldTypeDomain"),
            ]
        ),
    ]
)
