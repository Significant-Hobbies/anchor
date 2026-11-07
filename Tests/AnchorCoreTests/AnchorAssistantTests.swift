#if !os(watchOS)
@testable import AnchorCore
import Foundation
import Darwin
import PersonalSyncKit
import SwiftData
import Testing

@Suite("Assistant consent and native commands", .serialized)
@MainActor
struct AnchorAssistantTests {
    @Test("Planner consent defaults off, binds one account, retains ownership when stopped")
    func consent() async throws {
        let fixture = try SyncFixture(); defer { fixture.cleanUp() }
        #expect(!fixture.sync.isPlannerSharingEnabled)
        let goal = Goal(title: "Shared goal"); goal.keywords = ["PRIVATE LEARNED WORD"]
        fixture.context.insert(goal)
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        #expect(await fixture.sync.setPlannerSharingEnabled(true))
        #expect(fixture.sync.isPlannerSharingEnabled)
        let store = HubPlannerSharingStore(directory: fixture.directory)
        let state = try #require(try store.load())
        let names = state.names
        #expect(names == [AnchorMirrorNaming.Kind.goal.name(for: goal.id)])
        let projected = try AnchorMirror.records(in: fixture.context, tombstonesFor: [], hubAccountID: "stable-A", plannerNames: names)
        #expect(projected.count == 1)
        #expect(!String(decoding: projected[0].payload!, as: UTF8.self).contains("PRIVATE LEARNED"))
        #expect(try AnchorMirror.records(in: fixture.context, tombstonesFor: [], hubAccountID: "stable-A").isEmpty)
        #expect(await fixture.sync.setPlannerSharingEnabled(false))
        #expect(!fixture.sync.isPlannerSharingEnabled)
        #expect(try store.load()?.names == names)
        await fixture.signIn("B")
        #expect(!(await fixture.sync.setPlannerSharingEnabled(true)))
        #expect(try store.load()?.owner == "stable-A")
    }

    @Test("Only this UI context's actual new insertions inherit enabled account consent")
    func insertionProvenance() async throws {
        let fixture = try SyncFixture(); defer { fixture.cleanUp() }
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        #expect(await fixture.sync.setPlannerSharingEnabled(true))
        let local = Goal(title: "Created here"); fixture.context.insert(local)
        try fixture.context.save()
        let store = HubPlannerSharingStore(directory: fixture.directory)
        #expect(try store.load()?.names.contains(AnchorMirrorNaming.Kind.goal.name(for: local.id)) == true)
        let otherContext = ModelContext(fixture.container)
        let imported = Goal(title: "Other context/import")
        otherContext.insert(imported); try otherContext.save()
        fixture.sync.refreshImportedModels()
        #expect(try store.load()?.names.contains(AnchorMirrorNaming.Kind.goal.name(for: imported.id)) == false)
        #expect(await fixture.sync.setPlannerSharingEnabled(false))
        let stopped = Goal(title: "After stopping"); fixture.context.insert(stopped); try fixture.context.save()
        #expect(try store.load()?.names.contains(AnchorMirrorNaming.Kind.goal.name(for: stopped.id)) == false)
    }

