// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "tokenTicker",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "tokenTicker",
            path: "Sources/tokenTicker",
            resources: [.process("../../Resources")]
        ),
        .testTarget(
            name: "tokenTickerTests",
            dependencies: ["tokenTicker"],
            path: "Tests/tokenTickerTests"
        )
    ]
)
