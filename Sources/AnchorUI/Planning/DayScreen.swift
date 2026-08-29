#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

struct PlanScreen: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.anchorWorkspaceMaxWidth) private var workspaceMaxWidth
    @Environment(\.modelContext) private var context
    @Query(sort: \PlanBlock.plannedStart) private var allBlocks: [PlanBlock]
    @Query(sort: \ScheduleTemplate.createdAt) private var templates: [ScheduleTemplate]
    @Query(sort: \HabitCompletion.updatedAt, order: .reverse) private var habitCompletions: [HabitCompletion]
    @Query(sort: \DayPlanConfirmation.updatedAt, order: .reverse) private var confirmations: [DayPlanConfirmation]
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var sessions: [FocusSession]
    private let controller: FocusController
    private let onOpenFocus: () -> Void
    @State private var today = Date()
    @State private var editorSeed: EditorSeed?
    @State private var showsRoutines = false
    @State private var editingBlock: PlanBlock?
    @State private var placingHabit: ScheduleTemplate?
    @State private var explainingBlock: PlanBlock?
    @State private var loadError: String?
    @State private var checkInDeferredInSession = false

    init(controller: FocusController, onOpenFocus: @escaping () -> Void) {
        self.controller = controller
        self.onOpenFocus = onOpenFocus
    }

    private var dayInterval: DateInterval {
        Calendar.current.dateInterval(of: .day, for: today)
            ?? DateInterval(start: today, duration: 86_400)
    }

    private var blocks: [PlanBlock] {
        allBlocks.filter { dayInterval.contains($0.plannedStart) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                dayHeader

                if shouldShowDailyCheckIn {
                    dailyCheckIn
                } else if todayConfirmation?.decision == .adjusted {
                    todayOnlyStatus
                }

                if !todayHabits.isEmpty {
                    todayHabitsSection
                }

                if !blocks.isEmpty {
                    daySummary
                }

                if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(theme.caution)
                }

                if blocks.isEmpty {
                    Card(padding: Space.lg) {
                        #if os(macOS)
                        HStack(spacing: Space.lg) {
                            emptyDayCopy
                            Spacer(minLength: Space.lg)
                            Button("Add the first block") { editorSeed = EditorSeed(start: suggestedStart) }
                                .buttonStyle(PrimaryButtonStyle(expands: false))
                        }
                        #else
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: Space.lg) {
                                emptyDayCopy
                                Spacer(minLength: Space.lg)
                                Button("Add the first block") { editorSeed = EditorSeed(start: suggestedStart) }
                                    .buttonStyle(PrimaryButtonStyle(expands: false))
                            }
                            VStack(alignment: .leading, spacing: Space.md) {
                                emptyDayCopy
                                Button("Add the first block") { editorSeed = EditorSeed(start: suggestedStart) }
                                .buttonStyle(PrimaryButtonStyle())
                            }
                        }
                        #endif
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(timelineItems) { item in
                            switch item {
                            case let .block(block):
                                PlanBlockRow(
                                    block: block,
                                    linkedSession: block.sessionID.flatMap { id in sessions.first { $0.id == id } },
                                    hasDifferentActiveSession: controller.hasSession && controller.session?.id != block.sessionID,
                                    isCurrent: isCurrent(block),
                                    onStart: { start(block) },
                                    onOpenFocus: onOpenFocus,
                                    onComplete: { complete(block) },
                                    onEdit: { editingBlock = block },
                                    onExplain: { explainingBlock = block }
                                )
                            case let .gap(gap):
                                ScheduleGapRow(gap: gap) {
                                    editorSeed = EditorSeed(start: gap.start)
                                }
                            }
                        }
                    }
                }

                if !activeTemplates.isEmpty {
                    Button { showsRoutines = true } label: {
                        HStack {
                            Label("Your usual week · \(activeTemplates.count) item\(activeTemplates.count == 1 ? "" : "s")", systemImage: "calendar.badge.clock")
                            Spacer()
                            Text("Manage")
                            Image(systemName: "chevron.right")
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(theme.textSecondary)
                        .padding(Space.md)
                        .background(theme.surface, in: .rect(cornerRadius: Radius.md))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: workspaceMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            if !blocks.isEmpty {
                Button("Add a block") { editorSeed = EditorSeed(start: suggestedStart) }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, Space.xs)
                    .background(.bar)
            }
        }
        .background(theme.canvas)
        .sheet(item: $editorSeed) { seed in
            PlanBlockEditor(initialDay: today, suggestedStart: seed.start) { refresh() }
                .anchorTheme()
        }
        .sheet(isPresented: $showsRoutines) {
            RoutineManager(onChange: refresh)
                .anchorTheme()
        }
        .sheet(item: $editingBlock) { block in
            PlanBlockEditor(initialDay: today, block: block) { refresh() }
                .anchorTheme()
        }
        .sheet(item: $placingHabit) { habit in
            PlanBlockEditor(
                initialDay: today,
                suggestedStart: habit.habitSuggestedStart(on: today) ?? suggestedStart,
                placingHabit: habit
            ) { refresh() }
                .anchorTheme()
        }
        .sheet(item: $explainingBlock) { block in
            DivergenceEditor(block: block) { kind, note in
                let originalState = block.state
                let event = DivergenceEvent(
                    blockID: block.id,
                    sessionID: block.sessionID,
                    kind: kind,
                    note: note
                )
                context.insert(event)
                if block.state == .planned { block.state = .skipped }
                do {
                    try context.save()
                    return true
                } catch {
                    block.state = originalState
                    context.delete(event)
                    return false
                }
            }
            .anchorTheme()
        }
        .task {
            refresh()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                let current = Date()
                if !Calendar.current.isDate(current, inSameDayAs: today) {
                    today = current
                    refresh()
                }
            }
        }
        .onChange(of: controller.hasSession) { reconcileSessions() }
    }

    private var dayHeader: some View {
        DoodleScene(
            "TodayDoodle",
            eyebrow: Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
            title: "Draw the day",
            message: "Give the important things a place. The plan can move when life does."
        )
    }

    private var activeTemplates: [ScheduleTemplate] {
        templates.filter { !$0.isArchived && !$0.isBehaviorHabit }
    }

    private var todayHabits: [ScheduleTemplate] {
        templates
            .filter { $0.isActiveBehaviorHabit && $0.applies(to: today) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var todayConfirmation: DayPlanConfirmation? {
        confirmations.first { Calendar.current.isDate($0.day, inSameDayAs: today) }
    }

    private var shouldShowDailyCheckIn: Bool {
        todayConfirmation?.decision.isConfirmed != true && !checkInDeferredInSession
    }

    private var usualDayName: String {
        today.formatted(.dateTime.weekday(.wide))
    }

    private var dailyCheckIn: some View {
        Card(padding: Space.lg) {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .top, spacing: Space.sm) {
                    Image(systemName: "sun.horizon.fill")
                        .foregroundStyle(theme.accent)
                        .frame(width: 32, height: 32)
                        .background(theme.accent.opacity(0.12), in: .circle)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(activeTemplates.isEmpty ? "Build your usual week" : "Same plan today?")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        Text(activeTemplates.isEmpty
                             ? "Set the week once. Anchor will bring each day forward for a quick confirmation."
                             : "Your usual \(usualDayName) is already here. Confirm it, or change only today.")
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Space.sm) { dailyCheckInButtons }
                    VStack(spacing: Space.sm) { dailyCheckInButtons }
                }
            }
        }
        .accessibilityIdentifier("anchor.today.daily-check-in")
    }

    private var todayHabitsSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(
                "Today’s habits",
                subtitle: "Finish one as it happens, or give it a place in the day"
            )
            VStack(spacing: Space.xs) {
                ForEach(todayHabits) { habit in
                    todayHabitRow(habit)
                }
            }
        }
        .accessibilityIdentifier("anchor.today.habits")
    }

    private func todayHabitRow(_ habit: ScheduleTemplate) -> some View {
        let placed = placedBlock(for: habit)
        let direct = directCompletion(for: habit)
        let isDone = placed?.state == .completed || direct?.isCompleted == true

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.sm) {
                habitIdentity(habit, placed: placed, isDone: isDone)
                Spacer(minLength: Space.sm)
                habitActions(habit, placed: placed, direct: direct, isDone: isDone)
            }
            VStack(alignment: .leading, spacing: Space.sm) {
                habitIdentity(habit, placed: placed, isDone: isDone)
                habitActions(habit, placed: placed, direct: direct, isDone: isDone)
            }
        }
        .padding(Space.md)
        .background(theme.surface, in: .rect(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(theme.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("anchor.today.habit.\(habit.id.uuidString)")
    }

    private func habitIdentity(_ habit: ScheduleTemplate, placed: PlanBlock?, isDone: Bool) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: isDone ? "checkmark" : (habit.lifeDirection?.symbolName ?? "leaf"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isDone ? theme.positive : theme.accent)
                .frame(width: 34, height: 34)
                .background((isDone ? theme.positive : theme.accent).opacity(0.11), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(habitStatusCopy(habit, placed: placed, isDone: isDone))
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .accessibilityIdentifier("anchor.today.habit.status")
            }
        }
    }

    @ViewBuilder
    private func habitActions(
        _ habit: ScheduleTemplate,
        placed: PlanBlock?,
        direct: HabitCompletion?,
        isDone: Bool
    ) -> some View {
        if isDone {
            HStack(spacing: Space.xs) {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.positive)
                if placed == nil && direct?.isCompleted == true {
                    Button("Undo") { setHabitCompleted(false, habit: habit) }
                        .buttonStyle(QuietButtonStyle(expands: false))
                        .accessibilityIdentifier("anchor.today.habit.undo")
                }
            }
        } else if let placed {
            Button("Done", systemImage: "checkmark") { complete(placed) }
                .buttonStyle(QuietButtonStyle(expands: false))
                .accessibilityIdentifier("anchor.today.habit.done")
        } else {
            HStack(spacing: Space.xs) {
                Button("Done", systemImage: "checkmark") { setHabitCompleted(true, habit: habit) }
                    .buttonStyle(QuietButtonStyle(expands: false))
                    .accessibilityIdentifier("anchor.today.habit.done")
                Button("Place", systemImage: "calendar.badge.plus") { placingHabit = habit }
                    .buttonStyle(PrimaryButtonStyle(expands: false))
                    .accessibilityIdentifier("anchor.today.habit.place")
            }
        }
    }

    private func habitStatusCopy(_ habit: ScheduleTemplate, placed: PlanBlock?, isDone: Bool) -> String {
        if isDone { return "Completed today" }
        if let placed {
            return "Placed at \(placed.plannedStart.formatted(date: .omitted, time: .shortened))"
        }
        if let suggested = habit.habitSuggestedStart(on: today) {
            return "Suggested around \(suggested.formatted(date: .omitted, time: .shortened)) · available all day"
        }
        return "Any time today"
    }

    private func placedBlock(for habit: ScheduleTemplate) -> PlanBlock? {
        allBlocks
            .filter { $0.templateID == habit.id }
            .filter { Calendar.current.isDate($0.templateOccurrenceDay ?? $0.plannedStart, inSameDayAs: today) }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private func directCompletion(for habit: ScheduleTemplate) -> HabitCompletion? {
        habitCompletions
            .filter { $0.habitID == habit.id && Calendar.current.isDate($0.day, inSameDayAs: today) }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private func setHabitCompleted(_ completed: Bool, habit: ScheduleTemplate) {
        do {
            try HabitDayService(context: context).setCompleted(completed, habitID: habit.id, on: today)
            loadError = nil
        } catch {
            context.rollback()
            loadError = "Anchor could not save that habit. Nothing else changed."
        }
    }

    @ViewBuilder
    private var dailyCheckInButtons: some View {
        if activeTemplates.isEmpty {
            Button("Set up usual week") { showsRoutines = true }
                .buttonStyle(PrimaryButtonStyle())
        } else {
            Button("Use usual \(usualDayName)") { recordCheckIn(.usual) }
                .buttonStyle(PrimaryButtonStyle())
            Button("Adjust today") { recordCheckIn(.adjusted) }
                .buttonStyle(QuietButtonStyle())
        }
        Button("Later") {
            recordCheckIn(.later)
            checkInDeferredInSession = true
        }
        .buttonStyle(QuietButtonStyle(expands: false))
    }

    private var todayOnlyStatus: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "pencil.and.list.clipboard")
                .foregroundStyle(theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Adjusting today only")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Text("Edit or move blocks below. Your usual \(usualDayName) will not change.")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 0)
            Button("Edit usual week") { showsRoutines = true }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.accent)
        }
        .padding(Space.md)
        .background(theme.accent.opacity(0.08), in: .rect(cornerRadius: Radius.md))
    }

    private var emptyDayCopy: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text("Give the day one anchor")
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Text("Start with the thing worth protecting. Commitments, rest, and recurring routines can take their place around it.")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
        }
    }

    private var daySummary: some View {
        let completed = blocks.filter { $0.state == .completed }.count
        let active = blocks.filter { isCurrent($0) || $0.state == .inProgress }.count
        let ahead = blocks.filter { $0.state == .planned && !isCurrent($0) }.count
        return HStack(spacing: Space.xs) {
            Image(systemName: "scribble.variable")
                .foregroundStyle(theme.accent)
            Text(blocks.isEmpty
                 ? "The page is open. Start with one honest block."
                 : "\(completed) finished · \(active) now · \(ahead) ahead")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("anchor.today.completion")
    }

    private var timelineItems: [PlanTimelineItem] {
        var result: [PlanTimelineItem] = []
        let sorted = blocks.sorted { $0.plannedStart < $1.plannedStart }
        for (index, block) in sorted.enumerated() {
            result.append(.block(block))
            guard index + 1 < sorted.count else { continue }
            let end = block.plannedStart.addingTimeInterval(Double(block.plannedSeconds))
            let next = sorted[index + 1].plannedStart
            if next.timeIntervalSince(end) >= 30 * 60 {
                result.append(.gap(ScheduleGap(start: end, end: next)))
            }
        }
        return result
    }

    private var suggestedStart: Date {
        let calendar = Calendar.current
        let now = Date()
        let base = calendar.isDate(now, inSameDayAs: today) ? now : calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today) ?? today
        let minute = calendar.component(.minute, from: base)
        let rounded = calendar.date(byAdding: .minute, value: (15 - minute % 15) % 15, to: base) ?? base
        let latestEnd = blocks.map { $0.plannedStart.addingTimeInterval(Double($0.plannedSeconds)) }.max()
        return max(rounded, latestEnd ?? rounded)
    }

    private func isCurrent(_ block: PlanBlock) -> Bool {
        let now = Date()
        return block.state == .inProgress || (now >= block.plannedStart && now < block.plannedStart.addingTimeInterval(Double(block.plannedSeconds)))
    }

    private func refresh() {
        do {
            _ = try DayPlanService(context: context).materialize(day: today)
            reconcileSessions()
            loadError = nil
        } catch {
            loadError = "The plan is still on this device, but Anchor could not refresh it: \(error.localizedDescription)"
        }
    }

    private func recordCheckIn(_ decision: DayPlanConfirmationDecision) {
        do {
            try DailyPlanService(context: context).record(decision, for: today)
            loadError = nil
        } catch {
            context.rollback()
            loadError = "Anchor could not save today’s confirmation. Your schedule is still available."
        }
    }

    private func reconcileSessions() {
        for block in allBlocks {
            guard let sessionID = block.sessionID,
                  let session = sessions.first(where: { $0.id == sessionID }) else { continue }
            block.actualStartedAt = session.startedAt
            if session.state == .finished {
                block.actualEndedAt = session.endedAt
                block.state = .completed
            } else {
                block.state = .inProgress
            }
        }
        if context.hasChanges { try? context.save() }
    }

    private func start(_ block: PlanBlock) {
        guard !controller.hasSession else {
            onOpenFocus()
            return
        }
        let session = controller.start(
            goal: nil,
            intent: block.title,
            minutes: max(1, Int(ceil(Double(block.plannedSeconds) / 60))),
            notes: block.details
        )
        let previousSessionID = block.sessionID
        let previousStart = block.actualStartedAt
        let previousState = block.state
        let previousUpdatedAt = block.updatedAt
        block.sessionID = session.id
        block.actualStartedAt = session.startedAt
        block.state = .inProgress
        do {
            try context.save()
            loadError = nil
        } catch {
            block.sessionID = previousSessionID
            block.actualStartedAt = previousStart
            block.state = previousState
            block.updatedAt = previousUpdatedAt
            loadError = "Focus started, but Anchor could not attach it to this plan block. It will appear as unplanned in Review."
        }
        onOpenFocus()
    }

    private func complete(_ block: PlanBlock) {
        let previousStart = block.actualStartedAt
        let previousEnd = block.actualEndedAt
        let previousState = block.state
        let previousUpdatedAt = block.updatedAt
        block.complete()
        do {
            try context.save()
            loadError = nil
        } catch {
            block.actualStartedAt = previousStart
            block.actualEndedAt = previousEnd
            block.state = previousState
            block.updatedAt = previousUpdatedAt
            loadError = "Anchor could not save this completion. The block remains open so you can try again."
        }
    }
}

