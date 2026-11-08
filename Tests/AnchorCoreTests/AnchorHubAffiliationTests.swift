#if !os(watchOS)
@testable import AnchorCore
import Foundation
import PersonalSyncKit
import SwiftData
import Testing

@Suite("Hub affiliation convergence", .serialized)
@MainActor
struct AnchorHubAffiliationTests {
    @Test("Native planner and history projections use the shared affiliation policy")
    func nativeProjectionParity() throws {
        let fixture = try SyncFixture(); defer { fixture.cleanUp() }
        let c = fixture.context
        c.insert(MachineActivityDay(day: .now, activeSeconds: 60, trackedSeconds: 120))
        c.insert(Goal(title: "Synthetic goal")); c.insert(Project(name: "Synthetic project"))
        c.insert(SavedTag(name: "Synthetic tag")); c.insert(AnchorPreferences()); c.insert(BehaviorProfile())
        let template = ScheduleTemplate(title: "Synthetic habit", startMinutesFromMidnight: 600, plannedSeconds: 600)
        c.insert(template); c.insert(HabitCompletion(habitID: template.id, day: .now))
        c.insert(DayPlanConfirmation(day: .now, decision: .later))
        let block = PlanBlock(title: "Synthetic block", plannedStart: .now, plannedSeconds: 600)
        c.insert(block); c.insert(DivergenceEvent(blockID: block.id, kind: .unknown))
        let session = fixture.addSession("Synthetic history"); session.hubAccountID = "stable-A"
        try c.save()
        let generic = try AnchorMirror.records(in: c, tombstonesFor: [])
        #expect(generic.allSatisfy { $0.hubOwnerID == nil })
        #expect(generic.contains { $0.name.hasPrefix("machineday-") && $0.hubOwnerID == nil })
        let plannerKinds = AnchorMirrorNaming.Kind.allCases.filter(\.isPlanner)
        let names = Set(generic.filter { AnchorMirrorNaming.kind(of: $0.name)?.isPlanner == true }.map(\.name))
        #expect(Set(names.compactMap(AnchorMirrorNaming.kind)) == Set(plannerKinds))
        let projected = try AnchorMirror.records(in: c, tombstonesFor: [], hubAccountID: "stable-A", plannerNames: names)
        for record in projected {
            #expect(record.hubOwnerID == AnchorHubAffiliation.owner(for: record.name, verifiedOwner: "stable-A"))
        }
        #expect(projected.contains { $0.name.hasPrefix("session-") && $0.hubOwnerID == nil })
        #expect(projected.contains { $0.name.hasPrefix("distraction-") && $0.hubOwnerID == nil })
        let tombstones = try AnchorMirror.records(in: ModelContext(try AnchorStore.makeContainer(kind: .inMemory)), tombstonesFor: [], hubAccountID: "stable-A", plannerNames: names)
        #expect(tombstones.count == plannerKinds.count)
        #expect(tombstones.allSatisfy { $0.payload == nil && $0.hubOwnerID == "stable-A" })
        for kind in AnchorMirrorNaming.Kind.allCases {
            #expect(AnchorHubAffiliation.requiresOwner(kind.name(for: UUID())) == kind.isPlanner)
        }
        for name in [UUID().uuidString, UUID().uuidString.lowercased(), "unknown-name", "machineday-invalid"] {
            #expect(!AnchorHubAffiliation.requiresOwner(name))
        }
        #expect(AnchorHubAffiliation.requiresOwner("savedtag-invalid"))
        let count = try c.fetchCount(FetchDescriptor<SavedTag>())
        _ = try AnchorMirror.apply([MirrorRecord(name: "savedtag-invalid", modifiedAt: .now, payload: nil, hubOwnerID: "stable-A")], in: c, account: "stable-A", plannerNames: ["savedtag-invalid"])
        #expect(try c.fetchCount(FetchDescriptor<SavedTag>()) == count)
    }

    @Test("Native command and device producers agree with the affiliation policy")
    func commandAndDeviceParity() async throws {
        let fixture = try SyncFixture(); defer { fixture.cleanUp() }
        let deviceID = UUID().uuidString.lowercased()
        let device = AnchorAgentDevice(id: UUID(uuidString: deviceID)!, deviceId: deviceID, platform: "macOS",
                                       updatedAt: .now, observedAt: .now, state: "idle", capturePresented: false)
        let deviceRecord = try device.record(owner: "stable-A")
        #expect(deviceRecord.hubOwnerID == AnchorHubAffiliation.owner(for: deviceRecord.name, verifiedOwner: "stable-A"))
        let sync = fixture.makeSync(deviceId: deviceID)
        let controller = FocusController(context: fixture.context)
        sync.attachFocusController(controller)
        await fixture.tokens.save("A"); await sync.account?.restore()
        #expect(await sync.approveHubHistory())
        #expect(await sync.setPlannerSharingEnabled(true))
        let command = AnchorAgentCommand(id: UUID(), requestId: UUID().uuidString, action: .start,
                                        targetDeviceId: deviceID, issuedAt: .now, expiresAt: .now.addingTimeInterval(300),
                                        status: .pending, args: .init(intent: "Synthetic command", minutes: 25))
        let store = AnchorAgentCommandStore(directory: fixture.directory)
        try store.ingest([MirrorRecord(name: command.recordName, modifiedAt: .now, payload: try AnchorAgentCommand.encoder.encode(command), hubOwnerID: "stable-A")], owner: "stable-A", deviceID: deviceID)
        let records = try store.records(owner: "stable-A")
        #expect(records.count == 1)
        #expect(records.allSatisfy { $0.hubOwnerID == AnchorHubAffiliation.owner(for: $0.name, verifiedOwner: "stable-A") })
        await sync.synchronize()
        let emittedDevice = try #require(await fixture.server.pushes.flatMap(\.mutations).first { $0.id.hasPrefix(AnchorHubAffiliation.devicePrefix) })
        #expect(AnchorHubAffiliation.requiresOwner(emittedDevice.id))
        #expect(AnchorHubAffiliation.requiresOwner(command.recordName))
    }

