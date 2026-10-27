// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Folzio",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FolzioCore", targets: ["FolzioCore"]),
        .executable(name: "FolzioApp", targets: ["FolzioApp"]),
        .executable(name: "make-fixtures", targets: ["make-fixtures"]),
        .executable(name: "make-icon", targets: ["make-icon"]),
    ],
    targets: [
        .target(name: "FolzioCore"),
        .target(
            name: "FolzioLocalization",
            dependencies: ["FolzioCore"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "FolzioApp",
            dependencies: ["FolzioCore", "FolzioLocalization"]
        ),
        .target(
            name: "FixtureKit",
            dependencies: ["FolzioCore"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "make-fixtures",
            dependencies: ["FixtureKit"]
        ),
        .executableTarget(name: "make-icon"),
        .testTarget(
            name: "FolzioCoreTests",
            dependencies: ["FolzioCore", "FolzioLocalization", "FixtureKit"]
        ),
        .testTarget(
            name: "FolzioPerformanceTests",
            dependencies: ["FolzioCore", "FixtureKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
