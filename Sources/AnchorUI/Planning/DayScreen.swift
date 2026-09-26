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
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var sessions: [FocusSession]
    @Query(sort: \AnchorPreferences.updatedAt, order: .reverse) private var preferences: [AnchorPreferences]
    @Query private var projects: [Project]
    private let controller: FocusController
    private let onOpenFocus: () -> Void
    @State private var today = Date()
    @State private var lastCalendarDay = Date()
    @State private var showsCopyDay = false
    @State private var editorSeed: EditorSeed?
    @State private var showsCustomize = false
    @State private var editingBlock: PlanBlock?
    @State private var explainingBlock: PlanBlock?
    @State private var showsLogSheet = false
    @State private var loggingBlock: PlanBlock?
    @State private var loadError: String?

    init(controller: FocusController, onOpenFocus: @escaping () -> Void) {
        self.controller = controller
        self.onOpenFocus = onOpenFocus
    }

    private var dayInterval: DateInterval {
        Calendar.current.dateInterval(of: .day, for: today)
            ?? DateInterval(start: today, duration: 86_400)
    }

    private var blocks: [PlanBlock] {
        allBlocks.filter { $0.plannedStart >= dayInterval.start && $0.plannedStart < dayInterval.end }
    }

    private var timetableEntries: [DayTimetable.Entry] {
        blocks.sorted { $0.plannedStart < $1.plannedStart }.map { block in
            DayTimetable.Entry(
                block: block,
                projectName: projects.first { $0.id == block.projectID }?.name,
                linkedSession: block.sessionID.flatMap { id in sessions.first { $0.id == id } },
                hasDifferentActiveSession: controller.hasSession && controller.session?.id != block.sessionID,
                isCurrent: isCurrent(block)
            )
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                dayHeader

                dayControls

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
                            Button("Add the first entry") { editorSeed = EditorSeed(start: suggestedStart) }
                                .buttonStyle(PrimaryButtonStyle(expands: false))
                        }
                        #else
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: Space.lg) {
                                emptyDayCopy
                                Spacer(minLength: Space.lg)
                                Button("Add the first entry") { editorSeed = EditorSeed(start: suggestedStart) }
                                    .buttonStyle(PrimaryButtonStyle(expands: false))
                            }
                            VStack(alignment: .leading, spacing: Space.md) {
                                emptyDayCopy
                                Button("Add the first entry") { editorSeed = EditorSeed(start: suggestedStart) }
                                .buttonStyle(PrimaryButtonStyle())
                            }
                        }
                        #endif
                    }
                } else {
                    DayTimetable(
                        day: today,
                        entries: timetableEntries,
                        windowStartHour: timetablePrefs.startHour,
                        windowEndHour: timetablePrefs.endHour,
                        showsLivedTrace: timetablePrefs.showsLivedTrace,
                        dimsFinished: timetablePrefs.dimsFinished,
                        onStart: start,
                        onOpenFocus: onOpenFocus,
                        onComplete: complete,
                        onEdit: { editingBlock = $0 },
                        onExplain: { explainingBlock = $0 },
                        onLogActual: { loggingBlock = $0 },
                        onAddAt: { editorSeed = EditorSeed(start: $0) }
                    )
                }

            }
            .padding(Space.lg)
            .frame(maxWidth: workspaceMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            if !blocks.isEmpty {
                Button("Add an entry") { editorSeed = EditorSeed(start: suggestedStart) }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, Space.xs)
                    .background(.bar)
            }
        }
        .onAppear { scrollToNow(proxy) }
        }
        .background(theme.canvas)
        .sheet(isPresented: $showsCopyDay) {
            CopyDaySheet(sourceDay: today, entryCount: blocks.count) { destination in
                do {
                    _ = try DayPlanService(context: context).copyDay(from: today, to: destination)
                    today = destination
                    refresh()
                    return nil
                } catch {
                    context.rollback()
                    return "Anchor could not copy the day. Nothing was replaced."
                }
            }
            .anchorTheme()
        }
        .onChange(of: today) { refresh() }
        .sheet(item: $editorSeed) { seed in
            PlanBlockEditor(initialDay: today, suggestedStart: seed.start) { refresh() }
                .anchorTheme()
        }
        .sheet(item: $editingBlock) { block in
            PlanBlockEditor(initialDay: today, block: block) { refresh() }
                .anchorTheme()
        }
        .sheet(isPresented: $showsCustomize) {
            TimetableOptionsSheet(routineCount: activeTemplates.count, onChange: refresh)
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
        .sheet(isPresented: $showsLogSheet) {
            LogTimeSheet(day: today, onSave: refresh)
                .anchorTheme()
        }
        .sheet(item: $loggingBlock) { block in
            LogTimeSheet(day: today, block: block, onSave: refresh)
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
                if !Calendar.current.isDate(current, inSameDayAs: lastCalendarDay) {
                    if Calendar.current.isDate(today, inSameDayAs: lastCalendarDay) { today = current }
                    lastCalendarDay = current
                    refresh()
                }
            }
        }
        .onChange(of: controller.hasSession) { reconcileSessions() }
    }

    private var dayHeader: some View {
        DoodleScene(
            "TodayDoodle",
            eyebrow: today.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
            title: "Draw the day",
            message: "Everything this day asks of you, laid out on the clock.",
            compact: true
        )
    }

    private var dayControls: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.sm) {
                DatePicker("Day", selection: $today, displayedComponents: .date)
                Button("Today") { today = Date() }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Go to today")
            }
            HStack(spacing: Space.xs) {
                Button("Copy day", systemImage: "doc.on.doc") { showsCopyDay = true }
                    .buttonStyle(QuietButtonStyle(expands: false))
                    .disabled(blocks.isEmpty)
                    .accessibilityIdentifier("anchor.today.copy-day")
                Button("Log time", systemImage: "clock.arrow.circlepath") { showsLogSheet = true }
                    .buttonStyle(QuietButtonStyle(expands: false))
                    .accessibilityIdentifier("anchor.today.log-time")
                Button("Customize", systemImage: "slider.horizontal.3") { showsCustomize = true }
                    .buttonStyle(QuietButtonStyle(expands: false))
                    .accessibilityIdentifier("anchor.today.customize")
            }
        }
    }

    private var activeTemplates: [ScheduleTemplate] {
        templates.filter { !$0.isArchived && !$0.isBehaviorHabit }
    }

    private var timetablePrefs: (startHour: Int, endHour: Int, showsLivedTrace: Bool, dimsFinished: Bool) {
        let prefs = AnchorPreferencesPolicy.latest(in: preferences)
        return (
            prefs?.timetableStartHour ?? 7,
            prefs?.timetableEndHour ?? 22,
            prefs?.timetableShowsLivedTrace ?? true,
            prefs?.timetableDimsFinished ?? true
        )
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

    private func scrollToNow(_ proxy: ScrollViewProxy) {
        guard Calendar.current.isDateInToday(today), !blocks.isEmpty else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(DayTimetable.nowAnchorID, anchor: .top)
        }
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
        do {
            try PlanBlockFocusStarter.start(block, controller: controller, context: context)
            loadError = nil
        } catch {
            loadError = controller.lastError ?? "Anchor could not start this planned session. Please try again."
            return
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


private struct EditorSeed: Identifiable {
    let id = UUID()
    let start: Date
}

/// How Today draws its timetable. The choices live on `AnchorPreferences`, so
/// they travel with the rest of the owner's private Anchor data, and they only
/// shape the display — entries outside the chosen hours still expand the grid
/// rather than disappear.
struct TimetableOptionsSheet: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \AnchorPreferences.updatedAt, order: .reverse) private var preferences: [AnchorPreferences]
    @State private var showsRoutines = false
    @State private var saveError: String?

    let routineCount: Int
    let onChange: () -> Void

    private var prefs: AnchorPreferences? {
        AnchorPreferencesPolicy.latest(in: preferences)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Text("The timetable only ever answers one question: what does this day ask of you. These choices shape how it draws that answer.")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)

                    if let saveError {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(theme.negative)
                    }

                    Card(padding: Space.lg) {
                        VStack(alignment: .leading, spacing: Space.md) {
                            Stepper(value: startHourBinding, in: 0...23) {
                                HStack {
                                    Text("Day starts")
                                        .foregroundStyle(theme.textPrimary)
                                    Spacer()
                                    Text(hourLabel(prefs?.timetableStartHour ?? 7))
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(theme.textSecondary)
                                }
                            }
                            .accessibilityIdentifier("anchor.timetable.start-hour")
                            Stepper(value: endHourBinding, in: 1...24) {
                                HStack {
                                    Text("Day ends")
                                        .foregroundStyle(theme.textPrimary)
                                    Spacer()
                                    Text(hourLabel(prefs?.timetableEndHour ?? 22))
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(theme.textSecondary)
                                }
                            }
                            .accessibilityIdentifier("anchor.timetable.end-hour")
                            Text("Entries outside these hours still appear — the grid grows to include them.")
                                .font(.caption)
                                .foregroundStyle(theme.textTertiary)
                        }
                    }

                    Card(padding: Space.lg) {
                        VStack(alignment: .leading, spacing: Space.md) {
                            Toggle("Show the lived trace", isOn: livedTraceBinding)
                                .tint(theme.accent)
                                .accessibilityIdentifier("anchor.timetable.lived-trace")
                            Toggle("Dim finished entries", isOn: dimsFinishedBinding)
                                .tint(theme.accent)
                                .accessibilityIdentifier("anchor.timetable.dims-finished")
                        }
                    }

                    Button { showsRoutines = true } label: {
                        HStack {
                            Label("Your usual week · \(routineCount) item\(routineCount == 1 ? "" : "s")", systemImage: "calendar.badge.clock")
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
                    .accessibilityIdentifier("anchor.timetable.routines")
                }
                .padding(Space.lg)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(theme.canvas)
            .navigationTitle("Customize Today")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showsRoutines) {
            RoutineManager(onChange: onChange)
                .anchorTheme()
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 360, idealHeight: 460)
        #endif
    }

    private var startHourBinding: Binding<Int> {
        Binding(
            get: { prefs?.timetableStartHour ?? 7 },
            set: { newValue in
                update { prefs in
                    prefs.timetableStartHour = newValue
                    if prefs.timetableEndHour <= newValue {
                        prefs.timetableEndHour = min(24, newValue + 1)
                    }
                }
            }
        )
    }

    private var endHourBinding: Binding<Int> {
        Binding(
            get: { prefs?.timetableEndHour ?? 22 },
            set: { newValue in
                update { prefs in
                    prefs.timetableEndHour = newValue
                    if prefs.timetableStartHour >= newValue {
                        prefs.timetableStartHour = max(0, newValue - 1)
                    }
                }
            }
        )
    }

    private var livedTraceBinding: Binding<Bool> {
        Binding(
            get: { prefs?.timetableShowsLivedTrace ?? true },
            set: { newValue in update { $0.timetableShowsLivedTrace = newValue } }
        )
    }

    private var dimsFinishedBinding: Binding<Bool> {
        Binding(
            get: { prefs?.timetableDimsFinished ?? true },
            set: { newValue in update { $0.timetableDimsFinished = newValue } }
        )
    }

    private func hourLabel(_ hour: Int) -> String {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date())
        let date = calendar.date(byAdding: .hour, value: hour, to: base) ?? base
        return date.formatted(.dateTime.hour())
    }

    private func update(_ mutate: (AnchorPreferences) -> Void) {
        let record: AnchorPreferences
        if let existing = prefs {
            record = existing
        } else {
            record = AnchorPreferences()
            context.insert(record)
        }
        mutate(record)
        record.updatedAt = Date()
        do {
            try context.save()
            saveError = nil
        } catch {
            context.rollback()
            saveError = "Anchor could not save that choice. Try again."
        }
    }
}

