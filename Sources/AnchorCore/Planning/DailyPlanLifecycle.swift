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
    public static let maximumActiveHabits = 5
    public static let upgradeStreak = 7

    public init() {}

    public func canAdd(activeHabitCount: Int) -> Bool {
        activeHabitCount < Self.maximumActiveHabits
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

    /// Schedule-aware streak calculation. Missing due occurrences are misses,
    /// even if the app was not opened on that day. Moved blocks are matched by
    /// their original occurrence day, not their edited start time.
    public func streak(
        for schedule: Schedule,
        blocks: [PlanBlockRecord],
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
            let dueStart = calendar.date(
                byAdding: .minute,
                value: schedule.startMinutesFromMidnight,
                to: day
            ) ?? day
            guard dueStart >= schedule.levelStartedAt else { continue }
            let dueEnd = dueStart.addingTimeInterval(Double(schedule.plannedSeconds))
            guard dueEnd <= now else { continue }

            let occurrence = matching.first { block in
                let occurrenceDay = calendar.startOfDay(for: block.templateOccurrenceDay ?? block.plannedStart)
                return calendar.isDate(occurrenceDay, inSameDayAs: day)
            }
            guard occurrence?.state == .completed else { break }
            count += 1
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
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        streak(for: schedule, blocks: blocks, now: now, calendar: calendar) >= Self.upgradeStreak
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
            .filter { !$0.isArchived }
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
