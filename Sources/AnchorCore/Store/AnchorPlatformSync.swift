#if !os(watchOS)
import CryptoKit
import Foundation
import Observation
import PersonalSyncKit
import SwiftData
import Synchronization

@MainActor
@Observable
public final class AnchorPlatformSync {
    /// Use the service's canonical application origin directly. Starting OAuth
    /// on the marketing-domain redirect splits browser cookies and callbacks
    /// across two hosts, which makes native Google sign-in unnecessarily
    /// fragile.
    public static let identityURL = URL(string: "https://live.significanthobbies.com")!

    /// Completed sessions are append-only mirror records: a tombstone must
    /// never erase history that actually happened.
    nonisolated static func isAppendOnlyRecord(_ name: String) -> Bool {
        name.hasPrefix(AnchorMirrorNaming.Kind.focusSession.prefix) || UUID(uuidString: name) != nil
    }

    private let context: ModelContext
    private let identity: PersonalIdentityClient?
    private let supportDirectory: URL
    private let deviceId: String
    private let transport: URLSession
    private let identityOrigin: URL
    private let sessionSynchronizationEnabled: Bool
    private let receiptStore: HubSyncReceiptStore
    /// The shared dual-mirror runtime: the same `MirrorRecord`s reach the Hub
    /// `anchor` domain and the app's private CloudKit zone, and pulls from
    /// either side apply into the local store.
    let runtime: MirrorRuntime?
    private var activeUserID: String?
    private var generation = UUID()
    private var isDisconnecting = false
    private var saveObserver: NSObjectProtocol?
    private var saveDebounce: Task<Void, Never>?
    /// The same `SyncVersionStore` instance the Hub transport uses, so wire
    /// names pulled under a legacy bare-UUID alias keep that identity.
    private let hubVersions: SyncVersionStore?
    /// Count of `didSave` notifications observed for `context`. Captured with
    /// each records snapshot; a mismatch at apply time means a local save
    /// landed mid-pass and the merge must retry rather than commit stale.
    /// Posted synchronously inside `save()`, so the counter is locked rather
    /// than deferred to a later actor hop.
    private let saveGeneration = Mutex(0)
    /// One pinned synchronize pass: the freshly verified account plus the
    /// local-save generation captured by the records snapshot.
    private var syncPass: (account: PersonalSyncAccount?, saveGeneration: Int, attempt: UUID)?
    public let account: PersonalAccountModel?
    public private(set) var isSyncing = false
    public private(set) var pendingCount = 0
    public private(set) var ownershipNotice: String?
    public private(set) var receipt = HubSyncReceipt()

    public convenience init(
        context: ModelContext,
        storeKind: AnchorStore.StoreKind = .persistent,
        enabled: Bool = true,
        sessionSynchronizationEnabled: Bool = AnchorExternalSyncPolicy.allowsSessionSynchronization(),
        receiptStore: HubSyncReceiptStore = HubSyncReceiptStore()
    ) {
        // Only a persistent store may start external sync. A local-only,
        // in-memory or failed-preflight fallback must not inspect Keychain
        // tokens or open an account runtime; CloudKit continuity itself is
        // native and needs no replacement transport here.
        let enabled = enabled && storeKind == .persistent && !CloudKitSchemaSeed.isRequested
        let defaults = UserDefaults.standard
        let deviceKey = "personal-platform-device-id"
        let deviceId = defaults.string(forKey: deviceKey) ?? UUID().uuidString.lowercased()
        if enabled { defaults.set(deviceId, forKey: deviceKey) }
        self.init(
            context: context,
            identity: enabled ? PersonalIdentityClient(
                baseURL: Self.identityURL,
                tokenStore: KeychainBearerTokenStore(
                    service: "com.significanthobbies.anchor.personal-platform"
                )
            ) : nil,
            supportDirectory: AnchorStore.storeURL().deletingLastPathComponent(),
            deviceId: deviceId,
            sessionSynchronizationEnabled: sessionSynchronizationEnabled && enabled,
            receiptStore: receiptStore
        )
    }

