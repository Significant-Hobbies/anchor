import Foundation
import SwiftData

/// The owner's explicit response to Anchor's start-of-day question. Keeping
/// this separate from plan blocks preserves the distinction between the usual
/// week, a today-only decision, and what was eventually observed.
@Model
public final class DayPlanConfirmation {
    public var id: UUID = UUID()
    public var day: Date = Date()
    public var decisionRaw: String = DayPlanConfirmationDecision.later.rawValue
    public var baselineRevision: String = ""
    public var confirmedAt: Date?
    public var deferredAt: Date?
    public var updatedAt: Date = Date()

    public init(
        id: UUID = UUID(),
        day: Date,
        decision: DayPlanConfirmationDecision,
        baselineRevision: String = "",
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.day = day
        self.decision = decision
        self.baselineRevision = baselineRevision
        self.updatedAt = recordedAt
        if decision.isConfirmed {
            confirmedAt = recordedAt
        } else {
            deferredAt = recordedAt
        }
    }

    public var decision: DayPlanConfirmationDecision {
        get { DayPlanConfirmationDecision(rawValue: decisionRaw) ?? .later }
        set { decisionRaw = newValue.rawValue }
    }
}

public enum DayPlanConfirmationDecision: String, CaseIterable, Codable, Sendable {
    case usual
    case adjusted
    case later

    public var isConfirmed: Bool { self != .later }
}

/// Pure policy for the deliberately small behavior-change system. Ordinary
/// recurring schedule items never enter this policy.
public struct HabitPolicy: Sendable {
    public static let upgradeStreak = 7

    public init() {}

    public func canAdd(activeHabitCount: Int) -> Bool {
        activeHabitCount >= 0
    }

    public struct WeeklyProgress: Sendable, Equatable {
        public var completed: Int
        public var scheduled: Int

        public init(completed: Int, scheduled: Int) {
            self.completed = completed
            self.scheduled = scheduled
        }
    }

    public struct Schedule: Sendable, Equatable {
        public var templateID: UUID
        public var levelStartedAt: Date
        public var startMinutesFromMidnight: Int
        public var plannedSeconds: Int
        public var weekdays: Set<ScheduleWeekday>

        public init(
            templateID: UUID,
            levelStartedAt: Date,
            startMinutesFromMidnight: Int,
            plannedSeconds: Int,
            weekdays: Set<ScheduleWeekday>
        ) {
            self.templateID = templateID
            self.levelStartedAt = levelStartedAt
            self.startMinutesFromMidnight = startMinutesFromMidnight
            self.plannedSeconds = plannedSeconds
            self.weekdays = weekdays
        }
    }

    /// Counts consecutive completed *scheduled occurrences*. A day on which a
    /// habit was not scheduled is absent and therefore cannot break the streak.
    /// An occurrence that is not yet due is ignored; a due skipped, moved, or
    /// unfinished occurrence breaks the sequence.
    public func streak(
        for templateID: UUID,
        blocks: [PlanBlockRecord],
        since levelStartedAt: Date? = nil,
        now: Date = Date()
    ) -> Int {
        let occurrences = blocks
            .filter { $0.templateID == templateID }
            .filter { levelStartedAt == nil || $0.plannedStart >= levelStartedAt! }
            .filter { block in
                block.state == .completed
                    || block.plannedStart.addingTimeInterval(Double(block.plannedSeconds)) <= now
            }
            .sorted { $0.plannedStart > $1.plannedStart }

        var count = 0
        for occurrence in occurrences {
            guard occurrence.state == .completed else { break }
            count += 1
        }
        return count
    }

