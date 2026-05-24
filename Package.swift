// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AiUsageMenu",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AiUsageMenu", targets: ["AiUsageMenuApp"])
    ],
    targets: [
        .executableTarget(
            name: "AiUsageMenuApp",
            path: "Sources/AiUsageMenuApp"
        ),
        .testTarget(
            name: "AiUsageMenuAppTests",
            dependencies: ["AiUsageMenuApp"],
            path: "Tests/AiUsageMenuAppTests"
        )
    ]
)
