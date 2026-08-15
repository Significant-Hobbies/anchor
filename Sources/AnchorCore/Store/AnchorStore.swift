import Foundation
import SwiftData

/// Schema + container construction, in one place so the app, the previews, the
/// MCP server and the tests all agree on what "the database" is.
public enum AnchorStore {
    public static let schema = Schema([
        Goal.self,
        FocusSession.self,
        Distraction.self,
    ])

    /// App group so the Mac app, the iOS app and any future extension all read
    /// the same file. Falls back to the default location if the group is absent
    /// (which is the case for `swift test` and for unsigned local builds).
    public static let appGroupIdentifier = "group.com.significanthobbies.anchor"

    /// CloudKit container backing cross-device sync.
    public static let cloudKitIdentifier = "iCloud.com.significanthobbies.anchor"

    public enum StoreKind: Sendable {
        /// On disk, synced through CloudKit when entitlements allow it.
        case persistent
        /// On disk, never synced. Used when the user turns sync off.
        case localOnly
        /// RAM only. Previews and tests.
        case inMemory
    }

    /// Build a container. Throws rather than trapping so the app can show a real
    /// error instead of dying on launch with a corrupt store.
    public static func makeContainer(kind: StoreKind = .persistent) throws -> ModelContainer {
        switch kind {
        case .inMemory:
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: config)

        case .localOnly:
            let config = ModelConfiguration(
                schema: schema,
                url: storeURL(),
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: config)

        case .persistent:
            let config = ModelConfiguration(
                schema: schema,
                url: storeURL(),
                cloudKitDatabase: .automatic
            )
            return try ModelContainer(for: schema, configurations: config)
        }
    }

    /// Best-effort container: tries CloudKit, falls back to local-only, then to
    /// memory. The app stays usable even when iCloud is misconfigured — losing
    /// sync should never mean losing the ability to start a timer.
    public static func makeResilientContainer() -> (container: ModelContainer, kind: StoreKind) {
        for kind in [StoreKind.persistent, .localOnly, .inMemory] {
            if let container = try? makeContainer(kind: kind) {
                return (container, kind)
            }
        }
        // If even in-memory fails the process is unrecoverable.
        fatalError("Anchor could not open any model container.")
    }

    /// Where the database lives.
    ///
    /// Resolution order, and why:
    /// 1. `ANCHOR_STORE_PATH` — lets the MCP server (or a test) point at an
    ///    explicit file when the automatic choice is wrong.
    /// 2. The app-group container, *only if it already exists*. `containerURL(_:)`
    ///    hands back a path whether or not the entitlement was granted, so the
    ///    existence check is what actually distinguishes a provisioned app from
    ///    an unsigned command-line process.
    /// 3. Application Support.
    ///
    /// Both the app and the CLI run this same logic, so they land on the same
    /// file in either world: entitled app and CLI both see the group container,
    /// unsigned dev build and CLI both fall back to Application Support.
    public static func storeURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["ANCHOR_STORE_PATH"], !override.isEmpty {
            let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            return url
        }

        if let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ), FileManager.default.fileExists(atPath: group.path) {
            return group.appending(path: "Anchor.store")
        }

        let directory = URL.applicationSupportDirectory.appending(path: "Anchor", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "Anchor.store")
    }
}
