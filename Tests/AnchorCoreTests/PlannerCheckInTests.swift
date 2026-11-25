import Foundation
import Testing
@testable import AnchorCore

struct PlannerCheckInTests {
    @Test func checkInPersistsAndCanBeResolvedAfterBlockRemoval() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("Anchor.store")
        let store = PlannerCheckInStore(storeURL: database)
        #expect(try store.load().isEmpty)
        let id = UUID()
        let start = Date()
        func record(_ outcome: PlannerOutcome, _ text: String) -> PlannerCheckIn {
            PlannerCheckIn(id: id, title: "Send proposal", plannedStart: start, outcome: outcome, reason: text)
        }
        let blocked = record(.blocked, "  Waiting for sign-off ")
        try store.save(blocked)
        let reopened = PlannerCheckInStore(storeURL: database)
        #expect(try reopened.load()[id]?.reason == "Waiting for sign-off")
        #expect(throws: PlannerCheckInStore.ValidationError.self) { try reopened.save(record(.blocked, " ")) }
        #expect(try store.load()[id] == blocked)
        for outcome in [PlannerOutcome.unsuccessful, .successful] {
            try reopened.save(record(outcome, "old reason"))
            #expect(try store.load()[id]?.outcome == outcome)
            #expect(try store.load()[id]?.reason == "")
        }
        #expect(try PlannerCheckInStore(storeURL: root.appendingPathComponent("other.store")).load().isEmpty)
    }

    @Test func defaultStartFitsBetweenCalendarAndManualEntries() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        func minutes(_ count: Int) -> Date { now.addingTimeInterval(Double(count * 60)) }
        let entries = [DateInterval(start: minutes(100), end: minutes(150)),
                       DateInterval(start: minutes(10), end: minutes(40)),
                       DateInterval(start: minutes(20), end: minutes(50))]
        #expect(PlannerGap.suggestedStart(from: now, until: minutes(200), occupied: entries) == minutes(50))
        #expect(PlannerGap.suggestedStart(from: now, until: minutes(40), occupied: entries) == now)
    }
}
