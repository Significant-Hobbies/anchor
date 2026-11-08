#if !os(watchOS)
@testable import AnchorCore
import Foundation
import PersonalSyncKit
import SwiftData
import Testing

@Suite("Legacy finished-session synchronization", .serialized)
@MainActor
struct LegacyFinishedSessionSyncTests {
    @Test("Planner full repull accepts a finished session's stale end-time marker")
    func plannerRepullPreservesFinishedHistory() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        let session = historicalSession()
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        await fixture.sync.synchronize()
        #expect(fixture.sync.receipt.failure == nil)

        var legacy = FocusSessionPayload(session)
        legacy.hubAccountID = nil
        let payload = try JSONSerialization.jsonObject(with: AnchorAgentCommand.encoder.encode(legacy))
        let change: [String: Any] = [
            "cursor": 2, "changeId": "legacy-finished-marker", "domain": "anchor",
            "id": session.id.uuidString.lowercased(), "operation": "upsert", "version": 4,
            "occurredAt": "2026-08-30T21:28:27Z", "recordedAt": "2026-08-30T21:28:28Z",
            "originDeviceId": "old-device", "record": payload,
        ]
        try await fixture.server.enqueueRemote(String(decoding: JSONSerialization.data(withJSONObject: change), as: UTF8.self))
        let goal = Goal(title: "Planner after full repull")
        fixture.context.insert(goal)
        try fixture.context.save()
        #expect(await fixture.sync.setPlannerSharingEnabled(true))
        await fixture.sync.synchronize()

        #expect(fixture.sync.receipt.failure == nil)
        #expect(fixture.sync.pendingCount == 0)
        let imported = try #require(try fixture.context.fetch(FetchDescriptor<FocusSession>()).first)
        #expect(imported.state == .finished)
        #expect(imported.runningSince == nil)
        #expect(imported.focusedSeconds() == 0)
        #expect(imported.endedAt == session.endedAt)
        #expect(imported.hubAccountID == "stable-A")
        let goalName = AnchorMirrorNaming.Kind.goal.name(for: goal.id)
        #expect(await fixture.server.pushes.flatMap(\.mutations).contains { $0.id == goalName })
        await fixture.sync.synchronize()
        #expect(fixture.sync.receipt.failure == nil)
        #expect(try fixture.context.fetchCount(FetchDescriptor<FocusSession>()) == 1)
    }

    @Test("Only an ended finished session can clear the stale marker")
    func malformedAndForeignRecordsRemainRejected() throws {
        for variant in ["running", "missing-end", "different-marker", "backwards-end", "foreign-owner"] {
            let fixture = try SyncFixture()
            defer { fixture.cleanUp() }
            let session = historicalSession()
            var payload = FocusSessionPayload(session)
            payload.hubAccountID = "stable-A"
            switch variant {
            case "running": payload.stateRaw = "running"
            case "missing-end": payload.endedAt = nil
            case "different-marker": payload.runningSince = session.startedAt
            case "backwards-end":
                payload.endedAt = session.startedAt.addingTimeInterval(-1)
                payload.runningSince = payload.endedAt
            default: payload.hubAccountID = "stable-B"
            }
            let record = MirrorRecord(
                name: session.id.uuidString.lowercased(), modifiedAt: .now,
                payload: try AnchorAgentCommand.encoder.encode(payload), appendOnly: true
            )
            #expect(throws: (any Error).self) {
                try AnchorMirror.apply([record], in: fixture.context, account: "stable-A")
            }
            #expect(try fixture.context.fetchCount(FetchDescriptor<FocusSession>()) == 0)
        }
    }

    @Test("Hub exports canonicalize the marker without changing stored duration")
    func outgoingFinishedHistoryHasNoRunningMarker() throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        let session = historicalSession()
        session.hubAccountID = "stable-A"
        fixture.context.insert(session)
        let records = try AnchorMirror.records(in: fixture.context, tombstonesFor: [], hubAccountID: "stable-A")
        let record = try #require(records.first)
        let payload = try AnchorAgentCommand.decoder.decode(FocusSessionPayload.self, from: #require(record.payload))
        #expect(payload.runningSince == nil)
        #expect(payload.bankedSeconds == 0)
        #expect(payload.stateRaw == "finished")
        #expect(session.runningSince == session.endedAt)
        #expect(session.focusedSeconds() == 0)
    }

    private func historicalSession() -> FocusSession {
        let start = Date(timeIntervalSince1970: 1_788_117_780)
        let end = start.addingTimeInterval(7_527)
        let session = FocusSession(goal: nil, intent: "Synthetic legacy history", plannedSeconds: 60, startedAt: start)
        session.state = .finished
        session.endedAt = end
        session.runningSince = end
        session.bankedSeconds = 0
        session.endReason = .endedEarly
        return session
    }
}
#endif
