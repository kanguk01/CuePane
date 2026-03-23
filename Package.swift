// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CuePane",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "CuePane",
            targets: ["CuePane"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "CuePane",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
    ]
)
