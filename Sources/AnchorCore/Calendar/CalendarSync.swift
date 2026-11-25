import Foundation
import SwiftData

/// A planner removal identifies one Google occurrence across devices and imports.
/// CloudKit may deliver duplicate markers; membership is by key.
@Model
public final class RemovedCalendarOccurrence {
    public var eventKey: String = ""

    public init(eventKey: String) {
        self.eventKey = eventKey
    }
}

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

public extension GoogleCalendarEvent {
    static func linkedCalendar(_ key: String) -> (accountID: String, calendarID: String)? {
        let parts = key.split(separator: "\u{1F}", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return (String(parts[0]), String(parts[1]))
    }
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
    /// - Only successfully fetched account/calendar pairs provide evidence of absence.
    ///   Device-local visibility preferences never authorize deleting shared records.
    /// - A missing event may remove an untouched import or unlink historical activity.
    ///   A local override can live on a different day from the provider event, so
    ///   absence in the local window is never sufficient evidence to unlink it.
    /// - All-day events are not imported in v1; a timed event that became
    ///   all-day is treated like a cancellation.
    /// - Touched blocks always keep their content; the worst case is a cleared
    ///   link.
    public static func plan(
        events: [GoogleCalendarEvent],
        blocks: [PlanBlockRecord],
        window: DateInterval,
        fetchedCalendars: [String: Set<String>],
        removedEventKeys: Set<String> = []
    ) -> CalendarSyncPlan {
        var plan = CalendarSyncPlan()

        let managed = blocks.filter { block in
            guard let key = block.externalEventKey else { return false }
            if removedEventKeys.contains(key) {
                // A stale copy may arrive from another device after the removal.
                plan.deletions.append(block.id)
                return false
            }
            guard let source = GoogleCalendarEvent.linkedCalendar(key) else { return false }
            return fetchedCalendars[source.accountID]?.contains(source.calendarID) == true
        }
        var blocksByKey: [String: [PlanBlockRecord]] = [:]
        for block in managed where block.externalEventKey != nil {
            blocksByKey[block.externalEventKey!, default: []].append(block)
        }

        var seenKeys = Set<String>()
        for event in events where fetchedCalendars[event.accountID]?.contains(event.calendarID) == true {
            guard !removedEventKeys.contains(event.linkKey), seenKeys.insert(event.linkKey).inserted else { continue }
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

            guard let primary = linked.first(where: \.isTemplateOverride) ?? linked.first else {
                plan.creations.append(event)
                continue
            }
            if !matches(primary, event: event) {
                if isUntouched(primary) {
                    plan.updates.append(CalendarBlockUpdate(blockID: primary.id, event: event))
                } else if !primary.isTemplateOverride && primary.plannedStart != event.start {
                    // Keep the owner's original occurrence and show Google's new time.
                    plan.detachments.append(primary.id)
                    plan.creations.append(event)
                }
                // At the same start time, keep the claimed entry and its link.
                // A title or duration change must not duplicate a finished meeting.
            }
            for duplicate in linked where duplicate.id != primary.id && !duplicate.isTemplateOverride {
                if isUntouched(duplicate) { plan.deletions.append(duplicate.id) }
                else { plan.detachments.append(duplicate.id) }
            }
        }

        for block in managed
        where !block.isTemplateOverride && block.externalEventKey != nil
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
        now: Date = Date(),
        window: DateInterval? = nil,
        removedEventKeys: Set<String> = []
    ) async -> CalendarSyncReport {
        let window = window ?? CalendarSyncPolicy.syncWindow(now: now, calendar: calendar)
        let batch = await fetch(accounts: accounts, window: window)
        return batch.reconcile(blocks: blocks, removedEventKeys: removedEventKeys, now: now)
    }

    public func fetch(accounts: [CalendarSyncAccount], window: DateInterval) async -> CalendarEventBatch {
        var batch = CalendarEventBatch(window: window)
        for account in accounts {
            do {
                var events: [GoogleCalendarEvent] = []
                for calendarID in account.selectedCalendarIDs.sorted() {
                    try Task.checkCancellation()
                    events += try await store.events(
                        accessToken: account.accessToken,
                        accountID: account.id,
                        calendarID: calendarID,
                        window: window
                    )
                }
                // Only a complete account response can establish which events vanished.
                batch.events += events
                batch.fetchedCalendars[account.id] = account.selectedCalendarIDs
            } catch {
                batch.failedAccountIDs.insert(account.id)
            }
        }
        return batch
    }
}

/// Keep the network result separate from reconciliation so a long request cannot
/// overwrite edits made while it was fetching, or act on a disconnected account.
public struct CalendarEventBatch: Sendable {
    fileprivate var window: DateInterval
    fileprivate var events: [GoogleCalendarEvent] = []
    fileprivate var fetchedCalendars: [String: Set<String>] = [:]
    fileprivate var failedAccountIDs: Set<String> = []

    public func reconcile(
        blocks: [PlanBlockRecord], eligibleAccountIDs: Set<String>? = nil,
        removedEventKeys: Set<String> = [], now: Date
    ) -> CalendarSyncReport {
        let plan = CalendarSyncPolicy.plan(
            events: events,
            blocks: blocks,
            window: window,
            fetchedCalendars: fetchedCalendars.filter { eligibleAccountIDs?.contains($0.key) ?? true },
            removedEventKeys: removedEventKeys
        )
        var report = CalendarSyncReport(syncedAt: now)
        report.failedAccounts = failedAccountIDs.intersection(eligibleAccountIDs ?? failedAccountIDs)
        report.creations = plan.creations
        report.updates = plan.updates
        report.deletions = plan.deletions
        report.detachments = plan.detachments
        return report
    }
}