    @Test("Local planner writes settle after the accepted Hub echo and real edits and deletes propagate once")
    func localPlannerConvergence() async throws {
        let fixture = try SyncFixture(); defer { fixture.cleanUp() }
        await fixture.server.enableAcceptedEchoes()
        let tag = SavedTag(name: "Synthetic stable tag"); fixture.context.insert(tag); try fixture.context.save()
        let name = AnchorMirrorNaming.Kind.savedTag.name(for: tag.id)
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        #expect(await fixture.sync.setPlannerSharingEnabled(true))
        await fixture.sync.synchronize()
        #expect(await fixture.server.acceptedVersion(for: name) == 1)
        for _ in 0..<3 { await fixture.sync.synchronize() }
        #expect(await fixture.server.acceptedVersion(for: name) == 1)
        #expect(await fixture.server.pushes.flatMap(\.mutations).filter { $0.id == name }.count == 1)
        try await fixture.sync.runtime?.repullAll()
        await fixture.sync.synchronize()
        #expect(await fixture.server.acceptedVersion(for: name) == 1)
        tag.name = "Synthetic real edit"; try fixture.context.save()
        await fixture.sync.synchronize(); await fixture.sync.synchronize()
        #expect(await fixture.server.acceptedVersion(for: name) == 2)
        fixture.context.delete(tag); try fixture.context.save()
        await fixture.sync.synchronize(); await fixture.sync.synchronize(); await fixture.sync.synchronize()
        #expect(await fixture.server.acceptedVersion(for: name) == 3)
        let mutations = await fixture.server.pushes.flatMap(\.mutations).filter { $0.id == name }
        #expect(mutations.count == 3)
        #expect(mutations.last?.operation == .delete)
        #expect(fixture.sync.receipt.lastSuccessfulAt != nil)
    }

    @Test("Unchanged native command output settles after its accepted Hub echo")
    func commandConvergence() async throws {
        let fixture = try SyncFixture(); defer { fixture.cleanUp() }
        await fixture.server.enableAcceptedEchoes()
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        #expect(await fixture.sync.setPlannerSharingEnabled(true))
        let command = AnchorAssistantTests().command(.start, device: "synthetic-device")
        let store = AnchorAgentCommandStore(directory: fixture.directory)
        try store.ingest([AnchorAssistantTests().record(command, owner: "stable-A")], owner: "stable-A", deviceID: "synthetic-device")
        await fixture.sync.synchronize()
        #expect(await fixture.server.acceptedVersion(for: command.recordName) == 1)
        for _ in 0..<3 { await fixture.sync.synchronize() }
        try await fixture.sync.runtime?.repullAll()
        await fixture.sync.synchronize()
        #expect(await fixture.server.acceptedVersion(for: command.recordName) == 1)
        #expect(await fixture.server.pushes.flatMap(\.mutations).filter { $0.id == command.recordName }.count == 1)
    }

    @Test("Remote-first planner import rereads native state without uploading the unchanged record")
    func remoteFirstPlannerConvergence() async throws {
        let fixture = try SyncFixture(); defer { fixture.cleanUp() }
        await fixture.server.enableAcceptedEchoes()
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        #expect(await fixture.sync.setPlannerSharingEnabled(true))
        let remoteTime = Date.now.addingTimeInterval(60)
        let tag = SavedTag(name: "Synthetic remote tag")
        let name = AnchorMirrorNaming.Kind.savedTag.name(for: tag.id)
        let payload = try AnchorAgentCommand.encoder.encode(SavedTagPayload(tag))
        try await AnchorAssistantTests().enqueue(MirrorRecord(name: name, modifiedAt: .now, payload: payload), fixture: fixture, cursor: 101, occurredAt: remoteTime)
        await fixture.sync.synchronize()
        #expect(try fixture.context.fetch(FetchDescriptor<SavedTag>()).first?.name == "Synthetic remote tag")
        for _ in 0..<3 { await fixture.sync.synchronize() }
        #expect(await fixture.server.pushes.flatMap(\.mutations).filter { $0.id == name }.isEmpty)
        tag.name = "Synthetic remote edit"
        try await AnchorAssistantTests().enqueue(MirrorRecord(name: name, modifiedAt: .now, payload: try AnchorAgentCommand.encoder.encode(SavedTagPayload(tag))), fixture: fixture, cursor: 102, occurredAt: remoteTime.addingTimeInterval(1))
        await fixture.sync.synchronize(); await fixture.sync.synchronize()
        #expect(try fixture.context.fetch(FetchDescriptor<SavedTag>()).first?.name == "Synthetic remote edit")
        try await AnchorAssistantTests().enqueue(MirrorRecord(name: name, modifiedAt: .now, payload: nil), fixture: fixture, cursor: 103, occurredAt: remoteTime.addingTimeInterval(2))
        await fixture.sync.synchronize()
        #expect(try fixture.context.fetch(FetchDescriptor<SavedTag>()).isEmpty)
        for _ in 0..<3 { await fixture.sync.synchronize() }
        #expect(await fixture.server.pushes.flatMap(\.mutations).filter { $0.id == name }.isEmpty)
        #expect(fixture.sync.receipt.lastSuccessfulAt != nil)
    }
}
#endif