struct PlanBlockEditor: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""
    @State private var selectedProjectID: UUID?
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
        _selectedProjectID = State(initialValue: block?.projectID ?? sourceTemplate?.projectID)
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
                } else if block?.externalEventKey != nil {
                    Label("Imported from Google Calendar. Editing makes it yours — sync won't overwrite it.", systemImage: "calendar.badge.clock")
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

                        ProjectPicker(selectedID: $selectedProjectID)

                        if isBehaviorHabit {
                            Label("Habit", systemImage: "leaf")
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
                    || block.projectID != selectedProjectID
                    || block.kind != kind
                    || block.flexibility != flexibility
                    || block.lifeDirection != direction
                block.projectID = selectedProjectID
                block.title = trimmed
                block.details = details
                block.plannedStart = plannedStart
                block.plannedSeconds = minutes * 60
                block.kind = kind
                block.flexibility = flexibility
                block.lifeDirection = direction
                block.behaviorPattern = behaviorPattern
                if (block.templateID != nil || block.externalEventKey != nil) && occurrenceChanged {
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
                let placed = try HabitDayService(context: context).place(
                    placingHabit,
                    on: initialDay,
                    at: plannedStart,
                    plannedSeconds: minutes * 60,
                    title: trimmed,
                    details: details
                )
                placed.projectID = selectedProjectID
                try context.save()
            } else if let template {
                template.projectID = selectedProjectID
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
                    projectID: selectedProjectID,
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
                    projectID: selectedProjectID,
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
