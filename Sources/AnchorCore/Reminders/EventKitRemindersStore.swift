#if os(macOS) || os(iOS)
import EventKit
import Foundation

/// The real EventKit adapter. Used on Mac and iPhone; the watch has no
/// Reminders editing surface so it never constructs this.
public final class EventKitRemindersStore: RemindersStoreProtocol, @unchecked Sendable {
    private let eventStore = EKEventStore()

    public init() {}

    public func requestAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToReminders()
    }

    public func reminderLists() async throws -> [ReminderListInfo] {
        eventStore.calendars(for: .reminder)
            .filter(\.allowsContentModifications)
            .map { ReminderListInfo(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title < $1.title }
    }

    public func defaultListID() async throws -> String? {
        eventStore.defaultCalendarForNewReminders()?.calendarIdentifier
    }

    public func fetchLinkedReminders(links: [UUID: String]) async throws -> [SyncedReminder] {
        var found: [SyncedReminder] = []
        for (blockID, externalID) in links {
            guard let reminder = eventStore.calendarItem(withIdentifier: externalID) as? EKReminder else {
                continue
            }
            found.append(
                SyncedReminder(
                    externalID: reminder.calendarItemExternalIdentifier ?? externalID,
                    blockID: blockID,
                    title: reminder.title ?? "",
                    dueDate: reminder.dueDateComponents?.date,
                    isCompleted: reminder.isCompleted,
                    listID: reminder.calendar.calendarIdentifier,
                    notes: reminder.notes
                )
            )
        }
        return found
    }

    public func upsert(_ reminder: SyncedReminder, blockID: UUID, listID: String) async throws -> String {
        let ekReminder = reminder.externalID.isEmpty
            ? nil
            : eventStore.calendarItem(withIdentifier: reminder.externalID) as? EKReminder
        let target = ekReminder ?? EKReminder(eventStore: eventStore)
        target.title = reminder.title
        target.isCompleted = reminder.isCompleted
        target.notes = reminder.notes
        target.dueDateComponents = reminder.dueDate.map {
            Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0)
        }
        if ekReminder == nil || target.calendar.calendarIdentifier != listID,
           let list = eventStore.calendar(withIdentifier: listID) {
            target.calendar = list
        }
        try eventStore.save(target, commit: true)
        return target.calendarItemExternalIdentifier ?? reminder.externalID
    }

    public func delete(externalID: String) async throws {
        guard let reminder = eventStore.calendarItem(withIdentifier: externalID) as? EKReminder else {
            return
        }
        try eventStore.remove(reminder, commit: true)
    }
}
#endif
