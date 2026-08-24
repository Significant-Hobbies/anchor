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
    @Query private var profiles: [BehaviorProfile]
    @Query(sort: \ScheduleTemplate.createdAt) private var templates: [ScheduleTemplate]
    @State private var showsProfile = false
    @State private var showsNewHabit = false
    @State private var showsManager = false
    @State private var editingTemplate: ScheduleTemplate?

    public init() {}

    private var activeTemplates: [ScheduleTemplate] {
        templates.filter { !$0.isArchived }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Habits")
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("Notice a pattern, choose a better direction, then give the replacement a real place in your week.")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                }

                Button { showsProfile = true } label: {
                    Card(padding: Space.lg) {
                        HStack(spacing: Space.md) {
                            Image("HabitsOnboarding")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 108, height: 88)
                                .clipShape(.rect(cornerRadius: Radius.md))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: Space.xxs) {
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
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionHeader("Scheduled habits", subtitle: "These become blocks in Today and the next action in Focus")
                    if activeTemplates.isEmpty {
                        EmptyStateView(
                            symbol: "repeat",
                            title: "No habits scheduled yet",
                            message: "Add one at a time and Anchor will place it into the days you choose."
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(activeTemplates) { template in
                                Button { editingTemplate = template } label: {
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
                    Button("Add a habit") { showsNewHabit = true }
                        .buttonStyle(PrimaryButtonStyle())
                    if !activeTemplates.isEmpty {
                        Button("Manage", action: { showsManager = true })
                            .buttonStyle(QuietButtonStyle(expands: false))
                    }
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(theme.canvas)
        .sheet(isPresented: $showsProfile) { BehaviorProfileEditor().anchorTheme() }
        .sheet(isPresented: $showsNewHabit) {
            PlanBlockEditor(initialDay: Date(), startsRecurring: true) {}
                .anchorTheme()
        }
        .sheet(item: $editingTemplate) { template in
            PlanBlockEditor(initialDay: Date(), template: template) {}
                .anchorTheme()
        }
        .sheet(isPresented: $showsManager) { RoutineManager(onChange: {}).anchorTheme() }
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
