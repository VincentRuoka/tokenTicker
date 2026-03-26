// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "token-ticker",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "token-ticker",
            path: "Sources/token-ticker",
            resources: [
                .process("Resources/token-ticker.png"),
                .copy("Resources/icons")
            ]
        ),
        .testTarget(
            name: "token-ticker-tests",
            dependencies: ["token-ticker"],
            path: "Tests/token-ticker-tests"
        )
    ]
)