    /// The promise visible on a habit card: completed occurrences out of the
    /// occurrences scheduled for this calendar week. This is deliberately not
    /// the seven-occurrence upgrade streak, which can span several weeks.
    public func weeklyProgress(
        for schedule: Schedule,
        blocks: [PlanBlockRecord],
        completions: [HabitCompletionRecord] = [],
        weekContaining date: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyProgress {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return WeeklyProgress(completed: 0, scheduled: 0)
        }

        var day = calendar.startOfDay(for: week.start)
        let end = calendar.startOfDay(for: week.end)
        var scheduled = 0
        var completed = 0
        let matching = blocks.filter { $0.templateID == schedule.templateID }

        while day < end {
            defer {
                day = calendar.date(byAdding: .day, value: 1, to: day)
                    ?? day.addingTimeInterval(86_400)
            }
            guard schedule.weekdays.contains(ScheduleWeekday(day: day, calendar: calendar)) else {
                continue
            }
            scheduled += 1

            let occurrence = matching.first { block in
                let occurrenceDay = calendar.startOfDay(for: block.templateOccurrenceDay ?? block.plannedStart)
                return calendar.isDate(occurrenceDay, inSameDayAs: day)
            }
            let directCompletion = latestCompletion(
                for: schedule.templateID,
                on: day,
                completions: completions,
                calendar: calendar
            )
            if occurrence?.state == .completed || directCompletion?.isCompleted == true {
                completed += 1
            }
        }

        return WeeklyProgress(completed: completed, scheduled: scheduled)
    }

    /// Schedule-aware streak calculation. Missing due occurrences are misses,
    /// even if the app was not opened on that day. Moved blocks are matched by
    /// their original occurrence day, not their edited start time.
    public func streak(
        for schedule: Schedule,
        blocks: [PlanBlockRecord],
        completions: [HabitCompletionRecord] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let startDay = calendar.startOfDay(for: schedule.levelStartedAt)
        var day = calendar.startOfDay(for: now)
        let matching = blocks.filter { $0.templateID == schedule.templateID }
        var count = 0

        while day >= startDay {
            defer {
                day = calendar.date(byAdding: .day, value: -1, to: day)
                    ?? day.addingTimeInterval(-86_400)
            }
            guard schedule.weekdays.contains(ScheduleWeekday(day: day, calendar: calendar)) else {
                continue
            }
            let occurrence = matching.first { block in
                let occurrenceDay = calendar.startOfDay(for: block.templateOccurrenceDay ?? block.plannedStart)
                return calendar.isDate(occurrenceDay, inSameDayAs: day)
            }
            let directCompletion = latestCompletion(
                for: schedule.templateID,
                on: day,
                completions: completions,
                calendar: calendar
            )
            if occurrence?.state == .completed || directCompletion?.isCompleted == true {
                count += 1
            } else if !calendar.isDate(day, inSameDayAs: now) {
                break
            }
        }
        return count
    }

    public func canUpgrade(
        templateID: UUID,
        blocks: [PlanBlockRecord],
        since levelStartedAt: Date? = nil,
        now: Date = Date()
    ) -> Bool {
        streak(for: templateID, blocks: blocks, since: levelStartedAt, now: now) >= Self.upgradeStreak
    }

    public func canUpgrade(
        schedule: Schedule,
        blocks: [PlanBlockRecord],
        completions: [HabitCompletionRecord] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        streak(
            for: schedule,
            blocks: blocks,
            completions: completions,
            now: now,
            calendar: calendar
        ) >= Self.upgradeStreak
    }

    private func latestCompletion(
        for habitID: UUID,
        on day: Date,
        completions: [HabitCompletionRecord],
        calendar: Calendar
    ) -> HabitCompletionRecord? {
        completions
            .filter { $0.habitID == habitID && calendar.isDate($0.day, inSameDayAs: day) }
            .max { $0.updatedAt < $1.updatedAt }
    }
}

public extension ScheduleTemplate {
    func habitSchedule() -> HabitPolicy.Schedule {
        HabitPolicy.Schedule(
            templateID: id,
            levelStartedAt: currentHabitLevelStartedAt,
            startMinutesFromMidnight: startMinutesFromMidnight,
            plannedSeconds: plannedSeconds,
            weekdays: weekdays
        )
    }
}

public enum HabitDayError: Error, Equatable {
    case notBehaviorHabit
    case unavailableOnDay
}

/// Persists only explicit daily habit decisions. Availability itself is
/// derived from the habit's weekdays, so merely opening the app creates no
/// records and no false schedule evidence.
@MainActor
public struct HabitDayService {
    private let context: ModelContext
    public var calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    public func completion(for habitID: UUID, on day: Date) throws -> HabitCompletion? {
        try context.fetch(FetchDescriptor<HabitCompletion>())
            .filter { $0.habitID == habitID && calendar.isDate($0.day, inSameDayAs: day) }
            .max { $0.updatedAt < $1.updatedAt }
    }

