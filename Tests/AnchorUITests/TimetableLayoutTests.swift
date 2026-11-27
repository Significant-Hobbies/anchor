#if os(macOS)
import Foundation
import AnchorCore
import Testing

@testable import AnchorUI

@Suite("Timetable layout")
struct TimetableLayoutTests {
    @Test("One check copies the scheduled slot and a later check opens the edited actual")
    @MainActor
    func copyToDone() throws {
        let start = Date(timeIntervalSinceReferenceDate: 3_600)
        let block = PlanBlock(title: "Write notes", details: "First draft", plannedStart: start, plannedSeconds: 900)
        var recorded: [DayLedgerEntry] = []
        var edited: DayLedgerEntry?
        func calendar() -> CalendarActualData {
            CalendarActualData(entries: recorded, edit: { edited = $0 }, record: { recorded.append($0); return true }, available: true)
        }

        calendar().check(block)
        let entry = try #require(recorded.first)
        #expect(entry.sourcePlanID == block.id && entry.id == block.id)
        #expect(entry.title == block.title && entry.notes == block.details)
        #expect(entry.start == start && entry.end == start.addingTimeInterval(900))
        recorded[0].title = "Review with team"
        recorded[0].start = start.addingTimeInterval(300)
        calendar().check(block)
        #expect(recorded.count == 1 && edited == recorded.first)
        #expect(block.title == "Write notes" && block.plannedStart == start)
    }

    @Test("Dragging selects whole quarter hours in either direction and stays inside the grid")
    func quarterHourSelection() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let range = DateInterval(start: start, duration: 3_600)
        func select(_ a: CGFloat, _ b: CGFloat) -> DateInterval {
            TimetableLayout.selection(from: a, to: b, hourHeight: 56, range: range, step: .fifteen)
        }
        #expect(select(1, 13) == DateInterval(start: start, duration: 900))
        #expect(select(43, 13) == DateInterval(start: start.addingTimeInterval(900), duration: 1_800))
        #expect(select(13, 43) == select(43, 13))
        let fiveMinuteSlot = TimetableLayout.selection(from: 9, to: 14, hourHeight: 56, range: range, step: .five)
        #expect(fiveMinuteSlot == DateInterval(start: start.addingTimeInterval(600), duration: 300))
        #expect(select(-20, 80) == range)
        #expect(select(56, 56) == DateInterval(start: start.addingTimeInterval(2_700), duration: 900))
    }

    @Test("Non-overlapping entries share a single lane")
    func nonOverlapping() {
        let placements = TimetableLayout.place([(0, 3_600), (3_600, 7_200), (9_000, 10_800)])
        #expect(placements.allSatisfy { $0.lane == 0 && $0.laneCount == 1 })
    }

    @Test("Overlapping entries split into lanes only inside their cluster")
    func overlapLanes() {
        let placements = TimetableLayout.place([
            (0, 3_600),      // A
            (1_800, 5_400),  // B overlaps A
            (7_200, 9_000),  // C starts a new cluster
            (7_380, 7_800),  // D overlaps C
            (7_440, 8_100)   // E overlaps C and D
        ])
        #expect(placements[0] == .init(lane: 0, laneCount: 2))
        #expect(placements[1] == .init(lane: 1, laneCount: 2))
        #expect(placements[2] == .init(lane: 0, laneCount: 3))
        #expect(placements[3] == .init(lane: 1, laneCount: 3))
        #expect(placements[4] == .init(lane: 2, laneCount: 3))
    }

    @Test("Quarter-hour cards fit back to back in one lane")
    func quarterHourCards() {
        let first = TimetableLayout.cardBounds(from: 0, to: 14, in: 56)
        let next = TimetableLayout.cardBounds(from: 14, to: 28, in: 56)
        #expect(first.start == 0 && first.end == 13)
        #expect(next.start == 14 && next.end == 27)
        #expect(TimetableLayout.place([first, next]).allSatisfy { $0.laneCount == 1 })
    }

    @Test("Short rows at midnight stay inside the day and keep both actions reachable")
    func lastSlotCollision() {
        let first = TimetableLayout.cardBounds(from: 42, to: 51, in: 56)
        let last = TimetableLayout.cardBounds(from: 51, to: 56, in: 56)
        #expect(last.end == 56)
        #expect(TimetableLayout.place([first, last]).allSatisfy { $0.laneCount == 2 })
    }

    @Test("The last five minutes are selectable on standard and daylight-saving days")
    func fullDayRange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        for month in [1, 3, 11] {
            let day = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: month == 3 ? 8 : 1)))
            let range = TimetableLayout.displayRange(for: day, calendar: calendar)
            let bottom = CGFloat(range.duration / 3600) * 56
            let slot = TimetableLayout.selection(from: bottom, to: bottom, hourHeight: 56, range: range, step: .five)
            #expect(calendar.component(.hour, from: slot.start) == 23)
            #expect(calendar.component(.minute, from: slot.start) == 55)
            #expect(slot.end == calendar.date(byAdding: .day, value: 1, to: day))
        }
    }
}
#endif
