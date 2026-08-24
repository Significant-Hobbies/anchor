import Foundation
import SwiftData

/// Schema + container construction, in one place so the app, the previews, the
/// MCP server and the tests all agree on what "the database" is.
public enum AnchorStore {
    public static let schema = Schema([
        Project.self,
        SavedTag.self,
        Goal.self,
        FocusSession.self,
        Distraction.self,
        MachineActivityDay.self,
        BehaviorProfile.self,
        ScheduleTemplate.self,
        PlanBlock.self,
        DivergenceEvent.self,
    ])

    /// App group so the Mac app, the iOS app and any future extension all read
    /// the same file. Falls back to the default location if the group is absent
    /// (which is the case for `swift test` and for unsigned local builds).
    public static let appGroupIdentifier = "group.com.significanthobbies.anchor"

    /// CloudKit container backing cross-device sync.
    public static let cloudKitIdentifier = "iCloud.com.significanthobbies.anchor"

    public enum StoreKind: Equatable, Sendable {
        /// On disk, synced through CloudKit when entitlements allow it.
        case persistent
        /// On disk, never synced. Used when the user turns sync off.
        case localOnly
        /// RAM only. Previews and tests.
        case inMemory

        public var storageDescription: String {
            switch self {
            case .persistent: "On this device, with iCloud continuity"
            case .localOnly: "Stored only on this device"
            case .inMemory: "Temporary storage"
            }
        }
    }

    /// Keep configuration construction inspectable so tests can prove that the
    /// production path targets Anchor's exact container instead of relying on
    /// entitlement-order discovery.
    public static func configuration(
        kind: StoreKind,
        url: URL? = nil
    ) -> ModelConfiguration {
        switch kind {
        case .inMemory:
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        case .localOnly:
            ModelConfiguration(
                schema: schema,
                url: url ?? storeURL(),
                cloudKitDatabase: .none
            )
        case .persistent:
            ModelConfiguration(
                schema: schema,
                url: url ?? storeURL(),
                cloudKitDatabase: .private(cloudKitIdentifier)
            )
        }
    }

    /// Build a container. Throws rather than trapping so the app can show a real
    /// error instead of dying on launch with a corrupt store.
    public static func makeContainer(kind: StoreKind = .persistent) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: configuration(kind: kind))
    }

    /// Best-effort container: tries CloudKit, falls back to local-only, then to
    /// memory. The app stays usable even when iCloud is misconfigured — losing
    /// sync should never mean losing the ability to start a timer.
    public static func makeResilientContainer() -> (container: ModelContainer, kind: StoreKind) {
        for kind in resilientStoreKinds(
            hasExplicitStorePath: ProcessInfo.processInfo.environment["ANCHOR_STORE_PATH"]?.isEmpty == false
        ) {
            if let container = try? makeContainer(kind: kind) {
                return (container, kind)
            }
        }
        // If even in-memory fails the process is unrecoverable.
        fatalError("Anchor could not open any model container.")
    }

    /// DebugLocal and other explicitly unsigned shells must never start a
    /// CloudKit mirror. Container construction can appear to succeed before
    /// Core Data discovers the missing entitlement on its background queue, so
    /// this boundary cannot rely on the catch-and-fallback path above.
    public static func makeLocalResilientContainer(url: URL? = nil) -> (container: ModelContainer, kind: StoreKind) {
        if let container = try? ModelContainer(
            for: schema,
            configurations: configuration(kind: .localOnly, url: url)
        ) {
            return (container, .localOnly)
        }
        if let container = try? makeContainer(kind: .inMemory) {
            return (container, .inMemory)
        }
        fatalError("Anchor could not open a local model container.")
    }

    /// An explicit path is used by UI tests and local tools that deliberately
    /// operate outside the signed app container. Do not ask CloudKit to mirror
    /// those stores: Core Data can terminate asynchronously when the process
    /// does not carry the production iCloud entitlement, which cannot be caught
    /// by the container-construction fallback above.
    public static func resilientStoreKinds(hasExplicitStorePath: Bool) -> [StoreKind] {
        hasExplicitStorePath
            ? [.localOnly, .inMemory]
            : [.persistent, .localOnly, .inMemory]
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
