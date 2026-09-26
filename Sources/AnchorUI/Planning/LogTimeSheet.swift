#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

/// Records time that actually happened — the logger half of Today. Two modes
/// share one sheet: "still happening" opens an in-progress entry you finish
/// later (quick capture), and a finished entry stores its real start and end
/// so the day review counts it as observed rather than timed.
struct LogTimeSheet: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var details = ""
    @State private var selectedProjectID: UUID?
    @State private var kind: PlanBlockKind = .focus
    @State private var start: Date
    @State private var end: Date
    @State private var stillHappening: Bool
    @State private var saveError: String?

    private let block: PlanBlock?
    private let onSave: () -> Void

    init(
        day: Date,
        suggestedStart: Date? = nil,
        block: PlanBlock? = nil,
        onSave: @escaping () -> Void
    ) {
        let now = Date()
        let calendar = Calendar.current
        let fallbackStart = calendar.isDateInToday(day)
            ? now
            : calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        let resolvedStart = block?.actualStartedAt ?? block?.plannedStart ?? suggestedStart ?? fallbackStart
        let isOngoing = block?.state == .inProgress && block?.actualStartedAt != nil
        _title = State(initialValue: block?.title ?? "")
        _details = State(initialValue: block?.details ?? "")
        _selectedProjectID = State(initialValue: block?.projectID)
        _kind = State(initialValue: block?.kind ?? .focus)
        _start = State(initialValue: resolvedStart)
        _end = State(initialValue: block?.actualEndedAt ?? min(now, resolvedStart.addingTimeInterval(30 * 60)))
        _stillHappening = State(initialValue: block == nil ? calendar.isDateInToday(day) : isOngoing)
        self.block = block
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Text("Write down what actually happened. Logged entries count as observed time in the day review — they never pretend to be a timed focus session.")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)

                    if let saveError {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(theme.negative)
                            .accessibilityIdentifier("anchor.log.error")
                    }

                    Card(padding: Space.lg) {
                        VStack(alignment: .leading, spacing: Space.md) {
                            editorLabel("What happened", detail: "The thing you actually did")
                            TextField("What did you do?", text: $title, axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(.system(size: 23, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme.textPrimary)
                                .lineLimit(1...3)
                                .accessibilityIdentifier("anchor.log.title")
                            Divider().overlay(theme.hairline)
                            TextField("Anything worth remembering", text: $details, axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(.subheadline)
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(2...4)

                            ProjectPicker(selectedID: $selectedProjectID)

                            FlowRow(spacing: Space.xs) {
                                ForEach(PlanBlockKind.allCases, id: \.self) { option in
                                    Button {
                                        withAnimation(Motion.snappy) { kind = option }
                                    } label: {
                                        Chip(option.label, symbol: option.symbolName, isSelected: kind == option)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    Card(padding: Space.lg) {
                        VStack(alignment: .leading, spacing: Space.md) {
                            editorLabel("When it happened", detail: "The real span, not the planned one")
                            VStack(alignment: .leading, spacing: Space.xxs) {
                                Text("STARTED").font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(theme.textTertiary)
                                DatePicker("Started", selection: $start)
                                    .labelsHidden()
                                    .accessibilityIdentifier("anchor.log.start")
                            }
                            Toggle("Still happening", isOn: $stillHappening)
                                .tint(theme.accent)
                                .disabled(start > Date())
                                .accessibilityIdentifier("anchor.log.still-happening")
                                .onChange(of: stillHappening) { _, ongoing in
                                    guard !ongoing, end <= start else { return }
                                    let now = Date()
                                    end = now
                                    if end <= start { start = now.addingTimeInterval(-30 * 60) }
                                }
                            if !stillHappening {
                                VStack(alignment: .leading, spacing: Space.xxs) {
                                    Text("ENDED").font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(theme.textTertiary)
                                    DatePicker("Ended", selection: $end, in: ...Date())
                                        .labelsHidden()
                                        .accessibilityIdentifier("anchor.log.end")
                                }
                            }
                            if stillHappening {
                                Text("Anchor keeps this entry open on the timetable. Finish it from the block's actions when you're done.")
                                    .font(.caption)
                                    .foregroundStyle(theme.textTertiary)
                            }
                        }
                    }
                }
                .padding(Space.lg)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(theme.canvas)
            .navigationTitle(block == nil ? "Log time" : "Log actual time")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("anchor.log.save")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 540, idealWidth: 620, minHeight: 420, idealHeight: 560)
        #endif
    }

    private func editorLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.textPrimary)
            Text(detail)
                .font(.caption)
                .foregroundStyle(theme.textTertiary)
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        if stillHappening {
            guard start <= now else {
                saveError = "An entry that is still happening can't start in the future."
                return
            }
        } else {
            guard end > start else {
                saveError = "The entry has to end after it starts."
                return
            }
            guard end <= now.addingTimeInterval(60) else {
                saveError = "Logged time can't end in the future — leave \"Still happening\" on instead."
                return
            }
        }

        let target: PlanBlock
        if let block {
            target = block
        } else {
            target = PlanBlock(
                projectID: selectedProjectID,
                title: trimmed,
                details: details,
                plannedStart: start,
                plannedSeconds: stillHappening
                    ? max(60, Int(now.timeIntervalSince(start)))
                    : max(60, Int(end.timeIntervalSince(start))),
                kind: kind
            )
            context.insert(target)
        }
        target.projectID = selectedProjectID
        target.title = trimmed
        target.details = details
        target.kind = kind
        target.actualStartedAt = start
        if stillHappening {
            target.actualEndedAt = nil
            target.state = .inProgress
        } else {
            target.actualEndedAt = end
            target.state = .completed
        }
        target.updatedAt = now
        do {
            try context.save()
            saveError = nil
            onSave()
            dismiss()
        } catch {
            context.rollback()
            saveError = "Anchor could not save this entry. Nothing was recorded."
        }
    }
}
#endif