    @Test("Every planner envelope roundtrips with account validation and local private fields preserved")
    func plannerRoundtrip() throws {
        let source = try SyncFixture(); defer { source.cleanUp() }
        let c = source.context
        let goal = Goal(title: "Ship"); goal.keywords = ["PRIVATE"]
        c.insert(goal); c.insert(Project(name: "Product")); c.insert(SavedTag(name: "Writing"))
        c.insert(AnchorPreferences()); c.insert(BehaviorProfile())
        let template = ScheduleTemplate(title: "Habit", startMinutesFromMidnight: 600, plannedSeconds: 600); c.insert(template)
        c.insert(HabitCompletion(habitID: template.id, day: .now))
        c.insert(DayPlanConfirmation(day: .now, decision: .later))
        let block = PlanBlock(title: "Build", plannedStart: .now, plannedSeconds: 600)
        block.externalEventKey = "PRIVATE-CALENDAR"; block.reminderExternalIdentifier = "PRIVATE-REMINDER"; c.insert(block)
        let event = DivergenceEvent(blockID: block.id, kind: .unknown, note: "PRIVATE NOTE"); c.insert(event)
        try c.save()
        let names = Set(try AnchorMirror.records(in: c, tombstonesFor: []).map(\.name))
        let records = try AnchorMirror.records(in: c, tombstonesFor: [], hubAccountID: "A", plannerNames: names)
        #expect(records.count == 10)
        let wire = records.map { String(decoding: $0.payload!, as: UTF8.self) }.joined()
        #expect(!wire.contains("PRIVATE"))
        let destination = try SyncFixture(); defer { destination.cleanUp() }
        #expect(try AnchorMirror.apply(records, in: destination.context, account: "A", plannerNames: names))
        #expect(try destination.context.fetch(FetchDescriptor<Goal>()).first?.title == "Ship")
        #expect(try destination.context.fetch(FetchDescriptor<PlanBlock>()).first?.externalEventKey == nil)
        #expect(throws: (any Error).self) { try AnchorMirror.apply(records, in: destination.context, account: "B", plannerNames: names) }
        let before = goal.keywords
        #expect(try AnchorMirror.apply(records, in: c, account: "A", plannerNames: names))
        #expect(goal.keywords == before)
        #expect(block.externalEventKey == "PRIVATE-CALENDAR")
    }