    /// Internal composition seam: tests use temporary files, in-memory tokens
    /// and a URLSession transport, without opening the owner's Keychain.
    init(
        context: ModelContext,
        identity: PersonalIdentityClient?,
        supportDirectory: URL,
        deviceId: String,
        sessionSynchronizationEnabled: Bool = true,
        receiptStore: HubSyncReceiptStore,
        transport: URLSession = .shared,
        platformURL: URL = URL(string: "https://personal-platform.sarthakagrawal927.workers.dev")!,
        identityOrigin: URL = AnchorPlatformSync.identityURL,
        cloudKit: (any MirrorTransport)? = nil,
        observeLocalSaves: Bool = true
    ) {
        self.context = context
        self.identity = identity
        self.supportDirectory = supportDirectory
        self.deviceId = deviceId
        self.sessionSynchronizationEnabled = sessionSynchronizationEnabled
        self.receiptStore = receiptStore
        self.transport = transport
        self.identityOrigin = identityOrigin
        account = identity.map {
            PersonalAccountModel(identity: $0, callbackScheme: "anchor", identityURL: identityOrigin)
        }

        var transports: [any MirrorTransport] = []
        var hubVersions: SyncVersionStore?
        if let identity,
           let versions = try? SyncVersionStore(
               fileURL: supportDirectory.appending(path: "anchor-hub-versions.json")
           ) {
            hubVersions = versions
            transports.append(
                HubMirrorTransport(
                    domain: .anchor,
                    deviceId: deviceId,
                    client: PersonalSyncClient(baseURL: platformURL, session: transport),
                    versions: versions,
                    account: { [identity] in try await identity.verifiedSyncAccount() },
                    // The Hub leg stays quiet until this device's history is
                    // explicitly bound to the verified account; CloudKit still
                    // mirrors while approval is pending.
                    accountGate: { [supportDirectory] verified in
                        (try? HubHistoryOwnershipStore(directory: supportDirectory).owner())
                            == verified.userID
                    },
                    appendOnly: Self.isAppendOnlyRecord
                )
            )
        }
        if let cloudKit { transports.append(cloudKit) }
        self.hubVersions = hubVersions
        runtime = transports.isEmpty ? nil : MirrorRuntime(
            transports: transports,
            store: MirrorBookkeepingStore(
                fileURL: supportDirectory.appending(path: "anchor-mirror-bookkeeping.json")
            )
        )

        // Every local save bumps the snapshot generation; with observation
        // enabled it also schedules a debounced mirror pass — the old outbox
        // had to be fed explicitly; the mirror diffs the document itself.
        let contextID = ObjectIdentifier(context)
        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard (notification.object as? ModelContext).map(ObjectIdentifier.init) == contextID else { return }
            guard let self else { return }
            self.saveGeneration.withLock { $0 += 1 }
            guard observeLocalSaves else { return }
            Task { @MainActor [weak self] in self?.scheduleSynchronizeAfterLocalSave() }
        }
    }

    isolated deinit {
        if let saveObserver { NotificationCenter.default.removeObserver(saveObserver) }
        saveDebounce?.cancel()
    }

    private func scheduleSynchronizeAfterLocalSave() {
        guard sessionSynchronizationEnabled else { return }
        saveDebounce?.cancel()
        saveDebounce = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1_500))
            guard !Task.isCancelled else { return }
            await self?.synchronize()
        }
    }

    public func restoreAndSynchronize() async {
        // QA stores must never inspect the owner's shared Keychain.
        guard sessionSynchronizationEnabled, !isDisconnecting else { return }
        let hadBearer = await hasBearerToken()
        await account?.restore()
        selectAccount()
        if account?.isSignedIn == false, let errorMessage = account?.errorMessage {
            let stillHasBearer = await hasBearerToken()
            let failure: HubSyncFailure = hadBearer && !stillHasBearer
                ? .signInExpired
                : .classify(accountMessage: errorMessage)
            recordFailure(failure)
        }
        await synchronize()
    }

    public func connect() async {
        guard !isDisconnecting else { return }
        await account?.connect()
        await synchronize(announcing: true)
    }

    public func disconnect() async {
        guard !isDisconnecting else { return }
        isDisconnecting = true
        selectAccount() // Invalidate callbacks before awaiting remote sign-out.
        defer { isDisconnecting = false }
        await account?.signOut()
    }

    /// Permanently removes the connected Significant Hobbies account. Anchor's
    /// local and iCloud planner data remains independent and is not deleted.
    public func deleteAccount() async throws {
        selectAccount()
        let attempt = generation
        guard sessionSynchronizationEnabled, !isDisconnecting, let identity,
              let userID = activeUserID,
              let bearerToken = try await identity.bearerToken() else {
            throw AnchorAccountDeletionError.signedOut
        }
        _ = try await verifiedIdentity(token: bearerToken, userID: userID)
        guard isCurrent(userID, attempt: attempt) else { throw AnchorAccountDeletionError.signedOut }
        let request = AnchorAccountDeletionRequest.make(
            identityURL: identityOrigin, bearerToken: bearerToken
        )
        let (data, response) = try await transport.data(for: request)
        try AnchorAccountDeletionRequest.validate(data: data, response: response)
        receiptStore.scoped(to: userID).save(HubSyncReceipt())
        // Drop this device's mirror bookkeeping so the next account is not
        // blocked by a dead owner's pull tokens or bound owner.
        try? await runtime?.forgetBookkeeping()
        if isCurrent(userID, attempt: attempt) { await disconnect() }
    }

    private var historyOwnership: HubHistoryOwnershipStore {
        HubHistoryOwnershipStore(directory: supportDirectory)
    }

    public var needsHistoryApproval: Bool {
        guard let owner = try? historyOwnership.owner() else { return true }
        guard owner == account?.session?.userId else { return false }
        if ownershipNotice != nil { return true }
        return (try? context.fetch(FetchDescriptor<FocusSession>()).contains { $0.hubAccountID == nil }) ?? false
    }

    /// No network or owner change is allowed inside a running focus session.
    /// Save each session's provenance before adopting any legacy account queue.
    func approveLocalHistory(for userID: String) throws {
        guard !userID.isEmpty else { throw HubHistoryOwnershipError.invalidOwner }
        if let owner = try historyOwnership.owner(), owner != userID {
            throw HubHistoryOwnershipError.differentAccount
        }
        let sessions = try context.fetch(FetchDescriptor<FocusSession>())
        guard !sessions.contains(where: { $0.isActive }) else { throw HubHistoryOwnershipError.activeSession }
        let unowned = sessions.filter { $0.hubAccountID == nil }
        for session in unowned { session.hubAccountID = userID }
        do { try context.save() }
        catch {
            for session in unowned { session.hubAccountID = nil }
            throw error
        }
        try historyOwnership.approve(userID)
    }

    @discardableResult
    public func approveHubHistory() async -> Bool {
        guard sessionSynchronizationEnabled, !isDisconnecting, !isSyncing,
              let identity, let runtime else { return false }
        selectAccount()
        guard let userID = activeUserID else { return false }
        let attempt = generation
        do {
            let sessions = try context.fetch(FetchDescriptor<FocusSession>())
            guard !sessions.contains(where: { $0.isActive }) else { throw HubHistoryOwnershipError.activeSession }
            guard let verified = try await identity.verifiedSyncAccount(),
                  verified.userID == userID, isCurrent(userID, attempt: attempt) else { throw PersonalIdentityError.missingSession }
            try approveLocalHistory(for: verified.userID)
            try await identity.requireCurrentAccount(verified)
            try await runtime.bindOwner(verified.userID)
            guard isCurrent(userID, attempt: attempt) else { return false }
            ownershipNotice = nil
            return true
        } catch {
            guard isCurrent(userID, attempt: attempt) else { return false }
            ownershipNotice = error is HubHistoryOwnershipError
                ? error.localizedDescription
                : "Could not approve this Hub connection. Local history and waiting changes are preserved."
            return false
        }
    }

    public func synchronize(announcing _: Bool = false) async {
        guard sessionSynchronizationEnabled, let runtime, !isDisconnecting, !isSyncing else { return }
        selectAccount()
        let attempt = generation
        isSyncing = true
        defer {
            syncPass = nil
            if isCurrent(attempt) { isSyncing = false }
        }
        do {
            // Pin one verified account for the whole pass. The transport
            // re-verifies on its own requests, so a resolution failure here is
            // not fatal — it just leaves the pass unauthenticated, which the
            // Hub leg reports as its usual "not signed in" outcome.
            let pinned = try? await identity?.verifiedSyncAccount()
            guard isCurrent(attempt) else { return }
            syncPass = (account: pinned ?? nil, saveGeneration: saveGeneration.withLock { $0 }, attempt: attempt)
            // Check continuity before a pull can recreate a missing version map.
            try await validateVersionContinuity()
            let outcome = try await runtime.synchronize(records: {
                try await self.mirrorRecords()
            }, validateLocalSnapshot: { _ in
                try await self.validateSyncPass()
            }) { records in
                try await self.commitMirrorRecords(records)
            }
            guard isCurrent(attempt) else { return }
            // The durable owner file must still equal the pinned account before
            // any receipt is published — a pass that started as A can never
            // report success to a store that has become someone else's.
            if outcome.isComplete, let pinned, (try? historyOwnership.owner()) != pinned.userID { return }
            await refreshPendingCount()
            guard isCurrent(attempt) else { return }
            if outcome.isComplete { try await validateSyncPass() }
            await recordOutcome(outcome)
        } catch {
            guard isCurrent(attempt) else { return }
            await refreshPendingCount()
            guard isCurrent(attempt) else { return }
            if error is HubHistoryOwnershipError || error is PersonalSyncOwnershipError {
                ownershipNotice = error.localizedDescription
            }
            recordFailure(HubSyncFailure.classify(error))
        }
    }

    /// The account-scoped Hub projection: only finished sessions the pinned
    /// verified account owns, plus distraction metadata bound to those
    /// sessions. Anything else is native/iCloud-only and never staged.
    func mirrorRecords() async throws -> [MirrorRecord] {
        guard !context.hasChanges, let pass = syncPass, isCurrent(pass.attempt) else {
            throw AnchorMirrorSyncError.pendingLocalEdits
        }
        syncPass?.saveGeneration = saveGeneration.withLock { $0 }
        guard let account = syncPass?.account,
              (try? historyOwnership.owner()) == account.userID else { return [] }
        return try await hubRecords(for: account.userID)
    }

    /// The identical projection used for pending counts: what the durable
    /// owner is still owed, independent of who happens to be signed in.
    private func hubRecords(for owner: String) async throws -> [MirrorRecord] {
        let snapshotGeneration = saveGeneration.withLock { $0 }
        guard !context.hasChanges else { throw AnchorMirrorSyncError.pendingLocalEdits }
        try await validateVersionContinuity()
        var aliases: [UUID: String] = [:]
        if let hubVersions {
            for session in try context.fetch(FetchDescriptor<FocusSession>())
            where session.hubAccountID == owner && !session.isActive {
                // The same version store the Hub transport writes on pull: a
                // positive version under a bare UUID is evidence that session
                // already has a remote wire name. Lowercase wins over
                // uppercase; version values are per-alias, not comparable.
                let lower = session.id.uuidString.lowercased()
                let upper = session.id.uuidString
                if await hubVersions.version(for: lower, in: .anchor) > 0 {
                    aliases[session.id] = lower
                } else if await hubVersions.version(for: upper, in: .anchor) > 0 {
                    aliases[session.id] = upper
                }
            }
        }
        guard !context.hasChanges, saveGeneration.withLock({ $0 }) == snapshotGeneration else {
            throw AnchorMirrorSyncError.pendingLocalEdits
        }
        return try AnchorMirror.records(in: context, tombstonesFor: [], hubAccountID: owner) { id in
            aliases[id] ?? AnchorMirrorNaming.Kind.focusSession.name(for: id)
        }
    }

    private func validateVersionContinuity() async throws {
        let versionsURL = supportDirectory.appending(path: "anchor-hub-versions.json")
        if FileManager.default.fileExists(atPath: versionsURL.path) {
            // Validate retained disk evidence too; the actor's cached map must
            // not conceal an unreadable file that a relaunch cannot recover.
            _ = try JSONDecoder().decode([PersonalDomain: [String: Int]].self,
                                         from: Data(contentsOf: versionsURL))
        } else {
            let bookkeeping = try await MirrorBookkeepingStore(
                fileURL: supportDirectory.appending(path: "anchor-mirror-bookkeeping.json")
            ).load()
            let progressed = !bookkeeping.ledger.stamps.isEmpty
                || bookkeeping.pushedFingerprints.values.contains { !$0.isEmpty }
                || bookkeeping.pullTokens.values.contains { (Int(String(decoding: $0, as: UTF8.self)) ?? 1) > 0 }
            guard !progressed else { throw AnchorMirrorSyncError.invalidRecord }
        }
    }

    /// Apply pulled records into an isolated context off the same container and
    /// commit exactly once. On any failure the isolated context is discarded —
    /// the user context keeps its pending edits and no half-applied batch is
    /// mistaken for durable on retry.
    func commitMirrorRecords(_ records: [MirrorRecord]) async throws {
        try await validateSyncPass()
        guard let pass = syncPass, let account = pass.account else {
            throw AnchorMirrorSyncError.unverifiedAccount
        }
        guard !context.hasChanges, saveGeneration.withLock({ $0 }) == pass.saveGeneration else {
            throw AnchorMirrorSyncError.pendingLocalEdits
        }
        guard (try? historyOwnership.owner()) == account.userID else {
            throw HubHistoryOwnershipError.differentAccount
        }
        let isolated = ModelContext(context.container)
        isolated.autosaveEnabled = false
        let changed = try AnchorMirror.apply(records, in: isolated, account: account.userID)
        guard changed else { return }
        // A held main-context model does not see the isolated commit; a fresh
        // fetch refreshes it in place without resetting user edits.
        _ = try? context.fetch(FetchDescriptor<FocusSession>())
        _ = try? context.fetch(FetchDescriptor<Distraction>())
    }

    private func validateSyncPass() async throws {
        guard let pass = syncPass, let verified = pass.account, let identity,
              isCurrent(verified.userID, attempt: pass.attempt) else {
            throw AnchorMirrorSyncError.unverifiedAccount
        }
        try await identity.requireCurrentAccount(verified)
        guard isCurrent(verified.userID, attempt: pass.attempt),
              !context.hasChanges, saveGeneration.withLock({ $0 }) == pass.saveGeneration else {
            throw AnchorMirrorSyncError.pendingLocalEdits
        }
        guard try historyOwnership.owner() == verified.userID else {
            throw HubHistoryOwnershipError.differentAccount
        }
    }

    /// Only the Hub leg owns the receipt: CloudKit mirroring runs whenever the
    /// container is reachable, signed in or not. A gate-closed Hub leg is a
    /// pending state, not a failure — unless the displayed account's own
    /// bearer no longer verifies, which is an expired sign-in.
    private func recordOutcome(_ outcome: MirrorRuntime.Outcome) async {
        guard let hub = outcome.transports.first(where: { $0.transportID == "hub" }) else {
            receipt.recordSuccess(at: outcome.completedAt)
            if let userID = activeUserID { receiptStore.scoped(to: userID).save(receipt) }
            return
        }
        if let failure = hub.failure {
            guard failure != "not signed in" else {
                guard let userID = account?.session?.userId, let identity else { return }
                // "not signed in" means the transport resolved no usable
                // account. Re-verify what the displayed session resolves to:
                // a token that now belongs to someone else (or none) is an
                // expired sign-in; a verified same-user account blocked only
                // by ownership approval is a pending notice.
                let resolved = try? await identity.verifiedSyncAccount()
                if resolved?.userID != userID {
                    recordFailure(.signInExpired)
                } else if (try? historyOwnership.owner()) != userID {
                    let owner = try? historyOwnership.owner()
                    ownershipNotice = owner == nil
                        ? HubHistoryOwnershipError.approvalRequired.localizedDescription
                        : HubHistoryOwnershipError.differentAccount.localizedDescription
                }
                return
            }
            recordFailure(Self.classifyOutcomeFailure(failure))
        } else {
            receipt.recordSuccess(at: outcome.completedAt)
            if let userID = activeUserID { receiptStore.scoped(to: userID).save(receipt) }
        }
    }

    private static func classifyOutcomeFailure(_ message: String) -> HubSyncFailure {
        if message.contains("401") || message.contains("403")
            || message.contains("missingSession") || message.contains("sessionChanged") {
            return .signInExpired
        }
        if message.contains("-1009") || message.contains("-1001")
            || message.contains("-1005") || message.contains("-1020")
            || message.localizedCaseInsensitiveContains("offline")
            || message.localizedCaseInsensitiveContains("network connection") {
            return .offline
        }
        return .service
    }

    public func refreshPendingCount() async {
        selectAccount()
        guard let runtime else { return }
        let attempt = generation
        // The pending queue belongs to the durable bound owner, not whoever is
        // signed in — the same account projection that gates transport
        // eligibility decides what is still owed.
        var records: [MirrorRecord] = []
        if let owner = try? historyOwnership.owner() {
            guard let snapshot = try? await hubRecords(for: owner) else { return }
            records = snapshot
        }
        // Unreadable bookkeeping cannot prove anything was accepted, so the
        // honest answer is that every staged record is still owed.
        let pending = (try? await runtime.unpushedCount(transportID: "hub", records: records))
            ?? records.count
        guard isCurrent(attempt) else { return }
        pendingCount = pending
    }

    private func selectAccount() {
        let userID = isDisconnecting ? nil : account?.session?.userId
        guard activeUserID != userID else { return }
        activeUserID = userID
        generation = UUID()
        ownershipNotice = nil
        isSyncing = false
        pendingCount = 0
        // Legacy unscoped receipts/files are retained, never adopted by the
        // next person who signs in. Only verified stable IDs own new state.
        receipt = userID.map { receiptStore.scoped(to: $0).load() } ?? HubSyncReceipt()
    }

    private func isCurrent(_ userID: String, attempt: UUID) -> Bool {
        !isDisconnecting && generation == attempt && activeUserID == userID
            && account?.session?.userId == userID
    }

    private func isCurrent(_ attempt: UUID) -> Bool {
        !isDisconnecting && generation == attempt
            && activeUserID == account?.session?.userId
    }

    private func verifiedIdentity(token: String, userID: String) async throws -> PersonalIdentityClient {
        let boundIdentity = PersonalIdentityClient(
            baseURL: identityOrigin,
            session: transport,
            tokenStore: AnchorSyncTokenSnapshot(token: token)
        )
        let verified = try await boundIdentity.restoreSession()
        guard verified?.userId == userID else { throw PersonalIdentityError.missingSession }
        return boundIdentity
    }

    private func hasBearerToken() async -> Bool {
        guard let identity else { return false }
        return (try? await identity.bearerToken()) != nil
    }

    private func recordFailure(_ failure: HubSyncFailure) {
        receipt.recordFailure(failure, at: Date())
        if let userID = activeUserID { receiptStore.scoped(to: userID).save(receipt) }
    }
}

