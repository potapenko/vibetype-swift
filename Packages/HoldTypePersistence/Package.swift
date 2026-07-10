// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "HoldTypePersistence",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "HoldTypePersistence",
            targets: ["HoldTypePersistence"]
        ),
    ],
    targets: [
        .target(name: "HoldTypePersistence"),
        .testTarget(
            name: "HoldTypePersistenceTests",
            dependencies: ["HoldTypePersistence"]
        ),
    ]
)
