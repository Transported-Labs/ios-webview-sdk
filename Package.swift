// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "CUELiveLightshow",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "CueLightShow",
            targets: ["CueLightShow"]),
    ],
    targets: [
        .target(
            name: "CueLightShow",
            path: "CueLightShow"),
    ]
)
