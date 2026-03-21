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
    targets: [
        .executableTarget(
            name: "CuePane"
        ),
    ]
)