    @Test("Account imports refresh held planner models across real persistent contexts")
    func heldPlannerReadback() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "anchor-planner-readback-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try SyncFixture(storeURL: directory.appending(path: "planner.store")); defer { fixture.cleanUp() }
        let goal = Goal(title: "Before"); fixture.context.insert(goal)
        let block = PlanBlock(title: "Before", plannedStart: .now, plannedSeconds: 600); fixture.context.insert(block)
        try fixture.context.save()
        let names: Set<String> = [AnchorMirrorNaming.Kind.goal.name(for: goal.id), AnchorMirrorNaming.Kind.planBlock.name(for: block.id)]
        var records = try AnchorMirror.records(in: fixture.context, tombstonesFor: [], hubAccountID: "A", plannerNames: names)
        for i in records.indices {
            var json = try #require(try JSONSerialization.jsonObject(with: records[i].payload!) as? [String: Any])
            json["title"] = "After"
            records[i].payload = try JSONSerialization.data(withJSONObject: json)
        }
        let isolated = ModelContext(fixture.container)
        #expect(try AnchorMirror.apply(records, in: isolated, account: "A", plannerNames: names))
        fixture.sync.refreshImportedModels()
        #expect(goal.title == "After")
        #expect(block.title == "After")
        let deletion = MirrorRecord(name: AnchorMirrorNaming.Kind.planBlock.name(for: block.id), modifiedAt: .now, payload: nil, hubOwnerID: "A")
        #expect(try AnchorMirror.apply([deletion], in: isolated, account: "A", plannerNames: names))
        fixture.sync.refreshImportedModels()
        #expect(try fixture.context.fetch(FetchDescriptor<PlanBlock>()).isEmpty)
    }

    @Test("Actual Worker-created planner records decode and apply through the native account boundary")
    func backendWireCompatibility() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/AssistantBackendRecords.json")
        let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let entries = try #require(root["records"] as? [[String: Any]])
        let records = try entries.map { entry in
            MirrorRecord(name: try #require(entry["name"] as? String), modifiedAt: .now,
                         payload: try JSONSerialization.data(withJSONObject: try #require(entry["payload"])), hubOwnerID: "A")
        }
        let fixture = try SyncFixture(); defer { fixture.cleanUp() }
        #expect(try AnchorMirror.apply(records, in: fixture.context, account: "A", plannerNames: Set(records.map(\.name))))
        #expect(try fixture.context.fetch(FetchDescriptor<Goal>()).first?.title == "Build")
        let block = try #require(try fixture.context.fetch(FetchDescriptor<PlanBlock>()).first)
        #expect(block.plannedSeconds == 1800)
        #expect(abs(block.plannedStart.timeIntervalSince1970.truncatingRemainder(dividingBy: 1) - 0.123) < 0.0001)
        let projected = try AnchorMirror.records(in: fixture.context, tombstonesFor: [], hubAccountID: "A", plannerNames: Set(records.map(\.name)))
        let projectedBlock = try #require(projected.first { $0.name.hasPrefix("planblock-") }?.payload)
        let projectedJSON = try #require(try JSONSerialization.jsonObject(with: projectedBlock) as? [String: Any])
        #expect(projectedJSON["plannedStart"] as? String == "2026-11-08T10:00:00.123Z")
        #expect(try fixture.context.fetch(FetchDescriptor<ScheduleTemplate>()).first?.weekdayMask == 31)
        #expect(try fixture.context.fetch(FetchDescriptor<AnchorPreferences>()).first?.appearanceRaw == "dark")
    }

    func command(_ action: AnchorAgentCommand.Action, session: UUID? = nil, device: String = "device", now: Date = .now) -> AnchorAgentCommand {
        .init(id: UUID(), requestId: UUID().uuidString, action: action, targetDeviceId: device,
              issuedAt: now, expiresAt: now.addingTimeInterval(300), expectedSessionID: session, status: .pending,
              args: .init(intent: action == .start ? "Synthetic focus" : nil, minutes: action == .start ? 25 : nil))
    }
    func record(_ command: AnchorAgentCommand, owner: String = "A") throws -> MirrorRecord {
        MirrorRecord(name: command.recordName, modifiedAt: .now, payload: try AnchorAgentCommand.encoder.encode(command), hubOwnerID: owner)
    }

    @Test("Commands use the live controller, resume opens capture, durable replay never executes twice")
    func liveCommands() throws {
        let fixture = try SyncFixture(); defer { fixture.cleanUp() }
        let controller = FocusController(context: fixture.context, hubOwner: { "A" })
        let store = AnchorAgentCommandStore(directory: fixture.directory)
        func execute(_ command: AnchorAgentCommand) throws -> AnchorAgentCommand {
            try store.ingest([record(command)], owner: "A", deviceID: "device")
            try store.reconcile(owner: "A", deviceID: "device", controller: controller, context: fixture.context, approvedPlannerNames: [])
            return try #require(try store.load(owner: "A").commands[command.id.uuidString])
        }
        let start = command(.start)
        #expect(try execute(start).status == .applied)
        let session = try #require(controller.session)
        #expect(try execute(start).result?.sessionID == session.id)
        #expect(try fixture.context.fetch(FetchDescriptor<FocusSession>()).count == 1)
        #expect(try execute(command(.pause, session: session.id)).status == .applied)
        #expect(controller.isPaused)
        #expect(try execute(command(.resume, session: session.id)).result?.capturePresented == true)
        #expect(controller.isRunning)
        controller.dismissCapture() // Free decline remains available.
        #expect(try execute(command(.capture, session: session.id)).status == .applied)
        #expect(controller.parked.isEmpty)
        #expect(try execute(command(.end, session: session.id)).status == .applied)
        #expect(!controller.hasSession)
    }

    @Test("Expired, wrong-session, other-device and foreign-account commands cannot change focus")
    func commandGuards() throws {
        let fixture = try SyncFixture(); defer { fixture.cleanUp() }
        let controller = FocusController(context: fixture.context, hubOwner: { "A" })
        let store = AnchorAgentCommandStore(directory: fixture.directory)
        var expired = command(.start); expired.issuedAt = .now.addingTimeInterval(-600); expired.expiresAt = .now.addingTimeInterval(-300)
        let wrong = command(.pause, session: UUID())
        let foreignDevice = command(.start, device: "elsewhere")
        try store.ingest([record(expired), record(wrong), record(foreignDevice)], owner: "A", deviceID: "device")
        try store.reconcile(owner: "A", deviceID: "device", controller: controller, context: fixture.context, approvedPlannerNames: [])
        let values = try store.load(owner: "A").commands
        #expect(values[expired.id.uuidString]?.status == .failed)
        #expect(values[wrong.id.uuidString]?.status == .failed)
        #expect(values[foreignDevice.id.uuidString] == nil)
        #expect(!controller.hasSession)
        #expect(throws: (any Error).self) { try store.ingest([record(command(.start), owner: "B")], owner: "A", deviceID: "device") }
    }

    @Test("Planner commands call the native day service and replay cannot duplicate copied blocks")
    func plannerCommands() async throws {
        let fixture = try SyncFixture(); defer { fixture.cleanUp() }
        let sourceDay = ISO8601DateFormatter().date(from: "2026-11-09T12:00:00Z")!
        let targetDay = sourceDay.addingTimeInterval(86_400)
        let block = PlanBlock(title: "Authored", plannedStart: sourceDay, plannedSeconds: 1800)
        fixture.context.insert(block)
        let template = ScheduleTemplate(title: "Usual", startMinutesFromMidnight: 540, plannedSeconds: 600)
        fixture.context.insert(template)
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        #expect(await fixture.sync.setPlannerSharingEnabled(true))
        let store = AnchorAgentCommandStore(directory: fixture.directory)
        let controller = FocusController(context: fixture.context, hubOwner: { "stable-A" })
        func execute(_ command: AnchorAgentCommand) throws -> AnchorAgentCommand {
            try store.ingest([record(command, owner: "stable-A")], owner: "stable-A", deviceID: "device")
            let names = try #require(try HubPlannerSharingStore(directory: fixture.directory).load()).names
            try store.reconcile(owner: "stable-A", deviceID: "device", controller: controller, context: fixture.context, approvedPlannerNames: names)
            return try #require(try store.load(owner: "stable-A").commands[command.id.uuidString])
        }
        var copy = command(.copyDay)
        copy.args = .init(sourceDay: sourceDay, targetDay: targetDay, timeZone: "UTC")
        let copied = try execute(copy)
        #expect(copied.status == .applied)
        #expect(copied.result?.affectedRecordIDs?.count == 1)
        #expect(try execute(copy).result == copied.result)
        #expect(try fixture.context.fetch(FetchDescriptor<PlanBlock>()).count == 2)
        var materialize = command(.materializeDay)
        materialize.args = .init(day: targetDay, timeZone: "UTC")
        #expect(try execute(materialize).status == .applied)
        let made = try fixture.context.fetch(FetchDescriptor<PlanBlock>()).first { $0.templateID == template.id }
        #expect(made != nil)
        template.title = "Updated"; try fixture.context.save()
        var reconcile = command(.reconcileTemplate)
        reconcile.args = .init(timeZone: "UTC", templateID: template.id, from: sourceDay)
        #expect(try execute(reconcile).status == .applied)
        #expect(made?.title == "Updated")
    }

    @Test("Planner command failure preserves unsaved local drafts")
    func plannerDraftGuard() throws {
        let fixture = try SyncFixture(); defer { fixture.cleanUp() }
        let draft = Goal(title: "Unsaved draft"); fixture.context.insert(draft)
        var copy = command(.copyDay)
        copy.args = .init(sourceDay: .now, targetDay: .now.addingTimeInterval(86_400), timeZone: "UTC")
        let store = AnchorAgentCommandStore(directory: fixture.directory)
        try store.ingest([record(copy)], owner: "A", deviceID: "device")
        let controller = FocusController(context: fixture.context, hubOwner: { "A" })
        try store.reconcile(owner: "A", deviceID: "device", controller: controller, context: fixture.context, approvedPlannerNames: [])
        #expect(try store.load(owner: "A").commands[copy.id.uuidString]?.status == .failed)
        #expect(fixture.context.hasChanges)
        #expect(draft.title == "Unsaved draft")
    }

    @Test("A second process cannot race a durable command claim")
    func commandFileLock() throws {
        let fixture = try SyncFixture(); defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
        let store = AnchorAgentCommandStore(directory: fixture.directory)
        let descriptor = open(store.fileURL.appendingPathExtension("lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        #expect(descriptor >= 0)
        defer { close(descriptor) }
        #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        defer { _ = flock(descriptor, LOCK_UN) }
        #expect(throws: (any Error).self) { try store.ingest([record(command(.start))], owner: "A", deviceID: "device") }
        #expect(try store.load(owner: "A").commands.isEmpty)
    }

    @Test("Irrelevant commands skip before decoding and unsupported targeted records quarantine without content")
    func tolerantCommandIngest() throws {
        let fixture = try SyncFixture(); defer { fixture.cleanUp() }
        let store = AnchorAgentCommandStore(directory: fixture.directory)
        let unknown = UUID()
        func malformed(_ id: UUID, target: String, status: String = "pending") throws -> MirrorRecord {
            let payload: [String: Any] = ["recordType": "agentCommand", "id": id.uuidString,
                                         "targetDeviceId": target, "status": status, "action": "future_action",
                                         "args": ["note": "PRIVATE REJECTED CONTENT"]]
            return MirrorRecord(name: "agentcommand-" + id.uuidString.lowercased(), modifiedAt: .now,
                                payload: try JSONSerialization.data(withJSONObject: payload), hubOwnerID: "A")
        }
        let tombstone = MirrorRecord(name: "agentcommand-" + UUID().uuidString.lowercased(), modifiedAt: .now, payload: nil, hubOwnerID: "A")
        try store.ingest([tombstone, malformed(UUID(), target: "other-device"), malformed(UUID(), target: "device", status: "applied"),
                          malformed(unknown, target: "device")], owner: "A", deviceID: "device")
        let state = try store.load(owner: "A")
        #expect(state.commands.isEmpty)
        #expect(state.quarantinedIDs == [unknown.uuidString: "unsupportedOrMalformed"])
        #expect(!String(decoding: try Data(contentsOf: store.fileURL), as: UTF8.self).contains("PRIVATE REJECTED"))
    }

    func enqueue(_ record: MirrorRecord, fixture: SyncFixture, cursor: Int) async throws {
        let timestamp = ISO8601DateFormatter().string(from: .now.addingTimeInterval(60))
        let change: [String: Any] = ["cursor": cursor, "changeId": UUID().uuidString, "domain": "anchor", "id": record.name,
                                   "operation": record.payload == nil ? "delete" : "upsert", "version": cursor,
                                   "occurredAt": timestamp, "recordedAt": timestamp, "originDeviceId": "other-device",
                                   "record": try record.payload.map { try JSONSerialization.jsonObject(with: $0) } ?? NSNull()]
        try await fixture.server.enqueueRemote(String(decoding: JSONSerialization.data(withJSONObject: change), as: UTF8.self))
    }

    @Test("CloudKit-first planner collisions and unsupported commands do not block history or unrelated planner refresh")
    func cloudKitFirstAndMalformedCommand() async throws {
        let fixture = try SyncFixture(); defer { fixture.cleanUp() }
        let allowed = Goal(title: "Approved before")
        fixture.context.insert(allowed)
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        #expect(await fixture.sync.setPlannerSharingEnabled(true))
        let otherContext = ModelContext(fixture.container)
        let collided = Goal(title: "CloudKit first"); otherContext.insert(collided); try otherContext.save()
        fixture.sync.refreshImportedModels()
        let heldCollision = try #require(try fixture.context.fetch(FetchDescriptor<Goal>()).first { $0.id == collided.id })
        var allowedPayload = GoalPayload(allowed); allowedPayload.title = "Approved after"
        var collidedPayload = GoalPayload(collided); collidedPayload.title = "Remote title after approval"
        try await enqueue(MirrorRecord(name: AnchorMirrorNaming.Kind.goal.name(for: allowed.id), modifiedAt: .now,
                                       payload: AnchorAgentCommand.encoder.encode(allowedPayload)), fixture: fixture, cursor: 2)
        try await enqueue(MirrorRecord(name: AnchorMirrorNaming.Kind.goal.name(for: collided.id), modifiedAt: .now,
                                       payload: AnchorAgentCommand.encoder.encode(collidedPayload)), fixture: fixture, cursor: 3)
        let history = FocusSession(goal: nil, intent: "Other device completed", plannedSeconds: 60)
        history.state = .finished; history.runningSince = nil; history.bankedSeconds = 60; history.endedAt = .now; history.endReason = .completed
        try await enqueue(MirrorRecord(name: AnchorMirrorNaming.Kind.focusSession.name(for: history.id), modifiedAt: .now,
                                       payload: AnchorAgentCommand.encoder.encode(FocusSessionPayload(history))), fixture: fixture, cursor: 4)
        let badID = UUID()
        let bad: [String: Any] = ["recordType": "agentCommand", "id": badID.uuidString, "action": "future_action", "status": "pending", "targetDeviceId": "synthetic-device"]
        try await enqueue(MirrorRecord(name: "agentcommand-" + badID.uuidString.lowercased(), modifiedAt: .now,
                                       payload: JSONSerialization.data(withJSONObject: bad)), fixture: fixture, cursor: 5)
        await fixture.sync.synchronize()
        #expect(fixture.sync.receipt.failure == nil)
        #expect(fixture.sync.receipt.lastSuccessfulAt != nil)
        #expect(allowed.title == "Approved after")
        #expect(heldCollision.title == "CloudKit first")
        #expect(fixture.sync.plannerApprovalNotice != nil)
        #expect(fixture.sync.ownershipNotice == nil)
        #expect(!fixture.sync.needsHistoryApproval)
        #expect(try fixture.context.fetch(FetchDescriptor<FocusSession>()).contains { $0.id == history.id })
        #expect(try AnchorAgentCommandStore(directory: fixture.directory).load(owner: "stable-A").quarantinedIDs?[badID.uuidString] != nil)
        #expect(await fixture.sync.setPlannerSharingEnabled(true))
        await fixture.sync.synchronize()
        #expect(heldCollision.title == "Remote title after approval")
        #expect(await fixture.server.pulls.last?.cursor == 0)
    }

    @Test("A completed owned session arriving before CloudKit converges ends the held controller session")
    func completedSessionConvergence() async throws {
        let fixture = try SyncFixture(); defer { fixture.cleanUp() }
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        let controller = FocusController(context: fixture.context, hubOwner: { "stable-A" })
        fixture.sync.attachFocusController(controller)
        let session = try #require(controller.start(goal: nil, intent: "Two-device focus", minutes: 25))
        var finished = FocusSessionPayload(session)
        finished.stateRaw = "finished"; finished.runningSince = nil; finished.endedAt = .now; finished.bankedSeconds = 1500; finished.endReasonRaw = "completed"
        try await enqueue(MirrorRecord(name: AnchorMirrorNaming.Kind.focusSession.name(for: session.id), modifiedAt: .now,
                                       payload: AnchorAgentCommand.encoder.encode(finished)), fixture: fixture, cursor: 2)
        await fixture.sync.synchronize()
        #expect(fixture.sync.receipt.failure == nil)
        #expect(session.state == .finished)
        #expect(!controller.hasSession)
    }

    @Test("Emit a real native device wire fixture for backend interoperability")
    func nativeDeviceFixture() throws {
        guard let path = ProcessInfo.processInfo.environment["ANCHOR_NATIVE_DEVICE_FIXTURE_PATH"] else { return }
        let id = UUID(uuidString: "A1000000-0000-4000-8000-000000000001")!
        let session = FocusSession(id: UUID(uuidString: "B2000000-0000-4000-8000-000000000002")!, goal: nil, intent: "Synthetic native focus", plannedSeconds: 1500,
                                   startedAt: ISO8601DateFormatter().date(from: "2026-11-08T10:00:00Z")!)
        let observed = ISO8601DateFormatter().date(from: "2026-11-08T10:05:00Z")!
        let device = AnchorAgentDevice(id: id, deviceId: id.uuidString.lowercased(), platform: "macOS", updatedAt: observed,
                                      observedAt: observed, session: .init(session), activeSessionID: session.id, state: "running", capturePresented: false)
        let data = try AnchorAgentCommand.encoder.encode(device)
        let output: [String: Any] = ["name": "agentdevice-" + id.uuidString.lowercased(), "payload": try JSONSerialization.jsonObject(with: data)]
        try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path))
    }

    @Test("Stopping and re-enabling planner consent cannot resurrect queued focus actions")
    func consentEpochRejectsOldPending() async throws {
        let fixture = try SyncFixture(); defer { fixture.cleanUp() }
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        #expect(await fixture.sync.setPlannerSharingEnabled(true))
        let consentStore = HubPlannerSharingStore(directory: fixture.directory)
        let firstEpoch = try #require(try consentStore.load()?.enabledAt)
        let store = AnchorAgentCommandStore(directory: fixture.directory)
        let old = command(.start)
        // Queue before disabling, but do not execute it.
        try store.ingest([record(old, owner: "stable-A")], owner: "stable-A", deviceID: "device")
        #expect(await fixture.sync.setPlannerSharingEnabled(false))
        #expect(await fixture.sync.setPlannerSharingEnabled(true))
        let nextEpoch = try #require(try consentStore.load()?.enabledAt)
        #expect(nextEpoch > firstEpoch)
        let controller = FocusController(context: fixture.context, hubOwner: { "stable-A" })
        #expect(nextEpoch > old.issuedAt)
        try store.reconcile(owner: "stable-A", deviceID: "device", controller: controller, context: fixture.context,
                            approvedPlannerNames: [], consentEnabledAt: nextEpoch)
        #expect(try store.load(owner: "stable-A").commands[old.id.uuidString]?.status == .failed)
        #expect(!controller.hasSession)
        let fresh = command(.start, now: nextEpoch.addingTimeInterval(0.01))
        try store.ingest([record(fresh, owner: "stable-A")], owner: "stable-A", deviceID: "device")
        try store.reconcile(owner: "stable-A", deviceID: "device", controller: controller, context: fixture.context,
                            approvedPlannerNames: [], consentEnabledAt: nextEpoch)
        #expect(try store.load(owner: "stable-A").commands[fresh.id.uuidString]?.status == .applied)
        #expect(controller.hasSession)
        // Terminal failure and replay protection survive another toggle.
        #expect(await fixture.sync.setPlannerSharingEnabled(false))
        #expect(await fixture.sync.setPlannerSharingEnabled(true))
        try store.ingest([record(old, owner: "stable-A")], owner: "stable-A", deviceID: "device")
        #expect(try store.load(owner: "stable-A").commands[old.id.uuidString]?.status == .failed)
    }

    @Test("Valid uppercase UUID command targets route to the stable lowercase native device ID")
    func uppercaseDeviceTarget() throws {
        let fixture = try SyncFixture(); defer { fixture.cleanUp() }
        let deviceID = "a1000000-0000-4000-8000-000000000001"
        let store = AnchorAgentCommandStore(directory: fixture.directory)
        let start = command(.start, device: deviceID.uppercased())
        try store.ingest([record(start)], owner: "A", deviceID: deviceID)
        let controller = FocusController(context: fixture.context, hubOwner: { "A" })
        try store.reconcile(owner: "A", deviceID: deviceID, controller: controller, context: fixture.context, approvedPlannerNames: [])
        #expect(try store.load(owner: "A").commands[start.id.uuidString]?.status == .applied)
        #expect(controller.hasSession)
        let other = command(.start, device: "SYNTHETIC-DEVICE")
        try store.ingest([record(other)], owner: "A", deviceID: "synthetic-device")
        #expect(try store.load(owner: "A").commands[other.id.uuidString] == nil)
    }

    @Test("Actual Worker command timestamps with milliseconds decode without losing epoch ordering")
    func backendCommandMilliseconds() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/WorkerAgentCommand.json")
        let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let payload = try #require(root["payload"] as? [String: Any])
        let issuedAt = try #require(payload["issuedAt"] as? String)
        #expect(issuedAt.contains("."))
        let record = MirrorRecord(name: try #require(root["name"] as? String), modifiedAt: .now,
                                  payload: try JSONSerialization.data(withJSONObject: payload), hubOwnerID: "A")
        let value = try AnchorAgentCommand.decode(record)
        let reencoded = try AnchorAgentCommand.encoder.encode(value)
        #expect(try AnchorAgentCommand.decoder.decode(AnchorAgentCommand.self, from: reencoded).issuedAt == value.issuedAt)
        #expect(value.expiresAt > value.issuedAt)
        #expect(value.action == .pause)
    }

    @Test("A failed focus save reports failure and a durable claim prevents replay")
    func failedSave() throws {
        struct Failure: Error {}
        let fixture = try SyncFixture(); defer { fixture.cleanUp() }
        let controller = FocusController(context: fixture.context, hubOwner: { "A" }, persistContext: { _ in throw Failure() })
        let store = AnchorAgentCommandStore(directory: fixture.directory)
        let start = command(.start)
        try store.ingest([record(start)], owner: "A", deviceID: "device")
        try store.reconcile(owner: "A", deviceID: "device", controller: controller, context: fixture.context, approvedPlannerNames: [])
        #expect(try store.load(owner: "A").commands[start.id.uuidString]?.status == .failed)
        #expect(!controller.hasSession)
        try store.ingest([record(start)], owner: "A", deviceID: "device")
        #expect(try store.load(owner: "A").commands[start.id.uuidString]?.status == .failed)
    }
}
#endif