private actor AnchorSyncTokenSnapshot: PersonalBearerTokenStore {
    private var token: String?
    init(token: String) { self.token = token }
    func load() -> String? { token }
    func save(_ token: String) { self.token = token }
    func delete() { token = nil }
}

public enum AnchorAccountDeletionError: LocalizedError, Equatable, Sendable {
    case signedOut
    case invalidResponse
    case rejected(status: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .signedOut:
            "Sign in again before deleting this account."
        case .invalidResponse:
            "The account service returned an invalid response."
        case let .rejected(_, message):
            message
        }
    }
}

public enum AnchorAccountDeletionRequest {
    public static func make(identityURL: URL, bearerToken: String) -> URLRequest {
        var request = URLRequest(url: identityURL.appending(path: "api/auth/delete-user"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        return request
    }

    public static func validate(data: Data, response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else {
            throw AnchorAccountDeletionError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            let fallback = "The account could not be deleted. Sign in again and retry."
            let message = (try? JSONDecoder().decode(ServiceError.self, from: data).message)
                .flatMap { $0.isEmpty ? nil : $0 } ?? fallback
            throw AnchorAccountDeletionError.rejected(
                status: response.statusCode,
                message: message
            )
        }
    }

    private struct ServiceError: Decodable { let message: String }
}

public enum AnchorExternalSyncPolicy {
    public static func allowsSessionSynchronization(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["ANCHOR_DEMO_DATA"] != "1"
            && environment["ANCHOR_ONBOARDING_DEMO"] != "1"
            && environment["ANCHOR_STORE_PATH"]?.isEmpty != false
    }
}

public enum AnchorPlatformRecord {
    public static func encode(
        _ session: FocusSession,
        endedAt: Date
    ) -> PersonalSyncKit.JSONValue {
        let title = session.intent.isEmpty ? session.goal?.title ?? "Focus session" : session.intent
        return .object([
            "title": .string(title),
            "startedAt": .string(iso(session.startedAt)),
            "endedAt": .string(iso(endedAt)),
            "durationSeconds": .number(Double(max(0, Int(session.focusedSeconds(at: endedAt))))),
            "outcome": .string(session.endReason?.rawValue ?? "unknown"),
            "interruptionCount": .number(Double(session.distractionCount)),
        ])
    }

    public static func decode(_ change: SyncChange) -> FocusSession? {
        guard case let .object(record) = change.record,
              case let .string(title)? = record["title"],
              case let .string(startedText)? = record["startedAt"],
              case let .string(endedText)? = record["endedAt"],
              let startedAt = ISO8601DateFormatter().date(from: startedText),
              let endedAt = ISO8601DateFormatter().date(from: endedText)
        else { return nil }
        let duration = max(0, record.integer("durationSeconds"))
        let session = FocusSession(
            id: stableUUID(change.id),
            goal: nil,
            intent: title,
            plannedSeconds: duration,
            startedAt: startedAt
        )
        session.endedAt = endedAt
        session.bankedSeconds = Double(duration)
        session.runningSince = nil
        session.state = SessionState.finished
        if case let .string(outcome)? = record["outcome"] {
            session.endReason = SessionEndReason(rawValue: outcome) ?? .completed
        } else {
            session.endReason = .completed
        }
        return session
    }

    public static func stableUUID(_ value: String) -> UUID {
        if let uuid = UUID(uuidString: value) { return uuid }
        let bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    public static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}

private extension Dictionary where Key == String, Value == PersonalSyncKit.JSONValue {
    func integer(_ key: String) -> Int {
        guard case let .number(value)? = self[key] else { return 0 }
        return Int(value)
    }
}
#endif
