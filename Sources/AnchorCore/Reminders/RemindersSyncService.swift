import Foundation

/// What one sync pass did, for status display and tests.
public struct RemindersSyncReport: Sendable, Equatable {
    public var upserted: Int = 0
    public var deleted: Int = 0
    public var externalCompletions: [UUID] = []
    public var writebacks: [ReminderWriteback] = []
    public var syncedAt: Date

    public init(syncedAt: Date) {
        self.syncedAt = syncedAt
    }
}

/// Orchestrates one reconciliation pass between the current plan window and
/// the linked Reminders list. The service holds no EventKit dependency — the
/// store protocol supplies it — and returns writebacks/completions rather
/// than touching SwiftData, so callers decide when to commit.
public struct RemindersSyncService: Sendable {
    public var store: any RemindersStoreProtocol
    public var calendar: Calendar

    public init(store: any RemindersStoreProtocol, calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    public func sync(
        blocks: [PlanBlockRecord],
        listID: String?,
        exportDetails: Bool,
        now: Date = Date()
    ) async throws -> RemindersSyncReport {
        let resolvedList = if let listID { listID } else { try await store.defaultListID() }
        guard let resolvedList else { throw RemindersSyncError.noList }

        let window = RemindersSyncPolicy.syncWindow(now: now, calendar: calendar)
        let links = Dictionary(
            blocks.compactMap { block in
                block.reminderExternalIdentifier.map { (block.id, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let linked = try await store.fetchLinkedReminders(links: links)
        let plan = RemindersSyncPolicy.plan(
            blocks: blocks,
            linkedReminders: linked,
            listID: resolvedList,
            exportDetails: exportDetails,
            window: window
        )

        var report = RemindersSyncReport(syncedAt: now)
        report.externalCompletions = plan.externalCompletions

        for upsert in plan.upserts {
            let externalID = try await store.upsert(
                upsert.reminder, blockID: upsert.blockID, listID: resolvedList
            )
            report.upserted += 1
            report.writebacks.append(
                ReminderWriteback(blockID: upsert.blockID, externalID: externalID, syncedAt: now)
            )
        }
        let blockByReminder = Dictionary(
            linked.compactMap { reminder in reminder.blockID.map { (reminder.externalID, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        for externalID in plan.deletions {
            try await store.delete(externalID: externalID)
            report.deleted += 1
            if let blockID = blockByReminder[externalID] {
                report.writebacks.append(
                    ReminderWriteback(blockID: blockID, externalID: "", syncedAt: now)
                )
            }
        }
        // Blocks whose link disappeared (reminder deleted in Reminders, or the
        // list changed) also need their stale identifier cleared — unless this
        // pass already issued them a fresh link via upsert.
        let linkedBlockIDs = Set(linked.compactMap(\.blockID))
        let upsertedBlockIDs = Set(plan.upserts.map(\.blockID))
        for block in blocks
        where block.reminderExternalIdentifier != nil
            && !linkedBlockIDs.contains(block.id)
            && !upsertedBlockIDs.contains(block.id) {
            report.writebacks.append(
                ReminderWriteback(blockID: block.id, externalID: "", syncedAt: now)
            )
        }
        return report
    }
}
