import Foundation
import Testing

@testable import AnchorCore

@Suite("Formatting")
struct FormatTests {
    @Test("The clock hides hours until they exist")
    func clockHidesEmptyHours() {
        // A 25-minute session should read "24:59", not "0:24:59".
        #expect(Format.clock(0) == "00:00")
        #expect(Format.clock(59) == "00:59")
        #expect(Format.clock(60) == "01:00")
        #expect(Format.clock(1499) == "24:59")
        #expect(Format.clock(3599) == "59:59")
        #expect(Format.clock(3600) == "1:00:00")
        #expect(Format.clock(3661) == "1:01:01")
    }

    @Test("The clock never shows negative time")
    func clockClampsNegatives() {
        // Remaining is already clamped, but the ring reads this during the
        // frame where a session ends.
        #expect(Format.clock(-5) == "00:00")
    }

    @Test("The clock rounds rather than truncating")
    func clockRounds() {
        #expect(Format.clock(59.6) == "01:00")
        #expect(Format.clock(59.4) == "00:59")
    }

    @Test("Durations read compactly and drop empty units")
    func durationIsCompact() {
        #expect(Format.duration(0) == "0s")
        #expect(Format.duration(45) == "45s")
        #expect(Format.duration(60) == "1m")
        #expect(Format.duration(1500) == "25m")
        #expect(Format.duration(3600) == "1h")
        #expect(Format.duration(4800) == "1h 20m")
        // Exactly two hours is "2h", never "2h 0m".
        #expect(Format.duration(7200) == "2h")
    }

    @Test("Percentages round to whole numbers")
    func percent() {
        #expect(Format.percent(0) == "0%")
        #expect(Format.percent(0.5) == "50%")
        #expect(Format.percent(0.7353) == "74%")
        #expect(Format.percent(1) == "100%")
    }
}

@Suite("Store location")
struct AnchorStoreTests {
    @Test("An in-memory container is usable and isolated")
    func inMemoryContainer() throws {
        let container = try AnchorStore.makeContainer(kind: .inMemory)
        #expect(container.schema.entities.count == 10)
    }

    @Test("The schema carries the complete CloudKit-safe model set")
    func schemaShape() {
        let names = Set(AnchorStore.schema.entities.map(\.name))
        #expect(names == [
            "Project", "SavedTag", "Goal", "FocusSession", "Distraction", "MachineActivityDay",
            "BehaviorProfile", "ScheduleTemplate", "PlanBlock", "DivergenceEvent",
        ])
    }

    @Test("Identifiers are the Significant Hobbies ones the entitlements declare")
    func identifiers() {
        // These must match Apps/*/Anchor.entitlements exactly or CloudKit and the
        // shared app group fail silently at runtime rather than at build time.
        #expect(AnchorStore.appGroupIdentifier == "group.com.significanthobbies.anchor")
        #expect(AnchorStore.cloudKitIdentifier == "iCloud.com.significanthobbies.anchor")
    }

    @Test("Persistent storage explicitly selects Anchor's CloudKit container")
    func persistentConfiguration() {
        let configuration = AnchorStore.configuration(kind: .persistent)
        #expect(configuration.cloudKitContainerIdentifier == AnchorStore.cloudKitIdentifier)
        #expect(AnchorStore.StoreKind.persistent.storageDescription == "On this device, with iCloud continuity")
        #expect(AnchorStore.StoreKind.localOnly.storageDescription == "Stored only on this device")
    }

    @Test("Explicit local paths never attempt CloudKit")
    func explicitStorePathSelection() {
        #expect(AnchorStore.resilientStoreKinds(hasExplicitStorePath: true) == [.localOnly, .inMemory])
        #expect(
            AnchorStore.resilientStoreKinds(hasExplicitStorePath: false)
                == [.persistent, .localOnly, .inMemory]
        )
    }

    @MainActor
    @Test("Unsigned app builds open a local-only container")
    func localResilientContainerNeverUsesCloudKit() {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "anchor-local-\(UUID().uuidString).store")
        let result = AnchorStore.makeLocalResilientContainer(url: url)
        #expect(result.kind == .localOnly)
        #expect(result.container.configurations.first?.cloudKitContainerIdentifier == nil)
    }

    @Test("The store path always lands on a writable directory")
    func storeURLIsWritable() {
        let url = AnchorStore.storeURL()
        #expect(url.lastPathComponent.hasSuffix(".store"))
        // Whichever branch resolution took, the parent must exist — this is what
        // the MCP server depends on to find the same file as the app.
        var isDirectory: ObjCBool = false
        let parent = url.deletingLastPathComponent().path
        #expect(FileManager.default.fileExists(atPath: parent, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }
}

