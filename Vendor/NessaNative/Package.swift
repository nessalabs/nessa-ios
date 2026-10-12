// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "NessaNative",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "NessaNative", targets: ["NessaNative"])],
    targets: [
        .binaryTarget(name: "nessa_device_clientFFI", path: "NessaDeviceClient.xcframework"),
        .target(name: "NessaNative", dependencies: ["nessa_device_clientFFI"], path: "Sources")
    ]
)
