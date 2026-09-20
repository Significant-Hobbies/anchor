import Foundation

/// A Google account participating in one sync pass, with its resolved access
/// token and the calendars the owner chose to import from.
public struct CalendarSyncAccount: Sendable, Equatable {
    public var id: String
    public var accessToken: String
    public var selectedCalendarIDs: Set<String>

    public init(id: String, accessToken: String, selectedCalendarIDs: Set<String>) {
        self.id = id
        self.accessToken = accessToken
        self.selectedCalendarIDs = selectedCalendarIDs
    }
}

public struct CalendarBlockUpdate: Sendable, Equatable {
    public var blockID: UUID
    public var event: GoogleCalendarEvent

    public init(blockID: UUID, event: GoogleCalendarEvent) {
        self.blockID = blockID
        self.event = event
    }
}

/// The reconciliation a single import pass must perform. Pure data so tests
/// assert the plan without a store or network.
public struct CalendarSyncPlan: Sendable, Equatable {
    /// Events with no linked block — one `.commitment` block each.
    public var creations: [GoogleCalendarEvent] = []
    /// Linked, untouched blocks whose event changed.
    public var updates: [CalendarBlockUpdate] = []
    /// Blocks to remove: untouched blocks whose event was cancelled, became
    /// all-day, or vanished — plus untouched duplicates of the same event.
    public var deletions: [UUID] = []
    /// Blocks to keep but unlink: owner-touched blocks whose event changed,
    /// vanished, or was cancelled — and touched duplicates.
    public var detachments: [UUID] = []

    public init() {}
}

public enum CalendarSyncPolicy {
    /// Same rolling window as the Reminders sync: today plus the next seven
    /// days.
    public static func syncWindow(now: Date, calendar: Calendar = .current) -> DateInterval {
        RemindersSyncPolicy.syncWindow(now: now, calendar: calendar)
    }

    public static func isInWindow(_ block: PlanBlockRecord, window: DateInterval) -> Bool {
        block.plannedStart >= window.start && block.plannedStart < window.end
    }

    /// A block the owner has not claimed. Once it is started, completed,
    /// skipped, moved, or edited it is theirs — sync must never rewrite it.
    /// `isTemplateOverride` doubles as the edited marker: the editor sets it
    /// when an imported block is changed by hand.
    public static func isUntouched(_ block: PlanBlockRecord) -> Bool {
        block.state == .planned
            && block.sessionID == nil
            && block.actualStartedAt == nil
            && !block.isTemplateOverride
    }

    /// Whether the linked event still matches what the block shows.
    static func matches(_ block: PlanBlockRecord, event: GoogleCalendarEvent) -> Bool {
        block.title == event.title
            && block.plannedStart == event.start
            && block.plannedSeconds == max(60, Int(event.end.timeIntervalSince(event.start)))
    }

    /// Reconcile fetched events against linked blocks.
    ///
    /// - Only blocks whose link belongs to a managed account are considered —
    ///   a disconnected or failed account's blocks must not look "vanished".
    /// - A vanished event (deleted upstream, moved outside the window, or on a
    ///   calendar the owner unselected) removes untouched blocks and detaches
    ///   touched ones.
    /// - All-day events are not imported in v1; a timed event that became
    ///   all-day is treated like a cancellation.
    /// - Touched blocks always keep their content; the worst case is a cleared
    ///   link.
    public static func plan(
        events: [GoogleCalendarEvent],
        blocks: [PlanBlockRecord],
        window: DateInterval,
        managedAccountIDs: Set<String>
    ) -> CalendarSyncPlan {
        var plan = CalendarSyncPlan()

        let managed = blocks.filter { block in
            guard let key = block.externalEventKey,
                  let accountID = key.components(separatedBy: "\u{1F}").first
            else { return false }
            return managedAccountIDs.contains(accountID)
        }
        var blocksByKey: [String: [PlanBlockRecord]] = [:]
        for block in managed where block.externalEventKey != nil {
            blocksByKey[block.externalEventKey!, default: []].append(block)
        }

        var seenKeys = Set<String>()
        for event in events {
            seenKeys.insert(event.linkKey)
            let linked = blocksByKey[event.linkKey] ?? []

            // Cancelled or all-day events cannot be represented: untouched
            // blocks go, touched ones are detached.
            guard !event.isCancelled, !event.isAllDay else {
                for block in linked {
                    if isUntouched(block) { plan.deletions.append(block.id) }
                    else { plan.detachments.append(block.id) }
                }
                continue
            }

            guard let primary = linked.first else {
                plan.creations.append(event)
                continue
            }
            if isUntouched(primary) {
                if !matches(primary, event: event) {
                    plan.updates.append(CalendarBlockUpdate(blockID: primary.id, event: event))
                }
            } else {
                plan.detachments.append(primary.id)
            }
            for duplicate in linked.dropFirst() {
                if isUntouched(duplicate) { plan.deletions.append(duplicate.id) }
                else { plan.detachments.append(duplicate.id) }
            }
        }

        for block in managed
        where block.externalEventKey != nil
            && isInWindow(block, window: window)
            && !seenKeys.contains(block.externalEventKey!) {
            if isUntouched(block) { plan.deletions.append(block.id) }
            else { plan.detachments.append(block.id) }
        }
        return plan
    }
}

/// What one import pass did, for status display and tests.
public struct CalendarSyncReport: Sendable, Equatable {
    public var creations: [GoogleCalendarEvent] = []
    public var updates: [CalendarBlockUpdate] = []
    public var deletions: [UUID] = []
    public var detachments: [UUID] = []
    /// Accounts whose fetch failed — their blocks were left completely alone.
    public var failedAccounts: Set<String> = []
    public var syncedAt: Date

    public init(syncedAt: Date) {
        self.syncedAt = syncedAt
    }
}

/// Orchestrates one import pass across every connected account. Holds no
/// Google OAuth state — callers resolve access tokens per account — and never
/// touches SwiftData; the report describes mutations for the caller to apply.
public struct CalendarSyncService: Sendable {
    public var store: any GoogleCalendarStoreProtocol
    public var calendar: Calendar

    public init(store: any GoogleCalendarStoreProtocol, calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    public func sync(
        accounts: [CalendarSyncAccount],
        blocks: [PlanBlockRecord],
        now: Date = Date()
    ) async -> CalendarSyncReport {
        let window = CalendarSyncPolicy.syncWindow(now: now, calendar: calendar)
        var report = CalendarSyncReport(syncedAt: now)
        var events: [GoogleCalendarEvent] = []

        for account in accounts {
            do {
                for calendarID in account.selectedCalendarIDs {
                    events += try await store.events(
                        accessToken: account.accessToken,
                        accountID: account.id,
                        calendarID: calendarID,
                        window: window
                    )
                }
            } catch {
                report.failedAccounts.insert(account.id)
            }
        }

        let managedIDs = Set(accounts.map(\.id)).subtracting(report.failedAccounts)
        let plan = CalendarSyncPolicy.plan(
            events: events,
            blocks: blocks,
            window: window,
            managedAccountIDs: managedIDs
        )
        report.creations = plan.creations
        report.updates = plan.updates
        report.deletions = plan.deletions
        report.detachments = plan.detachments
        return report
    }
}
