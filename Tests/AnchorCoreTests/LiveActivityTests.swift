import Foundation
import SwiftData
import Testing

@testable import AnchorCore

// MARK: - Snapshot

@Suite("Live Activity snapshot")
struct LiveActivitySnapshotTests {
    @Test("Planned sessions derive a completion date from the wall clock")
    func plannedCompletionDate() {
        let start = Date(timeIntervalSince1970: 10_000)
        let snapshot = LiveActivitySnapshot(
            sessionID: UUID(),
            intent: "Ship auth",
            state: .running,
            startedAt: start,
            plannedSeconds: 60,
            bankedSeconds: 15,
            runningSince: start,
            pausedAt: nil,
            interruptionCount: 0
        )
        // 60 planned − 15 banked = 45 still needed → start + 45.
        #expect(snapshot.plannedCompletionDate == start.addingTimeInterval(45))
    }

    @Test("Open-ended sessions have no completion date")
    func openEndedHasNoCompletionDate() {
        let snapshot = LiveActivitySnapshot(
            sessionID: UUID(),
            intent: "Explore",
            state: .running,
            startedAt: Date(),
            plannedSeconds: 0,
            bankedSeconds: 0,
            runningSince: Date(),
            pausedAt: nil,
            interruptionCount: 0
        )
        #expect(snapshot.isOpenEnded)
        #expect(snapshot.plannedCompletionDate == nil)
    }

    @Test("Open-ended elapsed time includes focus banked before a pause")
    func openEndedElapsedReferenceIncludesBankedTime() {
        let resumedAt = Date(timeIntervalSince1970: 10_000)
        let snapshot = LiveActivitySnapshot(
            sessionID: UUID(),
            intent: "Explore",
            state: .running,
            startedAt: resumedAt.addingTimeInterval(-90),
            plannedSeconds: 0,
            bankedSeconds: 45,
            runningSince: resumedAt,
            pausedAt: nil,
            interruptionCount: 0
        )

        #expect(snapshot.elapsedReferenceDate == resumedAt.addingTimeInterval(-45))
    }

    @Test("Paused sessions have no completion date even when planned")
    func pausedHasNoCompletionDate() {
        let snapshot = LiveActivitySnapshot(
            sessionID: UUID(),
            intent: "Ship auth",
            state: .paused,
            startedAt: Date(),
            plannedSeconds: 60,
            bankedSeconds: 30,
            runningSince: nil,
            pausedAt: Date(),
            interruptionCount: 0
        )
        #expect(!snapshot.isOpenEnded)
        #expect(snapshot.plannedCompletionDate == nil)
    }
}

// MARK: - Controller lifecycle

@MainActor
@Suite("Live Activity lifecycle")
struct LiveActivityLifecycleTests {
    /// Records every coordinator call so tests can assert the exact sequence.
    final class RecordingCoordinator: LiveActivityCoordinating {
        enum Call: Equatable {
            case start(LiveActivitySnapshot)
            case update(LiveActivitySnapshot)
            case end
        }

        var calls: [Call] = []

        func start(with snapshot: LiveActivitySnapshot) {
            calls.append(.start(snapshot))
        }

        func update(with snapshot: LiveActivitySnapshot) {
            calls.append(.update(snapshot))
        }

        func end() {
            calls.append(.end)
        }
    }

    func makeController(
        coordinator: RecordingCoordinator = RecordingCoordinator()
    ) throws -> (FocusController, ModelContext, RecordingCoordinator) {
        let container = try AnchorStore.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let coordinator = coordinator
        let controller = FocusController(
            context: context,
            tagger: TaggingService(allowsOnDeviceModel: false),
            liveActivityCoordinator: coordinator
        )
        coordinator.calls.removeAll()
        return (controller, context, coordinator)
    }

    @Test("Launching without an active session cleans up an orphaned activity")
    func noActiveSessionEndsActivity() throws {
        let container = try AnchorStore.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let coordinator = RecordingCoordinator()

        _ = FocusController(
            context: context,
            tagger: TaggingService(allowsOnDeviceModel: false),
            liveActivityCoordinator: coordinator
        )

        #expect(coordinator.calls == [.end])
    }

    @Test("Starting a session publishes a running snapshot")
    func startPublishesSnapshot() throws {
        let (controller, _, coordinator) = try makeController()
        let session = controller.start(goal: nil, intent: "Ship auth", minutes: 25)

        guard case let .start(snapshot)? = coordinator.calls.first else {
            Issue.record("expected a start call")
            return
        }
        #expect(snapshot.sessionID == session.id)
        #expect(snapshot.intent == "Ship auth")
        #expect(snapshot.state == .running)
        #expect(snapshot.plannedSeconds == 1500)
        #expect(snapshot.interruptionCount == 0)
    }

    @Test("Pausing publishes a paused snapshot")
    func pausePublishesPausedSnapshot() throws {
        let (controller, _, coordinator) = try makeController()
        controller.start(goal: nil, intent: "Ship auth", minutes: 25)
        coordinator.calls.removeAll()
        controller.pause()

        guard case let .update(snapshot)? = coordinator.calls.first else {
            Issue.record("expected an update call")
            return
        }
        #expect(snapshot.state == .paused)
        #expect(snapshot.runningSince == nil)
        #expect(snapshot.pausedAt != nil)
    }

    @Test("Resuming publishes a running snapshot")
    func resumePublishesRunningSnapshot() throws {
        let (controller, _, coordinator) = try makeController()
        controller.start(goal: nil, intent: "Ship auth", minutes: 25)
        controller.pause()
        coordinator.calls.removeAll()
        controller.resume()

        guard case let .update(snapshot)? = coordinator.calls.first else {
            Issue.record("expected an update call")
            return
        }
        #expect(snapshot.state == .running)
        #expect(snapshot.runningSince != nil)
        #expect(snapshot.pausedAt == nil)
    }

