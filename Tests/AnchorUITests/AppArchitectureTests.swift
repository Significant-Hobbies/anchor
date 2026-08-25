import Foundation
import Testing

@testable import AnchorUI

@Suite("Shared app architecture")
struct AppArchitectureTests {
    @Test("Mac and iPhone are thin shells over the same product root")
    func fullAppsUseSharedRoot() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let shellPaths = [
            repository.appending(path: "Apps/Mac/AnchorMacApp.swift"),
            repository.appending(path: "Apps/iOS/AnchorIOSApp.swift"),
        ]

        for path in shellPaths {
            let source = try String(contentsOf: path, encoding: .utf8)
            #expect(source.contains("AnchorProductRoot(world: world)"))
            #expect(!source.contains("RootView("))
            #expect(!source.contains("AnchorPlatformSync("))
            #expect(!source.contains("preferredColorScheme"))
        }
    }

    @Test("Local-only build selection is shared by both full apps")
    func buildConfigurationUsesSharedFactory() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let factory = try String(
            contentsOf: repository.appending(path: "Apps/Shared/AnchorApplication.swift"),
            encoding: .utf8
        )

        #expect(factory.contains("func makeAnchorAppWorld() -> AnchorAppWorld"))
        #expect(factory.contains("ANCHOR_LOCAL_ONLY"))
    }
}
