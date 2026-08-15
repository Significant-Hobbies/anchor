import Foundation
import SwiftData

/// Plausible history, for screenshots and for trying the analytics before you
/// have three weeks of your own data.
///
/// Only runs when `ANCHOR_DEMO_DATA=1` is set, and only into an empty store, so
/// it can never touch real history.
public enum DemoData {
    public static var isRequested: Bool {
        ProcessInfo.processInfo.environment["ANCHOR_DEMO_DATA"] == "1"
    }

    /// Which tab to open on, for screenshots and manual QA. Honoured only in
    /// demo mode, so it can never alter a real launch.
    public static var initialTab: String? {
        guard isRequested else { return nil }
        return ProcessInfo.processInfo.environment["ANCHOR_INITIAL_TAB"]
    }

    /// Deterministic generator — the same seed produces the same history, so
    /// screenshots don't churn between runs.
    private struct Random {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(max(1, bound)))
        }
        mutating func chance(_ percent: Int) -> Bool { next(100) < percent }
    }

    private struct GoalSpec {
        let title: String
        let theme: GoalTheme
        let symbol: String
        let weight: Int
    }

    private static let goalSpecs: [GoalSpec] = [
        .init(title: "Ship the auth rewrite", theme: .building, symbol: "hammer", weight: 34),
        .init(title: "Write the launch post", theme: .writing, symbol: "square.and.pencil", weight: 22),
        .init(title: "Learn SwiftData properly", theme: .learning, symbol: "book", weight: 18),
        .init(title: "Q3 planning", theme: .planning, symbol: "map", weight: 14),
        .init(title: "Inbox and invoices", theme: .admin, symbol: "tray.full", weight: 12),
    ]

    private static let distractionSpecs: [(note: String, kind: DistractionKind, keywords: [String])] = [
        ("Slack from Ravi about the invoice", .message, ["slack", "ravi", "invoice"]),
        ("Slack thread about the outage", .message, ["slack", "outage"]),
        ("Ravi asked about deploy timing", .message, ["ravi", "deploy"]),
        ("Phone buzzed — delivery notification", .notification, ["delivery", "phone"]),
        ("Calendar alert for standup", .notification, ["calendar", "standup"]),
        ("Roommate came in to chat", .person, ["roommate", "chat"]),
        ("Email from the bank", .email, ["email", "bank"]),
        ("Started scrolling Twitter", .socialFeed, ["twitter", "scrolling"]),
        ("Opened Hacker News without thinking", .socialFeed, ["hacker", "news"]),
        ("Went down a Wikipedia rabbit hole on typography", .rabbitHole, ["wikipedia", "typography"]),
        ("Reading docs that turned into unrelated docs", .rabbitHole, ["docs", "reading"]),
        ("Remembered I hadn't replied to the landlord", .wanderingThought, ["landlord", "replied"]),
        ("Worrying about the deadline", .wanderingThought, ["worrying", "deadline"]),
        ("Jumped to fixing an unrelated bug", .otherWork, ["bug", "unrelated"]),
        ("Got hungry, made coffee", .bodily, ["hungry", "coffee"]),
        ("Laundry needed moving", .chore, ["laundry"]),
        ("Construction noise outside", .environment, ["construction", "noise"]),
    ]

    /// Inserts roughly three weeks of history. No-op if anything already exists.
    @MainActor
    public static func seedIfNeeded(into context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<FocusSession>())) ?? 0
        guard existing == 0 else { return }

        var random = Random(state: 0xA9C4_1F02)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let goals = goalSpecs.enumerated().map { index, spec -> Goal in
            let goal = Goal(
                title: spec.title,
                createdAt: calendar.date(byAdding: .day, value: -24, to: today) ?? today,
                symbolName: spec.symbol,
                tintIndex: index
            )
            goal.theme = spec.theme
            context.insert(goal)
            return goal
        }

        let weightedGoalIndices = goalSpecs.enumerated().flatMap { index, spec in
            Array(repeating: index, count: spec.weight)
        }

        for dayOffset in stride(from: 21, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let isWeekend = weekday == 1 || weekday == 7

            // A believable pattern: most weekdays worked, weekends mostly not,
            // and one deliberate gap so the streak logic has something to say.
            if isWeekend, !random.chance(25) { continue }
            if dayOffset == 9 || dayOffset == 10 { continue }

            let sessionCount = isWeekend ? 1 : 1 + random.next(3)
            var hour = 9 + random.next(2)

            for _ in 0..<sessionCount {
                hour += 1 + random.next(3)
                guard hour < 21,
                      let startedAt = calendar.date(
                          bySettingHour: hour,
                          minute: random.next(4) * 15,
                          second: 0,
                          of: day
                      )
                else { continue }

                let goalIndex = weightedGoalIndices[random.next(weightedGoalIndices.count)]
                let planned = [25, 25, 45, 50, 90][random.next(5)] * 60

                // Most sessions run their course; some get cut short.
                let outcomeRoll = random.next(100)
                let reason: SessionEndReason
                let focused: Double
                if outcomeRoll < 62 {
                    reason = .completed
                    focused = Double(planned)
                } else if outcomeRoll < 88 {
                    reason = .endedEarly
                    focused = Double(planned) * (0.4 + Double(random.next(40)) / 100)
                } else {
                    reason = .abandoned
                    focused = Double(planned) * (0.15 + Double(random.next(35)) / 100)
                }

                let session = FocusSession(
                    goal: goals[goalIndex],
                    intent: goalSpecs[goalIndex].title,
                    plannedSeconds: planned,
                    startedAt: startedAt
                )
                session.bankedSeconds = focused
                session.runningSince = nil
                session.state = .finished
                session.endedAt = startedAt.addingTimeInterval(focused * 1.15)
                session.endReason = reason
                context.insert(session)

                // Interruptions cluster later in a session, which is also true
                // in life — the first ten minutes are the easy ones.
                let interruptionCount = random.next(100) < 30 ? 0 : 1 + random.next(3)
                for index in 0..<interruptionCount {
                    let spec = distractionSpecs[random.next(distractionSpecs.count)]
                    let offset = focused * (0.25 + Double(random.next(70)) / 100)
                    guard offset < focused else { continue }

                    let isLast = index == interruptionCount - 1
                    let distraction = Distraction(
                        note: spec.note,
                        capturedAt: startedAt.addingTimeInterval(offset),
                        offsetSeconds: offset,
                        session: session,
                        didReturnToFocus: !(reason == .abandoned && isLast)
                    )
                    distraction.kind = spec.kind
                    distraction.keywords = spec.keywords
                    distraction.kindConfidence = 0.6 + Double(random.next(35)) / 100
                    // A few remain open so the "to deal with" list isn't empty.
                    if random.chance(65) {
                        distraction.handledAt = distraction.capturedAt.addingTimeInterval(7200)
                    }
                    context.insert(distraction)
                }
            }
        }

        try? context.save()
    }
}
