// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CoverFlowUI",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CoverFlowUI", targets: ["CoverFlowUI"]),
    ],
    targets: [
        .target(name: "CoverFlowUI"),
        .testTarget(name: "CoverFlowUITests", dependencies: ["CoverFlowUI"]),
    ]
)