private struct PlanBlockRow: View {
    @Environment(\.anchorTheme) private var theme
    @State private var showsActions = false
    let block: PlanBlock
    let linkedSession: FocusSession?
    let hasDifferentActiveSession: Bool
    let isCurrent: Bool
    let onStart: () -> Void
    let onOpenFocus: () -> Void
    let onComplete: () -> Void
    let onEdit: () -> Void
    let onExplain: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Space.sm) {
            VStack(spacing: 2) {
                Text(block.plannedStart.formatted(date: .omitted, time: .shortened))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(theme.textPrimary)
                Text(Format.duration(Double(block.plannedSeconds)))
                    .font(.caption2)
                    .foregroundStyle(theme.textTertiary)
            }
            .frame(width: 58)

            DayRailSegment(
                isCurrent: isCurrent,
                isCompleted: block.state == .completed
            )
            .frame(width: 20, height: 74)

            VStack(alignment: .leading, spacing: 3) {
                Text(block.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                HStack(spacing: Space.xxs) {
                    Text(block.kind.label)
                    Text("·")
                    Text(block.flexibility.label)
                    if block.templateID != nil {
                        Text("·")
                        Label("Recurring", systemImage: "repeat")
                    }
                    if let direction = block.lifeDirection {
                        Text("·")
                        Text(direction.label)
                    }
                }
                .font(.caption)
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)
            }
            Spacer(minLength: Space.xs)

            #if os(macOS)
            Button { showsActions.toggle() } label: {
                actionIcon
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showsActions, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    actionChoices
                }
                .padding(Space.xs)
                .frame(minWidth: 190)
                .anchorTheme()
            }
            .accessibilityLabel(actionLabel)
            .accessibilityIdentifier("anchor.today.block-actions")
            #else
            Menu {
                actionChoices
            } label: {
                actionIcon
            }
            .accessibilityLabel(actionLabel)
            .accessibilityIdentifier("anchor.today.block-actions")
            #endif
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .background(
            isCurrent ? theme.surfaceRaised : .clear,
            in: .rect(cornerRadius: Radius.md)
        )
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(theme.accent.opacity(0.22), lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(isCurrent ? (theme.isDark ? 0.22 : 0.07) : 0), radius: 12, y: 5)
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
    }

    private var actionIcon: some View {
        Label(actionLabel, systemImage: stateSymbol)
            .labelStyle(.iconOnly)
            .font(.title3)
            .foregroundStyle(stateTint)
            .frame(width: 44, height: 44)
            .contentShape(.rect)
    }

    @ViewBuilder
    private var actionChoices: some View {
        if linkedSession?.isActive == true {
            Button("Open timer") { choose(onOpenFocus) }
        } else if block.state == .planned {
            if !hasDifferentActiveSession {
                Button("Start now") { choose(onStart) }
            }
            Button("Edit or move") { choose(onEdit) }
            Button("Finished without timing") { choose(onComplete) }
        }
        Button("Explain a change") { choose(onExplain) }
    }

    private func choose(_ action: () -> Void) {
        showsActions = false
        action()
    }

    private var stateSymbol: String {
        if linkedSession?.isActive == true { return "timer" }
        return switch block.state {
        case .planned: "play.circle.fill"
        case .inProgress: "timer"
        case .completed: "checkmark.circle.fill"
        case .skipped: "minus.circle"
        case .moved: "arrow.right.circle"
        }
    }

    private var stateTint: Color {
        switch block.state {
        case .completed: theme.positive
        case .skipped, .moved: theme.textTertiary
        default: theme.accent
        }
    }

    private var actionLabel: String {
        if hasDifferentActiveSession { return "Actions for \(block.title); another session is active" }
        if linkedSession?.isActive == true { return "Open timer for \(block.title)" }
        return "Actions for \(block.title)"
    }
}

