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
        let block = PlanBlock(
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
}
#endif