@MainActor
@Suite("Machine activity")
struct MachineActivityRecorderTests {
    @Test("Idle observations become aggregate active and tracked totals")
    func recordsPresence() throws {
        let container = try AnchorStore.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let recorder = MachineActivityRecorder(context: context)
        let start = Date(timeIntervalSince1970: 30_000)

        recorder.observe(idleSeconds: 0, isTracking: false, at: start)
        recorder.observe(idleSeconds: 2, isTracking: false, at: start.addingTimeInterval(10))
        recorder.observe(idleSeconds: 0, isTracking: true, at: start.addingTimeInterval(20))
        recorder.flush()

        let record = try #require(context.fetch(FetchDescriptor<MachineActivityDay>()).first)
        #expect(record.activeSeconds == 18)
        #expect(record.trackedSeconds == 10)
        #expect(record.untrackedSeconds == 8)
    }
}

@Suite("Record derivations")
struct RecordTests {
    @Test("A distraction with no category still displays as something")
    func displayKindFallsBack() {
        let distraction = Distraction(note: "unknown")
        #expect(distraction.kind == nil)
        #expect(distraction.displayKind == .other)
    }

    @Test("Setting a category by hand round-trips through the raw string")
    func kindRoundTrip() {
        let distraction = Distraction(note: "slack")
        distraction.kind = .message
        #expect(distraction.kindRaw == "message")
        #expect(distraction.kind == .message)
        distraction.kind = nil
        #expect(distraction.kindRaw == nil)
        #expect(distraction.displayKind == .other)
    }

    @Test("Every category maps to a label, symbol and origin")
    func taxonomyIsComplete() {
        for kind in DistractionKind.allCases {
            #expect(!kind.label.isEmpty)
            #expect(!kind.symbolName.isEmpty)
            #expect(DistractionOrigin.allCases.contains(kind.origin))
        }
        for theme in GoalTheme.allCases {
            #expect(!theme.label.isEmpty)
            #expect(!theme.symbolName.isEmpty)
        }
    }

    @Test("Interruption rate ignores sessions too short to be meaningful")
    func shortSessionsReportNoRate() {
        // A 30-second session with one interruption would otherwise report 120
        // interruptions per hour and dominate every average.
        let record = Fixture.session(focused: 30, distractions: [
            Fixture.distraction("a", kind: .message),
        ])
        #expect(record.interruptionRate == 0)
    }

    @Test("didComplete reflects the recorded outcome, not the elapsed time")
    func completionFlag() {
        #expect(Fixture.session(reason: .completed).didComplete)
        #expect(!Fixture.session(reason: .endedEarly).didComplete)
        #expect(!Fixture.session(reason: .abandoned).didComplete)
        #expect(!Fixture.session(reason: nil).didComplete)
    }
}

@Suite("Demo data")
struct DemoDataTests {
    @MainActor
    @Test("Seeding fills an empty store and never runs twice")
    func seedsOnceIntoEmptyStore() throws {
        let container = try AnchorStore.makeContainer(kind: .inMemory)
        let context = ModelContextFactory.make(container)

        DemoData.seedIfNeeded(into: context)
        let sessions = try context.sessionRecords()
        #expect(sessions.count > 20)
        #expect(sessions.contains { !$0.distractions.isEmpty })

        // A second call must be a no-op — it would otherwise double real history
        // for anyone who launched once with the flag set.
        DemoData.seedIfNeeded(into: context)
        #expect(try context.sessionRecords().count == sessions.count)
    }

    @MainActor
    @Test("Seeded history is deterministic, so screenshots don't churn")
    func seedingIsDeterministic() throws {
        func fingerprint() throws -> [String] {
            let context = ModelContextFactory.make(try AnchorStore.makeContainer(kind: .inMemory))
            DemoData.seedIfNeeded(into: context)
            return try context.sessionRecords()
                .sorted { $0.startedAt < $1.startedAt }
                .map { "\($0.goalTitle)|\(Int($0.focusedSeconds))|\($0.distractions.count)" }
        }
        #expect(try fingerprint() == fingerprint())
    }

    @MainActor
    @Test("Seeded analytics are coherent, not just present")
    func seededDataIsCoherent() throws {
        let context = ModelContextFactory.make(try AnchorStore.makeContainer(kind: .inMemory))
        DemoData.seedIfNeeded(into: context)
        let records = try context.sessionRecords()
        let stats = AnalyticsEngine().overview(records)

        #expect(stats.focusedSeconds > 0)
        #expect(stats.completedCount > 0)
        #expect(stats.completionRate > 0 && stats.completionRate <= 1)
        #expect(stats.recoveryRate > 0 && stats.recoveryRate <= 1)
        // Interruptions must land inside the session that owns them.
        for record in records {
            for distraction in record.distractions {
                #expect(distraction.offsetSeconds >= 0)
                #expect(distraction.offsetSeconds <= record.focusedSeconds)
            }
        }
    }
}

import SwiftData

/// Tiny helper so the SwiftData import stays confined to where it is needed.
enum ModelContextFactory {
    @MainActor
    static func make(_ container: ModelContainer) -> ModelContext {
        ModelContext(container)
    }
}
