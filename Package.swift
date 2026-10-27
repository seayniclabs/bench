// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Bench",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "BenchCore",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Sources/BenchCore"
        ),
        .executableTarget(
            name: "Bench",
            dependencies: [
                "BenchCore",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/Bench",
            exclude: ["Bench.entitlements", "Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Bench/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "BenchTests",
            dependencies: [
                "BenchCore",
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Tests/BenchTests"
        )
    ]
)