private struct ScheduleGap: Identifiable {
    let start: Date
    let end: Date
    var id: Date { start }
    var seconds: TimeInterval { end.timeIntervalSince(start) }
}

private enum PlanTimelineItem: Identifiable {
    case block(PlanBlock)
    case gap(ScheduleGap)

    var id: String {
        switch self {
        case let .block(block): "block-\(block.id)"
        case let .gap(gap): "gap-\(gap.start.timeIntervalSinceReferenceDate)"
        }
    }
}

private struct EditorSeed: Identifiable {
    let id = UUID()
    let start: Date
}

private struct ScheduleGapRow: View {
    @Environment(\.anchorTheme) private var theme
    let gap: ScheduleGap
    let onUse: () -> Void

    var body: some View {
        Button(action: onUse) {
            HStack(spacing: Space.sm) {
                Text(gap.start.formatted(date: .omitted, time: .shortened))
                    .font(.caption.monospacedDigit())
                    .frame(width: 58)
                DayGapMark()
                    .frame(width: 20, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open space · \(Format.duration(gap.seconds))")
                        .font(.subheadline.weight(.medium))
                    Text("Use this time")
                        .font(.caption)
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer()
            }
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use open time at \(gap.start.formatted(date: .omitted, time: .shortened)) for \(Format.duration(gap.seconds))")
    }
}

private struct DayRailSegment: View {
    @Environment(\.anchorTheme) private var theme
    let isCurrent: Bool
    let isCompleted: Bool

    var body: some View {
        ZStack {
            DayRailShape()
                .stroke(theme.hairline, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            if isCurrent {
                DayRailShape()
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            }
            Circle()
                .fill(isCompleted ? theme.positive : (isCurrent ? theme.accent : theme.canvas))
                .overlay(
                    Circle().strokeBorder(
                        isCompleted ? theme.positive : (isCurrent ? theme.accent : theme.textTertiary),
                        lineWidth: isCurrent ? 2 : 1
                    )
                )
                .frame(width: isCurrent ? 14 : 11, height: isCurrent ? 14 : 11)
            if isCurrent {
                Circle()
                    .strokeBorder(theme.accent.opacity(0.18), lineWidth: 5)
                    .frame(width: 22, height: 22)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct DayGapMark: View {
    @Environment(\.anchorTheme) private var theme

    var body: some View {
        ZStack {
            DayRailShape()
                .stroke(
                    theme.hairline,
                    style: StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: [3, 5])
                )
            Image(systemName: "plus")
                .font(.caption2.weight(.bold))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 18, height: 18)
                .background(theme.canvas, in: .circle)
                .overlay(Circle().strokeBorder(theme.hairline))
        }
        .accessibilityHidden(true)
    }
}

private struct DayRailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX + 0.5, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.midX - 0.5, y: rect.maxY),
            control1: CGPoint(x: rect.midX - 1.4, y: rect.height * 0.28),
            control2: CGPoint(x: rect.midX + 1.2, y: rect.height * 0.72)
        )
        return path
    }
}

struct PlanBlockEditor: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""
    @State private var plannedStart: Date
    @State private var minutes = 30
    @State private var kind: PlanBlockKind = .focus
    @State private var flexibility: ScheduleFlexibility = .flexible
    @State private var repeats = false
    @State private var weekdays: Set<ScheduleWeekday>
    @State private var usesSuggestedTime = false
    @State private var direction: LifeDirection?
    @State private var behaviorPattern: BehaviorPattern?
    @State private var saveError: String?
    private let block: PlanBlock?
    private let template: ScheduleTemplate?
    private let placingHabit: ScheduleTemplate?
    private let isBehaviorHabit: Bool
    private let initialDay: Date
    private let onSave: () -> Void

