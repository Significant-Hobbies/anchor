#if !os(watchOS)
import CryptoKit
import Foundation
import Observation
import PersonalSyncKit
import SwiftData

@MainActor
@Observable
public final class AnchorPlatformSync {
    /// Use the service's canonical application origin directly. Starting OAuth
    /// on the marketing-domain redirect splits browser cookies and callbacks
    /// across two hosts, which makes native Google sign-in unnecessarily
    /// fragile.
    public static let identityURL = URL(string: "https://live.significanthobbies.com")!
    /// iCloud is Anchor's bidirectional source of truth. Hub is deliberately an
    /// outbound summary view, so signing in can never inject old Hub sessions
    /// into the local planner or history.
    nonisolated public static let importsRemoteSessions = false

    private let context: ModelContext
    private let identity: PersonalIdentityClient?
    private let supportDirectory: URL
    private let deviceId: String
    private let transport: URLSession
    private let platformURL: URL
    private let identityOrigin: URL
    private let sessionSynchronizationEnabled: Bool
    private let receiptStore: HubSyncReceiptStore
    private var activeUserID: String?
    private var generation = UUID()
    private var activeRuntime: PersonalSyncRuntime?
    private var busyAccounts: Set<String> = []
    private var isDisconnecting = false
    public let account: PersonalAccountModel?
    public private(set) var isSyncing = false
    public private(set) var pendingCount = 0
    public private(set) var receipt = HubSyncReceipt()

    public convenience init(
        context: ModelContext,
        enabled: Bool = true,
        sessionSynchronizationEnabled: Bool = AnchorExternalSyncPolicy.allowsSessionSynchronization(),
        receiptStore: HubSyncReceiptStore = HubSyncReceiptStore()
    ) {
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
            sessionSynchronizationEnabled: sessionSynchronizationEnabled,
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
        identityOrigin: URL = AnchorPlatformSync.identityURL
    ) {
        self.context = context
        self.identity = identity
        self.supportDirectory = supportDirectory
        self.deviceId = deviceId
        self.sessionSynchronizationEnabled = sessionSynchronizationEnabled
        self.receiptStore = receiptStore
        self.transport = transport
        self.platformURL = platformURL
        self.identityOrigin = identityOrigin
        account = identity.map {
            PersonalAccountModel(identity: $0, callbackScheme: "anchor", identityURL: identityOrigin)
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
        if isCurrent(userID, attempt: attempt) { await disconnect() }
    }

    public func synchronize(announcing _: Bool = false) async {
        guard sessionSynchronizationEnabled else { return }
        selectAccount()
        guard let identity, let userID = activeUserID,
              !busyAccounts.contains(userID) else { return }
        let attempt = generation
        busyAccounts.insert(userID)
        isSyncing = true
        defer {
            busyAccounts.remove(userID)
            if isCurrent(userID, attempt: attempt) { isSyncing = false }
        }
        do {
            guard let token = try await identity.bearerToken() else {
                throw PersonalIdentityError.missingSession
            }
            // Verify the exact token snapshot before choosing a namespace. A
            // token change during an await must never send A's queue as B.
            let boundIdentity = try await verifiedIdentity(token: token, userID: userID)
            guard isCurrent(userID, attempt: attempt) else { return }
            let runtime = try PersonalSyncRuntime(
                domain: .anchor,
                deviceId: deviceId,
                supportDirectory: supportDirectory.appending(path: "hub-accounts-v1")
                    .appending(path: HubSyncReceiptStore.namespace(for: userID)),
                identity: boundIdentity,
                client: PersonalSyncClient(baseURL: platformURL, session: transport)
            )
            activeRuntime = runtime
            try await enqueueFinishedSessions(using: runtime)
            guard isCurrent(userID, attempt: attempt) else { return }
            let queued = await runtime.pendingMutationCount()
            guard isCurrent(userID, attempt: attempt) else { return }
            pendingCount = queued
            // Hub history stays in Hub. It is never inserted into the planner.
            _ = try await runtime.synchronize()
            let pending = await runtime.pendingMutationCount()
            guard isCurrent(userID, attempt: attempt) else { return }
            pendingCount = pending
            receipt.recordSuccess(at: Date())
            receiptStore.scoped(to: userID).save(receipt)
        } catch {
            guard isCurrent(userID, attempt: attempt) else { return }
            await refreshPendingCount()
            guard isCurrent(userID, attempt: attempt) else { return }
            recordFailure(HubSyncFailure.classify(error))
        }
    }

    public func refreshPendingCount() async {
        selectAccount()
        guard let runtime = activeRuntime, let userID = activeUserID else { return }
        let attempt = generation
        let pending = await runtime.pendingMutationCount()
        guard isCurrent(userID, attempt: attempt) else { return }
        pendingCount = pending
    }

    private func selectAccount() {
        let userID = isDisconnecting ? nil : account?.session?.userId
        guard activeUserID != userID else { return }
        activeUserID = userID
        generation = UUID()
        activeRuntime = nil
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

    private func enqueueFinishedSessions(using runtime: PersonalSyncRuntime) async throws {
        let sessions = try context.fetch(FetchDescriptor<FocusSession>())
            .filter { $0.endedAt != nil }
        for session in sessions {
            guard let endedAt = session.endedAt else { continue }
            try await runtime.enqueue(
                recordId: session.id.uuidString.lowercased(),
                occurredAt: AnchorPlatformRecord.iso(session.startedAt),
                record: AnchorPlatformRecord.encode(session, endedAt: endedAt)
            )
        }
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
