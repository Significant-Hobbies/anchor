import Foundation
import Testing

@testable import AnchorCore

/// Builders keep the tests about the assertion rather than about setup.
enum Fixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static let day0 = Date(timeIntervalSince1970: 1_700_000_000)

    static func distraction(
        _ note: String,
        kind: DistractionKind,
        at offset: Double = 300,
        capturedAt: Date = day0,
        returned: Bool = true,
        keywords: [String] = []
    ) -> DistractionRecord {
        DistractionRecord(
            id: UUID(),
            note: note,
            kind: kind,
            keywords: keywords,
            capturedAt: capturedAt,
            offsetSeconds: offset,
            didReturnToFocus: returned,
            isHandled: false,
            confidence: 0.8
        )
    }

    static func session(
        goal: String = "Ship auth",
        theme: GoalTheme? = .building,
        startedAt: Date = day0,
        focused: Double = 1500,
        planned: Int = 1500,
        state: SessionState = .finished,
        reason: SessionEndReason? = .completed,
        distractions: [DistractionRecord] = []
    ) -> SessionRecord {
        SessionRecord(
            id: UUID(),
            goalTitle: goal,
            goalTheme: theme,
            intent: goal,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(focused),
            plannedSeconds: planned,
            focusedSeconds: focused,
            state: state,
            endReason: reason,
            distractions: distractions
        )
    }
}

@Suite("Analytics")
struct AnalyticsEngineTests {
    let engine = AnalyticsEngine(calendar: Fixture.calendar)

    @Test("Overview totals and rates")
    func overview() {
        let records = [
            Fixture.session(focused: 1500, reason: .completed, distractions: [
                Fixture.distraction("slack", kind: .message),
                Fixture.distraction("thought", kind: .wanderingThought, returned: false),
            ]),
            Fixture.session(focused: 900, reason: .endedEarly),
            Fixture.session(focused: 1800, reason: .abandoned),
        ]
        let stats = engine.overview(records, now: Fixture.day0)

        #expect(stats.sessionCount == 3)
        #expect(stats.completedCount == 1)
        #expect(stats.abandonedCount == 1)
        #expect(stats.focusedSeconds == 4200)
        #expect(stats.distractionCount == 2)
        // One of the two interruptions ended the session.
        #expect(stats.recoveryRate == 0.5)
        #expect(abs(stats.completionRate - 1.0 / 3.0) < 0.0001)
        #expect(stats.medianSessionSeconds == 1500)
    }

    @Test("Recovery rate is 1 when nothing has interrupted you")
    func recoveryRateWithNoDistractions() {
        // Guards against dividing by zero and reporting 0% recovery to someone
        // who has never been interrupted.
        let stats = engine.overview([Fixture.session()], now: Fixture.day0)
        #expect(stats.recoveryRate == 1)
        #expect(stats.interruptionsPerHour == 0)
    }

    @Test("Interruption rate is per focused hour, not per session")
    func interruptionRate() {
        let record = Fixture.session(focused: 7200, distractions: [
            Fixture.distraction("a", kind: .message),
            Fixture.distraction("b", kind: .email),
            Fixture.distraction("c", kind: .person),
        ])
        #expect(abs(record.interruptionRate - 1.5) < 0.0001)
    }

    @Test("Distraction leaderboard ranks by count then by damage")
    func distractionLeaderboard() {
        let records = [
            Fixture.session(distractions: [
                Fixture.distraction("a", kind: .message, at: 100),
                Fixture.distraction("b", kind: .message, at: 300),
                Fixture.distraction("c", kind: .message, at: 500, returned: false),
                Fixture.distraction("d", kind: .rabbitHole, at: 600),
            ]),
        ]
        let stats = engine.byDistractionKind(records)

        #expect(stats.first?.kind == .message)
        #expect(stats.first?.count == 3)
        #expect(stats.first?.brokeSessionCount == 1)
        #expect(stats.first?.medianOffsetSeconds == 300)
        #expect(stats.first?.origin == .external)
        #expect(stats.last?.kind == .rabbitHole)
        #expect(stats.last?.origin == .internal)
    }

    @Test("Origin split separates what came to you from what you went to")
    func originSplit() {
        let records = [
            Fixture.session(distractions: [
                Fixture.distraction("a", kind: .message),
                Fixture.distraction("b", kind: .notification),
                Fixture.distraction("c", kind: .socialFeed),
            ]),
        ]
        let split = engine.byOrigin(records)
        #expect(split.first?.origin == .external)
        #expect(split.first?.count == 2)
        #expect(split.contains { $0.origin == .internal && $0.count == 1 })
    }

