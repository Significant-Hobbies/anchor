import Foundation
import Testing
@testable import AnchorCore

struct DailyChecklistTests {
    @Test func recurringItemsPersistAndOnlyTheLastTwoLocalDatesCanBeChecked() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("anchor.store")
        let store = DailyChecklistStore(storeURL: url)
        let timeZone = try #require(TimeZone(identifier: "America/New_York"))
        // The clocks changed the day before. Local midnight here is 04:00 UTC.
        let formatter = ISO8601DateFormatter()
        let beforeMidnight = try #require(formatter.date(from: "2026-03-09T03:59:59Z"))
        let afterMidnight = beforeMidnight.addingTimeInterval(1)
        let (today, yesterday) = ("2026-3-8", "2026-3-7")
        #expect(DailyChecklist.availableDates(at: beforeMidnight, timeZone: timeZone) == [today, yesterday])
        #expect(try store.load().items.isEmpty)
        let added = try store.add("  Close open tabs  ")
        let item = try #require(added.items.first)
        #expect(item.title == "Close open tabs")
        let firstCheck = try store.setChecked(true, itemID: item.id, on: yesterday, now: { beforeMidnight }, timeZone: { timeZone })
        #expect(firstCheck.items.first?.isChecked(on: today) == false)
        #expect(firstCheck.items.first?.isChecked(on: yesterday) == true)
        let secondCheck = try store.setChecked(true, itemID: item.id, on: today, now: { beforeMidnight }, timeZone: { timeZone })
        #expect(try DailyChecklistStore(storeURL: url).load() == secondCheck)

        #expect(throws: DailyChecklistStore.EditError.dateClosed) {
            try store.setChecked(false, itemID: item.id, on: yesterday, now: { afterMidnight }, timeZone: { timeZone })
        }
        #expect(throws: DailyChecklistStore.EditError.dateClosed) {
            try store.setChecked(true, itemID: item.id, on: "2026-3-10", now: { afterMidnight }, timeZone: { timeZone })
        }
        #expect(try store.load() == secondCheck)
        let nextDay = try store.setChecked(true, itemID: item.id, on: "2026-3-9", now: { afterMidnight }, timeZone: { timeZone })
        #expect(nextDay.items.first?.isChecked(on: "2026-3-9") == true)
        #expect(nextDay.items.first?.isChecked(on: today) == true)
        #expect(nextDay.items.first?.isChecked(on: yesterday) == false)
        #expect(try store.remove(item.id).items.isEmpty)
    }
}
