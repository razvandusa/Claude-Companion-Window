// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeCompanion",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClaudeCompanion", targets: ["ClaudeCompanion"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "1.9.0")
    ],
    targets: [
        .executableTarget(
            name: "ClaudeCompanion",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Sources/ClaudeCompanion",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ClaudeCompanionTests",
            dependencies: ["ClaudeCompanion"],
            path: "Tests/ClaudeCompanionTests"
        )
    ]
)
