// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeStatusBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClaudeStatusBarCore", targets: ["ClaudeStatusBarCore"]),
        .library(name: "ClaudeStatusBarApp", targets: ["ClaudeStatusBarApp"]),
        .executable(name: "usage-cli", targets: ["usage-cli"]),
    ],
    targets: [
        .target(name: "ClaudeStatusBarCore"),
        .target(name: "ClaudeStatusBarApp", dependencies: ["ClaudeStatusBarCore"]),
        .target(name: "TestSupport", dependencies: ["ClaudeStatusBarCore"]),
        .executableTarget(
            name: "usage-cli",
            dependencies: ["ClaudeStatusBarCore"]
        ),
        .testTarget(
            name: "ClaudeStatusBarCoreTests",
            dependencies: ["ClaudeStatusBarCore", "TestSupport"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "ClaudeStatusBarAppTests",
            dependencies: ["ClaudeStatusBarApp", "ClaudeStatusBarCore", "TestSupport"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
