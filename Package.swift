// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIChat",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "AIChat",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: ".",
            exclude: ["run.sh", "build-dmg.sh", "Assets.xcassets", "README.md", ".github", "docs"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