    @Test("Extending publishes an updated planned duration")
    func extendPublishesUpdate() throws {
        let (controller, _, coordinator) = try makeController()
        controller.start(goal: nil, intent: "Ship auth", minutes: 25)
        coordinator.calls.removeAll()
        controller.extend(byMinutes: 5)

        guard case let .update(snapshot)? = coordinator.calls.first else {
            Issue.record("expected an update call")
            return
        }
        #expect(snapshot.plannedSeconds == 1800)
    }

    @Test("Ending a session ends the Live Activity")
    func endCallsEnd() throws {
        let (controller, _, coordinator) = try makeController()
        controller.start(goal: nil, intent: "Ship auth", minutes: 25)
        coordinator.calls.removeAll()
        controller.end(reason: .endedEarly)

        #expect(coordinator.calls == [.end])
    }

    @Test("Auto-completion at the plan boundary ends the Live Activity")
    func autoCompleteEndsActivity() throws {
        let (controller, _, coordinator) = try makeController()
        controller.start(goal: nil, intent: "Ship auth", minutes: 25)
        let start = Date(timeIntervalSince1970: 10_000)
        controller.session?.plannedSeconds = 60
        controller.session?.bankedSeconds = 15
        controller.session?.runningSince = start

        coordinator.calls.removeAll()
        controller.refresh(at: start.addingTimeInterval(90))

        #expect(coordinator.calls == [.end])
    }

    @Test("Parking a distraction updates the interruption count")
    func parkUpdatesInterruptionCount() throws {
        let (controller, _, coordinator) = try makeController()
        controller.start(goal: nil, intent: "Ship auth", minutes: 25)
        coordinator.calls.removeAll()
        controller.park(note: "Slack from Ravi", kind: .message)

        guard case let .update(snapshot)? = coordinator.calls.first else {
            Issue.record("expected an update call")
            return
        }
        #expect(snapshot.interruptionCount == 1)
    }

    @Test("Surrendering ends the Live Activity")
    func surrenderEndsActivity() throws {
        let (controller, _, coordinator) = try makeController()
        controller.start(goal: nil, intent: "Ship auth", minutes: 25)
        coordinator.calls.removeAll()
        controller.surrender(to: "Went to twitter")

        #expect(coordinator.calls.last == .end)
    }

    @Test("Importing an active session starts a Live Activity")
    func importedSessionStartsActivity() throws {
        let (controller, context, coordinator) = try makeController()
        #expect(!controller.hasSession)

        let imported = FocusSession(
            goal: nil,
            intent: "Started on the Mac",
            plannedSeconds: 1_500
        )
        context.insert(imported)
        try context.save()

        coordinator.calls.removeAll()
        controller.synchronizeActiveSessionFromStore()

        guard case let .start(snapshot)? = coordinator.calls.first else {
            Issue.record("expected a start call")
            return
        }
        #expect(snapshot.sessionID == imported.id)
        #expect(snapshot.intent == "Started on the Mac")
    }

    @Test("A remotely finished session ends the Live Activity")
    func importedFinishedSessionEndsActivity() throws {
        let (controller, context, coordinator) = try makeController()
        controller.start(goal: nil, intent: "Started on the Mac", minutes: 25)
        controller.session?.state = .finished
        controller.session?.endedAt = Date()
        try context.save()

        coordinator.calls.removeAll()
        controller.synchronizeActiveSessionFromStore()

        #expect(coordinator.calls.contains(.end))
        #expect(!controller.hasSession)
    }

    @Test("Restoring an in-flight session on launch starts a Live Activity")
    func restoredSessionStartsActivity() throws {
        let container = try AnchorStore.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let first = FocusController(
            context: context,
            tagger: TaggingService(allowsOnDeviceModel: false)
        )
        first.start(goal: nil, intent: "Ship auth", minutes: 25)

        let coordinator = RecordingCoordinator()
        _ = FocusController(
            context: context,
            tagger: TaggingService(allowsOnDeviceModel: false),
            liveActivityCoordinator: coordinator
        )

        guard case let .start(snapshot)? = coordinator.calls.first else {
            Issue.record("expected a start call on restore")
            return
        }
        #expect(snapshot.intent == "Ship auth")
        #expect(snapshot.state == .running)
    }

    @Test("A noop coordinator never throws and does not block lifecycle")
    func noopCoordinatorIsSafe() throws {
        let container = try AnchorStore.makeContainer(kind: .inMemory)
        let controller = FocusController(
            context: ModelContext(container),
            tagger: TaggingService(allowsOnDeviceModel: false)
        )
        controller.start(goal: nil, intent: "Ship auth", minutes: 25)
        controller.pause()
        controller.resume()
        controller.park(note: "Slack", kind: .message)
        controller.end(reason: .endedEarly)
        // No crash means the noop path is safe.
        #expect(!controller.hasSession)
    }

    @Test("Starting a new session after ending starts a fresh Live Activity")
    func restartStartsFreshActivity() throws {
        let (controller, _, coordinator) = try makeController()
        controller.start(goal: nil, intent: "First", minutes: 25)
        controller.end(reason: .endedEarly)
        coordinator.calls.removeAll()
        let second = controller.start(goal: nil, intent: "Second", minutes: 25)

        guard case let .start(snapshot)? = coordinator.calls.first else {
            Issue.record("expected a start call")
            return
        }
        #expect(snapshot.sessionID == second.id)
        #expect(snapshot.intent == "Second")
    }
}
