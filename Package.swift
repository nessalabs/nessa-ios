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
                "ClawdiaDesignSystem"
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
