import Foundation
import Testing
import UserNotifications

@testable import AnchorCore

@Suite("Planner start reminders")
struct PlannerStartReminderTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor
    @Test func recurringEntryIsScheduledBeforeOpeningItsDay() throws {
        let calendar = Calendar.current
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)))
        let template = ScheduleTemplate(title: "Read", startMinutesFromMidnight: 600, plannedSeconds: 300)
        let block = PlanBlock(template: template, day: tomorrow, calendar: calendar)
        let projected = PlannerStartReminder.upcoming(blocks: [], templates: [template], now: now, calendar: calendar)
        let original = try #require(projected.first { $0.start == block.plannedStart })
        block.title = "Read chapter two"
        let materialized = PlannerStartReminder.upcoming(blocks: [block], templates: [template], now: now, calendar: calendar)
        #expect(materialized.filter { $0.key == original.key }.map(\.title) == ["Read chapter two"])
        block.state = .completed
        #expect(!PlannerStartReminder.upcoming(blocks: [block], templates: [template], now: now, calendar: calendar).contains { $0.key == original.key })
    }

    @Test func ordersFutureAlertsAndLeavesCapacityForOtherNotifications() {
        let entries = (0..<5).map { PlannerStartReminder(id: UUID(), title: "Entry \($0)", start: now.addingTimeInterval(Double($0) * 120)) }
        let requests = PlannerReminderUpdate(entries: entries.reversed(), leadMinutes: 1).requests(now: now, otherPending: 58)
        #expect(requests.map(\.content.title) == ["Entry 1", "Entry 2"])
        #expect((requests.first?.trigger as? UNCalendarNotificationTrigger)?.dateComponents.second == 0)
        #expect(requests.first?.content.body == "Starts in 1 min")
    }

    @Test func startsInsideLeadWindowAlertOnceAtStart() throws {
        let entry = PlannerStartReminder(id: UUID(), title: "Starting soon", start: now.addingTimeInterval(30))
        let update = PlannerReminderUpdate(entries: [entry], leadMinutes: 1)
        let request = try #require(update.requests(now: now, otherPending: 0).first)
        #expect(request.content.body == "Starts now")
        #expect((request.trigger as? UNCalendarNotificationTrigger)?.dateComponents.date == entry.start)
        let alreadyDue = ScheduledPlannerReminder(start: entry.start, fire: now.addingTimeInterval(-30))
        #expect(update.requests(now: now, otherPending: 0, scheduled: [request.identifier: alreadyDue]).isEmpty)
        #expect(update.requests(now: entry.start, otherPending: 0).isEmpty)
    }

    @Test func editsReplaceTheSameIdentifierAndOffSchedulesNothing() throws {
        let id = UUID()
        let original = PlannerStartReminder(id: id, title: "First", start: now.addingTimeInterval(600))
        let edited = PlannerStartReminder(id: id, title: "Updated", start: now.addingTimeInterval(1200))
        let before = try #require(PlannerReminderUpdate(entries: [original], leadMinutes: 1).requests(now: now, otherPending: 0).first)
        let after = try #require(PlannerReminderUpdate(entries: [edited], leadMinutes: 0).requests(now: now, otherPending: 0).first)
        #expect(before.identifier == after.identifier)
        #expect(after.identifier.hasPrefix("anchor.planner.start."))
        #expect(after.content.title == "Updated")
        #expect(after.content.body == "Starts now")
        let trigger = try #require(after.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents.date == edited.start)
        #expect(PlannerReminderUpdate(entries: [edited], leadMinutes: -1).requests(now: now, otherPending: 0).isEmpty)
    }
}