    @Test("Recurring themes cluster on keywords, not raw text")
    func recurringThemes() {
        let records = [
            Fixture.session(distractions: [
                Fixture.distraction("slack from ravi", kind: .message, keywords: ["slack", "ravi"]),
                Fixture.distraction("ravi slacked again", kind: .message, keywords: ["ravi", "slacked"]),
                Fixture.distraction("email", kind: .email, keywords: ["email"]),
            ]),
        ]
        let recurring = engine.recurringDistractions(records, minimumCount: 2)
        #expect(recurring.count == 1)
        #expect(recurring.first?.label == "ravi")
        #expect(recurring.first?.count == 2)
    }

    @Test("By-goal grouping sums time and falls back to the intent when unassigned")
    func goalGrouping() {
        let records = [
            Fixture.session(goal: "Ship auth", focused: 1500),
            Fixture.session(goal: "Ship auth", focused: 900),
            Fixture.session(goal: "", theme: nil, focused: 600),
        ]
        let goals = engine.byGoal(records)
        #expect(goals.first?.title == "Ship auth")
        #expect(goals.first?.focusedSeconds == 2400)
        #expect(goals.first?.sessionCount == 2)
        // An empty goal title falls back to the intent, which is also empty here.
        #expect(goals.contains { $0.title == "Unassigned" })
    }

    @Test("Daily series includes empty days so charts don't flatter you")
    func dailySeriesIsDense() {
        let start = Fixture.day0
        let end = Fixture.calendar.date(byAdding: .day, value: 4, to: start)!
        let records = [
            Fixture.session(startedAt: start, focused: 1800),
            Fixture.session(startedAt: end, focused: 3600),
        ]
        let buckets = engine.byDay(records, from: start, to: end)

        #expect(buckets.count == 5)
        #expect(buckets[0].focusedSeconds == 1800)
        #expect(buckets[1].focusedSeconds == 0)
        #expect(buckets[2].focusedSeconds == 0)
        #expect(buckets[4].focusedSeconds == 3600)
    }

    @Test("Streaks count consecutive days and tolerate today being unstarted")
    func streaks() {
        // Three consecutive days ending yesterday.
        let today = Fixture.calendar.startOfDay(for: Fixture.day0)
        let records = (1...3).map { offset in
            Fixture.session(
                startedAt: Fixture.calendar.date(byAdding: .day, value: -offset, to: today)!,
                focused: 1800
            )
        }
        // Yesterday counts, so the streak is not reported as broken before you
        // have had a chance to work today.
        #expect(engine.currentStreak(records, now: Fixture.day0) == 3)
        #expect(engine.bestStreak(records) == 3)
    }

    @Test("A gap breaks the current streak but not the best one")
    func brokenStreak() {
        let today = Fixture.calendar.startOfDay(for: Fixture.day0)
        let offsets = [1, 2, 3, 10, 11]
        let records = offsets.map { offset in
            Fixture.session(
                startedAt: Fixture.calendar.date(byAdding: .day, value: -offset, to: today)!,
                focused: 1800
            )
        }
        #expect(engine.currentStreak(records, now: Fixture.day0) == 3)
        #expect(engine.bestStreak(records) == 3)
    }

    @Test("Sessions under a minute don't count toward a streak")
    func trivialSessionsDoNotCount() {
        let records = [Fixture.session(startedAt: Fixture.day0, focused: 30)]
        #expect(engine.currentStreak(records, now: Fixture.day0) == 0)
    }

    @Test("Median handles even and odd counts, and empty input")
    func median() {
        #expect(AnalyticsEngine.median([]) == 0)
        #expect(AnalyticsEngine.median([5]) == 5)
        #expect(AnalyticsEngine.median([1, 3]) == 2)
        #expect(AnalyticsEngine.median([1, 3, 10]) == 3)
    }

    @Test("The model brief contains only numbers that exist")
    func briefIsGrounded() {
        let records = [
            Fixture.session(goal: "Ship auth", focused: 3600, distractions: [
                Fixture.distraction("slack", kind: .message),
            ]),
        ]
        let brief = engine.brief(records, now: Fixture.day0)
        #expect(brief.contains("Sessions: 1"))
        #expect(brief.contains("1.0 hours"))
        #expect(brief.contains("Ship auth"))
        #expect(brief.contains("Message x1"))
    }
}
