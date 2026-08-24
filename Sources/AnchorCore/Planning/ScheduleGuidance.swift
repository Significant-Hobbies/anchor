import Foundation

/// A concrete, editable starting point for turning a chosen direction into a
/// recurring habit. These are deliberately local and deterministic: the owner
/// sees a useful suggestion even when Apple Intelligence is unavailable.
public struct HabitSuggestion: Sendable, Equatable, Identifiable {
    public var direction: LifeDirection
    public var title: String
    public var startMinutesFromMidnight: Int
    public var plannedMinutes: Int

    public var id: LifeDirection { direction }

    public init(
        direction: LifeDirection,
        title: String,
        startMinutesFromMidnight: Int,
        plannedMinutes: Int
    ) {
        self.direction = direction
        self.title = title
        self.startMinutesFromMidnight = startMinutesFromMidnight
        self.plannedMinutes = plannedMinutes
    }
}

public extension LifeDirection {
    var habitSuggestion: HabitSuggestion {
        switch self {
        case .sleep:
            HabitSuggestion(direction: self, title: "Wind-down routine", startMinutesFromMidnight: 22 * 60, plannedMinutes: 30)
        case .presence:
            HabitSuggestion(direction: self, title: "Screen-free pause", startMinutesFromMidnight: 12 * 60 + 30, plannedMinutes: 10)
        case .relationships:
            HabitSuggestion(direction: self, title: "Reach out to someone", startMinutesFromMidnight: 19 * 60, plannedMinutes: 20)
        case .creativity:
            HabitSuggestion(direction: self, title: "Make something", startMinutesFromMidnight: 18 * 60 + 30, plannedMinutes: 30)
        case .movement:
            HabitSuggestion(direction: self, title: "Move your body", startMinutesFromMidnight: 7 * 60 + 30, plannedMinutes: 30)
        case .calm:
            HabitSuggestion(direction: self, title: "Quiet reset", startMinutesFromMidnight: 8 * 60, plannedMinutes: 10)
        case .focus:
            HabitSuggestion(direction: self, title: "Deep focus block", startMinutesFromMidnight: 9 * 60, plannedMinutes: 45)
        case .selfTrust:
            HabitSuggestion(direction: self, title: "Keep one promise", startMinutesFromMidnight: 8 * 60 + 30, plannedMinutes: 20)
        }
    }
}

/// Picks the block Focus should put in front of the owner now.
public struct ScheduledFocusResolver: Sendable {
    public init() {}

    public func nextBlock(
        from blocks: [PlanBlockRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PlanBlockRecord? {
        let day = calendar.dateInterval(of: .day, for: now)
        let open = blocks
            .filter { block in
                (day?.contains(block.plannedStart) ?? calendar.isDate(block.plannedStart, inSameDayAs: now))
                    && block.state != .completed
                    && block.state != .skipped
                    && block.state != .moved
            }
            .sorted { $0.plannedStart < $1.plannedStart }

        if let active = open.first(where: { $0.state == .inProgress }) { return active }
        if let current = open.first(where: {
            $0.plannedStart <= now
                && now < $0.plannedStart.addingTimeInterval(TimeInterval($0.plannedSeconds))
        }) { return current }
        if let upcoming = open.first(where: { $0.plannedStart > now }) { return upcoming }
        return open.last
    }
}
