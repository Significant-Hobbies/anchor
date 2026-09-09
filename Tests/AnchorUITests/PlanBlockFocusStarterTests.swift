#if os(macOS)
import AnchorCore
import Foundation
import SwiftData
import Testing
@testable import AnchorUI

@Suite("Scheduled focus handoff")
@MainActor
struct PlanBlockFocusStarterTests {
    @Test("A mini-timer start remains linked to the planned block")
    func startLinksSessionToPlan() throws {
        let container = try AnchorStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        let project = Project(name: "Utility")
        context.insert(project)
        let block = PlanBlock(
            projectID: project.id,
            title: "Review the launch",
            details: "Resolve the final decisions.",
            plannedStart: Date(),
            plannedSeconds: 1_800,
            kind: .focus,
            flexibility: .flexible
        )
        context.insert(block)
        try context.save()

        let controller = FocusController(context: context)
        try PlanBlockFocusStarter.start(
            block,
            controller: controller,
            context: context
        )

        #expect(controller.hasSession)
        #expect(block.state == PlanBlockState.inProgress)
        #expect(block.actualStartedAt != nil)
        #expect(block.sessionID == controller.session?.id)
        #expect(controller.session?.intent == "Review the launch")
        #expect(controller.session?.notes == "Resolve the final decisions.")
        #expect(controller.session?.project?.id == project.id)
        controller.end()
    }

