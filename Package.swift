// swift-tools-version: 6.0
import PackageDescription

let swiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "scrib3",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "Scrib3Core", targets: ["Scrib3Core"]),
        .executable(name: "scrib3", targets: ["Scrib3App"]),
    ],
    targets: [
        .target(
            name: "Scrib3Core",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "Scrib3App",
            dependencies: ["Scrib3Core"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "Scrib3CoreTests",
            dependencies: ["Scrib3Core"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "Scrib3AppTests",
            dependencies: ["Scrib3App"],
            swiftSettings: swiftSettings
        ),
    ]
)
