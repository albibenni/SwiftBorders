// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SwiftBorders",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "SwiftBordersCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "swiftborders",
            dependencies: ["SwiftBordersCore"],
            path: "Sources/SwiftBorders",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SwiftBordersCoreTests",
            dependencies: ["SwiftBordersCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
