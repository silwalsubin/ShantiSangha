// swift-tools-version: 6.0
import PackageDescription

// Mirrors Apple's RealityKitContent template — no explicit resources
// declaration. Xcode auto-recognizes the .rkassets folder inside the
// target source directory and runs the Reality Composer Pro build
// tool on it during compilation.
let package = Package(
    name: "SolarSystemAssets",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .visionOS(.v2),
    ],
    products: [
        .library(
            name: "SolarSystemAssets",
            targets: ["SolarSystemAssets"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SolarSystemAssets",
            dependencies: []),
    ]
)
