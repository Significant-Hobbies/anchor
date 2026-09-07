#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

public struct TodayScreen: View {
    private let controller: FocusController
    private let onOpenFocus: () -> Void

    public init(controller: FocusController, onOpenFocus: @escaping () -> Void) {
        self.controller = controller
        self.onOpenFocus = onOpenFocus
    }

    public var body: some View {
        PlanScreen(controller: controller, onOpenFocus: onOpenFocus)
    }
}

public struct HabitsScreen: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.anchorWorkspaceMaxWidth) private var workspaceMaxWidth
    @Environment(\.modelContext) private var context
    @Query private var profiles: [BehaviorProfile]
    @Query(sort: \ScheduleTemplate.createdAt) private var templates: [ScheduleTemplate]
    @Query(sort: \PlanBlock.plannedStart) private var planBlocks: [PlanBlock]
    @Query(sort: \HabitCompletion.updatedAt, order: .reverse) private var habitCompletions: [HabitCompletion]
    @State private var showsProfile = false
    @State private var showsNewHabit = false
    @State private var editingTemplate: ScheduleTemplate?
    @State private var schedulingTemplate: ScheduleTemplate?
    @State private var progressionError: String?

    public init() {}

    private var activeTemplates: [ScheduleTemplate] {
        templates.filter(\.isActiveBehaviorHabit)
    }

    private var pausedTemplates: [ScheduleTemplate] {
        templates.filter { $0.isBehaviorHabit && $0.archivedAt != nil && $0.graduatedAt == nil }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                DoodleScene(
                    "HabitsDoodle",
                    eyebrow: "Habits",
                    title: "Habits",
                    message: "Tick it off or add it to your day. A time is optional."
                )

                Button { showsProfile = true } label: {
                    HStack(spacing: Space.sm) {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundStyle(theme.accent)
                            .frame(width: 28, height: 28)
                            .background(theme.accent.opacity(0.12), in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Patterns and replacements")
                                .font(.headline)
                                .foregroundStyle(theme.textPrimary)
                            Text(profileSummary)
                                .font(.subheadline)
                                .foregroundStyle(theme.textSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(theme.textTertiary)
                    }
                    .padding(Space.md)
                    .background(theme.surface, in: .rect(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(theme.hairline))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("anchor.habits.behavior-profile")
                .accessibilityValue(profileSummary)

                if let progressionError {
                    Label(progressionError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(theme.negative)
                }

                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack(alignment: .firstTextBaseline) {
                        SectionHeader("Your habits", subtitle: "Track them here. Schedule only what needs a time.")
                        Spacer(minLength: Space.sm)
                        Text("\(activeTemplates.count) active")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(theme.accent)
                    }
                    if activeTemplates.isEmpty {
                        EmptyStateView(
                            symbol: "repeat",
                            title: "No habits yet",
                            message: "Add a small intention for the days it matters. Time is optional."
                        )
                    } else {
                        VStack(spacing: Space.sm) {
                            ForEach(activeTemplates) { template in
                                habitCard(template)
                            }
                        }
                    }
                }

                Button("Add a habit", systemImage: "plus") {
                    showsNewHabit = true
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("anchor.habits.add")

                if !pausedTemplates.isEmpty {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionHeader("Paused", subtitle: "Kept for later without crowding this week")
                        ForEach(pausedTemplates) { template in
                            HStack(spacing: Space.sm) {
                                Image(systemName: "pause.circle")
                                    .foregroundStyle(theme.textTertiary)
                                Text(template.title)
                                    .foregroundStyle(theme.textPrimary)
                                Spacer()
                                Button("Resume") { resume(template) }
                                    .buttonStyle(QuietButtonStyle(expands: false))
                            }
                            .padding(Space.md)
                            .background(theme.surface, in: .rect(cornerRadius: Radius.md))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(theme.hairline))
                        }
                    }
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: workspaceMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(theme.canvas)
        .sheet(isPresented: $showsProfile) { BehaviorProfileEditor().anchorTheme() }
        .sheet(isPresented: $showsNewHabit) {
            PlanBlockEditor(initialDay: Date(), startsBehaviorHabit: true) {}
                .anchorTheme()
        }
        .sheet(item: $editingTemplate) { template in
            PlanBlockEditor(initialDay: Date(), template: template) {}
                .anchorTheme()
        }
        .sheet(item: $schedulingTemplate) { template in
            PlanBlockEditor(initialDay: Date(), placingHabit: template) {}
                .anchorTheme()
        }
    }

    private var profileSummary: String {
        let patterns = profiles.first?.selectedPatterns.count ?? 0
        let directions = profiles.first?.desiredDirections.count ?? 0
        if patterns == 0 && directions == 0 { return "Choose what tends to pull you and what you want that time to become." }
        return "\(patterns) pattern\(patterns == 1 ? "" : "s") · \(directions) direction\(directions == 1 ? "" : "s")"
    }

    private func habitTiming(_ template: ScheduleTemplate) -> String {
        guard template.habitUsesSuggestedTime else { return "Any time" }
        let start = Calendar.current.startOfDay(for: Date())
        let time = Calendar.current.date(byAdding: .minute, value: template.startMinutesFromMidnight, to: start) ?? start
        return "Suggested \(time.formatted(date: .omitted, time: .shortened))"
    }

    private func weeklyProgress(for template: ScheduleTemplate) -> HabitPolicy.WeeklyProgress {
        HabitPolicy().weeklyProgress(
            for: template.habitSchedule(),
            blocks: planBlocks.map { $0.snapshot() },
            completions: habitCompletions.map { $0.snapshot() }
        )
    }

    private func habitCard(_ template: ScheduleTemplate) -> some View {
        let progress = weeklyProgress(for: template)
        return VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .top, spacing: Space.sm) {
                Image(systemName: template.lifeDirection?.symbolName ?? "repeat")
                    .font(.headline)
                    .foregroundStyle(theme.accent)
                    .frame(width: 36, height: 36)
                    .background(theme.accent.opacity(0.12), in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text(template.title)
                        .font(.headline)
                        .foregroundStyle(theme.textPrimary)
                    Text("\(habitTiming(template)) · \(template.weekdays.sorted { $0.rawValue < $1.rawValue }.map(\.compactLabel).joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                    if let pattern = template.behaviorPattern {
                        Text("Instead of \(pattern.label.lowercased())")
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                Spacer(minLength: Space.sm)
                Menu {
                    Button("Pause habit", systemImage: "pause") { pause(template) }
                    Button("Edit habit", systemImage: "pencil") { editingTemplate = template }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .menuIndicator(.hidden)
                .accessibilityLabel("More actions for \(template.title)")
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: Space.md) {
                    habitProgress(progress)
                    Spacer(minLength: 0)
                    habitActions(template)
                }
                VStack(alignment: .leading, spacing: Space.sm) {
                    habitProgress(progress)
                    habitActions(template)
                }
            }
        }
        .padding(Space.md)
        .background(theme.surface, in: .rect(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(theme.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("anchor.habits.card.\(template.id.uuidString)")
    }

    private func habitProgress(_ progress: HabitPolicy.WeeklyProgress) -> some View {
        Text("\(progress.completed) of \(progress.scheduled) this week")
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(theme.textSecondary)
    }

    private func completedBlock(_ template: ScheduleTemplate) -> PlanBlock? {
        planBlocks.first {
            $0.templateID == template.id && $0.state == .completed
                && Calendar.current.isDate($0.templateOccurrenceDay ?? $0.plannedStart, inSameDayAs: Date())
        }
    }

    private func isCompleted(_ template: ScheduleTemplate) -> Bool {
        let direct = habitCompletions.first {
            $0.habitID == template.id && Calendar.current.isDate($0.day, inSameDayAs: Date())
        }
        return direct?.isCompleted == true || completedBlock(template) != nil
    }

    private func habitActions(_ template: ScheduleTemplate) -> some View {
        let done = isCompleted(template)
        return FlowRow(spacing: Space.xs) {
            Button(done ? "Undo check-off" : "Done", systemImage: done ? "arrow.uturn.backward" : "checkmark") {
                setCompleted(!done, template: template)
            }
            .buttonStyle(QuietButtonStyle(expands: false))
            .disabled(completedBlock(template) != nil)
            .accessibilityHint(done ? "Tap to undo today's check-off" : "Record without scheduling a time")
            .accessibilityIdentifier("anchor.habits.complete")
            Button("Schedule", systemImage: "calendar.badge.plus") { schedulingTemplate = template }
                .buttonStyle(QuietButtonStyle(expands: false))
                .disabled(!template.applies(to: Date()))
        }
    }

    private func setCompleted(_ completed: Bool, template: ScheduleTemplate) {
        do {
            try HabitDayService(context: context).setCompleted(completed, habitID: template.id, on: Date())
            progressionError = nil
        } catch {
            context.rollback()
            progressionError = "Anchor could not save that check-off. Please try again."
        }
    }

    private func pause(_ template: ScheduleTemplate) {
        template.archivedAt = Date()
        persistScheduleChange(template, failure: "Anchor could not pause that habit.")
    }

    private func resume(_ template: ScheduleTemplate) {
        template.archivedAt = nil
        template.habitLevelStartedAt = Date()
        persistScheduleChange(template, failure: "Anchor could not resume that habit.")
    }

    private func persistScheduleChange(_ template: ScheduleTemplate, failure: String) {
        template.updatedAt = Date()
        do {
            try DayPlanService(context: context).reconcileFutureBlocks(for: template)
            progressionError = nil
        } catch {
            context.rollback()
            progressionError = failure
        }
    }


}

private struct HabitUpgradeSheet: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let template: ScheduleTemplate
    let onUpgrade: () -> Void
    @State private var saveError: String?

    private var availableDays: [ScheduleWeekday] {
        ScheduleWeekday.allCases.filter { !template.weekdays.contains($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    DoodleScene(
                        "HabitsDoodle",
                        eyebrow: "RHYTHM",
                        title: "Change only what helps",
                        message: "Make this available on one more day, or leave it exactly as it is.",
                        compact: true
                    )
                    if let saveError {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(theme.negative)
                    }
                    if !availableDays.isEmpty {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Text("Make it available one more day")
                                .font(.headline)
                                .foregroundStyle(theme.textPrimary)
                            FlowRow(spacing: Space.xs) {
                                ForEach(availableDays, id: \.self) { day in
                                    Button(day.label) { applyDayUpgrade(day) }
                                        .buttonStyle(.bordered)
                                        .tint(theme.accent)
                                }
                            }
                        }
                    } else {
                        EmptyStateView(
                            symbol: "calendar.badge.checkmark",
                            title: "Already available every day",
                            message: "Keep the rhythm, or use Edit to change its days and suggested time."
                        )
                    }
                }
                .padding(Space.lg)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(theme.canvas)
            .navigationTitle("Adjust \(template.title)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 430, idealHeight: 560)
        #endif
    }

    private func applyDayUpgrade(_ day: ScheduleWeekday) {
        template.weekdays.insert(day)
        persistUpgrade()
    }

    private func persistUpgrade() {
        template.habitVersion += 1
        template.habitLevelStartedAt = Date()
        template.lastProgressPromptedAt = nil
        template.updatedAt = Date()
        do {
            try DayPlanService(context: context).reconcileFutureBlocks(for: template)
            saveError = nil
            onUpgrade()
            dismiss()
        } catch {
            context.rollback()
            saveError = "Anchor could not apply this upgrade. Nothing was changed."
        }
    }
}

public struct HistoryScreen: View {
    @Environment(\.anchorTheme) private var theme
    @State private var section: Section = .day

    public init(section: Section = .day) {
        _section = State(initialValue: section)
    }

    public enum Section: String, CaseIterable, Identifiable, Sendable {
        case day = "Day review"
        case interruptions = "Interruptions"
        case trends = "Trends"
        public var id: String { rawValue }
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("History section", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Space.lg)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.xs)
            .frame(maxWidth: 680)

            switch section {
            case .day: DayReviewScreen()
            case .interruptions: LogScreen()
            case .trends: AnalyticsScreen()
            }
        }
        .background(theme.canvas)
    }
}
#endif
