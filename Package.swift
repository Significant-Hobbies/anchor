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
            revision: "33da9b4f8e48d7c58182c42b0995dbe264ce4681"
        ),
        .package(url: "https://github.com/sass-maker/ui-library", from: "0.1.14"),
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
            dependencies: [
                "AnchorCore",
                // iOS and macOS only: the watch app keeps AnchorTheme.
                .product(name: "SaaSMakerUI", package: "ui-library", condition: .when(platforms: [.iOS, .macOS])),
            ],
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
            resources: [.copy("Fixtures/LegacyNotes.store"), .copy("Fixtures/AssistantBackendRecords.json"), .copy("Fixtures/WorkerAgentCommand.json"), .copy("Fixtures/WorkerHistoryEdit.json")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AnchorUITests",
            dependencies: [
                "AnchorUI",
                .product(name: "PersonalSyncKit", package: "significanthobbies"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
