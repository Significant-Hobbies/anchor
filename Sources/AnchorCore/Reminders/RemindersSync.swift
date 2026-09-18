import Foundation

/// A value-type mirror of a Reminders entry. The sync core never touches
/// EventKit directly — it reconciles `PlanBlockRecord` snapshots against
/// these records so the whole policy is testable without device permission.
public struct SyncedReminder: Sendable, Equatable {
    public var externalID: String
    public var blockID: UUID?
    public var title: String
    public var dueDate: Date?
    public var isCompleted: Bool
    public var listID: String
    public var notes: String?

    public init(
        externalID: String,
        blockID: UUID?,
        title: String,
        dueDate: Date?,
        isCompleted: Bool,
        listID: String,
        notes: String? = nil
    ) {
        self.externalID = externalID
        self.blockID = blockID
        self.title = title
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.listID = listID
        self.notes = notes
    }
}

public struct ReminderListInfo: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// Everything the sync needs from EventKit, injectable so tests supply a
/// deterministic store instead of a real EKEventStore.
public protocol RemindersStoreProtocol: Sendable {
    func requestAccess() async throws -> Bool
    func reminderLists() async throws -> [ReminderListInfo]
    func defaultListID() async throws -> String?
    /// Reminders for known block→external-id links. Implementations resolve
    /// the reminder by its store identifier and report which block it serves.
    func fetchLinkedReminders(links: [UUID: String]) async throws -> [SyncedReminder]
    /// Creates or updates a reminder for the block; returns its external id.
    func upsert(_ reminder: SyncedReminder, blockID: UUID, listID: String) async throws -> String
    func delete(externalID: String) async throws
}

public enum RemindersSyncError: Error, Equatable {
    case accessDenied
    case noList
}

public struct RemindersUpsert: Sendable, Equatable {
    public var blockID: UUID
    public var reminder: SyncedReminder

    public init(blockID: UUID, reminder: SyncedReminder) {
        self.blockID = blockID
        self.reminder = reminder
    }
}

public struct ReminderWriteback: Sendable, Equatable {
    public var blockID: UUID
    public var externalID: String
    public var syncedAt: Date

    public init(blockID: UUID, externalID: String, syncedAt: Date) {
        self.blockID = blockID
        self.externalID = externalID
        self.syncedAt = syncedAt
    }
}

/// The reconciliation a single sync pass must perform. Pure data so tests
/// assert the plan without a store.
public struct RemindersSyncPlan: Sendable, Equatable {
    /// Reminders to create or update (block → desired reminder contents).
    public var upserts: [RemindersUpsert] = []
    /// Linked reminders whose block is gone, archived, or out of window.
    public var deletions: [String] = []
    /// Blocks a reminder marked complete externally — completion flows back.
    public var externalCompletions: [UUID] = []

    public init() {}
}

public enum RemindersSyncPolicy {
    /// MVP window: today plus the next seven days.
    public static func syncWindow(now: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 8, to: start) ?? start.addingTimeInterval(8 * 86_400)
        return DateInterval(start: start, end: end)
    }

    public static func isInWindow(_ block: PlanBlockRecord, window: DateInterval) -> Bool {
        block.plannedStart >= window.start && block.plannedStart < window.end
    }

    /// What the reminder should say for a block. `details` is opt-in only;
    /// Distraction and session notes never appear here by construction.
    public static func desiredReminder(
        for block: PlanBlockRecord,
        listID: String,
        exportDetails: Bool,
        existingExternalID: String? = nil
    ) -> SyncedReminder {
        SyncedReminder(
            externalID: existingExternalID ?? "",
            blockID: block.id,
            title: block.title,
            dueDate: block.plannedStart,
            isCompleted: block.state == .completed,
            listID: listID,
            notes: exportDetails && !block.details.isEmpty ? block.details : nil
        )
    }

    /// Reconcile desired state (blocks in window) against linked reminders.
    ///
    /// - Blocks in the window upsert; blocks outside it don't create reminders
    ///   and lose any stale link.
    /// - A linked reminder whose block vanished or left the window is deleted.
    /// - External completion flows back one way: a completed reminder marks a
    ///   still-uncompleted block for completion; the reverse (an uncompleted
    ///   reminder reopening a completed block) is ignored — completion is
    ///   monotonic so a stray uncheck can't resurrect finished work.
    public static func plan(
        blocks: [PlanBlockRecord],
        linkedReminders: [SyncedReminder],
        listID: String,
        exportDetails: Bool,
        window: DateInterval
    ) -> RemindersSyncPlan {
        var plan = RemindersSyncPlan()
        let blocksByID = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })
        let reminderByBlock = Dictionary(
            linkedReminders.compactMap { reminder in
                reminder.blockID.map { ($0, reminder) }
            },
            uniquingKeysWith: { first, _ in first }
        )

        for block in blocks where isInWindow(block, window: window) {
            let linked = reminderByBlock[block.id]
            let desired = desiredReminder(
                for: block,
                listID: listID,
                exportDetails: exportDetails,
                existingExternalID: linked?.externalID
            )
            if needsUpsert(desired: desired, existing: linked) {
                plan.upserts.append(RemindersUpsert(blockID: block.id, reminder: desired))
            }
            if linked?.isCompleted == true, block.state != .completed {
                plan.externalCompletions.append(block.id)
            }
        }

        for reminder in linkedReminders {
            guard let blockID = reminder.blockID else { continue }
            let block = blocksByID[blockID]
            let stale = block == nil || !isInWindow(block!, window: window)
            if stale && reminder.listID == listID {
                plan.deletions.append(reminder.externalID)
            }
        }
        return plan
    }

    private static func needsUpsert(desired: SyncedReminder, existing: SyncedReminder?) -> Bool {
        guard let existing else { return true }
        return existing.title != desired.title
            || existing.isCompleted != desired.isCompleted
            || existing.dueDate != desired.dueDate
            || existing.notes != desired.notes
            || existing.listID != desired.listID
    }
}
