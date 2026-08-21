#if !os(watchOS)
import AnchorCore
import Foundation
import PersonalSyncKit
import Testing

@Suite("Personal Platform session contract")
struct AnchorPlatformRecordTests {
    @Test
    func finishedSessionContainsNoDistractionText() throws {
        let start = try #require(ISO8601DateFormatter().date(from: "2026-08-21T06:00:00Z"))
        let end = start.addingTimeInterval(1_800)
        let session = FocusSession(
            goal: nil,
            intent: "Write proposal",
            plannedSeconds: 1_800,
            startedAt: start
        )
        session.bankedSeconds = 1_800
        session.runningSince = nil
        session.endedAt = end
        session.state = .finished
        let distraction = Distraction(note: "Private message from a friend", session: session)
        session.distractions = [distraction]

        let payload = AnchorPlatformRecord.encode(session, endedAt: end)
        let json = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)

        #expect(json.contains("Write proposal"))
        #expect(json.contains("interruptionCount"))
        #expect(json.contains("1800"))
        #expect(!json.contains("Private message"))
    }

    @Test
    func paceSessionUsesStableIdentityAndWallClockDates() throws {
        let change = try JSONDecoder().decode(SyncChange.self, from: Data("""
        {"cursor":1,"changeId":"change-1","domain":"anchor","id":"pace-session","operation":"upsert","version":1,"occurredAt":"2026-08-21T06:00:00Z","recordedAt":"2026-08-21T06:30:01Z","originDeviceId":"pace","record":{"title":"Write proposal","startedAt":"2026-08-21T06:00:00Z","endedAt":"2026-08-21T06:30:00Z","durationSeconds":1800,"interruptionCount":2}}
        """.utf8))

        let first = try #require(AnchorPlatformRecord.decode(change))
        let second = try #require(AnchorPlatformRecord.decode(change))

        #expect(first.id == second.id)
        #expect(first.intent == "Write proposal")
        #expect(first.state == .finished)
        #expect(first.focusedSeconds() == 1_800)
    }
}
#endif
