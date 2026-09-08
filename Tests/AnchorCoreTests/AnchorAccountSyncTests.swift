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
        let pushed = await fixture.server.pushes.flatMap(\.mutations).map(\.id)
        #expect(pushed == [local.id.uuidString.lowercased()])
        #expect(try HubHistoryOwnershipStore(directory: fixture.directory).owner() == "stable-A")
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
        let session = controller.start(goal: nil, intent: "Synthetic offline focus", minutes: 1)
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
        #expect(bPushes.allSatisfy { !$0.mutations.contains { $0.id == local.id.uuidString.lowercased() } })
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
        #expect(pushes.allSatisfy { $0.mutations.first?.id == local.id.uuidString.lowercased() })
        #expect(pushes.allSatisfy { $0.mutations.first?.baseVersion == 0 })
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
        await fixture.sync.synchronize()
        #expect(await fixture.server.pushes.last?.mutations.first?.baseVersion == 7)
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
        #expect(fixture.sync.pendingCount == 1)
        #expect(fixture.sync.receipt.failure == .service)
        let first = try #require(await fixture.server.pushes.first?.mutations.first)
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
        let retry = try #require(await fixture.server.pushes.last)
        #expect(retry.token == "A-refreshed")
        #expect(retry.mutations == [first])
        #expect(relaunched.pendingCount == 0)
        #expect(relaunched.receipt.failure == nil)
        #expect(relaunched.receipt.lastSuccessfulAt != nil)
        #expect(try fixture.context.fetchCount(FetchDescriptor<FocusSession>()) == 0)
    }

    @Test("Failed acknowledgement retains the pending export and retries without importing history")
    func failedAcknowledgementRetainsPendingExport() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        let local = fixture.addSession("Synthetic durable export")
        await fixture.server.holdPushes(for: "A")
        await fixture.signIn("A")
        #expect(await fixture.sync.approveHubHistory())
        let attempt = Task { await fixture.sync.synchronize() }
        await fixture.server.waitUntilHeld("A")
        let accountDirectory = fixture.directory.appending(path: "hub-accounts-v1")
            .appending(path: HubSyncReceiptStore.namespace(for: "stable-A"))
        let outbox = accountDirectory.appending(path: "personal-sync-outbox.json")
        let backup = accountDirectory.appending(path: "synthetic-outbox-backup.json")
        try FileManager.default.moveItem(at: outbox, to: backup)
        try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: false)
        await fixture.server.release("A", status: 200)
        await attempt.value
        #expect(fixture.sync.pendingCount == 1)
        #expect(fixture.sync.receipt.lastSuccessfulAt == nil)
        #expect(fixture.sync.receipt.failure != nil)
        #expect(await fixture.server.pulls.isEmpty)
        #expect(local.intent == "Synthetic durable export")
        try FileManager.default.removeItem(at: outbox)
        try FileManager.default.moveItem(at: backup, to: outbox)
        let relaunched = fixture.makeSync()
        await fixture.server.allowPushes(for: "A")
        await fixture.server.stopHoldingPushes(for: "A")
        await relaunched.restoreAndSynchronize()
        let pushes = await fixture.server.pushes
        #expect(pushes.count == 2)
        #expect(pushes.first?.mutations == pushes.last?.mutations)
        #expect(relaunched.pendingCount == 0)
        #expect(relaunched.receipt.lastSuccessfulAt != nil)
        #expect(relaunched.receipt.failure == nil)
        #expect(try fixture.context.fetchCount(FetchDescriptor<FocusSession>()) == 1)
        #expect(!AnchorPlatformSync.importsRemoteSessions)
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
        await fixture.sync.synchronize()
        let bReceipt = fixture.sync.receipt
        let bNotice = fixture.sync.ownershipNotice
        #expect(!fixture.sync.isSyncing)
        #expect(bNotice != nil)
        await fixture.server.release("A", status: status)
        await a.value
        #expect(fixture.sync.account?.session?.userId == "stable-B")
        #expect(fixture.sync.receipt == bReceipt)
        #expect(fixture.sync.ownershipNotice == bNotice)
        #expect(fixture.sync.pendingCount == 0)
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
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appending(path: "hub-accounts-v1").path))
        await fixture.tokens.save("expired")
        await fixture.sync.synchronize()
        #expect(fixture.sync.receipt.failure == .signInExpired)
        #expect(await fixture.server.pushes.isEmpty)
    }
}

@MainActor
private final class SyncFixture {
    let directory = FileManager.default.temporaryDirectory.appending(path: "anchor-account-sync-\(UUID())")
    let suite = "anchor-account-sync-\(UUID())"
    let tokens = FixtureTokens()
    let server = FixtureHub()
    let context: ModelContext
    let origin: URL
    let transport: URLSession
    let identity: PersonalIdentityClient
    let defaults: UserDefaults
    let receipts: HubSyncReceiptStore
    lazy var sync = makeSync()

    init() throws {
        context = ModelContext(try AnchorStore.makeContainer(kind: .inMemory))
        origin = URL(string: "https://\(UUID().uuidString.lowercased()).invalid")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        transport = URLSession(configuration: configuration)
        identity = PersonalIdentityClient(baseURL: origin, session: transport, tokenStore: tokens)
        defaults = UserDefaults(suiteName: suite)!
        receipts = HubSyncReceiptStore(defaults: defaults)
        FixtureProtocol.servers.withLock { $0[origin.host!] = server }
    }

    func makeSync() -> AnchorPlatformSync {
        AnchorPlatformSync(
            context: context, identity: identity, supportDirectory: directory,
            deviceId: "synthetic-device", receiptStore: receipts,
            transport: transport, platformURL: origin, identityOrigin: origin
        )
    }