    @Test("Starting different work preserves the plan and records the replan")
    func startDifferentWorkRecordsReplan() throws {
        let container = try AnchorStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        let block = PlanBlock(
            title: "Review the launch",
            plannedStart: Date(),
            plannedSeconds: 1_800,
            kind: .focus,
            flexibility: .flexible
        )
        context.insert(block)
        try context.save()

        let controller = FocusController(context: context)
        try PlanBlockFocusStarter.start(
            block,
            intent: "Handle the outage",
            minutes: 15,
            controller: controller,
            context: context
        )

        let replans = try context.fetch(FetchDescriptor<DivergenceEvent>())
        #expect(controller.session?.intent == "Handle the outage")
        #expect(controller.session?.plannedSeconds == 900)
        #expect(block.sessionID == controller.session?.id)
        #expect(replans.count == 1)
        #expect(replans.first?.kind == DivergenceKind.deliberateReplan)
        #expect(replans.first?.blockID == block.id)
        #expect(replans.first?.sessionID == controller.session?.id)
    }
    @Test("A failed timer creation cannot attach or replan the scheduled block")
    func failedStartLeavesScheduleUntouched() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("anchor-start-caller-\(UUID())/fixture.store")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let context = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        context.autosaveEnabled = false
        let block = PlanBlock(title: "Original plan", plannedStart: Date(), plannedSeconds: 900, kind: .focus, flexibility: .flexible)
        context.insert(block)
        try context.save()
        let controller = FocusController(context: context, tagger: TaggingService(allowsOnDeviceModel: false), persistContext: { _ in throw CocoaError(.fileWriteOutOfSpace) })
        #expect(throws: PlanBlockFocusStarter.StartFailure.persistence) {
            try PlanBlockFocusStarter.start(block, intent: "Changed activity", controller: controller, context: context)
        }
        #expect(!controller.hasSession && block.sessionID == nil && block.actualStartedAt == nil)
        #expect(block.state == .planned && block.title == "Original plan")
        try context.save()
        let reopened = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        #expect(try reopened.fetch(FetchDescriptor<FocusSession>()).isEmpty)
        #expect(try reopened.fetch(FetchDescriptor<DivergenceEvent>()).isEmpty)
        #expect(try reopened.fetch(FetchDescriptor<PlanBlock>()).first?.sessionID == nil)
    }

    @Test("Composer retains the complete draft and only removes its own transient goal", arguments: [false, true])
    func failedComposerPreservesDraftAndRetries(existingGoal: Bool) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("anchor-start-draft-\(UUID())/fixture.store")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let context = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        context.autosaveEnabled = false
        let goal = Goal(title: "Existing goal")
        let project = Project(name: "Synthetic project")
        context.insert(goal)
        context.insert(project)
        try context.save()
        @MainActor final class FailurePlan { var enabled = true }
        let failure = FailurePlan()
        let controller = FocusController(context: context, tagger: TaggingService(allowsOnDeviceModel: false), persistContext: { context in
            if failure.enabled { throw CocoaError(.fileWriteOutOfSpace) }
            try AnchorStore.save(context)
        })
        var draft = StartComposerDraft(intent: " Draft work ", notes: "Context", selectedGoalID: existingGoal ? goal.id : nil, selectedProjectID: project.id, selectedTagIDs: ["synthetic"])
        let before = draft
        let start: (Goal?, String, Int, Project?, String, [String]) -> Bool = { goal, intent, minutes, project, notes, tags in
            controller.start(goal: goal, intent: intent, minutes: minutes, project: project, notes: notes, tagIDStrings: tags) != nil
        }
        for _ in 0..<2 {
            let started = draft.submit(selectedGoal: existingGoal ? goal : nil, selectedProject: project, minutes: 25, goalTintIndex: 0, context: context, onStart: start)
            #expect(!started)
            #expect(draft == before && !controller.hasSession)
        }
        // Persist unrelated work, proving failed-created goals and sessions stay absent.
        try context.save()
        let failedReopen = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        let goals = try failedReopen.fetch(FetchDescriptor<Goal>())
        #expect(goals.count == 1 && goals.first?.id == goal.id)
        #expect(try failedReopen.fetch(FetchDescriptor<FocusSession>()).isEmpty)
        failure.enabled = false
        let started = draft.submit(selectedGoal: existingGoal ? goal : nil, selectedProject: project, minutes: 25, goalTintIndex: 0, context: context, onStart: start)
        #expect(started)
        #expect(draft == StartComposerDraft())
        let reopened = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        let sessions = try reopened.fetch(FetchDescriptor<FocusSession>())
        #expect(sessions.count == 1 && sessions.first?.intent == "Draft work")
        #expect(sessions.first?.project?.id == project.id && sessions.first?.notes == "Context")
        #expect(sessions.first?.tagIDStrings == ["synthetic"])
        #expect(try reopened.fetchCount(FetchDescriptor<Goal>()) == (existingGoal ? 1 : 2))
        controller.end()
    }

    @Test("Session, schedule link and deliberate replan commit once or roll back together")
    func scheduledTransactionRollbackRetryAndReopen() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("anchor-atomic-link-\(UUID())/fixture.store")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let context = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        context.autosaveEnabled = false
        let project = Project(name: "Synthetic project")
        context.insert(project)
        let block = PlanBlock(projectID: project.id, title: "Authored plan", details: "Preserve entry context", plannedStart: Date(), plannedSeconds: 900, kind: .focus, flexibility: .flexible)
        context.insert(block)
        try context.save()
        let updatedAt = block.updatedAt
        @MainActor final class Writes { var fail = true; var count = 0 }
        let writes = Writes()
        let controller = FocusController(context: context, tagger: TaggingService(allowsOnDeviceModel: false), persistContext: { context in
            writes.count += 1
            // All three mutations must already participate in this one save.
            #expect(block.sessionID != nil && block.state == .inProgress)
            #expect(try context.fetchCount(FetchDescriptor<FocusSession>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<DivergenceEvent>()) == 1)
            if writes.fail { throw CocoaError(.fileWriteOutOfSpace) }
            try AnchorStore.save(context)
        })
        for _ in 0..<2 {
            #expect(throws: PlanBlockFocusStarter.StartFailure.persistence) {
                try PlanBlockFocusStarter.start(block, intent: "Changed work", controller: controller, context: context)
            }
            #expect(!controller.hasSession && block.sessionID == nil && block.actualStartedAt == nil)
            #expect(block.state == .planned && block.updatedAt == updatedAt && block.title == "Authored plan")
        }
        #expect(writes.count == 2)
        try context.save() // Unrelated later save must not revive failed objects.
        let failed = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        #expect(try failed.fetch(FetchDescriptor<FocusSession>()).isEmpty)
        #expect(try failed.fetch(FetchDescriptor<DivergenceEvent>()).isEmpty)
        #expect(try failed.fetch(FetchDescriptor<PlanBlock>()).first?.state == .planned)
        writes.fail = false
        try PlanBlockFocusStarter.start(block, intent: "Changed work", controller: controller, context: context)
        #expect(writes.count == 3 && controller.isRunning)
        try PlanBlockFocusStarter.start(block, intent: "Changed work", controller: controller, context: context)
        #expect(writes.count == 3) // No end/save/replan/notification on double invocation.
        let reopened = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        let saved = try #require(reopened.fetch(FetchDescriptor<FocusSession>()).first)
        let savedBlock = try #require(reopened.fetch(FetchDescriptor<PlanBlock>()).first)
        let replans = try reopened.fetch(FetchDescriptor<DivergenceEvent>())
        #expect(try reopened.fetchCount(FetchDescriptor<FocusSession>()) == 1)
        #expect(savedBlock.sessionID == saved.id && savedBlock.actualStartedAt == saved.startedAt && savedBlock.state == .inProgress)
        #expect(saved.project?.id == project.id && saved.notes == block.details && saved.intent == "Changed work")
        #expect(replans.count == 1 && replans.first?.sessionID == saved.id && replans.first?.blockID == block.id)
        #expect(replans.first?.note == "Did Changed work instead of Authored plan.")
        controller.end()
    }

    @Test("Another block or a stale link cannot reuse the active session")
    func activeLinkIdempotencyUsesExactSession() throws {
        let context = ModelContext(try AnchorStore.makeContainer(kind: .inMemory))
        context.autosaveEnabled = false
        let a = PlanBlock(title: "First", plannedStart: Date(), plannedSeconds: 900, kind: .focus, flexibility: .flexible)
        let b = PlanBlock(title: "Second", plannedStart: Date(), plannedSeconds: 900, kind: .focus, flexibility: .flexible)
        let c = PlanBlock(title: "Stale", plannedStart: Date(), plannedSeconds: 900, kind: .focus, flexibility: .flexible)
        for block in [a,b,c] { context.insert(block) }
        try context.save()
        let controller = FocusController(context: context, tagger: TaggingService(allowsOnDeviceModel: false))
        try PlanBlockFocusStarter.start(a, controller: controller, context: context)
        let first = try #require(controller.session)
        try PlanBlockFocusStarter.start(a, controller: controller, context: context)
        #expect(controller.session?.id == first.id)
        try PlanBlockFocusStarter.start(b, controller: controller, context: context)
        let second = try #require(controller.session)
        #expect(second.id != first.id && first.state == .finished && b.sessionID == second.id)
        c.sessionID = first.id // A real previous ID, but not this active session.
        try context.save()
        try PlanBlockFocusStarter.start(c, controller: controller, context: context)
        #expect(controller.session?.id != second.id && controller.session?.id != first.id)
        #expect(c.sessionID == controller.session?.id && second.state == .finished)
        #expect(try context.fetchCount(FetchDescriptor<FocusSession>()) == 3)
        controller.end()
    }

    @Test("A failed scheduled replacement preserves the already committed earlier end")
    func failedScheduledReplacementKeepsHistory() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("anchor-link-history-\(UUID())/fixture.store")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let context = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        context.autosaveEnabled = false
        let block = PlanBlock(title: "Next plan", plannedStart: Date(), plannedSeconds: 900, kind: .focus, flexibility: .flexible)
        context.insert(block)
        try context.save()
        let controller = FocusController(context: context, tagger: TaggingService(allowsOnDeviceModel: false), persistContext: { context in
            if block.sessionID != nil { throw CocoaError(.fileWriteOutOfSpace) }
            try AnchorStore.save(context)
        })
        let previous = try #require(controller.start(goal: nil, intent: "Previous work", minutes: 25))
        #expect(throws: PlanBlockFocusStarter.StartFailure.persistence) {
            try PlanBlockFocusStarter.start(block, controller: controller, context: context)
        }
        #expect(!controller.hasSession && block.sessionID == nil && block.state == .planned)
        try context.save()
        let reopened = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        let history = try reopened.fetch(FetchDescriptor<FocusSession>())
        #expect(history.count == 1 && history.first?.id == previous.id && history.first?.state == .finished)
        #expect(try reopened.fetch(FetchDescriptor<PlanBlock>()).first?.sessionID == nil)
    }

    @Test("Changing the linked block's actual activity preserves deliberate replan semantics")
    func linkedBlockChangedActivityStartsNewSession() throws {
        let context = ModelContext(try AnchorStore.makeContainer(kind: .inMemory))
        context.autosaveEnabled = false
        let block = PlanBlock(title: "Original plan", plannedStart: Date(), plannedSeconds: 900, kind: .focus, flexibility: .flexible)
        context.insert(block)
        try context.save()
        let controller = FocusController(context: context, tagger: TaggingService(allowsOnDeviceModel: false))
        try PlanBlockFocusStarter.start(block, controller: controller, context: context)
        let original = try #require(controller.session)
        try PlanBlockFocusStarter.start(block, intent: " Handle outage ", minutes: 20, controller: controller, context: context)
        let changed = try #require(controller.session)
        #expect(changed.id != original.id && original.state == .finished)
        #expect(changed.intent == "Handle outage" && changed.plannedSeconds == 1200)
        #expect(block.title == "Original plan" && block.sessionID == changed.id)
        let replans = try context.fetch(FetchDescriptor<DivergenceEvent>())
        #expect(replans.count == 1 && replans.first?.sessionID == changed.id)
        try PlanBlockFocusStarter.start(block, intent: "Handle outage", minutes: 20, controller: controller, context: context)
        #expect(controller.session?.id == changed.id)
        #expect(try context.fetchCount(FetchDescriptor<FocusSession>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<DivergenceEvent>()) == 1)
        controller.end()
    }

}
#endif
