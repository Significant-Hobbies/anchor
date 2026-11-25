import Foundation
import Testing
@testable import AnchorCore

struct PlannerCheckInTests {
    @Test func checkInPersistsAndCanBeResolvedAfterBlockRemoval() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("Anchor.store")
        let store = PlannerCheckInStore(storeURL: database)
        #expect(try store.load().records.isEmpty)
        let id = UUID()
        let start = Date()
        func record(_ outcome: PlannerOutcome, _ text: String) -> PlannerCheckIn {
            PlannerCheckIn(id: id, title: "Send proposal", plannedStart: start, outcome: outcome, reason: text)
        }
        let blocked = record(.blocked, "  Waiting for sign-off ")
        try store.save(blocked)
        let directory = database.appendingPathExtension("planner-check-ins")
        let file = directory.appendingPathComponent(id.uuidString + ".json")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
        let wrongID = directory.appendingPathComponent(UUID().uuidString + ".json")
        try FileManager.default.copyItem(at: file, to: wrongID)
        #expect(try store.load().hasUnreadableFiles)
        let malformed = directory.appendingPathComponent("bad.json")
        try Data("bad".utf8).write(to: malformed)
        #expect(try store.load().hasUnreadableFiles)
        let reopened = PlannerCheckInStore(storeURL: database)
        #expect(try reopened.load().records[id]?.reason == "Waiting for sign-off")
        #expect(throws: PlannerCheckInStore.ValidationError.self) { try reopened.save(record(.blocked, " ")) }
        #expect(try store.load().records[id] == blocked)
        for outcome in [PlannerOutcome.unsuccessful, .successful] {
            try reopened.save(record(outcome, "old reason"))
            #expect(try store.load().records[id]?.outcome == outcome)
            #expect(try store.load().records[id]?.reason == "")
        }
        #expect(try PlannerCheckInStore(storeURL: root.appendingPathComponent("other.store")).load().records.isEmpty)
    }

    @Test func defaultStartFitsBetweenCalendarAndManualEntries() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        func minutes(_ count: Int) -> Date { now.addingTimeInterval(Double(count * 60)) }
        #expect(PlannerGap.opening(from: now, until: minutes(4), occupied: []) == nil)
        let entries = [DateInterval(start: minutes(100), end: minutes(150)),
                       DateInterval(start: minutes(10), end: minutes(40)),
                       DateInterval(start: minutes(20), end: minutes(50))]
        #expect(PlannerGap.opening(from: now, until: minutes(200), occupied: entries) == DateInterval(start: minutes(50), duration: 1800))
        #expect(PlannerGap.opening(from: now, until: minutes(40), occupied: entries) == DateInterval(start: now, duration: 600))
    }
}
