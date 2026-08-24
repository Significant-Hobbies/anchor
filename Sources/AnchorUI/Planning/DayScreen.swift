#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

struct PlanScreen: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.modelContext) private var context
    @Query(sort: \PlanBlock.plannedStart) private var allBlocks: [PlanBlock]
    @Query(sort: \ScheduleTemplate.createdAt) private var templates: [ScheduleTemplate]
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var sessions: [FocusSession]
    private let controller: FocusController
    private let onOpenFocus: () -> Void
    @State private var selectedDay = Date()
    @State private var showsEditor = false
    @State private var showsRoutines = false
    @State private var editingBlock: PlanBlock?
    @State private var explainingBlock: PlanBlock?
    @State private var loadError: String?

    init(controller: FocusController, onOpenFocus: @escaping () -> Void) {
        self.controller = controller
        self.onOpenFocus = onOpenFocus
    }

    private var dayInterval: DateInterval {
        Calendar.current.dateInterval(of: .day, for: selectedDay)
            ?? DateInterval(start: selectedDay, duration: 86_400)
    }

    private var blocks: [PlanBlock] {
        allBlocks.filter { dayInterval.contains($0.plannedStart) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                dayHeader

                completionCard

                if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(theme.caution)
                }

                if blocks.isEmpty {
                    EmptyStateView(
                        symbol: "calendar.badge.plus",
                        title: "Give the day one anchor",
                        message: "Add a focus block, commitment, routine, rest, or intentional enjoyment. Recurring blocks return on the days you choose."
                    )
                    Button("Add the first block") { showsEditor = true }
                        .buttonStyle(PrimaryButtonStyle())
                } else {
                    VStack(spacing: 0) {
                        ForEach(blocks) { block in
                            PlanBlockRow(
                                block: block,
                                linkedSession: block.sessionID.flatMap { id in sessions.first { $0.id == id } },
                                hasDifferentActiveSession: controller.hasSession && controller.session?.id != block.sessionID,
                                onStart: { start(block) },
                                onOpenFocus: onOpenFocus,
                                onComplete: { complete(block) },
                                onEdit: { editingBlock = block },
                                onExplain: { explainingBlock = block }
                            )
                            if block.id != blocks.last?.id {
                                Divider().overlay(theme.hairline).padding(.leading, 76)
                            }
                        }
                    }
                    .padding(.horizontal, Space.md)
                    .background(theme.surface, in: .rect(cornerRadius: Radius.lg))
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(theme.hairline))
                }

                if !templates.filter({ !$0.isArchived }).isEmpty {
                    Button { showsRoutines = true } label: {
                        HStack {
                            Label("\(templates.filter { !$0.isArchived }.count) recurring routine\(templates.filter { !$0.isArchived }.count == 1 ? "" : "s")", systemImage: "repeat")
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
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            if !blocks.isEmpty {
                Button("Add a block") { showsEditor = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, Space.xs)
                    .background(.bar)
            }
        }
        .sheet(isPresented: $showsEditor) {
            PlanBlockEditor(initialDay: selectedDay) { refresh() }
                .anchorTheme()
        }
        .sheet(isPresented: $showsRoutines) {
            RoutineManager(onChange: refresh)
                .anchorTheme()
        }
        .sheet(item: $editingBlock) { block in
            PlanBlockEditor(initialDay: selectedDay, block: block) { refresh() }
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
        .task(id: Calendar.current.startOfDay(for: selectedDay)) { refresh() }
        .onChange(of: controller.hasSession) { reconcileSessions() }
    }

    private var dayHeader: some View {
        HStack(alignment: .center, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(Calendar.current.isDateInToday(selectedDay) ? "Today" : selectedDay.formatted(date: .complete, time: .omitted))
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Text("A plan is a hypothesis, not a verdict.")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            DatePicker("Day", selection: $selectedDay, displayedComponents: .date)
                .labelsHidden()
        }
    }

    private var completionCard: some View {
        let completed = blocks.filter { $0.state == .completed }.count
        let percent = Int((Double(completed) / Double(max(1, blocks.count)) * 100).rounded())
        return Card(padding: Space.lg) {
            HStack(spacing: Space.md) {
                ZStack {
                    Circle()
                        .stroke(theme.hairline, lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: Double(percent) / 100)
                        .stroke(theme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(percent)%")
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(theme.textPrimary)
                }
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(blocks.isEmpty ? "No blocks scheduled yet" : "\(completed) of \(blocks.count) scheduled blocks complete")
                        .font(.headline)
                        .foregroundStyle(theme.textPrimary)
                    Text("A neutral snapshot of the schedule so far — not a score.")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("anchor.today.completion")
    }

    private func refresh() {
        do {
            _ = try DayPlanService(context: context).materialize(day: selectedDay)
            reconcileSessions()
            loadError = nil
        } catch {
            loadError = "The plan is still on this device, but Anchor could not refresh it: \(error.localizedDescription)"
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
    let block: PlanBlock
    let linkedSession: FocusSession?
    let hasDifferentActiveSession: Bool
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

            Image(systemName: block.kind.symbolName)
                .font(.body.weight(.medium))
                .foregroundStyle(block.state == .completed ? theme.positive : theme.accent)
                .frame(width: 28, height: 28)
                .background((block.state == .completed ? theme.positive : theme.accent).opacity(0.12), in: .circle)

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

            Menu {
                if linkedSession?.isActive == true {
                    Button("Open timer", action: onOpenFocus)
                } else if block.state == .planned {
                    if !hasDifferentActiveSession {
                        Button("Start now", action: onStart)
                    }
                    Button("Edit or move", action: onEdit)
                    Button("Finished without timing", action: onComplete)
                }
                Button("Explain a change", action: onExplain)
            } label: {
                Image(systemName: stateSymbol)
                    .font(.title3)
                    .foregroundStyle(stateTint)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel(actionLabel)
        }
        .padding(.vertical, Space.sm)
        .accessibilityElement(children: .contain)
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
    @State private var direction: LifeDirection?
    @State private var behaviorPattern: BehaviorPattern?
    @State private var saveError: String?
    private let block: PlanBlock?
    private let template: ScheduleTemplate?
    private let onSave: () -> Void

    init(
        initialDay: Date,
        block: PlanBlock? = nil,
        template: ScheduleTemplate? = nil,
        startsRecurring: Bool = false,
        onSave: @escaping () -> Void
    ) {
        let calendar = Calendar.current
        let suggested = block?.plannedStart
            ?? template.flatMap {
                calendar.date(
                    byAdding: .minute,
                    value: $0.startMinutesFromMidnight,
                    to: calendar.startOfDay(for: initialDay)
                )
            }
            ?? calendar.date(
                bySettingHour: calendar.component(.hour, from: Date()),
                minute: 0,
                second: 0,
                of: initialDay
            )
            ?? initialDay
        _title = State(initialValue: block?.title ?? template?.title ?? "")
        _details = State(initialValue: block?.details ?? template?.details ?? "")
        _plannedStart = State(initialValue: suggested)
        _minutes = State(initialValue: max(5, (block?.plannedSeconds ?? template?.plannedSeconds ?? 1_800) / 60))
        _kind = State(initialValue: block?.kind ?? template?.kind ?? .focus)
        _flexibility = State(initialValue: block?.flexibility ?? template?.flexibility ?? .flexible)
        _repeats = State(initialValue: template != nil || startsRecurring)
        _weekdays = State(initialValue: template?.weekdays ?? [ScheduleWeekday(day: suggested)])
        _direction = State(initialValue: block?.lifeDirection ?? template?.lifeDirection)
        _behaviorPattern = State(initialValue: block?.behaviorPattern ?? template?.behaviorPattern)
        self.block = block
        self.template = template
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(theme.negative)
                            .accessibilityIdentifier("anchor.plan.save-error")
                    }
                }
                Section("Intention") {
                    TextField("What will you do?", text: $title)
                    TextField("Context or what success looks like", text: $details, axis: .vertical)
                        .lineLimit(2...4)
                    Picker("Kind", selection: $kind) {
                        ForEach(PlanBlockKind.allCases, id: \.self) { Label($0.label, systemImage: $0.symbolName).tag($0) }
                    }
                }
                Section("Time") {
                    DatePicker("Starts", selection: $plannedStart)
                    Stepper("\(minutes) minutes", value: $minutes, in: 5...240, step: 5)
                    Picker("Flexibility", selection: $flexibility) {
                        ForEach(ScheduleFlexibility.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                Section("Rhythm") {
                    if block == nil && template == nil {
                        Toggle("Repeat weekly", isOn: $repeats)
                    }
                    if repeats && block == nil {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 64), spacing: Space.xxs)], spacing: Space.xxs) {
                            ForEach(ScheduleWeekday.allCases, id: \.self) { day in
                                Button {
                                    if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                                } label: {
                                    Text(day.shortLabel)
                                        .frame(minWidth: 44, minHeight: 44)
                                }
                                .buttonStyle(.bordered)
                                .tint(weekdays.contains(day) ? theme.accent : theme.textTertiary)
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
            .navigationTitle(template != nil ? "Edit routine" : (block == nil ? (repeats ? "New routine" : "New block") : "Edit block"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (repeats && weekdays.isEmpty))
                }
            }
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
                try DayPlanService(context: context).reconcileFutureBlocks(for: template)
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
                    lifeDirection: direction
                )
                context.insert(template)
                try context.save()
                _ = try DayPlanService(context: context).materialize(day: plannedStart)
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
    @State private var saveError: String?
    let onChange: () -> Void

    private var activeTemplates: [ScheduleTemplate] { templates.filter { !$0.isArchived } }

    var body: some View {
        NavigationStack {
            List {
                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(theme.negative)
                        .accessibilityIdentifier("anchor.routine.save-error")
                }
                ForEach(activeTemplates) { template in
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
            .overlay {
                if activeTemplates.isEmpty {
                    ContentUnavailableView("No recurring routines", systemImage: "repeat", description: Text("Create one from Add a block and turn on Repeat weekly."))
                }
            }
            .navigationTitle("Recurring routines")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editingTemplate) { template in
                PlanBlockEditor(initialDay: Date(), template: template) {
                    saveError = nil
                    onChange()
                }
                .anchorTheme()
            }
        }
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
                HStack {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(Calendar.current.isDateInToday(selectedDay) ? "Today, honestly" : selectedDay.formatted(date: .complete, time: .omitted))
                            .font(.largeTitle.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        Text("The largest differences, not a score.")
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    DatePicker("Day", selection: $selectedDay, displayedComponents: .date).labelsHidden()
                }

                HStack(spacing: Space.sm) {
                    StatTile(label: "Planned", value: Format.duration(review.plannedSeconds), symbol: "calendar")
                    StatTile(label: "Observed time", value: observedTimeSummary, symbol: "clock")
                }

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
                            Card {
                                VStack(alignment: .leading, spacing: Space.xs) {
                                    Text(suggestion.title)
                                        .font(.headline)
                                        .foregroundStyle(theme.textPrimary)
                                    Text(suggestion.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(theme.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: 680)
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

private struct ReviewGapRow: View {
    @Environment(\.anchorTheme) private var theme
    let gap: DayReviewEngine.Gap
    let onExplain: () -> Void

    var body: some View {
        Card {
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
