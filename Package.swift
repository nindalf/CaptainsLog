// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CaptainsLog",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "CaptainsLogKit", targets: ["CaptainsLogKit"]),
        .executable(name: "captains-log", targets: ["captains-log"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "CaptainsLogKit",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ]
        ),
        .executableTarget(
            name: "captains-log",
            dependencies: [
                "CaptainsLogKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
