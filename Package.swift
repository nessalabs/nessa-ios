// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NessaMobile",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "NessaDesignSystem", targets: ["NessaDesignSystem"]),
        .library(name: "NessaFeatures", targets: ["NessaFeatures"])
    ],
    targets: [
        .target(name: "NessaDesignSystem"),
        .target(name: "NessaFeatures", dependencies: ["NessaDesignSystem"]),
        .testTarget(name: "NessaFeaturesTests", dependencies: ["NessaFeatures"])
    ]
)