    init(
        initialDay: Date,
        suggestedStart: Date? = nil,
        block: PlanBlock? = nil,
        template: ScheduleTemplate? = nil,
        placingHabit: ScheduleTemplate? = nil,
        startsRecurring: Bool = false,
        startsBehaviorHabit: Bool = false,
        onSave: @escaping () -> Void
    ) {
        let calendar = Calendar.current
        let sourceTemplate = template ?? placingHabit
        let suggested = block?.plannedStart
            ?? template.flatMap {
                calendar.date(
                    byAdding: .minute,
                    value: $0.startMinutesFromMidnight,
                    to: calendar.startOfDay(for: initialDay)
                )
            }
            ?? suggestedStart
            ?? calendar.date(
                bySettingHour: calendar.component(.hour, from: Date()),
                minute: 0,
                second: 0,
                of: initialDay
            )
            ?? initialDay
        _title = State(initialValue: block?.title ?? sourceTemplate?.title ?? "")
        _details = State(initialValue: block?.details ?? sourceTemplate?.details ?? "")
        _plannedStart = State(initialValue: suggested)
        _minutes = State(initialValue: max(5, (block?.plannedSeconds ?? sourceTemplate?.plannedSeconds ?? 1_800) / 60))
        _kind = State(initialValue: startsBehaviorHabit ? .routine : (block?.kind ?? sourceTemplate?.kind ?? .focus))
        _flexibility = State(initialValue: block?.flexibility ?? sourceTemplate?.flexibility ?? .flexible)
        _repeats = State(initialValue: template != nil || startsRecurring || startsBehaviorHabit)
        _weekdays = State(initialValue: template?.weekdays ?? [ScheduleWeekday(day: suggested)])
        _usesSuggestedTime = State(initialValue: template?.habitUsesSuggestedTime ?? false)
        _direction = State(initialValue: block?.lifeDirection ?? sourceTemplate?.lifeDirection)
        _behaviorPattern = State(initialValue: block?.behaviorPattern ?? sourceTemplate?.behaviorPattern)
        self.block = block
        self.template = template
        self.placingHabit = placingHabit
        self.isBehaviorHabit = startsBehaviorHabit || template?.isBehaviorHabit == true
        self.initialDay = initialDay
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                if block?.templateID != nil {
                    Label("This changes today only. Your usual week stays intact.", systemImage: "calendar.badge.clock")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(theme.textSecondary)
                        .padding(Space.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.accent.opacity(0.08), in: .rect(cornerRadius: Radius.sm))
                }
                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(theme.negative)
                        .accessibilityIdentifier("anchor.plan.save-error")
                }

