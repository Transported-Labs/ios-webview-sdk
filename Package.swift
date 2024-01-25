// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "CUELiveLightshow",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "WebViewSDK",
            targets: ["WebViewSDK"]),
    ],
    targets: [
        .target(
            name: "WebViewSDK",
            path: "WebViewSDK"),
    ]
)
