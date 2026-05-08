// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ClawdiaMobile",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "SharedKernel", targets: ["SharedKernel"]),
        .library(name: "ClawdiaObservability", targets: ["ClawdiaObservability"]),
        .library(name: "ClawdiaDesignSystem", targets: ["ClawdiaDesignSystem"]),
        .library(name: "ClawdiaFeatures", targets: ["ClawdiaFeatures"]),
        .executable(name: "ClawdiaVerificationTests", targets: ["ClawdiaVerificationTests"])
    ],
    dependencies: [
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.10.0"),
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift", exact: "0.12.2")
    ],
    targets: [
        .target(name: "SharedKernel"),
        .target(
            name: "ClawdiaObservability",
            dependencies: ["SharedKernel"]
        ),
        .target(
            name: "ClawdiaDesignSystem",
            dependencies: ["SharedKernel"]
        ),
        .target(
            name: "ClawdiaFeatures",
            dependencies: [
                "SharedKernel",
                "ClawdiaObservability",
                "ClawdiaDesignSystem",
                .product(name: "CryptoSwift", package: "CryptoSwift"),
                .product(name: "secp256k1", package: "secp256k1.swift")
            ]
        ),
        .executableTarget(
            name: "ClawdiaVerificationTests",
            dependencies: [
                "SharedKernel",
                "ClawdiaDesignSystem",
                "ClawdiaFeatures"
            ]
        )
    ]
)
