// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIChat",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AIChat",
            path: ".",
            exclude: ["run.sh", "build-dmg.sh", "Assets.xcassets"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
