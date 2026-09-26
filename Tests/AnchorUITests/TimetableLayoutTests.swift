#if os(macOS)
import Foundation
import Testing

@testable import AnchorUI

@Suite("Timetable layout")
struct TimetableLayoutTests {
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

    @Test("The visible window covers early blocks and the current hour")
    func displayRangeCoversNowAndBlocks() {
        let calendar = Calendar.current
        let today = Date()
        let dayStart = calendar.startOfDay(for: today)
        let range = TimetableLayout.displayRange(
            for: today,
            intervals: [(5 * 3_600, 6 * 3_600)],
            now: today,
            calendar: calendar
        )
        #expect(range.start == dayStart.addingTimeInterval(5 * 3_600))
        #expect(range.contains(today))
    }

    @Test("A day without context defaults to a working window")
    func displayRangeDefaults() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let range = TimetableLayout.displayRange(for: day, intervals: [], now: Date(), calendar: calendar)
        #expect(range.start == day.addingTimeInterval(7 * 3_600))
        #expect(range.end == day.addingTimeInterval(22 * 3_600))
    }
}
#endif
