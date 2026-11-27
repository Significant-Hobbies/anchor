#if !os(watchOS)
import AnchorCore
import SaaSMakerUI
import SwiftData
import SwiftUI

struct PlanScreen: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.anchorWorkspaceMaxWidth) private var workspaceMaxWidth
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var context
    private var calendarVisibility = CalendarBlockVisibility()
    @State private var removal: CalendarEventRemoval?
    @Query(sort: \PlanBlock.plannedStart) private var allBlocks: [PlanBlock]
    @Query(sort: \ScheduleTemplate.createdAt) private var templates: [ScheduleTemplate]
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var sessions: [FocusSession]
    @Query(sort: \AnchorPreferences.updatedAt, order: .reverse) private var preferences: [AnchorPreferences]
    @Query private var projects: [Project]
    private let calendarCoordinator: CalendarSyncCoordinator?
    @State private var showsCalendars = false
    private let controller: FocusController
    private let onOpenFocus: () -> Void
    private let onChangeActivity: ((PlanBlock) -> Void)?
    @State private var checkIns: [UUID: PlannerCheckIn] = [:]
    @State private var checkingEntry: PlannerCheckIn?
    @State private var checkInLoadFailed = false
    private enum CalendarViewMode: String { case day, week, review }
    @SceneStorage("anchor.planner.view") private var viewMode = CalendarViewMode.day
    @State private var periodSyncError: String?
    @State private var isLoadingPeriod = false
    @State private var refreshRequest = UUID()
    @Binding private var today: Date
    @State private var lastCalendarDay = Date()
    @State private var showsDatePicker = false
    @AppStorage("anchor.calendar.hour-height") private var hourHeight = 56.0
    @AppStorage(TimetableStep.preferenceKey) private var gridStep = TimetableStep.five
    @State private var showsCopyDay = false
    @State private var editorSeed: EditorSeed?
    @State private var advancedDraft: AdvancedDraft?
    @State private var draftTitle = ""
    @State private var draftError: String?
    @State private var showsCustomize = false
    @State private var activityTags: [String: ActivityCategory] = [:]
    @State private var editingBlock: PlanBlock?
    @State private var editingCalendarEvent: PlanBlock?
    @State private var explainingBlock: PlanBlock?
    @State private var loggingBlock: PlanBlock?
    @State private var gridHasViewport = false
    @State private var gridIsAtStart = true
    @State private var recenterDay = 0
    @State private var parkedDraft: AdvancedDraft?
    @State private var showsDayCalendarEvents = false
    @State private var loadError: String?
    @State private var showsAllCalendarEvents = false
    @State private var calendarReferenceTime = Date()

    init(controller: FocusController, calendarCoordinator: CalendarSyncCoordinator?, day: Binding<Date>, onChangeActivity: ((PlanBlock) -> Void)? = nil, onOpenFocus: @escaping () -> Void) {
        self.onChangeActivity = onChangeActivity
        _today = day
        self.calendarCoordinator = calendarCoordinator
        self.controller = controller
        self.onOpenFocus = onOpenFocus
    }

    private var dayInterval: DateInterval {
        Calendar.current.dateInterval(of: .day, for: today)
            ?? DateInterval(start: today, duration: 86_400)
    }

    private var visibleInterval: DateInterval {
        if viewMode == .week, let week = Calendar.current.dateInterval(of: .weekOfYear, for: today) { return week }
        return dayInterval
    }

    private var calendarImportInterval: DateInterval {
        if viewMode == .day && Calendar.current.isDateInToday(today) {
            // Today also shows upcoming calendar events beyond the timetable.
            return CalendarSyncPolicy.syncWindow(now: today)
        }
        return visibleInterval
    }

    private var visibleDays: [Date] {
        (0..<(viewMode == .week ? 7 : 1)).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: visibleInterval.start)
        }
    }

    private struct PeriodRequest: Equatable {
        let interval: DateInterval
        let refresh: UUID
    }

    private var visibleBlocks: [PlanBlock] {
        calendarVisibility.filter(allBlocks)
    }

    private var copyableBlocks: [PlanBlock] {
        visibleBlocks.filter { !$0.isUnplannedTimeLog && $0.plannedStart >= dayInterval.start && $0.plannedStart < dayInterval.end }
    }

    private func upcomingCalendarEvents(at now: Date) -> [PlanBlock] {
        let window = CalendarSyncPolicy.syncWindow(now: now)
        return visibleBlocks.filter { block in
            block.externalEventKey != nil
                && block.plannedStart < window.end
                && block.plannedStart.addingTimeInterval(Double(block.plannedSeconds)) > now
                && (block.state == .planned || block.state == .inProgress)
        }
    }

    private var timetableEntries: [DayTimetable.Entry] {
        visibleBlocks.filter { $0.plannedStart < dayInterval.end && $0.plannedEnd > dayInterval.start }.map { block in
            DayTimetable.Entry(
                block: block,
                projectName: projects.first { $0.id == block.projectID }?.name,
                linkedSession: block.sessionID.flatMap { id in sessions.first { $0.id == id } },
                hasDifferentActiveSession: controller.hasSession && controller.session?.id != block.sessionID,
                isCurrent: isCurrent(block),
                outcome: checkIns[block.id]?.outcome
            )
        }
    }

    var body: some View {
        CalendarActuals(blocks: visibleBlocks, sessions: sessions, allBlocks: allBlocks, editTimeLog: { loggingBlock = $0 }) { data in
            let period = visibleInterval
            let plans = visibleBlocks.filter { $0.plannedStart < period.end && $0.plannedEnd > period.start }
            let titles = Set(plans.map(\.title) + data.calendarEntries(in: period).map(\.title))
            calendar(data)
                .environment(\.calendarActivityTags, activityTags)
                .task(id: titles) {
                    if activityTags.count > 512 { activityTags = activityTags.filter { titles.contains($0.key) } }
                    let tagger = TaggingService()
                    for title in titles.sorted() where activityTags[title] == nil {
                        guard !Task.isCancelled else { return }
                        let category = await tagger.classifyActivity(title)
                        guard !Task.isCancelled else { return }
                        activityTags[title] = category
                    }
                }
        }
    }

    private func calendar(_ data: CalendarActualData) -> some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                if controller.hasSession && viewMode != .day { focusItem(recorded: data.recordedIDs, jump: { _ in }) }
                if viewMode == .week {
                    HStack {
                        Text(visibleInterval.start.formatted(date: .abbreviated, time: .omitted) + " – " +
                             (visibleDays.last ?? today).formatted(date: .abbreviated, time: .omitted))
                            .font(.headline)
                        Spacer()
                        calendarsButton.buttonStyle(.borderless)
                    }
                }
                if viewMode != .day {
                    CalendarListButton(isExpanded: $showsDayCalendarEvents)
                        .accessibilityIdentifier("anchor.today.show-calendar-events")
                }
                if isLoadingPeriod {
                    Label("Updating calendar events…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote).foregroundStyle(theme.textSecondary)
                } else if let periodSyncError {
                    HStack {
                        Text(periodSyncError).font(.footnote).foregroundStyle(theme.caution)
                        Button("Retry") { refreshRequest = UUID() }
                    }
                }
                if checkInLoadFailed {
                    Label("Some saved check-ins could not be read on this device.", systemImage: "exclamationmark.triangle")
                }
                if !openBlockers.isEmpty {
                    blockersSection
                }

                if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(theme.caution)
                }

                if viewMode == .review {
                    DayLedgerView(day: today, blocks: visibleBlocks, sessions: sessions, allBlocks: allBlocks,
                                  hidesCalendarPlans: !showsDayCalendarEvents)
                } else if viewMode == .week {
                    WeekAgenda(days: visibleDays, actuals: data,
                               entries: visibleBlocks.filter { !$0.isUnplannedTimeLog && $0.plannedStart < visibleInterval.end && $0.plannedEnd > visibleInterval.start },
                               openDay: { today = $0; viewMode = .day },
                               add: { day in today = day; viewMode = .day; beginDraft(suggestedEntry(on: day)) },
                               edit: { editingBlock = $0 }, move: { move($0, to: $1, at: $2, data: data) })
                } else {
                    let calendarEvents = Calendar.current.isDateInToday(today) ? upcomingCalendarEvents(at: calendarReferenceTime)
                        : visibleBlocks.filter { $0.externalEventKey != nil && $0.plannedStart < dayInterval.end && $0.plannedEnd > dayInterval.start }
                    if showsDayCalendarEvents {
                        if calendarEvents.isEmpty {
                            Text("No calendar events in this period.").font(.callout).foregroundStyle(theme.textSecondary).id("anchor.calendar.list")
                        } else {
                            upcomingCalendarSection(calendarEvents).id("anchor.calendar.list")
                        }
                    }

                    DayTimetable(
                        day: today,
                        entries: timetableEntries.filter { !$0.block.isUnplannedTimeLog },
                        actuals: data,
                        hourHeight: hourHeight, step: gridStep,
                        windowStartHour: timetablePrefs.startHour,
                        windowEndHour: timetablePrefs.endHour,
                        showsLivedTrace: timetablePrefs.showsLivedTrace,
                        dimsFinished: timetablePrefs.dimsFinished,
                        onDropEntry: { move($0, to: $1, at: $2, data: data) },
                        onCheckIn: openCheckIn,
                        onStart: start,
                        onOpenFocus: onOpenFocus,
                        onComplete: complete,
                        onEdit: { editingBlock = $0 },
                        onRemove: { removal = CalendarEventRemoval($0) },
                        onExplain: { explainingBlock = $0 },
                        onLogActual: { loggingBlock = $0 },
                        draft: visibleDraft,
                        draftTitle: $draftTitle,
                        draftError: draftError,
                        onSaveDraft: { saveDraft(data) },
                        onCancelDraft: clearDraft,
                        onDraftOptions: { title in
                            if let seed = visibleDraft { advancedDraft = AdvancedDraft(seed: seed, title: title) }
                        },
                        onAddAt: { interval, dragged, column in
                            guard dragged || visibleDraft?.column != column || draftTitle.isEmpty else { return }
                            let finalHour = Calendar.current.component(.hour, from: interval.start) == 23
                            beginDraft(EditorSeed(start: interval.start, minutes: Int(interval.duration / 60),
                                                  revealInGrid: finalHour, column: column))
                        }
                    )

                }
            }
            .padding(Space.lg)
            .frame(maxWidth: viewMode == .day ? .infinity : workspaceMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .onScrollGeometryChange(for: GridViewport.self) { geometry in
            GridViewport(ready: geometry.containerSize.height > 0 && geometry.contentSize.height > geometry.containerSize.height,
                         atStart: geometry.visibleRect.minY < 2)
        } action: { _, viewport in
            gridHasViewport = viewport.ready
            gridIsAtStart = viewport.atStart
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.xs) {
                periodNavigation
                if viewMode == .day {
                    HStack(spacing: Space.sm) {
                        if controller.hasSession || Calendar.current.isDateInToday(today) {
                            focusItem(recorded: data.recordedIDs) { time in
                                proxy.scrollTo(DayTimetable.hourAnchor(for: time, on: today), anchor: .top)
                            }
                        }
                        Spacer(minLength: 0)
                        calendarOptions
                    }
                }
                if viewMode != .review {
                    HStack(spacing: Space.xxs) {
                        if viewMode == .day {
                            columnHeading("Scheduled", actionLabel: "Add scheduled entry") { beginDraft(suggestedEntry) }
                            columnHeading("Done", actionLabel: "Add done entry") { beginDraft(suggestedActual(data)) }
                        } else {
                            Text("Scheduled").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Done").frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .font(.headline)
                    .padding(.leading, viewMode == .day ? (timetablePrefs.showsLivedTrace ? 62 : 50) : Space.md)
                    .accessibilityIdentifier("anchor.calendar.columns")
                }
            }
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.xs)
                .frame(maxWidth: viewMode == .day ? .infinity : workspaceMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .background(theme.canvas)
                .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
        }
        // A toolbar draft can start offscreen. Its bottom edge is the editor's
        // bottom edge, including when the software keyboard resizes the timetable.
        .onChange(of: visibleDraft?.id) { _, id in
            if let id, visibleDraft?.revealInGrid == true {
                DispatchQueue.main.async { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .task(id: gridHasViewport && viewMode == .day ? dayInterval.start : nil) {
            guard gridHasViewport, viewMode == .day, visibleDraft == nil, openBlockers.isEmpty, loadError == nil, periodSyncError == nil, !checkInLoadFailed else { return }
            let time = initialGridTime(actuals: data)
            await Task.yield()
            guard !Task.isCancelled else { return }
            let hour = DayTimetable.hourAnchor(for: time, on: today)
            proxy.scrollTo(hour, anchor: .top)
            #if os(macOS)
            // AppKit can restore the initial scroll origin after SwiftUI's first layout.
            // Stop as soon as the grid has moved, or an editor has taken focus.
            for _ in 0..<4 where hour > dayInterval.start {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, gridIsAtStart, visibleDraft == nil else { break }
                proxy.scrollTo(hour, anchor: .top)
            }
            #endif
        }
        .onChange(of: recenterDay) {
            if viewMode == .day { proxy.scrollTo(DayTimetable.hourAnchor(for: initialGridTime(actuals: data), on: today), anchor: .top) }
        }
        .onChange(of: showsDayCalendarEvents) { _, showsList in
            if showsList && viewMode == .day { proxy.scrollTo("anchor.calendar.list", anchor: .top) }
        }
        .onChange(of: showsDayCalendarEvents) { showsAllCalendarEvents = false }
        .onChange(of: today) { _, _ in showsAllCalendarEvents = false }
        }
        .background(theme.canvas)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .modifier(CalendarEventRemovalDialog(request: $removal, onRemove: refresh))
        .onAppear { reloadCheckIns() }
        .onReceive(NotificationCenter.default.publisher(for: .plannerCheckInsChanged)) { _ in reloadCheckIns() }
        .sheet(isPresented: $showsCalendars, onDismiss: {
            refreshRequest = UUID()
        }) {
            if let calendarCoordinator {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Button(showsDayCalendarEvents ? "Hide event list" : "View event list") {
                                showsCalendars = false
                                showsDayCalendarEvents.toggle()
                            }.accessibilityIdentifier("anchor.today.show-calendar-events")
                            CalendarSettings(coordinator: calendarCoordinator, inSheet: true, visibleInterval: calendarImportInterval)
                        }.padding(Space.lg)
                    }
                        .background(theme.canvas)
                        .navigationTitle("Google Calendar")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showsCalendars = false }
                            }
                        }
                }
                #if os(macOS)
                .frame(minWidth: 490, minHeight: 340)
                #endif
                .anchorTheme()
            }
        }
        .sheet(item: $checkingEntry) { entry in
            PlannerCheckInSheet(entry: entry, previous: checkIns[entry.id]) { record in
                try context.savePlannerCheckIn(record)
                checkIns[record.id] = record
            }
            .anchorTheme()
        }
        .sheet(isPresented: $showsCopyDay) {
            CopyDaySheet(sourceDay: today, entryCount: copyableBlocks.count) { destination in
                do {
                    _ = try DayPlanService(context: context).copyDay(from: today, to: destination, including: Set(copyableBlocks.map(\.id)))
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
        .task(id: PeriodRequest(interval: calendarImportInterval, refresh: refreshRequest)) {
            refresh()
            periodSyncError = nil
            guard let calendarCoordinator, !calendarCoordinator.accounts.isEmpty else {
                isLoadingPeriod = false
                return
            }
            isLoadingPeriod = true
            let error = await calendarCoordinator.sync(context: context, window: calendarImportInterval)
            guard !Task.isCancelled else { return }
            periodSyncError = error
            isLoadingPeriod = false
        }
        .sheet(item: $advancedDraft) { draft in
            let seed = draft.seed
            if seed.column == .done {
                LogTimeSheet(day: today, suggestedStart: seed.start, suggestedTitle: draft.title) { clearDraft(); refresh() }
                    .anchorTheme()
            } else {
                PlanBlockEditor(initialDay: seed.start, suggestedStart: seed.start, suggestedMinutes: seed.minutes,
                                suggestedTitle: draft.title, dayIsFull: seed.dayIsFull) { clearDraft(); refresh() }
                    .anchorTheme()
            }
        }
        .sheet(item: $editingBlock) { block in
            blockEditor(block)
        }
        .sheet(item: $editingCalendarEvent) { event in
            blockEditor(event)
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
        .sheet(item: $loggingBlock) { block in
            LogTimeSheet(day: today, block: block, onSave: refresh)
                .anchorTheme()
        }
        .task {
            calendarReferenceTime = Date()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                let current = Date()
                calendarReferenceTime = current
                if !Calendar.current.isDate(current, inSameDayAs: lastCalendarDay) {
                    if Calendar.current.isDate(today, inSameDayAs: lastCalendarDay) { today = current }
                    lastCalendarDay = current
                }
            }
        }
        .onChange(of: controller.hasSession) { reconcileSessions() }
    }

    private func reloadCheckIns() {
        do {
            let result = try context.plannerCheckInStore?.load()
            checkIns = result?.records ?? [:]
            checkInLoadFailed = result?.hasUnreadableFiles ?? false
        } catch { checkInLoadFailed = true }
    }

    private func openCheckIn(_ block: PlanBlock) {
        checkingEntry = PlannerCheckIn(block: block)
    }

    private var openBlockers: [PlannerCheckIn] {
        let removedIDs = calendarVisibility.removedBlockIDs
        let blocked = checkIns.values.filter { $0.outcome == .blocked && !removedIDs.contains($0.id.uuidString) }
        guard !blocked.isEmpty else { return [] }
        let blocksByID = Dictionary(allBlocks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return blocked.compactMap { record in
            guard let block = blocksByID[record.id] else { return record }
            if block.externalEventKey != nil && !showsDayCalendarEvents { return nil }
            var current = record
            current.title = block.title
            current.plannedStart = block.plannedStart
            return current
        }.sorted {
            ($0.plannedStart, $0.title) < ($1.plannedStart, $1.title)
        }
    }

    private var blockersSection: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                Label("Open blockers", systemImage: "pause.circle").font(.headline)
                ForEach(openBlockers) { item in
                    Divider()
                    Button {
                        checkingEntry = item
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: Space.xxs) {
                                Text(item.title).font(.subheadline.weight(.semibold))
                                Text(item.reason).font(.subheadline)
                                Text(item.plannedStart.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(theme.textSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Edit this check-in")
                }
            }
        }
    }

    private func blockEditor(_ block: PlanBlock) -> some View {
        PlanBlockEditor(initialDay: block.plannedStart, block: block) { refresh() }
            .anchorTheme()
    }

    private func upcomingCalendarSection(_ events: [PlanBlock]) -> some View {
        let previewCount = 3
        return Card {
            VStack(alignment: .leading, spacing: Space.xs) {
                Label(Calendar.current.isDateInToday(today) ? "Upcoming calendar events" : "Calendar events", systemImage: "calendar")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(events.prefix(showsAllCalendarEvents ? events.count : previewCount)) { event in
                    Divider()
                    Button {
                        editingCalendarEvent = event
                    } label: {
                        HStack(spacing: Space.sm) {
                            VStack(alignment: .leading, spacing: Space.xxs) {
                                Text(event.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(theme.textPrimary)
                                Text(
                                    event.plannedStart,
                                    format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()
                                )
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(theme.textSecondary)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens event details")
                }

                if events.count > previewCount {
                    Button(showsAllCalendarEvents ? "Show fewer events" : "Show all \(events.count) events") {
                        showsAllCalendarEvents.toggle()
                    }
                    .buttonStyle(QuietButtonStyle(expands: false))
                }
            }
        }
        .accessibilityIdentifier("anchor.today.upcoming-calendar")
    }

    @ViewBuilder
    private func focusItem(recorded: Set<UUID>, jump: @escaping (Date) -> Void) -> some View {
        if let session = controller.session, controller.hasSession {
            focusRow(controller.isRunning ? "In focus" : "Paused", title: session.intent.isEmpty ? session.goal?.title ?? "Focus session" : session.intent,
                     action: "Open timer", perform: onOpenFocus)
        } else if let record = ScheduledFocusResolver().nextBlock(from: visibleBlocks.filter { $0.plannedEnd > calendarReferenceTime }.map { $0.snapshot() }, recorded: recorded, now: calendarReferenceTime),
                  let block = visibleBlocks.first(where: { $0.id == record.id }) {
            if block.plannedStart > calendarReferenceTime {
                Button { jump(block.plannedStart) } label: {
                    HStack(spacing: Space.xs) {
                        Text("Up next · " + block.plannedStart.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(theme.textSecondary)
                        Text(block.title).fontWeight(.semibold).lineLimit(1)
                        Image(systemName: "chevron.right").font(.caption2)
                    }.font(.subheadline)
                }.buttonStyle(.plain).accessibilityHint("Show this event on the timetable")

                Spacer(minLength: 0)
                Button("Focus", systemImage: "scope", action: onOpenFocus).buttonStyle(.borderless)
            } else {
                HStack {
                    focusRow("Now · " + block.plannedStart.formatted(date: .omitted, time: .shortened),
                         title: block.title, action: "Start focus") { start(block) }
                    Menu {
                        if let onChangeActivity {
                            Button("Do something else in this slot") { onChangeActivity(block) }
                        }
                        Button("Start an unplanned session", action: onOpenFocus)
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuIndicator(.hidden)
                    .accessibilityLabel("More focus actions")
                }
            }
        } else {
            Button("Start focus", systemImage: "scope", action: onOpenFocus)
                .buttonStyle(QuietButtonStyle(expands: false))
        }
    }

    private func focusRow(_ status: String, title: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(status).font(.caption).foregroundStyle(theme.textSecondary)
                Text(title).font(.headline)
            }
            Spacer()
            Button(action, action: perform).buttonStyle(QuietButtonStyle(expands: false))
        }
        .accessibilityElement(children: .contain)
    }

    private var periodNavigation: some View {
        SMAdaptiveActionBar(spacing: Space.sm) {
            dateNavigation
            modePicker
        }
    }

    private var modePicker: some View {
        SMSegmentedControl("Calendar view", selection: $viewMode, segments: [
            SMSegment(.day, title: "Day"), SMSegment(.week, title: "Week"), SMSegment(.review, title: "Review")
        ], size: .compact)
        .accessibilityIdentifier("anchor.planner.view-mode")
    }

    private var dateNavigation: some View {
        HStack(spacing: Space.xxs) {
            periodArrow(-1)
            Button { showsDatePicker.toggle() } label: {
                HStack(spacing: Space.xxs) {
                    Text(today, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, Space.xxs)
                .frame(minHeight: periodHitSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose date")
            .accessibilityValue(today.formatted(date: .complete, time: .omitted))
            .popover(isPresented: $showsDatePicker) {
                DatePicker("Day", selection: $today, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .frame(width: 320)
                    .padding(.vertical, Space.sm)
                    .presentationCompactAdaptation(.popover)
                    .onChange(of: today) { _, _ in showsDatePicker = false }
            }
            periodArrow(1)
            Button("Today") {
                if Calendar.current.isDateInToday(today) { recenterDay += 1 }
                today = Date()
            }
                .buttonStyle(QuietButtonStyle(expands: false))
                .accessibilityLabel("Go to today")
        }
    }

    private var periodHitSize: CGFloat {
        #if os(macOS)
        28
        #else
        44
        #endif
    }

    private func periodArrow(_ direction: Int) -> some View {
        Button {
            let component: Calendar.Component = viewMode == .week ? .weekOfYear : .day
            today = Calendar.current.date(byAdding: component, value: direction, to: today) ?? today
        } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.subheadline.weight(.medium))
                .frame(minWidth: periodHitSize, minHeight: periodHitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel((direction < 0 ? "Previous " : "Next ") + (viewMode == .week ? "week" : "day"))
    }

    private func columnHeading(_ title: String, actionLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.xxs) {
                Text(title)
                Image(systemName: "plus.circle").font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(actionLabel)
    }

    private var calendarOptions: some View {
        Menu {
            calendarsButton
            customizeButton
            Divider()
            copyDayButton
        } label: {
            Image(systemName: "ellipsis.circle").frame(minWidth: periodHitSize, minHeight: periodHitSize)
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Calendar actions")
        .accessibilityIdentifier("anchor.today.tools")
    }

    @ViewBuilder private var calendarsButton: some View {
        if calendarCoordinator != nil {
            Button("Calendars…", systemImage: "calendar") { showsCalendars = true }
                .accessibilityIdentifier("anchor.today.calendars")
        }
    }

    private var copyDayButton: some View {
        Button("Copy day…", systemImage: "doc.on.doc") { showsCopyDay = true }
            .disabled(copyableBlocks.isEmpty)
            .accessibilityIdentifier("anchor.today.copy-day")
    }

    private var customizeButton: some View {
        Button("Timetable settings…", systemImage: "slider.horizontal.3") {
            showsCustomize = true
        }
        .accessibilityIdentifier("anchor.today.customize")
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

    private func initialGridTime(actuals: CalendarActualData) -> Date {
        let now = Date()
        if Calendar.current.isDateInToday(today) { return now.addingTimeInterval(-3600) }
        let firstPlan = timetableEntries.map(\.block).filter { $0.plannedSeconds < 86_400 }.map(\.plannedStart).min()
        let firstActual = actuals.calendarEntries(in: dayInterval).filter { $0.end.timeIntervalSince($0.start) < 86_400 }.map(\.start).min()
        return [firstPlan, firstActual].compactMap { $0 }.min()
            ?? Calendar.current.date(bySettingHour: timetablePrefs.startHour, minute: 0, second: 0, of: today) ?? today
    }

    private func suggestedActual(_ data: CalendarActualData) -> EditorSeed {
        let step = Double(gridStep.rawValue * 60)
        let end = Calendar.current.isDateInToday(today) ? Date() : initialGridTime(actuals: data).addingTimeInterval(step)
        let offset = floor(end.timeIntervalSince(dayInterval.start) / step) * step
        let start = max(0, min(offset - step, dayInterval.duration - step))
        return EditorSeed(start: dayInterval.start.addingTimeInterval(start), minutes: gridStep.rawValue, column: .done)
    }

    private var visibleDraft: EditorSeed? {
        guard viewMode == .day, let editorSeed, Calendar.current.isDate(editorSeed.start, inSameDayAs: today) else { return nil }
        return editorSeed
    }

    private func beginDraft(_ seed: EditorSeed) {
        let pending = parkedDraft
        if let previous = editorSeed, previous.column != seed.column {
            parkedDraft = draftTitle.isEmpty ? nil : AdvancedDraft(seed: previous, title: draftTitle)
            draftTitle = ""
        } else if let previous = editorSeed, !Calendar.current.isDate(previous.start, inSameDayAs: seed.start) {
            draftTitle = ""
        }
        if let pending, pending.seed.column == seed.column, Calendar.current.isDate(pending.seed.start, inSameDayAs: seed.start) {
            if editorSeed?.column == seed.column || editorSeed == nil { parkedDraft = nil }
            editorSeed = pending.seed
            draftTitle = pending.title
            draftError = nil
            return
        }
        draftError = nil
        editorSeed = seed
    }

    private func clearDraft() {
        editorSeed = nil
        draftTitle = ""
        draftError = nil
    }

    private func move(_ drag: CalendarDrag, to column: TimetableColumn, at time: Date, data: CalendarActualData) -> Bool {
        let plan = visibleBlocks.first { $0.id == drag.id && !$0.isUnplannedTimeLog }
        let actual = data.entries.first { $0.id == drag.id } ?? data.ongoing.first { $0.id == drag.id }
        let original: DayLedgerEntry
        switch drag.source {
        case .plan:
            guard let plan else { return false }
            original = DayLedgerEntry(id: plan.id, title: plan.title, start: plan.plannedStart, end: plan.plannedEnd, notes: plan.details, sourcePlanID: plan.id)
        case .actual:
            guard let actual else { return false }
            original = actual
        }
        if drag.resizing && (drag.source == .plan) != (column == .scheduled) { return false }
        var updated = original
        if drag.resizing {
            guard time > original.start else { return false }
            updated.end = time
        } else {
            updated.start = time
            updated.end = time.addingTimeInterval(original.end.timeIntervalSince(original.start))
        }
        if column == .done {
            // Reposition an existing copy without overwriting its edited title or notes.
            if let actual, drag.source == .plan {
                updated = actual
                updated.start = time
                updated.end = time.addingTimeInterval(actual.end.timeIntervalSince(actual.start))
            }
            return data.move(updated)
        }
        do {
            if drag.source == .actual {
                context.insert(PlanBlock(title: original.title, details: original.notes, plannedStart: updated.start,
                                         plannedSeconds: Int(updated.end.timeIntervalSince(updated.start))))
            } else if let plan {
                plan.plannedStart = updated.start
                plan.plannedSeconds = Int(updated.end.timeIntervalSince(updated.start))
                if plan.externalEventKey != nil || plan.templateID != nil { plan.isTemplateOverride = true }
                plan.updatedAt = Date()
                context.insert(DivergenceEvent(blockID: plan.id, sessionID: plan.sessionID, kind: .deliberateReplan,
                                               evidence: .scheduleChange, note: "Moved on the timetable"))
            }
            try context.save()
            return true
        } catch {
            context.rollback()
            loadError = "Couldn’t move this entry. Try again."
            return false
        }
    }

    private func saveDraft(_ actuals: CalendarActualData) {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seed = visibleDraft, !title.isEmpty else { return }
        if seed.column == .done {
            let entry = DayLedgerEntry(id: seed.id, title: title, start: seed.start,
                                       end: seed.start.addingTimeInterval(Double(seed.minutes * 60)))
            if actuals.available && actuals.record(entry) { clearDraft() }
            // The ledger presenter reports save errors and keeps this draft open.
            return
        }
        let block = PlanBlock(title: title, plannedStart: seed.start, plannedSeconds: seed.minutes * 60)
        context.insert(block)
        do {
            try context.save()
            clearDraft()
        } catch {
            context.delete(block)
            draftError = "Couldn’t save. Try again."
        }
    }

    private var suggestedEntry: EditorSeed { suggestedEntry(on: today) }

    private func suggestedEntry(on day: Date) -> EditorSeed {
        let calendar = Calendar.current
        let now = Date()
        let dayInterval = calendar.dateInterval(of: .day, for: day) ?? self.dayInterval
        let base = calendar.isDate(now, inSameDayAs: day) ? now : calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        let minute = calendar.component(.minute, from: base)
        let wholeMinute = calendar.dateInterval(of: .minute, for: base)?.start ?? base
        let rounded = calendar.date(byAdding: .minute, value: (gridStep.rawValue - minute % gridStep.rawValue) % gridStep.rawValue, to: wholeMinute) ?? wholeMinute
        let opening = PlannerGap.opening(from: rounded, until: dayInterval.end,
            occupied: visibleBlocks.filter { $0.plannedStart < dayInterval.end && $0.plannedEnd > base }
                .map { DateInterval(start: $0.plannedStart, end: $0.plannedEnd) })
        if let opening { return EditorSeed(start: opening.start, minutes: Int(opening.duration / 60)) }
        return EditorSeed(start: min(rounded, dayInterval.end.addingTimeInterval(-60)), dayIsFull: true)
    }

    private func isCurrent(_ block: PlanBlock) -> Bool {
        let now = Date()
        return block.state == .inProgress || (now >= block.plannedStart && now < block.plannedStart.addingTimeInterval(Double(block.plannedSeconds)))
    }

    private func refresh() {
        do {
            let planner = DayPlanService(context: context)
            let startOfToday = Calendar.current.startOfDay(for: Date())
            for day in visibleDays where day >= startOfToday {
                _ = try planner.materialize(day: day)
            }
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
        guard block.plannedEnd > Date() else {
            calendarReferenceTime = Date()
            return
        }
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


private struct GridViewport: Equatable {
    let ready: Bool
    let atStart: Bool
}

private struct AdvancedDraft: Identifiable {
    let seed: EditorSeed
    let title: String
    var id: UUID { seed.id }
}

enum TimetableColumn { case scheduled, done }

struct EditorSeed: Identifiable {
    let id = UUID()
    let start: Date
    var minutes = 30
    var dayIsFull = false
    var revealInGrid = true
    var column = TimetableColumn.scheduled
}

/// Day bounds use AnchorPreferences. Grid increments and alerts are device preferences.
struct TimetableOptionsSheet: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \AnchorPreferences.updatedAt, order: .reverse) private var preferences: [AnchorPreferences]
    @AppStorage("anchor.calendar.hour-height") private var hourHeight = 56.0
    @AppStorage(TimetableStep.preferenceKey) private var gridStep = TimetableStep.five
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

                    if let saveError {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(theme.negative)
                    }

                    Card(padding: Space.lg) {
                        VStack(alignment: .leading, spacing: Space.md) {
                            Picker("Hour spacing", selection: $hourHeight) {
                                Text("Compact").tag(44.0)
                                Text("Standard").tag(56.0)
                                Text("Spacious").tag(84.0)
                            }
                            Picker("Grid step", selection: $gridStep) {
                                ForEach(TimetableStep.allCases, id: \.self) { step in
                                    Text("\(step.rawValue) minutes").tag(step)
                                }
                            }
                            .accessibilityIdentifier("anchor.timetable.grid-step")
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
                            Text("Hours outside this window are shaded. You can add entries anywhere on the 24-hour timetable.")
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

                    PlannerStartReminderSettings()

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
            .navigationTitle("customize today")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("done") { dismiss() }
                        .accessibilityIdentifier("anchor.timetable.options-done")
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
    @State private var removal: CalendarEventRemoval?
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
    private let maximumMinutes: Int
    private let fullDaySuggestedStart: Date?
    private let isBehaviorHabit: Bool
    private let initialDay: Date
    private let onSave: () -> Void

    init(
        initialDay: Date,
        suggestedStart: Date? = nil,
        suggestedMinutes: Int = 30,
        suggestedTitle: String = "",
        dayIsFull: Bool = false,
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
        _title = State(initialValue: block?.title ?? sourceTemplate?.title ?? suggestedTitle)
        _details = State(initialValue: block?.details ?? sourceTemplate?.details ?? "")
        _selectedProjectID = State(initialValue: block?.projectID ?? sourceTemplate?.projectID)
        _plannedStart = State(initialValue: suggested)
        let initialMinutes = max(5, (block?.plannedSeconds ?? sourceTemplate?.plannedSeconds ?? suggestedMinutes * 60) / 60)
        _minutes = State(initialValue: initialMinutes)
        maximumMinutes = max(240, initialMinutes)
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
        self.fullDaySuggestedStart = dayIsFull ? suggestedStart : nil
        self.initialDay = initialDay
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                if plannedStart == fullDaySuggestedStart {
                    Label("No suggested opening from this time. Choose a different start or day.", systemImage: "calendar.badge.clock")
                        .font(.callout).foregroundStyle(theme.caution)
                }
                if block?.templateID != nil {
                    Label("this changes today only. your usual week stays intact.", systemImage: "calendar.badge.clock")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(theme.textSecondary)
                        .padding(Space.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.accent.opacity(0.08), in: .rect(cornerRadius: Radius.sm))
                } else if let block, block.externalEventKey != nil {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Label("imported from google calendar. editing makes it yours — sync won't overwrite it.", systemImage: "calendar.badge.clock")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(theme.textSecondary)
                        .padding(Space.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.accent.opacity(0.08), in: .rect(cornerRadius: Radius.sm))
                    Button("Remove from Anchor…", systemImage: "trash", role: .destructive) {
                        removal = CalendarEventRemoval(block)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("anchor.plan.remove-calendar-event")
                    }
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
                            .accessibilityIdentifier("anchor.plan.editor.title")
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
                            Label("habit", systemImage: "leaf")
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
                            editorLabel("Time", detail: placingHabit == nil ? "A useful edge, not a promise carved in stone" : "Choose a time for this day")
                            HStack(spacing: Space.lg) {
                                VStack(alignment: .leading, spacing: Space.xxs) {
                                    Text("STARTS").font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(theme.textTertiary)
                                    DatePicker("Starts", selection: $plannedStart)
                                        .labelsHidden()
                                }
                                VStack(alignment: .leading, spacing: Space.xxs) {
                                    Text("DURATION").font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(theme.textTertiary)
                                    Stepper("\(minutes) min", value: $minutes, in: 5...maximumMinutes, step: 5)
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
                ToolbarItem(placement: .cancellationAction) { Button("cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save", action: save)
                        .accessibilityIdentifier("anchor.plan.editor.save")
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (repeats && weekdays.isEmpty))
                }
            }
        }
        .modifier(CalendarEventRemovalDialog(request: $removal) {
            dismiss()
            onSave()
        })
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
                let durationChanged = minutes != max(5, block.plannedSeconds / 60)
                let scheduleChanged = block.plannedStart != plannedStart || durationChanged
                let providerFieldsChanged = scheduleChanged || block.title != trimmed
                let occurrenceChanged = providerFieldsChanged
                    || block.details != details
                    || block.projectID != selectedProjectID
                    || block.kind != kind
                    || block.flexibility != flexibility
                    || block.lifeDirection != direction
                block.projectID = selectedProjectID
                block.title = trimmed
                block.details = details
                block.plannedStart = plannedStart
                if durationChanged { block.plannedSeconds = minutes * 60 }
                block.kind = kind
                block.flexibility = flexibility
                block.lifeDirection = direction
                block.behaviorPattern = behaviorPattern
                if (block.templateID != nil && occurrenceChanged) || (block.externalEventKey != nil && providerFieldsChanged) {
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
                    Label("nothing usual yet — add the first item for this day.", systemImage: "calendar.badge.plus")
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
                        Button("stop repeating", role: .destructive) { archive(template) }
                    }
                    .contextMenu {
                        Button("edit future days") { editingTemplate = template }
                        Button("stop repeating", role: .destructive) { archive(template) }
                    }
                }
                }
            }
            .navigationTitle("your usual week")
            .toolbar {
                #if !os(macOS)
                ToolbarItem(placement: .primaryAction) {
                    Button("add to \(selectedWeekday.label)", systemImage: "plus") { showsNewTemplate = true }
                }
                ToolbarItem(placement: .confirmationAction) { Button("done") { dismiss() } }
                #endif
            }
            #if os(macOS)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: Space.sm) {
                    Button("add to \(selectedWeekday.label)", systemImage: "plus") {
                        showsNewTemplate = true
                    }
                    .buttonStyle(PrimaryButtonStyle(expands: false))
                    Spacer()
                    Button("done") { dismiss() }
                        .buttonStyle(QuietButtonStyle(expands: false))
                        .accessibilityIdentifier("anchor.routines.done")
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
            .navigationTitle("explain the gap")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save") {
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

private struct CalendarListButton: View {
    @Binding var isExpanded: Bool

    var body: some View {
        Button(isExpanded ? "Hide calendar list" : "Show calendar list", systemImage: "calendar") {
            isExpanded.toggle()
        }
        .buttonStyle(QuietButtonStyle(expands: false))
    }
}

struct DayReviewScreen: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.anchorWorkspaceMaxWidth) private var workspaceMaxWidth
    @Environment(\.modelContext) private var context
    private var calendarVisibility = CalendarBlockVisibility()
    @Query(sort: \PlanBlock.plannedStart) private var blocks: [PlanBlock]
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var sessions: [FocusSession]
    @Query(sort: \DivergenceEvent.occurredAt) private var divergences: [DivergenceEvent]
    @Query private var profiles: [BehaviorProfile]
    @State private var showsCalendarList = false
    @Binding var selectedDay: Date
    @State private var explainingGap: DayReviewEngine.Gap?

    init(selectedDay: Binding<Date>) {
        _selectedDay = selectedDay
    }

    private var review: DayReviewEngine.Review {
        let interval = Calendar.current.dateInterval(of: .day, for: selectedDay)
            ?? DateInterval(start: selectedDay, duration: 86_400)
        let dayBlocks = calendarVisibility.filter(blocks).filter { $0.contributesToDayReview(in: interval) }.map { $0.snapshot() }
        let daySessions = sessions.filter { $0.startedAt >= interval.start && $0.startedAt < interval.end }.map { $0.snapshot() }
        let dayDivergences = divergences.filter { $0.occurredAt >= interval.start && $0.occurredAt < interval.end }.map { $0.snapshot() }
        let profile = profiles.first?.snapshot() ?? BehaviorProfileRecord()
        var result = DayReviewEngine().review(
            day: selectedDay,
            blocks: dayBlocks,
            sessions: daySessions,
            divergences: dayDivergences,
            profile: profile
        )
        if !showsCalendarList {
            let hidden = Set(dayBlocks.filter { $0.externalEventKey != nil }.map(\.id))
            result.gaps.removeAll { hidden.contains($0.blockID) }
            result.suggestions.removeAll { hidden.contains($0.blockID) }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                DoodleScene(
                    "HistoryDoodle",
                    eyebrow: "analysis",
                    title: "Day analysis",
                    message: "Compare your plan with recorded time, interruptions, and changes.",
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

                CalendarListButton(isExpanded: $showsCalendarList)
                let review = self.review
                DayLedgerView(day: selectedDay, blocks: calendarVisibility.filter(blocks), sessions: sessions, allBlocks: blocks,
                              hidesCalendarPlans: !showsCalendarList)

                Text("Timer and activity analysis").font(.headline)
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
                            ? "Build the day in Today, then Anchor will reconcile it here."
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
                    Button("explain this gap", action: onExplain)
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
