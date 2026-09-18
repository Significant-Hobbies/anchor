import Foundation
import SwiftData
import Testing

@testable import AnchorCore

private final class MockRemindersStore: RemindersStoreProtocol, @unchecked Sendable {
    var accessGranted = true
    var lists = [ReminderListInfo(id: "list-default", title: "Reminders")]
    var reminders: [String: SyncedReminder] = [:]
    var deleted: [String] = []
    var upsertCalls = 0
    private var nextID = 0

    func requestAccess() async throws -> Bool { accessGranted }

    func reminderLists() async throws -> [ReminderListInfo] { lists }

    func defaultListID() async throws -> String? { "list-default" }

    func fetchLinkedReminders(links: [UUID: String]) async throws -> [SyncedReminder] {
        links.compactMap { blockID, externalID in
            reminders[externalID].map {
                var copy = $0
                copy.blockID = blockID
                return copy
            }
        }
    }

    func upsert(_ reminder: SyncedReminder, blockID: UUID, listID: String) async throws -> String {
        upsertCalls += 1
        let externalID = reminder.externalID.isEmpty ? newID() : reminder.externalID
        reminders[externalID] = SyncedReminder(
            externalID: externalID,
            blockID: blockID,
            title: reminder.title,
            dueDate: reminder.dueDate,
            isCompleted: reminder.isCompleted,
            listID: listID,
            notes: reminder.notes
        )
        return externalID
    }

    func delete(externalID: String) async throws {
        deleted.append(externalID)
        reminders[externalID] = nil
    }

    private func newID() -> String {
        nextID += 1
        return "reminder-\(nextID)"
    }
}

