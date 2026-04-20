// swift-tools-version: 6.0
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
            path: "Sources/Flow",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"]),
            ]
        ),
    ]
)
