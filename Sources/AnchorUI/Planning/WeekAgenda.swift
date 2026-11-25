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
        VStack(alignment: .leading, spacing: Space.md) {
            ForEach(days, id: \.self) { day in
                let end = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
                let blocks = entries.filter { $0.plannedStart < end && $0.plannedEnd > day }
                Card(padding: Space.md) {
                    VStack(alignment: .leading, spacing: Space.xs) {
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
                        if blocks.isEmpty {
                            Text("No entries").font(.subheadline).foregroundStyle(theme.textSecondary)
                        }
                        ForEach(blocks) { block in
                            Divider()
                            Button { edit(block) } label: {
                                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                                    Text(max(day, block.plannedStart), format: .dateTime.hour().minute())
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
        }
        .accessibilityIdentifier("anchor.planner.week")
    }
}
#endif
