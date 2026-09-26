#if !os(watchOS)
@testable import AnchorCore
import Foundation
import PersonalSyncKit
import SwiftData
import Synchronization
import Testing

@Suite("Account-scoped Hub transport", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct AnchorAccountSyncTests {
    @Test("Unchanged mirror payloads remain byte-stable across snapshots")
    func stableMirrorPayloads() throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        fixture.addSession("Synthetic deterministic snapshot")
        func payloads() throws -> [String: Data?] {
            Dictionary(uniqueKeysWithValues: try AnchorMirror.records(
                in: fixture.context, tombstonesFor: []
            ).map { ($0.name, $0.payload) })
        }
        let baseline = try payloads()
        for _ in 0..<100 { #expect(try payloads() == baseline) }
    }

    @Test("A delayed approval cannot overwrite a newer account's notice or claim its history")
    func ownedHistoryStaleApprovalPreservesNewAccount() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        let local = fixture.addSession("Synthetic unapproved history")
        await fixture.signIn("A")
        await fixture.server.holdPushes(for: "session-A")
        let approval = Task { await fixture.sync.approveHubHistory() }
        await fixture.server.waitUntilHeld("session-A")
        await fixture.signIn("B")
        await fixture.sync.synchronize()
        let notice = fixture.sync.ownershipNotice
        #expect(notice != nil)
        await fixture.server.release("session-A", status: 200)
        #expect(!(await approval.value))
        #expect(fixture.sync.ownershipNotice == notice)
        #expect(fixture.sync.account?.session?.userId == "stable-B")
        #expect(local.hubAccountID == nil)
        #expect(try HubHistoryOwnershipStore(directory: fixture.directory).owner() == nil)
        #expect(await fixture.server.pushes.isEmpty)
    }

    @Test("Session ownership survives reopening the real local SwiftData store")
    func ownedHistorySurvivesStoreReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "anchor-owner-store-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "history.store")
        let id = UUID()
        try autoreleasepool {
            let container = try AnchorStore.makeContainer(kind: .localOnly, url: url)
            let context = ModelContext(container)
            let session = FocusSession(id: id, goal: nil, plannedSeconds: 60)
            session.hubAccountID = "stable-A"
            context.insert(session)
            try context.save()
        }
        let reopened = try AnchorStore.makeContainer(kind: .localOnly, url: url)
        let records = try ModelContext(reopened).fetch(FetchDescriptor<FocusSession>())
        #expect(records.count == 1)
        #expect(records.first?.id == id)
        #expect(records.first?.hubAccountID == "stable-A")
    }

    @Test("A failed approval file write cannot start sync and can be retried")
    func ownedHistoryApprovalWriteFailureCanRetry() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        let local = fixture.addSession("Synthetic approval retry")
        try Data("Synthetic path obstruction".utf8).write(to: fixture.directory)
        await fixture.signIn("A")
        #expect(!(await fixture.sync.approveHubHistory()))
        #expect(fixture.sync.ownershipNotice != nil)
        await fixture.sync.synchronize()
        #expect(await fixture.server.pushes.isEmpty)
        #expect(fixture.sync.receipt.lastSuccessfulAt == nil)
        // The session's provenance was saved before the file failed. A retry
        // must preserve it instead of assigning it to the next signed-in user.
        #expect(local.hubAccountID == "stable-A")
        try FileManager.default.removeItem(at: fixture.directory)
        #expect(await fixture.sync.approveHubHistory())
        await fixture.sync.synchronize()
        #expect(fixture.sync.receipt.lastSuccessfulAt != nil)
        #expect(await fixture.server.pushes.count == 1)
        #expect(local.hubAccountID == "stable-A")
    }

    @Test("Malformed approval is preserved and refuses account adoption")
    func ownedHistoryMalformedApprovalFailsClosed() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        let local = fixture.addSession("Synthetic protected history")
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
        let file = fixture.directory.appending(path: "anchor-hub-history-owner.json")
        let malformed = Data("Synthetic malformed approval".utf8)
        try malformed.write(to: file)
        await fixture.signIn("B")
        #expect(!(await fixture.sync.approveHubHistory()))
        await fixture.sync.synchronize()
        #expect(await fixture.server.pushes.isEmpty)
        #expect(local.hubAccountID == nil)
        #expect(try Data(contentsOf: file) == malformed)
    }

    @Test("Unapproved history stays local even after a verified sign-in")
    func ownedHistoryNeedsApproval() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        let local = fixture.addSession("Synthetic unapproved history")
        await fixture.signIn("A")
        await fixture.sync.synchronize()
        #expect(await fixture.server.pushes.isEmpty)
        #expect(local.hubAccountID == nil)
        #expect(fixture.sync.ownershipNotice != nil)
    }

    @Test("Approval persists and never adopts another session owner")
    func ownedHistoryPersistsAcrossRelaunch() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        let local = fixture.addSession("Synthetic A history")
        let imported = fixture.addSession("Synthetic iCloud B history")
        imported.hubAccountID = "stable-B"
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        #expect(local.hubAccountID == "stable-A")
        #expect(imported.hubAccountID == "stable-B")
        let reopened = fixture.makeSync()
        await reopened.restoreAndSynchronize()
        let mutations = await fixture.server.pushes.flatMap(\.mutations)
        let pushed = Set(mutations.map(\.id))
        // A's Hub may only ever receive A-owned history. The session already
        // owned by stable-B must stay off A's account — and so must the
        // distraction metadata bound to it, whose payload carries its owner's
        // sessionID. A's own session and distraction still upload.
        #expect(pushed.contains("session-\(local.id.uuidString.lowercased())"))
        for distraction in try #require(local.distractions, "fixture session has a distraction") {
            #expect(pushed.contains("distraction-\(distraction.id.uuidString.lowercased())"))
        }
        #expect(!pushed.contains("session-\(imported.id.uuidString.lowercased())"))
        for distraction in try #require(imported.distractions, "fixture session has a distraction") {
            #expect(!pushed.contains("distraction-\(distraction.id.uuidString.lowercased())"))
        }
        let leaksImportedSession = mutations.contains { mutation in
            guard case let .object(fields) = mutation.record,
                  case let .string(sessionID) = fields["sessionID"] else { return false }
            return sessionID == imported.id.uuidString
        }
        #expect(!leaksImportedSession)
        #expect(pushed.allSatisfy { $0.hasPrefix("session-") || $0.hasPrefix("distraction-") })
        #expect(try HubHistoryOwnershipStore(directory: fixture.directory).owner() == "stable-A")
        // The reopened sync must leave both provenances exactly as they were.
        #expect(local.hubAccountID == "stable-A")
        #expect(imported.hubAccountID == "stable-B")
        await fixture.sync.disconnect()
        await fixture.signIn("B")
        #expect(!(await fixture.sync.approveHubHistory()))
        #expect(local.hubAccountID == "stable-A")
    }

    @Test("Approval refuses active focus without changing timing or ownership")
    func ownedHistoryApprovalPreservesActiveSession() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        let local = fixture.addSession("Synthetic active focus")
        local.state = .paused
        local.endedAt = nil
        let before = local.account
        await fixture.signIn("A")
        let requests = await fixture.server.identityRequests
        #expect(!(await fixture.sync.approveHubHistory()))
        #expect(await fixture.server.identityRequests == requests)
        #expect(local.hubAccountID == nil)
        #expect(local.account == before)
        #expect(try HubHistoryOwnershipStore(directory: fixture.directory).owner() == nil)
        #expect(await fixture.server.pushes.isEmpty)
    }

    @Test("New focus captures the approved owner without any transport")
    func ownedHistoryOfflineSessionInheritsOwner() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        let store = HubHistoryOwnershipStore(directory: fixture.directory)
        try store.approve("stable-A")
        let controller = FocusController(context: fixture.context, hubOwner: { try? store.owner() })
        let session = try #require(controller.start(goal: nil, intent: "Synthetic offline focus", minutes: 1))
        #expect(session.hubAccountID == "stable-A")
        controller.end(reason: .endedEarly)
        #expect(session.hubAccountID == "stable-A")
        #expect(await fixture.server.pushes.isEmpty)
        #expect(await fixture.server.pulls.isEmpty)
    }

    @Test("Previously exported history must not automatically upload as another account")
    func localHistoryMustNotFollowAccountSwitch() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        let local = fixture.addSession("Synthetic history exported by A")
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        await fixture.sync.synchronize()
        #expect(await fixture.server.pushes.count == 1)
        await fixture.sync.disconnect()
        await fixture.signIn("B")
        await fixture.sync.synchronize()
        let bPushes = await fixture.server.pushes.filter { $0.token == "B" }
        #expect(bPushes.isEmpty)
    }

    @Test("Each identity gets independent fingerprints, versions, cursor and receipt")
    func independentInitialExports() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        let local = fixture.addSession("Synthetic local summary")
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        await fixture.sync.synchronize()
        #expect(fixture.sync.receipt.lastSuccessfulAt != nil)
        #expect(try fixture.context.fetchCount(FetchDescriptor<FocusSession>()) == 1)
        await fixture.sync.disconnect()
        #expect(fixture.sync.receipt == HubSyncReceipt())
        await fixture.signIn("B")
        await fixture.sync.refreshPendingCount()
        #expect(fixture.sync.receipt == HubSyncReceipt())
        await fixture.sync.synchronize()
        let pushes = await fixture.server.pushes
        #expect(pushes.count == 1)
        #expect(pushes.map(\.token) == ["A"])
        #expect(pushes.allSatisfy { $0.mutations.contains { $0.id == "session-\(local.id.uuidString.lowercased())" } })
        #expect(pushes.allSatisfy { $0.mutations.allSatisfy { $0.baseVersion == 0 } })
        #expect(await fixture.server.pulls.map(\.cursor) == [0])
        #expect(try fixture.context.fetchCount(FetchDescriptor<FocusSession>()) == 1)
        #expect(local.intent == "Synthetic local summary")
        // A refreshed token and changed email still belong to stable user A.
        await fixture.sync.disconnect()
        await fixture.signIn("A-refreshed")
        await fixture.sync.refreshPendingCount()
        #expect(fixture.sync.receipt.lastSuccessfulAt != nil)
        await fixture.sync.synchronize()
        #expect(await fixture.server.pushes.count == 1)
        #expect(await fixture.server.pulls.last?.cursor == 11)
        // Editing A's local summary uses A's server version, not B's version.
        local.intent = "Synthetic amended summary"
        try fixture.context.save()
        await fixture.sync.synchronize()
        let amended = await fixture.server.pushes.last?.mutations.first {
            $0.id == "session-\(local.id.uuidString.lowercased())"
        }
        #expect(amended?.baseVersion == 7)
    }

    @Test("A failed queue survives B and relaunch without being sent as B")
    func failedQueueRetainsItsOwner() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        let a = fixture.addSession("Queued for A")
        await fixture.server.failPushes(for: "A")
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        await fixture.sync.synchronize()
        // Session + distraction records are both still owed to the Hub.
        #expect(fixture.sync.pendingCount == 2)
        #expect(fixture.sync.receipt.failure == .service)
        fixture.context.delete(a)
        try fixture.context.save()
        let b = fixture.addSession("Current local summary for B")
        await fixture.sync.disconnect()
        await fixture.signIn("B")
        await fixture.sync.synchronize()
        #expect(await fixture.server.pushes.allSatisfy { $0.token == "A" })
        #expect(b.hubAccountID == nil)
        #expect(fixture.sync.ownershipNotice != nil)
        fixture.context.delete(b)
        try fixture.context.save()
        await fixture.sync.disconnect()
        await fixture.server.allowPushes(for: "A")
        let relaunched = fixture.makeSync()
        await fixture.tokens.save("A-refreshed")
        await relaunched.restoreAndSynchronize()
        // The failed push never reached the server and the local rows were
        // deleted before bookkeeping persisted, so nothing is owed: the remote
        // converges empty and B never receives A's records.
        #expect(await fixture.server.pushes.count == 1)
        #expect(await fixture.server.pushes.allSatisfy { $0.token == "A" })
        #expect(relaunched.pendingCount == 0)
        #expect(relaunched.receipt.failure == nil)
        #expect(relaunched.receipt.lastSuccessfulAt != nil)
        #expect(try fixture.context.fetchCount(FetchDescriptor<FocusSession>()) == 0)
    }

    @Test("Failed bookkeeping write retains the pending export and retries it")
    func failedBookkeepingWriteRetainsPendingExport() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        let local = fixture.addSession("Synthetic durable export")
        await fixture.server.holdPushes(for: "A")
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        let attempt = Task { await fixture.sync.synchronize() }
        await fixture.server.waitUntilHeld("A")
        // Obstruct the bookkeeping save that follows a successful push: the
        // push was accepted remotely but the fingerprints were never recorded,
        // so the records must stay pending and retry on relaunch. The owner
        // binding already wrote the file, so move it aside before obstructing.
        let bookkeeping = fixture.directory.appending(path: "anchor-mirror-bookkeeping.json")
        let backup = fixture.directory.appending(path: "synthetic-bookkeeping-backup.json")
        try FileManager.default.moveItem(at: bookkeeping, to: backup)
        try FileManager.default.createDirectory(at: bookkeeping, withIntermediateDirectories: false)
        await fixture.server.release("A", status: 200)
        await attempt.value
        #expect(fixture.sync.pendingCount == 2)
        #expect(fixture.sync.receipt.lastSuccessfulAt == nil)
        #expect(fixture.sync.receipt.failure != nil)
        #expect(local.intent == "Synthetic durable export")
        try FileManager.default.removeItem(at: bookkeeping)
        try FileManager.default.moveItem(at: backup, to: bookkeeping)
        let relaunched = fixture.makeSync()
        await fixture.server.allowPushes(for: "A")
        await fixture.server.stopHoldingPushes(for: "A")
        await relaunched.restoreAndSynchronize()
        let pushes = await fixture.server.pushes
        #expect(pushes.count == 2)
        // Retried pushes get fresh idempotency keys; the record set is identical.
        #expect(pushes.first?.mutations.map(\.id).sorted() == pushes.last?.mutations.map(\.id).sorted())
        #expect(relaunched.pendingCount == 0)
        #expect(relaunched.receipt.lastSuccessfulAt != nil)
        #expect(relaunched.receipt.failure == nil)
        #expect(try fixture.context.fetchCount(FetchDescriptor<FocusSession>()) == 1)
    }

    @Test("Legacy unscoped state is preserved byte-for-byte and never assigned")
    func legacyStateIsUnassigned() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        let legacy = try PersonalSyncRuntime(
            domain: .anchor, deviceId: "legacy", supportDirectory: fixture.directory,
            identity: fixture.identity,
            client: PersonalSyncClient(baseURL: fixture.origin, session: fixture.transport)
        )
        try await legacy.enqueue(
            recordId: "unassigned-legacy", occurredAt: "2026-09-07T00:00:00Z",
            record: .object(["title": .string("Unassigned synthetic summary")])
        )
        let versions = try SyncVersionStore(fileURL: fixture.directory.appending(path: "personal-sync-versions.json"))
        try await versions.setVersion(99, for: "unassigned-legacy", in: .anchor)
        let cursors = try SyncCursorStore(fileURL: fixture.directory.appending(path: "personal-sync-cursors.json"))
        try await cursors.setCursor(99, for: .anchor)
        let legacyReceipt = HubSyncReceipt(lastSuccessfulAt: Date(timeIntervalSince1970: 123))
        fixture.receipts.save(legacyReceipt)
        let files = try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil)
        let before = try files.map { try Data(contentsOf: $0) }
        #expect(files.count == 4)
        await fixture.signIn("B")
        await fixture.sync.refreshPendingCount()
        #expect(fixture.sync.receipt == HubSyncReceipt())
        await fixture.sync.synchronize()
        #expect(await fixture.server.pushes.isEmpty)
        #expect(try files.map { try Data(contentsOf: $0) } == before)
        #expect(fixture.receipts.load() == legacyReceipt)
        #expect(await legacy.pendingMutationCount() == 1)
        #expect(try fixture.context.fetchCount(FetchDescriptor<FocusSession>()) == 0)
    }

    @Test("A delayed response cannot publish status for an unapproved B account", arguments: [200, 503])
    func delayedCompletionCannotMutateAnotherAccount(status: Int) async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        fixture.addSession("Synthetic delayed export")
        await fixture.server.holdPushes(for: "A")
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        let a = Task { await fixture.sync.synchronize() }
        await fixture.server.waitUntilHeld("A")
        await fixture.sync.disconnect()
        await fixture.signIn("B")
        // Mirror passes serialize, so B's synchronize waits for A's held push;
        // running it as a task lets the release proceed.
        let b = Task { await fixture.sync.synchronize() }
        await fixture.server.release("A", status: status)
        await a.value
        await b.value
        #expect(!fixture.sync.isSyncing)
        #expect(fixture.sync.account?.session?.userId == "stable-B")
        #expect(fixture.sync.receipt == HubSyncReceipt())
        // B resolved as an unapproved different account — A's late completion
        // cannot clear or overwrite that notice.
        #expect(fixture.sync.ownershipNotice != nil)
        // Switching accounts invalidates even a successful late response.
        // Keep A's records pending for an A-owned retry; B must neither
        // acknowledge nor receive them.
        #expect(fixture.sync.pendingCount == 2)
        #expect(await fixture.server.pushes.map(\.token) == ["A"])
    }

    @Test("Sign-out invalidates a delayed successful receipt and future exports")
    func signOutStopsFutureSync() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        fixture.addSession("Synthetic in-flight export")
        await fixture.server.holdPushes(for: "A")
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        let task = Task { await fixture.sync.synchronize() }
        await fixture.server.waitUntilHeld("A")
        await fixture.sync.disconnect()
        await fixture.server.release("A", status: 200)
        await task.value
        #expect(fixture.sync.receipt == HubSyncReceipt())
        #expect(!fixture.sync.isSyncing)
        fixture.addSession("Synthetic local-only session")
        await fixture.sync.synchronize()
        #expect(await fixture.server.pushes.count == 1)
        #expect(try fixture.context.fetchCount(FetchDescriptor<FocusSession>()) == 2)
    }

    @Test("Deletion verifies its identity and cannot sign out a later account")
    func deletionRemainsBoundToItsIdentity() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        await fixture.signIn("A")
        await fixture.tokens.save("B")
        await #expect(throws: PersonalIdentityError.missingSession) {
            try await fixture.sync.deleteAccount()
        }
        #expect(await fixture.server.deletions.isEmpty)
        await fixture.tokens.save("A")
        await fixture.server.holdPushes(for: "delete-A")
        let deletion = Task { try await fixture.sync.deleteAccount() }
        await fixture.server.waitUntilHeld("delete-A")
        await fixture.signIn("B")
        await fixture.sync.synchronize()
        let bReceipt = fixture.sync.receipt
        await fixture.server.release("delete-A", status: 200)
        try await deletion.value
        #expect(fixture.sync.account?.session?.userId == "stable-B")
        #expect(fixture.sync.receipt == bReceipt)
        #expect(await fixture.tokens.load() == "B")
        #expect(await fixture.server.deletions == ["A"])
    }

    @Test("A mismatched or expired bearer cannot select files or export")
    func identityMismatchAndExpiry() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        fixture.addSession("Synthetic protected summary")
        await fixture.signIn("A")
        await fixture.tokens.save("B") // Displayed A, stored token B.
        await fixture.sync.synchronize()
        #expect(fixture.sync.receipt.failure == .signInExpired)
        #expect(await fixture.server.pushes.isEmpty)
        #expect(!FileManager.default.fileExists(
            atPath: fixture.directory.appending(path: "anchor-mirror-bookkeeping.json").path
        ))
        await fixture.tokens.save("expired")
        await fixture.sync.synchronize()
        #expect(fixture.sync.receipt.failure == .signInExpired)
        #expect(await fixture.server.pushes.isEmpty)
    }

    @Test("A canonical remote session lands locally while foreign names stay remote")
    func remoteCanonicalSessionImports() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        let remoteID = UUID()
        try await fixture.server.enqueueRemote("""
        {"cursor":2,"changeId":"remote-session","domain":"anchor","id":"session-\(remoteID.uuidString.lowercased())","operation":"upsert","version":3,"occurredAt":"2026-09-02T09:00:00Z","recordedAt":"2026-09-02T09:00:01Z","originDeviceId":"other-device","record":{"recordType":"focusSession","id":"\(remoteID.uuidString)","startedAt":"2026-09-02T08:00:00Z","endedAt":"2026-09-02T09:00:00Z","plannedSeconds":3600,"bankedSeconds":3600,"stateRaw":"finished","endReasonRaw":"completed","intent":"Remote canonical session","notes":"","tagIDStrings":[],"hourlyRate":0,"currencyCode":"USD","computerActiveSeconds":0,"computerAwaySeconds":0}}
        """)
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        await fixture.sync.synchronize()
        let sessions = try fixture.context.fetch(FetchDescriptor<FocusSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.id == remoteID)
        #expect(sessions.first?.intent == "Remote canonical session")
        #expect(sessions.first?.state == .finished)
        // The applied remote is fingerprinted as present — it does not echo back.
        let pushes = await fixture.server.pushes
        #expect(pushes.flatMap(\.mutations).allSatisfy {
            $0.id != "session-\(remoteID.uuidString.lowercased())"
        })
    }

    @Test("History synced before the mirror still imports as finished sessions")
    func remoteLegacySummaryImports() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        try await fixture.server.enqueueRemote("""
        {"cursor":2,"changeId":"legacy-change","domain":"anchor","id":"session-legacy-export","operation":"upsert","version":1,"occurredAt":"2026-08-01T10:00:00Z","recordedAt":"2026-08-01T10:00:01Z","originDeviceId":"old-device","record":{"title":"Pre-mirror session","startedAt":"2026-08-01T09:00:00Z","endedAt":"2026-08-01T10:00:00Z","durationSeconds":3600,"outcome":"completed","interruptionCount":2}}
        """)
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        await fixture.sync.synchronize()
        let sessions = try fixture.context.fetch(FetchDescriptor<FocusSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.intent == "Pre-mirror session")
        #expect(sessions.first?.state == .finished)
        #expect(sessions.first?.focusedSeconds() == 3_600)
    }

    @Test("A legacy Hub summary filed under a bare UUID still imports exactly once")
    func remoteBareUUIDLegacySummaryImports() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        // Pre-mirror uploads used the session's own UUID as the Hub record id —
        // no kind prefix — with the summary fields AnchorPlatformRecord wrote.
        let legacyID = UUID()
        try await fixture.server.enqueueRemote("""
        {"cursor":2,"changeId":"legacy-bare","domain":"anchor","id":"\(legacyID.uuidString.lowercased())","operation":"upsert","version":4,"occurredAt":"2026-08-01T10:00:00Z","recordedAt":"2026-08-01T10:00:01Z","originDeviceId":"old-device","record":{"title":"Pre-mirror bare session","startedAt":"2026-08-01T09:00:00Z","endedAt":"2026-08-01T10:00:00Z","durationSeconds":3600,"outcome":"completed","interruptionCount":1}}
        """)
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        await fixture.sync.synchronize()
        let sessions = try fixture.context.fetch(FetchDescriptor<FocusSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.id == legacyID)
        #expect(sessions.first?.intent == "Pre-mirror bare session")
        #expect(sessions.first?.state == .finished)
        #expect(sessions.first?.endReason == .completed)
        #expect(sessions.first?.focusedSeconds() == 3_600)
        // The pull cursor is only durable because apply committed, so the next
        // pass resumes past it — and replaying the same change must never
        // duplicate the imported session under a canonical wire name.
        await fixture.sync.synchronize()
        #expect(await fixture.server.pulls.map(\.cursor) == [0, 11])
        #expect(try fixture.context.fetchCount(FetchDescriptor<FocusSession>()) == 1)
        let pushedIDs = await fixture.server.pushes.flatMap(\.mutations).map(\.id)
        #expect(pushedIDs.allSatisfy { $0 != "session-" + legacyID.uuidString.lowercased() })
    }

    @Test("Missing progressed versions block before a new pull can hide lost aliases")
    func missingVersionsBlockBeforeNonemptyDelta() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        let local = fixture.addSession("Previously synchronized")
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        await fixture.sync.synchronize()
        #expect(fixture.sync.receipt.lastSuccessfulAt != nil)
        let pullsBefore = await fixture.server.pulls.count
        let pushesBefore = await fixture.server.pushes.count
        let versionURL = fixture.directory.appending(path: "anchor-hub-versions.json")
        try FileManager.default.moveItem(at: versionURL, to: fixture.directory.appending(path: "versions-backup.json"))
        try await fixture.server.enqueueRemote("""
        {"cursor":12,"changeId":"new-delta","domain":"anchor","id":"\(UUID().uuidString.lowercased())","operation":"upsert","version":1,"occurredAt":"2026-08-01T10:00:00Z","recordedAt":"2026-08-01T10:00:01Z","originDeviceId":"old-device","record":{"title":"New remote summary","startedAt":"2026-08-01T09:00:00Z","endedAt":"2026-08-01T10:00:00Z","durationSeconds":3600,"outcome":"completed","interruptionCount":1}}
        """)
        fixture.sync = fixture.makeSync()
        await fixture.signIn("A")
        await fixture.sync.synchronize()
        #expect(fixture.sync.receipt.failure != nil)
        #expect(await fixture.server.pulls.count == pullsBefore)
        #expect(await fixture.server.pushes.count == pushesBefore)
        #expect(!FileManager.default.fileExists(atPath: versionURL.path))
        #expect(try fixture.context.fetch(FetchDescriptor<FocusSession>()).map(\.id) == [local.id])
    }

    @Test("A malformed record in a pulled batch rolls back the earlier apply work")
    func malformedPullBatchLeavesNoPartialState() async throws {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appending(path: "anchor-malformed-batch-\(UUID())")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let storeURL = storeDirectory.appending(path: "anchor.store")
        let fixture = try SyncFixture(storeURL: storeURL)
        defer { fixture.cleanUp() }
        // The pull applies in name order: the valid record lands first, the
        // corrupt one last, so the batch fails after the first session was
        // already inserted into the shared context.
        let goodID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let badID = UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!
        try await fixture.server.enqueueRemote("""
        {"cursor":2,"changeId":"batch-good","domain":"anchor","id":"session-\(goodID.uuidString.lowercased())","operation":"upsert","version":3,"occurredAt":"2026-09-02T09:00:00Z","recordedAt":"2026-09-02T09:00:01Z","originDeviceId":"other-device","record":{"recordType":"focusSession","id":"\(goodID.uuidString)","startedAt":"2026-09-02T08:00:00Z","endedAt":"2026-09-02T09:00:00Z","plannedSeconds":3600,"bankedSeconds":3600,"stateRaw":"finished","endReasonRaw":"completed","intent":"Remote good batch session","notes":"","tagIDStrings":[],"hourlyRate":0,"currencyCode":"USD","computerActiveSeconds":0,"computerAwaySeconds":0}}
        """)
        try await fixture.server.enqueueRemote("""
        {"cursor":3,"changeId":"batch-bad","domain":"anchor","id":"session-\(badID.uuidString.lowercased())","operation":"upsert","version":3,"occurredAt":"2026-09-02T09:05:00Z","recordedAt":"2026-09-02T09:05:01Z","originDeviceId":"other-device","record":{"recordType":"focusSession","id":"\(badID.uuidString)"}}
        """)
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        await fixture.sync.synchronize()
        #expect(fixture.sync.receipt.failure != nil)
        // Nothing the failed batch touched may remain: not visible in the
        // shared context, not staged as a local record for the next push, and
        // not committed to the store file.
        #expect(try fixture.context.fetch(FetchDescriptor<FocusSession>()).isEmpty)
        #expect(try AnchorMirror.records(in: fixture.context, tombstonesFor: []).isEmpty)
        let committed = ModelContext(fixture.container)
        #expect(try committed.fetch(FetchDescriptor<FocusSession>()).isEmpty)
        // Retrying without the corrupt change restarts the pull — the cursor
        // was never acknowledged — and the surviving record imports exactly
        // once and durably, instead of the memory-only copy winning the merge
        // and being pushed back up as this device's own work.
        await fixture.server.removeRemote(id: "session-\(badID.uuidString.lowercased())")
        await fixture.sync.synchronize()
        #expect(await fixture.server.pulls.map(\.cursor) == [0, 0])
        #expect(try fixture.context.fetchCount(FetchDescriptor<FocusSession>()) == 1)
        let persisted = try ModelContext(fixture.container).fetch(FetchDescriptor<FocusSession>())
        #expect(persisted.count == 1)
        #expect(persisted.first?.id == goodID)
        let pushedIDs = await fixture.server.pushes.flatMap(\.mutations).map(\.id)
        #expect(pushedIDs.allSatisfy { $0 != "session-\(goodID.uuidString.lowercased())" })
    }

    @Test("A remote session carrying a foreign owner is refused, not claimed")
    func foreignInboundSessionIsRejected() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        let remoteID = UUID()
        try await fixture.server.enqueueRemote("""
        {"cursor":2,"changeId":"forged-owner","domain":"anchor","id":"session-\(remoteID.uuidString.lowercased())","operation":"upsert","version":3,"occurredAt":"2026-09-02T09:00:00Z","recordedAt":"2026-09-02T09:00:01Z","originDeviceId":"other-device","record":{"recordType":"focusSession","id":"\(remoteID.uuidString)","hubAccountID":"stable-B","startedAt":"2026-09-02T08:00:00Z","endedAt":"2026-09-02T09:00:00Z","plannedSeconds":3600,"bankedSeconds":3600,"stateRaw":"finished","endReasonRaw":"completed","intent":"Forged owner session","notes":"","tagIDStrings":[],"hourlyRate":0,"currencyCode":"USD","computerActiveSeconds":0,"computerAwaySeconds":0}}
        """)
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        await fixture.sync.synchronize()
        // The payload's owner is untrusted: stable-B ≠ the verified account, so
        // the batch fails closed and nothing is claimed or committed.
        #expect(fixture.sync.receipt.failure != nil)
        #expect(try fixture.context.fetch(FetchDescriptor<FocusSession>()).isEmpty)
        #expect(try ModelContext(fixture.container).fetch(FetchDescriptor<FocusSession>()).isEmpty)
    }

    @Test("A record whose payload UUID disagrees with its name is refused")
    func nameMismatchedSessionIsRejected() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        let nameID = UUID()
        let payloadID = UUID()
        try await fixture.server.enqueueRemote("""
        {"cursor":2,"changeId":"uuid-mismatch","domain":"anchor","id":"session-\(nameID.uuidString.lowercased())","operation":"upsert","version":3,"occurredAt":"2026-09-02T09:00:00Z","recordedAt":"2026-09-02T09:00:01Z","originDeviceId":"other-device","record":{"recordType":"focusSession","id":"\(payloadID.uuidString)","startedAt":"2026-09-02T08:00:00Z","endedAt":"2026-09-02T09:00:00Z","plannedSeconds":3600,"bankedSeconds":3600,"stateRaw":"finished","endReasonRaw":"completed","intent":"Mismatched session","notes":"","tagIDStrings":[],"hourlyRate":0,"currencyCode":"USD","computerActiveSeconds":0,"computerAwaySeconds":0}}
        """)
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        await fixture.sync.synchronize()
        #expect(fixture.sync.receipt.failure != nil)
        #expect(try fixture.context.fetch(FetchDescriptor<FocusSession>()).isEmpty)
    }

    @Test("A remote distraction bound to a foreign or missing session is refused")
    func foreignParentDistractionIsRejected() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        // The parent exists locally but belongs to a different account: the
        // metadata payload must never attach to it.
        let foreign = fixture.addSession("Synthetic stable-B history")
        foreign.hubAccountID = "stable-B"
        try fixture.context.save()
        let distractionID = UUID()
        try await fixture.server.enqueueRemote("""
        {"cursor":2,"changeId":"foreign-parent","domain":"anchor","id":"distraction-\(distractionID.uuidString.lowercased())","operation":"upsert","version":3,"occurredAt":"2026-09-02T09:00:00Z","recordedAt":"2026-09-02T09:00:01Z","originDeviceId":"other-device","record":{"recordType":"distraction","id":"\(distractionID.uuidString)","capturedAt":"2026-09-02T08:30:00Z","kindConfidence":0,"kindIsUserSet":false,"offsetSeconds":120,"didReturnToFocus":true,"sessionID":"\(foreign.id.uuidString)","tagIDStrings":[]}}
        """)
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        await fixture.sync.synchronize()
        #expect(fixture.sync.receipt.failure != nil)
        // Only the fixture's own distraction exists — the remote row was refused.
        #expect(try fixture.context.fetch(FetchDescriptor<Distraction>()).count == 1)
        // An orphan parent is refused the same way.
        let orphanID = UUID()
        try await fixture.server.enqueueRemote("""
        {"cursor":3,"changeId":"orphan-parent","domain":"anchor","id":"distraction-\(orphanID.uuidString.lowercased())","operation":"upsert","version":3,"occurredAt":"2026-09-02T09:05:00Z","recordedAt":"2026-09-02T09:05:01Z","originDeviceId":"other-device","record":{"recordType":"distraction","id":"\(orphanID.uuidString)","capturedAt":"2026-09-02T08:35:00Z","kindConfidence":0,"kindIsUserSet":false,"offsetSeconds":60,"didReturnToFocus":true,"sessionID":"\(UUID().uuidString)","tagIDStrings":[]}}
        """)
        await fixture.sync.synchronize()
        #expect(fixture.sync.receipt.failure != nil)
        #expect(try fixture.context.fetchCount(FetchDescriptor<Distraction>()) == 1)
    }

    @Test("A failed durable commit is not acknowledged and retries to a reopened store")
    func isolatedSaveFailureRetriesAndReopens() async throws {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appending(path: "anchor-save-failure-\(UUID())")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let storeURL = storeDirectory.appending(path: "anchor.store")
        let fixture = try SyncFixture(storeURL: storeURL)
        defer { fixture.cleanUp() }
        let sessionID = UUID()
        let payload = Data("""
        {"recordType":"focusSession","id":"\(sessionID.uuidString)","startedAt":"2026-09-02T08:00:00Z","endedAt":"2026-09-02T09:00:00Z","plannedSeconds":3600,"bankedSeconds":3600,"stateRaw":"finished","endReasonRaw":"completed","intent":"Durable remote session","notes":"","tagIDStrings":[],"hourlyRate":0,"currencyCode":"USD","computerActiveSeconds":0,"computerAwaySeconds":0}
        """.utf8)
        let record = MirrorRecord(
            name: "session-\(sessionID.uuidString.lowercased())",
            modifiedAt: Date(), payload: payload, appendOnly: true
        )
        // An injected save failure must propagate: the mutation is abandoned
        // with the context, and a retry on a fresh context applies cleanly.
        struct SaveFailed: Error {}
        let failed = ModelContext(fixture.container)
        failed.autosaveEnabled = false
        #expect(throws: SaveFailed.self) {
            try AnchorMirror.apply([record], in: failed, account: "stable-A") { _ in throw SaveFailed() }
        }
        #expect(try ModelContext(fixture.container).fetch(FetchDescriptor<FocusSession>()).isEmpty)
        // A read-only SwiftData configuration exercises the default save
        // failure without relying on permissions of already-open SQLite FDs.
        let readOnly = ModelConfiguration(schema: AnchorStore.schema, url: storeURL,
                                          allowsSave: false, cloudKitDatabase: .none)
        let blockedContainer = try ModelContainer(for: AnchorStore.schema, configurations: [readOnly])
        let blocked = ModelContext(blockedContainer)
        blocked.autosaveEnabled = false
        #expect(throws: (any Error).self) {
            try AnchorMirror.apply([record], in: blocked, account: "stable-A")
        }
        #expect(try ModelContext(fixture.container).fetch(FetchDescriptor<FocusSession>()).isEmpty)
        // The retry runs on a fresh isolated context: the earlier failed
        // attempt is discarded, not mistaken for durable work.
        let retry = ModelContext(fixture.container)
        retry.autosaveEnabled = false
        #expect(try AnchorMirror.apply([record], in: retry, account: "stable-A"))
        #expect(try ModelContext(fixture.container).fetch(FetchDescriptor<FocusSession>()).count == 1)
        // And it survives reopening the real store.
        let reopened = try AnchorStore.makeContainer(kind: .localOnly, url: storeURL)
        let persisted = try ModelContext(reopened).fetch(FetchDescriptor<FocusSession>())
        #expect(persisted.count == 1)
        #expect(persisted.first?.id == sessionID)
        #expect(persisted.first?.hubAccountID == "stable-A")
    }

    @Test("Unsaved local edits are preserved and defer the pass instead of being committed")
    func unsavedLocalEditsArePreserved() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        // A draft the user has not saved must not be saved, rolled back or
        // acknowledged by the pass — it stays pending in the user context.
        let draft = FocusSession(goal: nil, intent: "Unsaved draft", plannedSeconds: 60)
        fixture.context.insert(draft)
        #expect(fixture.context.hasChanges)
        await fixture.sync.synchronize()
        // The pass failed rather than silently acknowledging unsaved work, and
        // the draft is untouched: still pending, still unclaimed.
        #expect(fixture.sync.receipt.failure != nil)
        #expect(fixture.context.hasChanges)
        #expect(draft.hubAccountID == nil)
        #expect(await fixture.server.pushes.isEmpty)
        // Once the user commits the draft themselves, the next pass applies.
        try fixture.context.save()
        await fixture.sync.synchronize()
        #expect(!fixture.context.hasChanges)
        #expect(fixture.sync.receipt.lastSuccessfulAt != nil)
        // Unapproved drafts stay local-only — never adopted by a sync pass.
        #expect(draft.hubAccountID == nil)
        #expect(await fixture.server.pushes.isEmpty)
    }

    @Test("A remote update refreshes the held main-context model after commit")
    func remoteUpdateRefreshesHeldModel() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        let local = fixture.addSession("Before remote edit")
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        await fixture.sync.synchronize()
        // A newer remote write for the same session must land durably and be
        // visible through the already-held model — an isolated save alone
        // leaves it stale until the main context refetches.
        try await fixture.server.enqueueRemote("""
        {"cursor":2,"changeId":"remote-edit","domain":"anchor","id":"session-\(local.id.uuidString.lowercased())","operation":"upsert","version":4,"occurredAt":"2027-01-01T09:00:00Z","recordedAt":"2027-01-01T09:00:01Z","originDeviceId":"other-device","record":{"recordType":"focusSession","id":"\(local.id.uuidString)","startedAt":"2027-01-01T08:00:00Z","endedAt":"2027-01-01T09:00:00Z","plannedSeconds":3600,"bankedSeconds":3600,"stateRaw":"finished","endReasonRaw":"completed","intent":"Remote updated intent","notes":"","tagIDStrings":[],"hourlyRate":0,"currencyCode":"USD","computerActiveSeconds":0,"computerAwaySeconds":0}}
        """)
        await fixture.sync.synchronize()
        #expect(local.intent == "Remote updated intent")
        #expect(local.hubAccountID == "stable-A")
    }
}
#endif