@Suite("Reminders sync")
struct RemindersSyncTests {
    private let now = Date(timeIntervalSince1970: 1_757_836_800) // 2025-09-14 00:00 UTC
    private var window: DateInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return RemindersSyncPolicy.syncWindow(now: now, calendar: calendar)
    }

    private func block(
        _ title: String,
        dayOffset: Double = 3600,
        state: PlanBlockState = .planned,
        externalID: String? = nil,
        details: String = ""
    ) -> PlanBlockRecord {
        PlanBlockRecord(
            id: UUID(),
            title: title,
            details: details,
            plannedStart: now.addingTimeInterval(dayOffset),
            plannedSeconds: 1_800,
            state: state,
            reminderExternalIdentifier: externalID
        )
    }

    @Test("New in-window blocks create linked reminders; blocks outside the window do not")
    func createsRemindersOnlyInsideWindow() async throws {
        let inside = block("Write")
        let outside = block("Far out", dayOffset: 10 * 86_400)
        let store = MockRemindersStore()
        let service = RemindersSyncService(store: store)

        let report = try await service.sync(blocks: [inside, outside], listID: nil, exportDetails: false, now: now)

        #expect(report.upserted == 1)
        #expect(store.reminders.count == 1)
        #expect(store.reminders.values.first?.title == "Write")
        #expect(store.reminders.values.first?.blockID == inside.id)
        #expect(store.reminders.values.first?.listID == "list-default")
        #expect(report.writebacks.count == 1)
    }

    @Test("Block fields map to reminder fields and details stay private by default")
    func mapsFieldsAndKeepsDetailsPrivate() async throws {
        let record = block("Deep work", details: "secret notes")
        let store = MockRemindersStore()
        let service = RemindersSyncService(store: store)

        _ = try await service.sync(blocks: [record], listID: nil, exportDetails: false, now: now)
        let reminder = store.reminders.values.first!
        #expect(reminder.title == "Deep work")
        #expect(reminder.dueDate == record.plannedStart)
        #expect(reminder.notes == nil)
        #expect(reminder.isCompleted == false)
    }

    @Test("Details export only when explicitly opted in")
    func detailsOptIn() async throws {
        let record = block("Deep work", details: "bring charger")
        let store = MockRemindersStore()
        let service = RemindersSyncService(store: store)

        _ = try await service.sync(blocks: [record], listID: nil, exportDetails: true, now: now)
        #expect(store.reminders.values.first?.notes == "bring charger")
    }

    @Test("An unchanged block does not re-upsert")
    func stableBlocksSkipUpsert() async throws {
        let record = block("Write", externalID: "existing-1")
        let store = MockRemindersStore()
        store.reminders["existing-1"] = SyncedReminder(
            externalID: "existing-1",
            blockID: record.id,
            title: "Write",
            dueDate: record.plannedStart,
            isCompleted: false,
            listID: "list-default"
        )
        let service = RemindersSyncService(store: store)

        let report = try await service.sync(blocks: [record], listID: nil, exportDetails: false, now: now)
        #expect(report.upserted == 0)
        #expect(store.upsertCalls == 0)
    }

    @Test("Changed block state updates the linked reminder")
    func completionPropagatesToReminder() async throws {
        let record = block("Write", state: .completed, externalID: "existing-1")
        let store = MockRemindersStore()
        store.reminders["existing-1"] = SyncedReminder(
            externalID: "existing-1", blockID: record.id, title: "Write",
            dueDate: record.plannedStart, isCompleted: false, listID: "list-default"
        )
        let service = RemindersSyncService(store: store)

        _ = try await service.sync(blocks: [record], listID: nil, exportDetails: false, now: now)
        #expect(store.reminders["existing-1"]?.isCompleted == true)
    }

    @Test("External completion flows back to an uncompleted block")
    func externalCompletionFlowsBack() async throws {
        let record = block("Write", externalID: "existing-1")
        let store = MockRemindersStore()
        store.reminders["existing-1"] = SyncedReminder(
            externalID: "existing-1", blockID: record.id, title: "Write",
            dueDate: record.plannedStart, isCompleted: true, listID: "list-default"
        )
        let service = RemindersSyncService(store: store)

        let report = try await service.sync(blocks: [record], listID: nil, exportDetails: false, now: now)
        #expect(report.externalCompletions == [record.id])
    }

    @Test("An uncompleted reminder does not reopen a completed block")
    func completionIsMonotonic() async throws {
        let record = block("Write", state: .completed, externalID: "existing-1")
        let store = MockRemindersStore()
        store.reminders["existing-1"] = SyncedReminder(
            externalID: "existing-1", blockID: record.id, title: "Write",
            dueDate: record.plannedStart, isCompleted: false, listID: "list-default"
        )
        let service = RemindersSyncService(store: store)

        let report = try await service.sync(blocks: [record], listID: nil, exportDetails: false, now: now)
        // The reminder gets aligned to the completed block instead of the
        // block regressing.
        #expect(store.reminders["existing-1"]?.isCompleted == true)
        #expect(report.externalCompletions.isEmpty)
    }

    @Test("A linked reminder whose block left the window is deleted")
    func outOfWindowLinksAreDeleted() async throws {
        let store = MockRemindersStore()
        let blockID = UUID()
        store.reminders["stale-1"] = SyncedReminder(
            externalID: "stale-1", blockID: blockID, title: "Old",
            dueDate: now.addingTimeInterval(30 * 86_400), isCompleted: false, listID: "list-default"
        )
        let stale = PlanBlockRecord(
            id: blockID, title: "Old",
            plannedStart: now.addingTimeInterval(30 * 86_400), plannedSeconds: 600,
            reminderExternalIdentifier: "stale-1"
        )
        let service = RemindersSyncService(store: store)

        let report = try await service.sync(blocks: [stale], listID: nil, exportDetails: false, now: now)
        #expect(report.deleted == 1)
        #expect(store.reminders["stale-1"] == nil)
        #expect(report.writebacks.contains { $0.blockID == blockID && $0.externalID == "" })
    }

    @Test("A block whose reminder vanished re-exports with a fresh link")
    func vanishedReminderReExports() async throws {
        let record = block("Write", externalID: "gone-1")
        let store = MockRemindersStore()
        let service = RemindersSyncService(store: store)

        let report = try await service.sync(blocks: [record], listID: nil, exportDetails: false, now: now)
        // The block re-exports; the new identifier replaces the dead link.
        #expect(report.upserted == 1)
        let writeback = report.writebacks.first { $0.blockID == record.id }
        #expect(writeback?.externalID.isEmpty == false)
        #expect(store.reminders.count == 1)
    }

    @Test("Missing configured list fails closed")
    func missingListFailsClosed() async throws {
        let service = RemindersSyncService(store: MissingListStore())
        await #expect(throws: RemindersSyncError.noList) {
            try await service.sync(blocks: [block("x")], listID: nil, exportDetails: false, now: now)
        }
    }

    @Test("Sync window covers today plus seven days")
    func windowIsTodayPlusSeven() {
        #expect(window.end.timeIntervalSince(window.start) == 8 * 86_400)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        #expect(window.start == calendar.startOfDay(for: now))
    }
}

private struct MissingListStore: RemindersStoreProtocol {
    func requestAccess() async throws -> Bool { true }
    func reminderLists() async throws -> [ReminderListInfo] { [] }
    func defaultListID() async throws -> String? { nil }
    func fetchLinkedReminders(links: [UUID: String]) async throws -> [SyncedReminder] { [] }
    func upsert(_ reminder: SyncedReminder, blockID: UUID, listID: String) async throws -> String { "" }
    func delete(externalID: String) async throws {}
}
