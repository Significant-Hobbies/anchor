#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

struct ObservedHabitsCard: View {
    let entries: [DayLedgerEntry]
    let blocks: [PlanBlock]
    let days: Int?
    @Query private var templates: [ScheduleTemplate]
    @Query(sort: \HabitCompletion.updatedAt, order: .reverse) private var completions: [HabitCompletion]

    private var patterns: [ObservedHabit] {
        let now = Date()
        let calendar = Calendar.current
        let start = days.flatMap { calendar.date(byAdding: .day, value: 1 - $0, to: calendar.startOfDay(for: now)) } ?? .distantPast
        let ids = Set(entries.map(\.id))
        var observations = entries.filter { $0.end <= now && $0.title != "Focus session" }.map { ($0.title, $0.start) }
        for block in blocks where block.state == .completed && !ids.contains(block.id) {
            observations.append((block.title, block.actualEndedAt ?? block.plannedStart))
        }
        let titles = Dictionary(templates.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        var seen: [UUID: Set<Date>] = [:]
        for completion in completions {
            let day = calendar.startOfDay(for: completion.day)
            guard seen[completion.habitID, default: []].insert(day).inserted,
                  completion.isCompleted, let title = titles[completion.habitID] else { continue }
            observations.append((title, day))
        }
        return ObservedHabit.derive(observations, from: start, through: now, calendar: calendar)
    }

    var body: some View {
        Card(padding: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Habit insights").font(.headline)
                let habits = patterns
                if habits.isEmpty {
                    Text("Activities you record on three or more separate days appear here.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(habits) { habit in
                        HStack {
                            Text(habit.title)
                            Spacer()
                            Text("\(habit.days) days").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.accessibilityIdentifier("anchor.insights.habits")
    }
}
#endif
