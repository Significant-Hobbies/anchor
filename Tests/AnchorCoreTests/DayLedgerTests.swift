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
        #expect(try DayLedgerStore(storeURL: url).load().entries == [actual])
        let corrupt = url.appendingPathExtension("actual-entries").appendingPathComponent("other.json")
        try Data("{broken".utf8).write(to: corrupt)
        let recoverable = try store.load()
        #expect(recoverable.hasUnreadableFiles && recoverable.entries == [actual])
        #expect(plan.title == "Draft proposal")
        #expect(throws: CocoaError.self) { try store.remove(plan) }
        try store.remove(actual)
        #expect(try store.load().entries.isEmpty)
        let damaged = url.appendingPathExtension("actual-entries").appendingPathComponent(plan.id.uuidString + ".json")
        try Data("broken record".utf8).write(to: damaged)
        try store.save(plan, replacing: nil)
        #expect(try store.load().entries == [plan])
        let files = try FileManager.default.contentsOfDirectory(at: damaged.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        let backup = try #require(files.first { $0.pathExtension == "unreadable" })
        #expect(try Data(contentsOf: backup) == Data("broken record".utf8))
    }

    @Test func insightsOnlyCountFinishedSlotsAndPreserveFuturePlanLinks() {
        let planned = entry("Call", 720, 750)
        var earlier = planned
        earlier.start = midnight.addingTimeInterval(60 * 500)
        earlier.end = earlier.start.addingTimeInterval(900)
        let next = entry("Gym", 800, 830)
        let period = DateInterval(start: midnight, duration: 600 * 60)
        let result = DayLedgerComparison(period: period, plans: [planned, next], actuals: [earlier, next], finishedBy: period.end)
        #expect(result.plannedSeconds == 0 && result.recordedSeconds == 900)
        #expect(result.changed == 1 && result.unplanned == 0 && result.unavailablePlans == 0)
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
        let next = DayLedgerComparison(period: DateInterval(start: period.end, duration: 86400), plans: [plan], actuals: [actual])
        #expect(next.changed == 1 && next.unplanned == 0 && next.linkedVarianceSeconds == 600)
    }
}
