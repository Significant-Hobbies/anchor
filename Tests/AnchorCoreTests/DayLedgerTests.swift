import Foundation
import Testing
@testable import AnchorCore

struct DayLedgerTests {
    private let midnight = Date(timeIntervalSince1970: 86_400)
    private func entry(_ title: String, _ start: Int, _ end: Int) -> DayLedgerEntry {
        DayLedgerEntry(title: title, start: midnight.addingTimeInterval(Double(start * 60)),
                       end: midnight.addingTimeInterval(Double(end * 60)))
    }

    @Test func editsSurviveReopeningAndRejectStaleCopies() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("anchor.store")
        let store = DayLedgerStore(storeURL: url)
        let plan = entry("Draft proposal", 540, 570)
        try store.save(plan, replacing: nil)
        try store.save(plan, replacing: nil)
        var actual = plan
        actual.title = "Resolved customer issue"
        actual.notes = "Proposal moved to Friday"
        try store.save(actual, replacing: plan)
        #expect(throws: CocoaError.self) { try store.save(plan, replacing: nil) }
        #expect(try DayLedgerStore(storeURL: url).load() == [actual])
        #expect(plan.title == "Draft proposal")
        #expect(throws: CocoaError.self) { try store.remove(plan) }
        try store.remove(actual)
        #expect(try store.load().isEmpty)
    }

    @Test func separatesUnrecordedUnplannedAndChangedAndClipsAtMidnight() {
        let period = DateInterval(start: midnight, duration: 86400)
        let plan = entry("Draft", 540, 570), same = entry("Lunch", 720, 750), pending = entry("Read", 780, 800)
        var actual = plan
        actual.end = actual.end.addingTimeInterval(600)
        let extra = entry("Call", -10, 10)
        let result = DayLedgerComparison(period: period, plans: [plan, same, pending], actuals: [actual, same, extra])
        #expect(result.matched == 1 && result.changed == 1 && result.unrecorded == 1 && result.unplanned == 1)
        #expect(result.plannedSeconds == 80 * 60 && result.recordedSeconds == 80 * 60)
        #expect(result.linkedVarianceSeconds == 600 && result.unplannedSeconds == 600)
        actual.start = midnight.addingTimeInterval(86400)
        actual.end = actual.start.addingTimeInterval(600)
        let moved = DayLedgerComparison(period: period, plans: [plan], actuals: [actual])
        #expect(moved.changed == 1 && moved.unrecorded == 0 && moved.recordedSeconds == 0)
    }
}
