// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppleReviewMCP",
    platforms: [.macOS("13.0")],
    products: [
        .executable(name: "AppleReviewMCPServer", targets: ["AppleReviewMCPServer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.7.1"),
    ],
    targets: [
        .executableTarget(
            name: "AppleReviewMCPServer",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources/AppleReviewMCPServer"
        ),
    ]
)