    @discardableResult
    public func setCompleted(
        _ completed: Bool,
        habitID: UUID,
        on day: Date,
        at timestamp: Date = Date()
    ) throws -> HabitCompletion {
        let normalized = calendar.startOfDay(for: day)
        let result: HabitCompletion
        if let existing = try completion(for: habitID, on: normalized) {
            result = existing
            result.isCompleted = completed
            result.completedAt = completed ? timestamp : nil
            result.updatedAt = timestamp
        } else {
            result = HabitCompletion(
                habitID: habitID,
                day: normalized,
                isCompleted: completed,
                completedAt: completed ? timestamp : nil,
                createdAt: timestamp,
                updatedAt: timestamp
            )
            context.insert(result)
        }
        try context.save()
        return result
    }

    /// Creates one owner-authored plan block at the chosen time. The habit's
    /// future suggestion is untouched.
    @discardableResult
    public func place(
        _ habit: ScheduleTemplate,
        on day: Date,
        at start: Date,
        plannedSeconds: Int,
        title: String? = nil,
        details: String? = nil
    ) throws -> PlanBlock {
        guard habit.isActiveBehaviorHabit else { throw HabitDayError.notBehaviorHabit }
        guard habit.applies(to: day, calendar: calendar) else { throw HabitDayError.unavailableOnDay }

        let normalized = calendar.startOfDay(for: day)
        if let existing = try context.fetch(FetchDescriptor<PlanBlock>()).first(where: { block in
            guard block.templateID == habit.id else { return false }
            return calendar.isDate(block.templateOccurrenceDay ?? block.plannedStart, inSameDayAs: normalized)
        }) {
            return existing
        }

        let block = PlanBlock(
            templateID: habit.id,
            templateOccurrenceDay: normalized,
            isTemplateOverride: true,
            projectID: habit.projectID,
            title: title ?? habit.title,
            details: details ?? habit.details,
            plannedStart: start,
            plannedSeconds: plannedSeconds,
            kind: habit.kind,
            flexibility: .flexible,
            behaviorPattern: habit.behaviorPattern,
            lifeDirection: habit.lifeDirection
        )
        context.insert(block)
        try context.save()
        return block
    }
}

@MainActor
public struct DailyPlanService {
    private let context: ModelContext
    public var calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    public func confirmation(for day: Date) throws -> DayPlanConfirmation? {
        let normalized = calendar.startOfDay(for: day)
        return try context.fetch(FetchDescriptor<DayPlanConfirmation>())
            .filter { calendar.isDate($0.day, inSameDayAs: normalized) }
            .max { $0.updatedAt < $1.updatedAt }
    }

    @discardableResult
    public func record(
        _ decision: DayPlanConfirmationDecision,
        for day: Date,
        at recordedAt: Date = Date()
    ) throws -> DayPlanConfirmation {
        let normalized = calendar.startOfDay(for: day)
        let revision = try baselineRevision()
        let result: DayPlanConfirmation
        if let existing = try confirmation(for: normalized) {
            result = existing
            result.decision = decision
            result.baselineRevision = revision
            result.updatedAt = recordedAt
            if decision.isConfirmed {
                result.confirmedAt = recordedAt
                result.deferredAt = nil
            } else {
                result.confirmedAt = nil
                result.deferredAt = recordedAt
            }
        } else {
            result = DayPlanConfirmation(
                day: normalized,
                decision: decision,
                baselineRevision: revision,
                recordedAt: recordedAt
            )
            context.insert(result)
        }
        try context.save()
        return result
    }

    /// A deterministic revision marker, not an analytics identifier. It exists
    /// so future on-device learning can distinguish the baseline the owner saw
    /// from later edits without conflating either with the lived day.
    public func baselineRevision() throws -> String {
        try context.fetch(FetchDescriptor<ScheduleTemplate>())
            .filter { !$0.isArchived && !$0.isBehaviorHabit }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { template in
                [
                    template.id.uuidString,
                    String(template.updatedAt.timeIntervalSince1970.bitPattern, radix: 16),
                    String(template.startMinutesFromMidnight),
                    String(template.plannedSeconds),
                    String(template.weekdayMask),
                    template.kindRaw,
                    template.flexibilityRaw,
                ].joined(separator: ":")
            }
            .joined(separator: "|")
    }
}
