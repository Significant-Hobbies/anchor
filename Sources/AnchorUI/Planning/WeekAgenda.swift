#if !os(watchOS)
import AnchorCore
import SwiftUI

struct WeekAgenda: View {
    @Environment(\.anchorTheme) private var theme
    let days: [Date]
    let actuals: CalendarActualData
    let entries: [PlanBlock]
    let openDay: (Date) -> Void
    let add: (Date) -> Void
    let edit: (PlanBlock) -> Void

    var body: some View {
        Card(padding: Space.md) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(days, id: \.self) { day in
                    let end = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
                    let blocks = entries.filter { $0.plannedStart < end && $0.plannedEnd > day }
                    if day != days.first { Divider().padding(.vertical, Space.xxs) }
                    HStack {
                        Button {
                            openDay(day)
                        } label: {
                            HStack(spacing: Space.xs) {
                                Text(day, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                                    .font(.headline)
                                Image(systemName: "chevron.right").font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Open day view")
                        Spacer()
                        Button { add(day) } label: {
                            Image(systemName: "plus").frame(width: 38, height: 38)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Add an entry for \(day.formatted(date: .complete, time: .omitted))")
                    }
                    HStack(alignment: .top, spacing: Space.sm) {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            ForEach(blocks) { block in
                                HStack(alignment: .top, spacing: Space.xxs) {
                                    CalendarCheckButton(block: block, data: actuals)
                                    Button { edit(block) } label: {
                                        row(block.title, at: block.plannedStart, day: day)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: Space.xs) {
                            ForEach(actuals.calendarEntries(in: DateInterval(start: day, end: end))) { entry in
                                Button { actuals.edit(entry) } label: {
                                    row(actuals.recordedIDs.contains(entry.id) ? entry.title : entry.title + " · In progress", at: entry.start, day: day)
                                }.buttonStyle(.plain)
                                .disabled(!actuals.available)
                                .accessibilityLabel("Edit done entry " + entry.title)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .accessibilityIdentifier("anchor.planner.week")
    }
    private func row(_ title: String, at start: Date, day: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.medium))
            if start < day { Text("Continues").font(.caption) }
            else { Text(start, style: .time).font(.caption.monospacedDigit()) }
        }.multilineTextAlignment(.leading)
    }
}
#endif
