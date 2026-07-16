// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeStatusBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClaudeStatusBarCore", targets: ["ClaudeStatusBarCore"]),
        .executable(name: "usage-cli", targets: ["usage-cli"]),
    ],
    targets: [
        .target(name: "ClaudeStatusBarCore"),
        .executableTarget(
            name: "usage-cli",
            dependencies: ["ClaudeStatusBarCore"]
        ),
        .testTarget(
            name: "ClaudeStatusBarCoreTests",
            dependencies: ["ClaudeStatusBarCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
