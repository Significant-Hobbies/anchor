#if !os(watchOS)
import CryptoKit
import Foundation
import Observation
import PersonalSyncKit
import SwiftData

@MainActor
@Observable
public final class AnchorPlatformSync {
    private let context: ModelContext
    private let connection: PersonalPlatformConnection?
    private let receiptStore: HubSyncReceiptStore
    public let account: PersonalAccountModel?
    public private(set) var isSyncing = false
    public private(set) var pendingCount = 0
    public private(set) var receipt: HubSyncReceipt

    public init(
        context: ModelContext,
        enabled: Bool = true,
        receiptStore: HubSyncReceiptStore = HubSyncReceiptStore()
    ) {
        self.context = context
        self.receiptStore = receiptStore
        receipt = receiptStore.load()
        guard enabled else {
            connection = nil
            account = nil
            return
        }
        let defaults = UserDefaults.standard
        let deviceKey = "personal-platform-device-id"
        let deviceId = defaults.string(forKey: deviceKey) ?? UUID().uuidString.lowercased()
        defaults.set(deviceId, forKey: deviceKey)
        let connection = try? PersonalPlatformConnection(
            domain: .anchor,
            keychainService: "com.significanthobbies.anchor.personal-platform",
            supportDirectory: AnchorStore.storeURL().deletingLastPathComponent(),
            deviceId: deviceId
        )
        self.connection = connection
        account = connection.map {
            PersonalAccountModel(identity: $0.identity, callbackScheme: "anchor")
        }
    }

    public func restoreAndSynchronize() async {
        let hadBearer = await hasBearerToken()
        await account?.restore()
        await refreshPendingCount()
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
        await account?.connect()
        await synchronize(announcing: true)
    }

    public func disconnect() async {
        await account?.signOut()
        receipt.failure = nil
        receipt.failedAt = nil
        receiptStore.save(receipt)
        await refreshPendingCount()
    }

    public func synchronize(announcing _: Bool = false) async {
        guard let connection, account?.isSignedIn == true, !isSyncing else {
            await refreshPendingCount()
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await enqueueFinishedSessions(using: connection)
            pendingCount = await connection.sync.pendingMutationCount()
            let changes = try await connection.sync.synchronize()
            try apply(changes)
            pendingCount = await connection.sync.pendingMutationCount()
            receipt.recordSuccess(at: Date())
            receiptStore.save(receipt)
        } catch {
            pendingCount = await connection.sync.pendingMutationCount()
            recordFailure(HubSyncFailure.classify(error))
        }
    }

    public func refreshPendingCount() async {
        guard let connection else {
            pendingCount = 0
            return
        }
        pendingCount = await connection.sync.pendingMutationCount()
    }

    private func hasBearerToken() async -> Bool {
        guard let connection else { return false }
        return (try? await connection.identity.bearerToken()) != nil
    }

    private func recordFailure(_ failure: HubSyncFailure) {
        receipt.recordFailure(failure, at: Date())
        receiptStore.save(receipt)
    }

    private func enqueueFinishedSessions(using connection: PersonalPlatformConnection) async throws {
        let sessions = try context.fetch(FetchDescriptor<FocusSession>())
            .filter { $0.endedAt != nil }
        for session in sessions {
            guard let endedAt = session.endedAt else { continue }
            try await connection.sync.enqueue(
                recordId: session.id.uuidString.lowercased(),
                occurredAt: AnchorPlatformRecord.iso(session.startedAt),
                record: AnchorPlatformRecord.encode(session, endedAt: endedAt)
            )
        }
    }

    private func apply(_ changes: [SyncChange]) throws {
        let existing = try context.fetch(FetchDescriptor<FocusSession>())
        for change in changes {
            let id = AnchorPlatformRecord.stableUUID(change.id)
            if change.operation == .delete {
                if let session = existing.first(where: { $0.id == id }) { context.delete(session) }
                continue
            }
            guard !existing.contains(where: { $0.id == id }),
                  let session = AnchorPlatformRecord.decode(change) else { continue }
            context.insert(session)
        }
        if context.hasChanges { try context.save() }
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
