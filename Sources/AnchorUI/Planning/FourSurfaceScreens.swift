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
    @State private var showsProfile = false
    @State private var showsNewHabit = false
    @State private var editingTemplate: ScheduleTemplate?
    @State private var upgradingTemplate: ScheduleTemplate?
    @State private var progressionError: String?

    public init() {}

    private var activeTemplates: [ScheduleTemplate] {
        templates.filter(\.isActiveBehaviorHabit)
    }

    private var readyHabits: [ScheduleTemplate] {
        activeTemplates.filter { template in
            streak(for: template) >= HabitPolicy.upgradeStreak
                && (template.lastProgressPromptedAt == nil
                    || template.lastProgressPromptedAt! < template.currentHabitLevelStartedAt)
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                DoodleScene(
                    "HabitsDoodle",
                    eyebrow: "Habits",
                    title: "Redraw the pattern",
                    message: "Notice what keeps pulling you, choose a better direction, then give it a real place in the week."
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

                if let readyHabit = readyHabits.first {
                    progressionPrompt(for: readyHabit)
                }

                if let progressionError {
                    Label(progressionError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(theme.negative)
                }

                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack(alignment: .firstTextBaseline) {
                        SectionHeader("Habits in practice", subtitle: "Behavior changes stay small; the rest of your schedule is unlimited")
                        Spacer(minLength: Space.sm)
                        Text("\(activeTemplates.count) / \(HabitPolicy.maximumActiveHabits)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(theme.accent)
                    }
                    if activeTemplates.isEmpty {
                        EmptyStateView(
                            symbol: "repeat",
                            title: "No habits scheduled yet",
                            message: "Add one at a time and Anchor will place it into the days you choose."
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(activeTemplates) { template in
                                Button {
                                    if streak(for: template) >= HabitPolicy.upgradeStreak {
                                        upgradingTemplate = template
                                    } else {
                                        editingTemplate = template
                                    }
                                } label: {
                                    HStack(spacing: Space.sm) {
                                        Image(systemName: template.lifeDirection?.symbolName ?? "repeat")
                                            .foregroundStyle(theme.accent)
                                            .frame(width: 28)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(template.title)
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(theme.textPrimary)
                                            Text("\(routineTime(template)) · \(template.weekdays.map(\.shortLabel).joined(separator: " "))")
                                                .font(.caption)
                                                .foregroundStyle(theme.textSecondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 3) {
                                            Text("\(streak(for: template)) / \(HabitPolicy.upgradeStreak)")
                                                .font(.caption.weight(.bold).monospacedDigit())
                                                .foregroundStyle(streak(for: template) >= HabitPolicy.upgradeStreak ? theme.positive : theme.textTertiary)
                                            Text(streak(for: template) >= HabitPolicy.upgradeStreak ? "Ready" : "streak")
                                                .font(.caption2)
                                                .foregroundStyle(theme.textTertiary)
                                        }
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(theme.textTertiary)
                                    }
                                    .padding(.vertical, Space.sm)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                if template.id != activeTemplates.last?.id {
                                    Divider().overlay(theme.hairline)
                                }
                            }
                        }
                        .padding(.horizontal, Space.md)
                        .background(theme.surface, in: .rect(cornerRadius: Radius.lg))
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(theme.hairline))
                    }
                }

                HStack(spacing: Space.sm) {
                    Button(activeTemplates.count >= HabitPolicy.maximumActiveHabits ? "Five habits in practice" : "Add a habit") {
                        showsNewHabit = true
                    }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(activeTemplates.count >= HabitPolicy.maximumActiveHabits)
                }
                if activeTemplates.count >= HabitPolicy.maximumActiveHabits && readyHabits.isEmpty {
                    Text("Complete seven scheduled occurrences in a row. Then Anchor will offer an upgrade or help you graduate one to make room.")
                        .font(.footnote)
                        .foregroundStyle(theme.textTertiary)
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
        .sheet(item: $upgradingTemplate) { template in
            HabitUpgradeSheet(template: template) {
                progressionError = nil
            }
            .anchorTheme()
        }
    }

    private var profileSummary: String {
        let patterns = profiles.first?.selectedPatterns.count ?? 0
        let directions = profiles.first?.desiredDirections.count ?? 0
        if patterns == 0 && directions == 0 { return "Choose what tends to pull you and what you want that time to become." }
        return "\(patterns) pattern\(patterns == 1 ? "" : "s") · \(directions) direction\(directions == 1 ? "" : "s")"
    }

    private func routineTime(_ template: ScheduleTemplate) -> String {
        let start = Calendar.current.startOfDay(for: Date())
        let time = Calendar.current.date(byAdding: .minute, value: template.startMinutesFromMidnight, to: start) ?? start
        return time.formatted(date: .omitted, time: .shortened)
    }

    private func streak(for template: ScheduleTemplate) -> Int {
        HabitPolicy().streak(
            for: template.habitSchedule(),
            blocks: planBlocks.map { $0.snapshot() }
        )
    }

    private func progressionPrompt(for template: ScheduleTemplate) -> some View {
        Card(padding: Space.lg) {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .top, spacing: Space.sm) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(theme.positive)
                        .frame(width: 34, height: 34)
                        .background(theme.positive.opacity(0.12), in: .circle)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(template.title) is ready for what’s next")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        Text("You completed seven scheduled occurrences in a row. Make this habit a little stronger, or make room for something new.")
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Space.sm) { progressionButtons(for: template) }
                    VStack(spacing: Space.sm) { progressionButtons(for: template) }
                }
            }
        }
        .accessibilityIdentifier("anchor.habits.progression-prompt")
    }

    @ViewBuilder
    private func progressionButtons(for template: ScheduleTemplate) -> some View {
        Button("Upgrade this habit") { upgradingTemplate = template }
            .buttonStyle(PrimaryButtonStyle())
        Button(activeTemplates.count >= HabitPolicy.maximumActiveHabits ? "Graduate & add new" : "Add a new habit") {
            prepareNewHabit(after: template)
        }
        .buttonStyle(QuietButtonStyle())
        Button("Later") { markPromptHandled(template) }
            .buttonStyle(QuietButtonStyle(expands: false))
    }

    private func prepareNewHabit(after template: ScheduleTemplate) {
        do {
            if activeTemplates.count >= HabitPolicy.maximumActiveHabits {
                template.graduatedAt = Date()
                template.archivedAt = Date()
                template.updatedAt = Date()
                try DayPlanService(context: context).reconcileFutureBlocks(for: template)
            } else {
                template.lastProgressPromptedAt = Date()
                template.updatedAt = Date()
                try context.save()
            }
            progressionError = nil
            showsNewHabit = true
        } catch {
            context.rollback()
            progressionError = "Anchor could not make room for the new habit. Nothing was changed."
        }
    }

    private func markPromptHandled(_ template: ScheduleTemplate) {
        template.lastProgressPromptedAt = Date()
        template.updatedAt = Date()
        do {
            try context.save()
            progressionError = nil
        } catch {
            context.rollback()
            progressionError = "Anchor could not save that choice. Please try again."
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
                        eyebrow: "LEVEL \(template.habitVersion + 1)",
                        title: "A little more, not a whole new life",
                        message: "Choose one concrete change. The next seven scheduled occurrences begin a fresh streak.",
                        compact: true
                    )
                    if let saveError {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(theme.negative)
                    }
                    Button { applyDurationUpgrade() } label: {
                        upgradeRow(
                            title: "Add five minutes",
                            detail: "\(template.plannedSeconds / 60) → \(template.plannedSeconds / 60 + 5) minutes",
                            symbol: "timer"
                        )
                    }
                    .buttonStyle(.plain)

                    if !availableDays.isEmpty {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Text("Or add one day")
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
                    }
                }
                .padding(Space.lg)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(theme.canvas)
            .navigationTitle("Upgrade \(template.title)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 430, idealHeight: 560)
        #endif
    }

    private func upgradeRow(title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: Space.md) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(theme.accent)
                .frame(width: 42, height: 42)
                .background(theme.accent.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(theme.textPrimary)
                Text(detail).font(.subheadline).foregroundStyle(theme.textSecondary)
            }
            Spacer()
            Image(systemName: "arrow.right")
                .foregroundStyle(theme.textTertiary)
        }
        .padding(Space.md)
        .background(theme.surface, in: .rect(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(theme.hairline))
    }

    private func applyDurationUpgrade() {
        template.plannedSeconds += 5 * 60
        persistUpgrade()
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

    public init() {}

    private enum Section: String, CaseIterable, Identifiable {
        case day = "Day review"
        case interruptions = "Interruptions"
        case trends = "Trends"
        var id: String { rawValue }
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("History section", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
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
