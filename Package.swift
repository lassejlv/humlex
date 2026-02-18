// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Humlex",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
        .package(url: "https://github.com/jamesrochabrun/ClaudeCodeSDK", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Humlex",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "ClaudeCodeSDK", package: "ClaudeCodeSDK"),
            ],
            path: "Sources/Humlex",
            resources: [
                .process("assets")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
