// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NessaMobile",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "NessaDesignSystem", targets: ["NessaDesignSystem"]),
        .library(name: "NessaFeatures", targets: ["NessaFeatures"]),
        .executable(name: "PhoneSyncVerification", targets: ["PhoneSyncVerification"])
    ],
    dependencies: [.package(path: "Vendor/NessaNative")],
    targets: [
        .target(name: "NessaDesignSystem"),
        .target(name: "NessaFeatures", dependencies: [
            "NessaDesignSystem", .product(name: "NessaNative", package: "NessaNative")
        ]),
        .testTarget(name: "NessaFeaturesTests", dependencies: ["NessaFeatures"]),
        .executableTarget(name: "PhoneSyncVerification", dependencies: ["NessaFeatures"],
            path: "verification/sync/NativeVerification")
    ]
)