    func signIn(_ token: String) async {
        await tokens.save(token)
        await sync.account?.restore()
        #expect(sync.account?.isSignedIn == true)
    }

    @discardableResult
    func addSession(_ title: String) -> FocusSession {
        let session = FocusSession(goal: nil, intent: title, plannedSeconds: 60)
        session.endedAt = session.startedAt.addingTimeInterval(60)
        session.bankedSeconds = 60
        session.runningSince = nil
        session.state = .finished
        session.endReason = .completed
        session.notes = "PRIVATE SYNTHETIC NOTE MUST NOT LEAVE"
        context.insert(session)
        return session
    }

    func cleanUp() {
        transport.invalidateAndCancel()
        FixtureProtocol.servers.withLock { _ = $0.removeValue(forKey: origin.host!) }
        defaults.removePersistentDomain(forName: suite)
        if FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

private actor FixtureTokens: PersonalBearerTokenStore {
    var token: String?
    func load() -> String? { token }
    func save(_ token: String) { self.token = token }
    func delete() { token = nil }
}

private actor FixtureHub {
    struct Push: Sendable { let token: String; let mutations: [SyncMutation] }
    struct Pull: Sendable { let token: String; let cursor: Int }
    struct Reply: Sendable { let status: Int; let data: Data }
    private(set) var identityRequests = 0
    private(set) var deletions: [String] = []
    private(set) var pushes: [Push] = []
    private(set) var pulls: [Pull] = []
    private var failures: Set<String> = []
    private var holds: Set<String> = []
    private var held: [String: CheckedContinuation<Int, Never>] = [:]
    private var waiting: [String: CheckedContinuation<Void, Never>] = [:]
    func failPushes(for token: String) { failures.insert(token) }
    func allowPushes(for token: String) { failures.remove(token) }
    func holdPushes(for token: String) { holds.insert(token) }
    func stopHoldingPushes(for token: String) { holds.remove(token) }
    func waitUntilHeld(_ token: String) async {
        if held[token] != nil { return }
        await withCheckedContinuation { waiting[token] = $0 }
    }
    func release(_ token: String, status: Int) { held.removeValue(forKey: token)?.resume(returning: status) }

    func respond(_ request: URLRequest, body: Data) async throws -> Reply {
        let token = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
        let user = token == "A-refreshed" ? "A" : token
        guard ["A", "B"].contains(user) else {
            return Reply(status: 401, data: Data(#"{"message":"Synthetic expired session"}"#.utf8))
        }
        func json(_ value: Any) throws -> Reply {
            Reply(status: 200, data: try JSONSerialization.data(withJSONObject: value))
        }
        switch request.url!.path {
        case "/api/personal-platform/session":
            identityRequests += 1
            let key = "session-\(token)"
            if holds.contains(key) {
                _ = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
                    held[key] = continuation
                    waiting.removeValue(forKey: key)?.resume()
                }
            }
            return try json(["userId": "stable-\(user)", "email": "\(token)@example.invalid"])
        case "/api/auth/sign-out": return try json([:])
        case "/api/auth/delete-user":
            deletions.append(token)
            let key = "delete-\(token)"
            if holds.contains(key) {
                _ = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
                    held[key] = continuation
                    waiting.removeValue(forKey: key)?.resume()
                }
            }
            return try json([:])
        case "/v1/sync/push":
            struct Envelope: Decodable { let domain: String; let mutations: [SyncMutation] }
            let envelope = try JSONDecoder().decode(Envelope.self, from: body)
            #expect(envelope.domain == "anchor")
            #expect(!String(decoding: body, as: UTF8.self).contains("PRIVATE SYNTHETIC"))
            for mutation in envelope.mutations {
                if case let .object(fields) = mutation.record {
                    #expect(Set(fields.keys) == ["title", "startedAt", "endedAt", "durationSeconds", "outcome", "interruptionCount"])
                }
            }
            pushes.append(Push(token: token, mutations: envelope.mutations))
            let status: Int
            if holds.contains(token) {
                status = await withCheckedContinuation {
                    held[token] = $0
                    waiting.removeValue(forKey: token)?.resume()
                }
            } else { status = failures.contains(token) ? 503 : 200 }
            guard status == 200 else { return Reply(status: status, data: Data("Synthetic unavailable".utf8)) }
            return try json(["results": envelope.mutations.map {
                ["id": $0.id, "idempotencyKey": $0.idempotencyKey, "status": "accepted", "version": user == "A" ? 7 : 19] as [String: Any]
            }])
        case "/v1/sync/pull":
            let cursor = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "cursor" }!.value!
            pulls.append(Pull(token: token, cursor: Int(cursor)!))
            let remote: [String: Any] = [
                "cursor": 1, "changeId": "remote-change", "domain": "anchor", "id": "remote-only-\(user)",
                "operation": "upsert", "version": 1, "occurredAt": "2026-09-01T00:00:00Z",
                "recordedAt": "2026-09-01T00:01:00Z", "originDeviceId": "other-device",
                "record": ["title": "Server history must stay remote", "startedAt": "2026-09-01T00:00:00Z",
                           "endedAt": "2026-09-01T00:01:00Z", "durationSeconds": 60, "outcome": "completed", "interruptionCount": 0],
            ]
            return try json(["changes": [remote], "cursor": user == "A" ? 11 : 29, "hasMore": false])
        default: throw URLError(.unsupportedURL)
        }
    }
}

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    static let servers = Mutex<[String: FixtureHub]>([:])
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let server = Self.servers.withLock({ $0[request.url!.host!] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                body.append(contentsOf: bytes.prefix(count))
            }
        }
        let requestBody = body
        Task {
            do {
                let reply = try await server.respond(request, body: requestBody)
                let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: reply.data)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    override func stopLoading() {}
}
#endif
