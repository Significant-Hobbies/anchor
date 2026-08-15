import Foundation

/// Every number the app reports, derived from snapshots. Pure functions only —
/// no storage, no clock of its own, no main actor. Give it records and a
/// calendar and it gives you the same answer every time.
public struct AnalyticsEngine: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    // MARK: - Headline

    public struct Overview: Sendable, Equatable, Codable {
        public var sessionCount: Int
        public var completedCount: Int
        public var abandonedCount: Int
        public var focusedSeconds: Double
        public var distractionCount: Int
        public var parkedAndReturnedCount: Int
        public var medianSessionSeconds: Double
        public var currentStreakDays: Int
        public var bestStreakDays: Int

        public var focusedHours: Double { focusedSeconds / 3600 }

        /// Share of sessions that ran their full planned length.
        public var completionRate: Double {
            sessionCount == 0 ? 0 : Double(completedCount) / Double(sessionCount)
        }

        /// Of every distraction captured, how often did parking it actually work?
        /// This is the number that tells you whether the app is doing its job.
        public var recoveryRate: Double {
            distractionCount == 0 ? 1 : Double(parkedAndReturnedCount) / Double(distractionCount)
        }

        public var interruptionsPerHour: Double {
            focusedSeconds < 60 ? 0 : Double(distractionCount) / (focusedSeconds / 3600)
        }
    }

    public func overview(_ records: [SessionRecord], now: Date = Date()) -> Overview {
        let finished = records.filter { $0.state == .finished }
        let distractions = records.flatMap(\.distractions)
        let durations = finished.map(\.focusedSeconds).sorted()

        return Overview(
            sessionCount: finished.count,
            completedCount: finished.filter { $0.endReason == .completed }.count,
            abandonedCount: finished.filter { $0.endReason == .abandoned }.count,
            focusedSeconds: records.reduce(0) { $0 + $1.focusedSeconds },
            distractionCount: distractions.count,
            parkedAndReturnedCount: distractions.filter(\.didReturnToFocus).count,
            medianSessionSeconds: Self.median(durations),
            currentStreakDays: currentStreak(records, now: now),
            bestStreakDays: bestStreak(records)
        )
    }

    // MARK: - Goals

    public struct GoalStat: Sendable, Equatable, Codable, Identifiable {
        public var id: String { title }
        public var title: String
        public var theme: GoalTheme?
        public var sessionCount: Int
        public var focusedSeconds: Double
        public var distractionCount: Int
        public var completedCount: Int

        public var focusedHours: Double { focusedSeconds / 3600 }
        public var interruptionsPerHour: Double {
            focusedSeconds < 60 ? 0 : Double(distractionCount) / (focusedSeconds / 3600)
        }
    }

    /// Focus time per goal, biggest first.
    public func byGoal(_ records: [SessionRecord]) -> [GoalStat] {
        let groups = Dictionary(grouping: records) { record in
            record.goalTitle.isEmpty ? (record.intent.isEmpty ? "Unassigned" : record.intent) : record.goalTitle
        }
        return groups.map { title, rows in
            GoalStat(
                title: title,
                theme: rows.compactMap(\.goalTheme).first,
                sessionCount: rows.count,
                focusedSeconds: rows.reduce(0) { $0 + $1.focusedSeconds },
                distractionCount: rows.reduce(0) { $0 + $1.distractions.count },
                completedCount: rows.filter { $0.endReason == .completed }.count
            )
        }
        .sorted { $0.focusedSeconds > $1.focusedSeconds }
    }

    /// Focus time per on-device theme — the grouping the model earns its keep on.
    public func byTheme(_ records: [SessionRecord]) -> [(theme: GoalTheme, seconds: Double, sessions: Int)] {
        let groups = Dictionary(grouping: records) { $0.goalTheme ?? .other }
        return groups.map { theme, rows in
            (theme, rows.reduce(0) { $0 + $1.focusedSeconds }, rows.count)
        }
        .sorted { $0.1 > $1.1 }
    }

    // MARK: - Distractions

    public struct DistractionStat: Sendable, Equatable, Codable, Identifiable {
        public var id: String { kind.rawValue }
        public var kind: DistractionKind
        public var count: Int
        /// How many times this category ended a session rather than being parked.
        public var brokeSessionCount: Int
        /// Median seconds into a session that this kind tends to land.
        public var medianOffsetSeconds: Double

        public var origin: DistractionOrigin { kind.origin }

        /// Share of the time this category wins.
        public var breakRate: Double {
            count == 0 ? 0 : Double(brokeSessionCount) / Double(count)
        }
    }

    /// The leaderboard: what interrupts you most, and what actually costs you the session.
    public func byDistractionKind(_ records: [SessionRecord]) -> [DistractionStat] {
        let all = records.flatMap(\.distractions)
        let groups = Dictionary(grouping: all, by: \.kind)
        return groups.map { kind, rows in
            DistractionStat(
                kind: kind,
                count: rows.count,
                brokeSessionCount: rows.filter { !$0.didReturnToFocus }.count,
                medianOffsetSeconds: Self.median(rows.map(\.offsetSeconds).sorted())
            )
        }
        .sorted { ($0.count, $0.brokeSessionCount) > ($1.count, $1.brokeSessionCount) }
    }

    public func byOrigin(_ records: [SessionRecord]) -> [(origin: DistractionOrigin, count: Int)] {
        let groups = Dictionary(grouping: records.flatMap(\.distractions), by: \.origin)
        return DistractionOrigin.allCases.compactMap { origin in
            guard let rows = groups[origin], !rows.isEmpty else { return nil }
            return (origin, rows.count)
        }
        .sorted { $0.count > $1.count }
    }

    /// Recurring specifics, clustered on the on-device keywords rather than the
    /// raw text, so "slack from Ravi" and "Ravi slacked again" land in one row.
    public func recurringDistractions(_ records: [SessionRecord], minimumCount: Int = 2) -> [(label: String, count: Int, kind: DistractionKind)] {
        var tally: [String: (count: Int, kind: DistractionKind)] = [:]
        for distraction in records.flatMap(\.distractions) {
            for keyword in distraction.keywords {
                let existing = tally[keyword]
                tally[keyword] = ((existing?.count ?? 0) + 1, existing?.kind ?? distraction.kind)
            }
        }
        return tally
            .filter { $0.value.count >= minimumCount }
            .map { ($0.key, $0.value.count, $0.value.kind) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Shape of a day

    public struct HourBucket: Sendable, Equatable, Codable, Identifiable {
        public var id: Int { hour }
        public var hour: Int
        public var focusedSeconds: Double
        public var distractionCount: Int
    }

    /// Focus and interruptions by hour of day. Answers "when am I actually good at this?".
    public func byHour(_ records: [SessionRecord]) -> [HourBucket] {
        var focus = [Int: Double]()
        var breaks = [Int: Int]()
        for record in records {
            let hour = calendar.component(.hour, from: record.startedAt)
            focus[hour, default: 0] += record.focusedSeconds
            for distraction in record.distractions {
                breaks[calendar.component(.hour, from: distraction.capturedAt), default: 0] += 1
            }
        }
        return (0..<24).map {
            HourBucket(hour: $0, focusedSeconds: focus[$0] ?? 0, distractionCount: breaks[$0] ?? 0)
        }
    }

    public struct DayBucket: Sendable, Equatable, Codable, Identifiable {
        public var id: Date { day }
        public var day: Date
        public var focusedSeconds: Double
        public var sessionCount: Int
        public var distractionCount: Int
    }

    /// A dense daily series — every day in the range, including empty ones, so
    /// charts don't silently close gaps and flatter the user.
    public func byDay(_ records: [SessionRecord], from start: Date, to end: Date) -> [DayBucket] {
        let grouped = Dictionary(grouping: records) { calendar.startOfDay(for: $0.startedAt) }
        var buckets: [DayBucket] = []
        var cursor = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while cursor <= last {
            let rows = grouped[cursor] ?? []
            buckets.append(
                DayBucket(
                    day: cursor,
                    focusedSeconds: rows.reduce(0) { $0 + $1.focusedSeconds },
                    sessionCount: rows.count,
                    distractionCount: rows.reduce(0) { $0 + $1.distractions.count }
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return buckets
    }

    // MARK: - Streaks

    private func focusDays(_ records: [SessionRecord]) -> Set<Date> {
        Set(records.filter { $0.focusedSeconds >= 60 }.map { calendar.startOfDay(for: $0.startedAt) })
    }

    /// Consecutive days up to today with at least a minute of focus.
    /// Yesterday still counts, so the streak doesn't read as broken before you've worked today.
    public func currentStreak(_ records: [SessionRecord], now: Date = Date()) -> Int {
        let days = focusDays(records)
        guard !days.isEmpty else { return 0 }
        let today = calendar.startOfDay(for: now)

        var cursor = today
        if !days.contains(today) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    public func bestStreak(_ records: [SessionRecord]) -> Int {
        let days = focusDays(records).sorted()
        guard !days.isEmpty else { return 0 }
        var best = 1
        var run = 1
        for index in 1..<days.count {
            let previous = days[index - 1]
            let gap = calendar.dateComponents([.day], from: previous, to: days[index]).day ?? 0
            if gap == 1 {
                run += 1
                best = max(best, run)
            } else {
                run = 1
            }
        }
        return best
    }

    // MARK: - Brief for the on-device summariser

    /// Compact, number-only text handed to the model. Kept explicit so the model
    /// has nothing to invent — it can only rephrase what is already here.
    public func brief(_ records: [SessionRecord], now: Date = Date()) -> String {
        let stats = overview(records, now: now)
        let goals = byGoal(records).prefix(3)
        let kinds = byDistractionKind(records).prefix(3)

        var lines: [String] = [
            "Sessions: \(stats.sessionCount), completed: \(stats.completedCount), abandoned: \(stats.abandonedCount).",
            "Focused time: \(String(format: "%.1f", stats.focusedHours)) hours.",
            "Interruptions: \(stats.distractionCount) (\(String(format: "%.1f", stats.interruptionsPerHour)) per focused hour).",
            // Same rounding the UI uses, so the model can never quote a number
            // that disagrees with the tile sitting next to it.
            "Recovered after parking: \(Int((stats.recoveryRate * 100).rounded()))% of interruptions.",
            "Current streak: \(stats.currentStreakDays) days.",
        ]
        if !goals.isEmpty {
            lines.append("Top goals by time: " + goals.map {
                "\($0.title) (\(String(format: "%.1f", $0.focusedHours))h, \($0.distractionCount) interruptions)"
            }.joined(separator: "; ") + ".")
        }
        if !kinds.isEmpty {
            lines.append("Most common interruptions: " + kinds.map {
                "\($0.kind.label) x\($0.count)"
            }.joined(separator: "; ") + ".")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Utilities

    static func median(_ sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
