#if !os(watchOS)
import AnchorCore
import SwiftUI

struct WeekAgenda: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.calendarActivityTags) private var activityTags
    let days: [Date]
    let actuals: CalendarActualData
    let entries: [PlanBlock]
    let openDay: (Date) -> Void
    let add: (Date) -> Void
    let edit: (PlanBlock) -> Void
    let move: (CalendarDrag, TimetableColumn, Date) -> Bool

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
                                }.draggable(CalendarDrag(id: block.id, source: .plan))
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 36, alignment: .top)
                        .contentShape(Rectangle())
                        .dropDestination(for: CalendarDrag.self) { items, _ in drop(items, on: day, column: .scheduled) }
                        VStack(alignment: .leading, spacing: Space.xs) {
                            ForEach(actuals.calendarEntries(in: DateInterval(start: day, end: end))) { entry in
                                Button { actuals.edit(entry) } label: {
                                    row(entry.title, at: entry.start, day: day, done: true, ongoing: !actuals.recordedIDs.contains(entry.id))
                                }.buttonStyle(.plain)
                                .disabled(!actuals.available && !actuals.storedLogIDs.contains(entry.id))
                                .accessibilityLabel("Edit done entry " + entry.title)
                                .draggable(CalendarDrag(id: entry.id, source: .actual))
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 36, alignment: .top)
                        .contentShape(Rectangle())
                        .dropDestination(for: CalendarDrag.self) { items, _ in drop(items, on: day, column: .done) }
                    }
                }
            }
        }
        .accessibilityIdentifier("anchor.planner.week")
    }
    private func drop(_ items: [CalendarDrag], on day: Date, column: TimetableColumn) -> Bool {
        guard let item = items.first, !item.resizing else { return false }
        let original = item.source == .plan ? entries.first { $0.id == item.id }?.plannedStart
            : (actuals.entries + actuals.ongoing).first { $0.id == item.id }?.start
        guard let original, let target = Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: original),
            minute: Calendar.current.component(.minute, from: original), second: Calendar.current.component(.second, from: original), of: day)
        else { return false }
        return move(item, column, target)
    }

    private func row(_ title: String, at start: Date, day: Date, done: Bool = false, ongoing: Bool = false) -> some View {
        let category = activityTags[title] ?? .suggestion(for: title)
        return VStack(alignment: .leading, spacing: 2) {
            Text(ongoing ? title + " · In progress" : title).font(.subheadline.weight(.medium))
            if start < day { Text("Continues").font(.caption) }
            else { Text(start, style: .time).font(.caption.monospacedDigit()) }
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(done ? theme.textPrimary : Color.black.opacity(0.91))
        .background(category.calendarColor.opacity(done ? 0.24 : 1), in: .rect(cornerRadius: Radius.sm))
        .overlay { RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(category.calendarColor.opacity(0.75)) }
        .help(category.rawValue.capitalized)
        .multilineTextAlignment(.leading)
    }
}
#endif