                Card(padding: Space.lg) {
                    VStack(alignment: .leading, spacing: Space.md) {
                        editorLabel("Intention", detail: "The thing that deserves a place")
                        TextField("What will you do?", text: $title, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 23, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1...3)
                        Divider().overlay(theme.hairline)
                        TextField("Context or what success looks like", text: $details, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(2...4)

                        if isBehaviorHabit {
                            Label("Behavior-change habit", systemImage: "leaf")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.accent)
                        } else {
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
                }

                Card(padding: Space.lg) {
                    VStack(alignment: .leading, spacing: Space.md) {
                        if isBehaviorHabit {
                            editorLabel("When", detail: "A suggestion, never a reservation")
                            Toggle("Suggest a time", isOn: $usesSuggestedTime)
                                .tint(theme.accent)
                            if usesSuggestedTime {
                                DatePicker("Around", selection: $plannedStart, displayedComponents: .hourAndMinute)
                            }
                            Text("The habit stays available all day. You can complete it directly or place it into Today when the day takes shape.")
                                .font(.caption)
                                .foregroundStyle(theme.textTertiary)
                        } else {
                            editorLabel("Time", detail: placingHabit == nil ? "A useful edge, not a promise carved in stone" : "Choose where this belongs today")
                            HStack(spacing: Space.lg) {
                                VStack(alignment: .leading, spacing: Space.xxs) {
                                    Text("STARTS").font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(theme.textTertiary)
                                    DatePicker("Starts", selection: $plannedStart)
                                        .labelsHidden()
                                }
                                VStack(alignment: .leading, spacing: Space.xxs) {
                                    Text("DURATION").font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(theme.textTertiary)
                                    Stepper("\(minutes) min", value: $minutes, in: 5...240, step: 5)
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                }
                                Spacer(minLength: 0)
                            }
                            Picker("Flexibility", selection: $flexibility) {
                                ForEach(ScheduleFlexibility.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }

                if placingHabit == nil {
                    Card(padding: Space.lg) {
                    VStack(alignment: .leading, spacing: Space.md) {
                    editorLabel(isBehaviorHabit ? "Days" : "Rhythm", detail: isBehaviorHabit ? "When this should be available" : "Make this a gentle default when it repeats")
                    if block == nil && template == nil && !isBehaviorHabit {
                        Toggle("Repeat weekly", isOn: $repeats)
                            .tint(theme.accent)
                    }
                    if repeats && block == nil {
                        FlowRow(spacing: Space.xs) {
                            ForEach(ScheduleWeekday.allCases, id: \.self) { day in
                                Button {
                                    if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                                } label: {
                                    Chip(day.shortLabel, isSelected: weekdays.contains(day))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(String(describing: day)) \(weekdays.contains(day) ? "selected" : "not selected")")
                            }
                        }
                        Picker("Make room for", selection: $direction) {
                            Text("No linked direction").tag(LifeDirection?.none)
                            ForEach(LifeDirection.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                        }
                        Picker("Helps replace", selection: $behaviorPattern) {
                            Text("No linked pattern").tag(BehaviorPattern?.none)
                            ForEach(BehaviorPattern.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                        }
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
            .navigationTitle(placingHabit != nil ? "Place habit" : (isBehaviorHabit ? (template == nil ? "New habit" : "Edit habit") : (template != nil ? "Edit usual week" : (block == nil ? (repeats ? "New usual-week item" : "New block") : "Edit block"))))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (repeats && weekdays.isEmpty))
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 540, idealWidth: 620, minHeight: 460, idealHeight: 680)
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
        let calendar = Calendar.current
        do {
            if let block {
                let scheduleChanged = block.plannedStart != plannedStart || block.plannedSeconds != minutes * 60
                let occurrenceChanged = scheduleChanged
                    || block.title != trimmed
                    || block.details != details
                    || block.kind != kind
                    || block.flexibility != flexibility
                    || block.lifeDirection != direction
                block.title = trimmed
                block.details = details
                block.plannedStart = plannedStart
                block.plannedSeconds = minutes * 60
                block.kind = kind
                block.flexibility = flexibility
                block.lifeDirection = direction
                block.behaviorPattern = behaviorPattern
                if block.templateID != nil && occurrenceChanged {
                    block.isTemplateOverride = true
                }
                block.updatedAt = Date()
                if scheduleChanged {
                    context.insert(DivergenceEvent(
                        blockID: block.id,
                        sessionID: block.sessionID,
                        kind: .deliberateReplan,
                        evidence: .scheduleChange,
                        note: "Block time or duration edited"
                    ))
                }
                try context.save()
            } else if let placingHabit {
                _ = try HabitDayService(context: context).place(
                    placingHabit,
                    on: initialDay,
                    at: plannedStart,
                    plannedSeconds: minutes * 60,
                    title: trimmed,
                    details: details
                )
            } else if let template {
                template.title = trimmed
                template.details = details
                template.startMinutesFromMidnight = calendar.component(.hour, from: plannedStart) * 60
                    + calendar.component(.minute, from: plannedStart)
                template.plannedSeconds = minutes * 60
                template.weekdays = weekdays
                template.kind = kind
                template.flexibility = flexibility
                template.lifeDirection = direction
                template.behaviorPattern = behaviorPattern
                if isBehaviorHabit { template.habitUsesSuggestedTime = usesSuggestedTime }
                template.updatedAt = Date()
                if isBehaviorHabit {
                    try context.save()
                } else {
                    try DayPlanService(context: context).reconcileFutureBlocks(for: template)
                }
            } else if repeats {
                let template = ScheduleTemplate(
                    title: trimmed,
                    details: details,
                    startMinutesFromMidnight: calendar.component(.hour, from: plannedStart) * 60 + calendar.component(.minute, from: plannedStart),
                    plannedSeconds: minutes * 60,
                    weekdays: weekdays,
                    kind: kind,
                    flexibility: flexibility,
                    behaviorPattern: behaviorPattern,
                    lifeDirection: direction,
                    isBehaviorHabit: isBehaviorHabit,
                    habitUsesSuggestedTime: isBehaviorHabit && usesSuggestedTime,
                    habitLevelStartedAt: isBehaviorHabit ? Date() : nil
                )
                context.insert(template)
                try context.save()
                if !isBehaviorHabit {
                    _ = try DayPlanService(context: context).materialize(day: plannedStart)
                }
            } else {
                context.insert(PlanBlock(
                    title: trimmed,
                    details: details,
                    plannedStart: plannedStart,
                    plannedSeconds: minutes * 60,
                    kind: kind,
                    flexibility: flexibility,
                    behaviorPattern: behaviorPattern,
                    lifeDirection: direction
                ))
                try context.save()
            }
            saveError = nil
            onSave()
            dismiss()
        } catch {
            context.rollback()
            saveError = "Anchor could not save this block. Please try again."
        }
    }
}

struct RoutineManager: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ScheduleTemplate.createdAt) private var templates: [ScheduleTemplate]
    @State private var editingTemplate: ScheduleTemplate?
    @State private var showsNewTemplate = false
    @State private var saveError: String?
    @State private var selectedWeekday = ScheduleWeekday(day: Date())
    let onChange: () -> Void

    private var activeTemplates: [ScheduleTemplate] {
        templates.filter { !$0.isArchived && !$0.isBehaviorHabit }
    }
    private var selectedTemplates: [ScheduleTemplate] {
        activeTemplates
            .filter { $0.weekdays.contains(selectedWeekday) }
            .sorted { lhs, rhs in
                if lhs.startMinutesFromMidnight == rhs.startMinutesFromMidnight {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.startMinutesFromMidnight < rhs.startMinutesFromMidnight
            }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Picker("Weekday", selection: $selectedWeekday) {
                            ForEach(ScheduleWeekday.allCases, id: \.self) { day in
                                Text(day.shortLabel)
                                    .tag(day)
                                    .accessibilityLabel(day.label)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("anchor.routine.weekday-picker")

                        Text("\(selectedTemplates.count) usual \(selectedTemplates.count == 1 ? "item" : "items") on \(selectedWeekday.label)")
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                } header: {
                    Text("Choose a day to shape")
                }

                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(theme.negative)
                        .accessibilityIdentifier("anchor.routine.save-error")
                }
                Section(selectedWeekday.label) {
                if selectedTemplates.isEmpty {
                    Label("Nothing usual yet — add the first item for this day.", systemImage: "calendar.badge.plus")
                        .foregroundStyle(theme.textSecondary)
                }
                ForEach(selectedTemplates) { template in
                    Button { editingTemplate = template } label: {
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text(template.title)
                                .font(.headline)
                                .foregroundStyle(theme.textPrimary)
                            Text("\(routineTime(template)) · \(template.weekdays.map(\.shortLabel).joined(separator: " "))")
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Stop repeating", role: .destructive) { archive(template) }
                    }
                    .contextMenu {
                        Button("Edit future days") { editingTemplate = template }
                        Button("Stop repeating", role: .destructive) { archive(template) }
                    }
                }
                }
            }
            .navigationTitle("Your usual week")
            .toolbar {
                #if !os(macOS)
                ToolbarItem(placement: .primaryAction) {
                    Button("Add to \(selectedWeekday.label)", systemImage: "plus") { showsNewTemplate = true }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                #endif
            }
            #if os(macOS)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: Space.sm) {
                    Button("Add to \(selectedWeekday.label)", systemImage: "plus") {
                        showsNewTemplate = true
                    }
                    .buttonStyle(PrimaryButtonStyle(expands: false))
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(QuietButtonStyle(expands: false))
                }
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.xs)
                .background(.bar)
            }
            #endif
            .sheet(isPresented: $showsNewTemplate) {
                PlanBlockEditor(initialDay: date(for: selectedWeekday), startsRecurring: true) {
                    saveError = nil
                    onChange()
                }
                .anchorTheme()
            }
            .sheet(item: $editingTemplate) { template in
                PlanBlockEditor(initialDay: Date(), template: template) {
                    saveError = nil
                    onChange()
                }
                .anchorTheme()
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 680, minHeight: 480, idealHeight: 620)
        #endif
    }

    private func archive(_ template: ScheduleTemplate) {
        template.archivedAt = Date()
        do {
            try DayPlanService(context: context).reconcileFutureBlocks(for: template)
            saveError = nil
            onChange()
        } catch {
            context.rollback()
            saveError = "Anchor could not stop this routine. Please try again."
        }
    }

    private func routineTime(_ template: ScheduleTemplate) -> String {
        let day = Calendar.current.startOfDay(for: Date())
        let time = Calendar.current.date(byAdding: .minute, value: template.startMinutesFromMidnight, to: day) ?? day
        return time.formatted(date: .omitted, time: .shortened)
    }

    private func date(for weekday: ScheduleWeekday) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayIndex = ScheduleWeekday(day: today, calendar: calendar).rawValue
        let offset = (weekday.rawValue - todayIndex + ScheduleWeekday.allCases.count)
            % ScheduleWeekday.allCases.count
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }
}

struct DivergenceEditor: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let title: String
    let onSave: (DivergenceKind, String) -> Bool
    @State private var selected: DivergenceKind?
    @State private var note = ""
    @State private var saveError: String?

    init(block: PlanBlock, onSave: @escaping (DivergenceKind, String) -> Bool) {
        self.title = block.title
        self.onSave = onSave
    }

    init(title: String, onSave: @escaping (DivergenceKind, String) -> Bool) {
        self.title = title
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    if let saveError {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(theme.negative)
                            .accessibilityIdentifier("anchor.divergence.save-error")
                    }
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("What changed \(title)?")
                            .font(.title.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        Text("Choose what best explains this block. A deliberate change is not a failure, and unsure stays unsure.")
                            .font(.body)
                            .foregroundStyle(theme.textSecondary)
                    }
                    ForEach(DivergenceKind.allCases, id: \.self) { kind in
                        Button {
                            selected = kind
                        } label: {
                            HStack(spacing: Space.sm) {
                                Image(systemName: kind.symbolName).frame(width: 28)
                                Text(kind.label).font(.body.weight(.medium))
                                Spacer()
                                Image(systemName: selected == kind ? "checkmark.circle.fill" : "circle")
                            }
                            .foregroundStyle(theme.textPrimary)
                            .padding(Space.md)
                            .background(selected == kind ? theme.surfaceRaised : theme.surface, in: .rect(cornerRadius: Radius.md))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(selected == kind ? causeTint(kind) : theme.hairline))
                        }
                        .buttonStyle(.plain)
                    }
                    TextField("A short note — optional", text: $note, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                }
                .padding(Space.lg)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(theme.canvas)
            .navigationTitle("Explain the gap")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let selected else { return }
                        if onSave(selected, note.trimmingCharacters(in: .whitespacesAndNewlines)) {
                            saveError = nil
                            dismiss()
                        } else {
                            saveError = "Anchor could not save this explanation. Please try again."
                        }
                    }
                    .disabled(selected == nil)
                }
            }
        }
    }

    private func causeTint(_ kind: DivergenceKind) -> Color {
        switch kind {
        case .internalPull: theme.color(for: .internal)
        case .externalInterruption: theme.color(for: .external)
        case .humanNeed, .estimateOverrun: theme.color(for: .mixed)
        case .deliberateReplan, .unknown: theme.textTertiary
        }
    }
}

