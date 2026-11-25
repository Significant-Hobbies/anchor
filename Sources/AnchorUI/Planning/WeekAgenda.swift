#if !os(watchOS)
import AnchorCore
import SwiftUI

struct WeekAgenda: View {
    @Environment(\.anchorTheme) private var theme
    let days: [Date]
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
                    ForEach(blocks) { block in
                        Button { edit(block) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                                Group {
                                    if block.plannedStart < day { Text("Continues") }
                                    else { Text(block.plannedStart, format: .dateTime.hour().minute()) }
                                }
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(theme.textSecondary)
                                Text(block.title).font(.body.weight(.medium))
                                Spacer(minLength: 0)
                                if block.externalEventKey != nil {
                                    Image(systemName: "calendar").font(.caption).foregroundStyle(theme.textSecondary)
                                }
                            }
                            .padding(.vertical, Space.xs)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .accessibilityIdentifier("anchor.planner.week")
    }
}
#endif
