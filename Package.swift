// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Anchor",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0"),
        // watchOS 26 has SwiftData and SwiftUI, but not `SystemLanguageModel` —
        // on-device tagging is compiled out there and the watch relies on the
        // phone/Mac to tag what it captures. See TaggingService.
        .watchOS("26.0"),
    ],
    products: [
        .library(name: "AnchorCore", targets: ["AnchorCore"]),
        .library(name: "AnchorUI", targets: ["AnchorUI"]),
        .executable(name: "anchor-mcp", targets: ["anchor-mcp"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/Significant-Hobbies/significanthobbies.git",
            revision: "e52fc1cffbb86b4a04f10ec2799f5bb7ed024b17"
        ),
    ],
    targets: [
        .target(
            name: "AnchorCore",
            dependencies: [
                .product(name: "PersonalSyncKit", package: "significanthobbies"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "AnchorUI",
            dependencies: ["AnchorCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "anchor-mcp",
            dependencies: ["AnchorCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AnchorCoreTests",
            dependencies: [
                "AnchorCore",
                .product(name: "PersonalSyncKit", package: "significanthobbies"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AnchorUITests",
            dependencies: ["AnchorUI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
