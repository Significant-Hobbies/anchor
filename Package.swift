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
            url: "https://github.com/Significant-Hobbies/personal-platform.git",
            revision: "55176cac008d3857ef815d9bc5c8e74b68e7c3f3"
        ),
    ],
    targets: [
        .target(
            name: "AnchorCore",
            dependencies: [
                .product(name: "PersonalSyncKit", package: "personal-platform"),
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
                .product(name: "PersonalSyncKit", package: "personal-platform"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
