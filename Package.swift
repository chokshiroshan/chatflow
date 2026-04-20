// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Flow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Flow", targets: ["Flow"]),
    ],
    targets: [
        .executableTarget(
            name: "Flow",
            path: "Sources/Flow"
        ),
        .testTarget(
            name: "FlowTests",
            dependencies: ["Flow"],
            path: "Tests/FlowTests"
        ),
    ]
)