struct DayReviewScreen: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.anchorWorkspaceMaxWidth) private var workspaceMaxWidth
    @Environment(\.modelContext) private var context
    @Query(sort: \PlanBlock.plannedStart) private var blocks: [PlanBlock]
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var sessions: [FocusSession]
    @Query(sort: \DivergenceEvent.occurredAt) private var divergences: [DivergenceEvent]
    @Query private var profiles: [BehaviorProfile]
    @State private var selectedDay = Date()
    @State private var explainingGap: DayReviewEngine.Gap?

    private var review: DayReviewEngine.Review {
        let interval = Calendar.current.dateInterval(of: .day, for: selectedDay)
            ?? DateInterval(start: selectedDay, duration: 86_400)
        let dayBlocks = blocks.filter { interval.contains($0.plannedStart) }.map { $0.snapshot() }
        let daySessions = sessions.filter { interval.contains($0.startedAt) }.map { $0.snapshot() }
        let dayDivergences = divergences.filter { interval.contains($0.occurredAt) }.map { $0.snapshot() }
        let profile = profiles.first?.snapshot() ?? BehaviorProfileRecord()
        return DayReviewEngine().review(
            day: selectedDay,
            blocks: dayBlocks,
            sessions: daySessions,
            divergences: dayDivergences,
            profile: profile
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                DoodleScene(
                    "HistoryDoodle",
                    eyebrow: "History",
                    title: "Read the real day",
                    message: "Compare what you drew with what happened. Keep the lesson, not the score.",
                    compact: true
                )

                HStack {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(Calendar.current.isDateInToday(selectedDay) ? "Reviewing today" : selectedDay.formatted(date: .complete, time: .omitted))
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        Text("The largest differences, not a score.")
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    DatePicker("Day", selection: $selectedDay, displayedComponents: .date).labelsHidden()
                }

                DayComparison(
                    planned: review.plannedSeconds,
                    observed: review.actualSeconds,
                    observedSummary: observedTimeSummary
                )

                if review.gaps.isEmpty {
                    EmptyStateView(
                        symbol: review.plannedSeconds == 0 ? "calendar.badge.plus" : "checkmark.circle",
                        title: review.plannedSeconds == 0 ? "Nothing was planned here yet" : "No meaningful gap needs explaining",
                        message: review.plannedSeconds == 0
                            ? "Build the day in Plan, then Anchor will reconcile it here."
                            : "Small differences are normal and stay out of the way."
                    )
                } else {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionHeader("What moved the day", subtitle: "Largest difference first")
                        ForEach(review.gaps) { gap in
                            ReviewGapRow(gap: gap) {
                                if blocks.contains(where: { $0.id == gap.blockID }) {
                                    explainingGap = gap
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionHeader("Try next", subtitle: "Evidence-based ideas you can accept or ignore")
                        ForEach(review.suggestions) { suggestion in
                            VStack(alignment: .leading, spacing: Space.xxs) {
                                Text(suggestion.title)
                                    .font(.headline)
                                    .foregroundStyle(theme.textPrimary)
                                Text(suggestion.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(theme.textSecondary)
                            }
                            .padding(.vertical, Space.sm)
                            Divider().overlay(theme.hairline)
                        }
                    }
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: workspaceMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $explainingGap) { gap in
            if let block = blocks.first(where: { $0.id == gap.blockID }) {
                DivergenceEditor(block: block) { kind, note in
                    let event = DivergenceEvent(
                        blockID: block.id,
                        sessionID: block.sessionID,
                        kind: kind,
                        note: note
                    )
                    context.insert(event)
                    do {
                        try context.save()
                        return true
                    } catch {
                        context.delete(event)
                        return false
                    }
                }
                .anchorTheme()
            } else {
                DivergenceEditor(title: gap.title) { kind, note in
                    let event = DivergenceEvent(
                        blockID: gap.blockID,
                        sessionID: gap.blockID,
                        kind: kind,
                        note: note
                    )
                    context.insert(event)
                    do {
                        try context.save()
                        return true
                    } catch {
                        context.delete(event)
                        return false
                    }
                }
                .anchorTheme()
            }
        }
    }

    private var observedTimeSummary: String {
        guard review.unobservedCompletedBlocks > 0 else {
            return Format.duration(review.actualSeconds)
        }
        return "\(Format.duration(review.actualSeconds)) timed + \(review.unobservedCompletedBlocks) untimed"
    }
}

private struct DayComparison: View {
    @Environment(\.anchorTheme) private var theme
    let planned: Double
    let observed: Double
    let observedSummary: String

    private var maximum: Double { max(1, max(planned, observed)) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .firstTextBaseline, spacing: Space.lg) {
                metric("Planned", Format.duration(planned), theme.textSecondary)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textTertiary)
                metric("Lived", observedSummary, theme.textPrimary)
            }

            VStack(spacing: Space.xs) {
                comparisonTrack(label: "Plan", fraction: planned / maximum, tint: theme.textTertiary)
                comparisonTrack(label: "Day", fraction: observed / maximum, tint: theme.textPrimary)
            }

            Text("Two traces of the same day. Difference is evidence, not failure.")
                .font(.caption)
                .foregroundStyle(theme.textTertiary)
        }
        .padding(Space.lg)
        .background(theme.surface, in: .rect(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(theme.hairline))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("anchor.history.day-comparison")
        .accessibilityValue(observedSummary)
    }

    private func metric(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(theme.textTertiary)
            Text(value)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func comparisonTrack(label: String, fraction: Double, tint: Color) -> some View {
        HStack(spacing: Space.sm) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(theme.textTertiary)
                .frame(width: 30, alignment: .leading)
            DrawnTrace(fraction: fraction, tint: tint)
                .frame(height: 14)
        }
    }
}

private struct ReviewGapRow: View {
    @Environment(\.anchorTheme) private var theme
    let gap: DayReviewEngine.Gap
    let onExplain: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            Capsule()
                .fill(causeTint)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(gap.title).font(.headline).foregroundStyle(theme.textPrimary)
                        Text("\(Format.duration(gap.plannedSeconds)) planned · \(gap.actualDurationKnown ? Format.duration(gap.actualSeconds) : "duration unknown") observed")
                            .font(.caption)
                            .foregroundStyle(theme.textTertiary)
                    }
                    Spacer()
                    Label(gap.cause.label, systemImage: gap.cause.symbolName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(causeTint)
                }
                Text(gap.evidenceDescription)
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                if gap.cause == .unknown {
                    Button("Explain this gap", action: onExplain)
                        .buttonStyle(QuietButtonStyle(expands: false))
                }
            }
        }
        .padding(.vertical, Space.sm)
        .overlay(alignment: .bottom) { Divider().overlay(theme.hairline) }
    }

    private var causeTint: Color {
        switch gap.cause {
        case .internalPull: theme.color(for: .internal)
        case .externalInterruption: theme.color(for: .external)
        case .humanNeed, .estimateOverrun: theme.color(for: .mixed)
        case .deliberateReplan, .unknown: theme.textSecondary
        }
    }
}

#endif
