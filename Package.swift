// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AiUsageMenu",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AiUsageMenu", targets: ["AiUsageMenuApp"]),
        .executable(name: "AIUsageUpdaterHelper", targets: ["AIUsageUpdaterHelper"])
    ],
    targets: [
        .executableTarget(
            name: "AiUsageMenuApp",
            path: "Sources/AiUsageMenuApp"
        ),
        .executableTarget(
            name: "AIUsageUpdaterHelper",
            path: "Sources/AIUsageUpdaterHelper"
        ),
        .testTarget(
            name: "AiUsageMenuAppTests",
            dependencies: ["AiUsageMenuApp"],
            path: "Tests/AiUsageMenuAppTests"
        )
    ]
)
