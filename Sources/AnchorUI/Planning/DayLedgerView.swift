#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

extension Notification.Name {
    static let actualEntriesChanged = Notification.Name("anchor.actual-entries.changed")
}

struct DayLedgerView: View {
    let day: Date
    let blocks: [PlanBlock]
    let sessions: [FocusSession]
    let allBlocks: [PlanBlock]
    var hidesCalendarPlans = false
    var body: some View {
        CalendarActuals(blocks: blocks, sessions: sessions, allBlocks: allBlocks) { data in
            LedgerRows(day: day, blocks: blocks, data: data, hidesCalendarPlans: hidesCalendarPlans)
        }
    }
}

private struct LedgerRows: View {
    let day: Date
    let blocks: [PlanBlock]
    let data: CalendarActualData
    let hidesCalendarPlans: Bool
    @Environment(\.anchorTheme) private var theme
    @State private var showsWeek = false
    private var plans: [DayLedgerEntry] {
        blocks.filter { !$0.isUnplannedTimeLog }.map { DayLedgerEntry(id: $0.id, title: $0.title, start: $0.plannedStart, end: $0.plannedEnd, notes: $0.details, sourcePlanID: $0.id) }
    }

    var body: some View {
        let period = Calendar.current.dateInterval(of: .day, for: day)!
        // Date pickers and slot labels expose minutes. Compare those same
        // visible boundaries even when a timer or imported plan stores seconds.
        let allPlans = plans.map(minutePrecision), allActuals = data.entries.map(minutePrecision)
        let comparison = DayLedgerComparison(period: period, plans: allPlans, actuals: allActuals)
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Text("Plan and actual").font(.title2.weight(.semibold))
                Spacer()
                Button { newEntry(period) } label: { Label("Log actual", systemImage: "plus") }
                    .buttonStyle(QuietButtonStyle(expands: false))
                    .disabled(!data.available)
                    .accessibilityIdentifier("anchor.actual.add")
            }
            if data.available {
                let hiddenPlanIDs = hidesCalendarPlans ? Set(blocks.filter { $0.externalEventKey != nil }.map(\.id)) : []
                let visiblePlans = comparison.plans.filter { !hiddenPlanIDs.contains($0.id) }
                let localPlanIDs = Set(visiblePlans.map(\.id))
                let actualByID = Dictionary(allActuals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                let planByID = Dictionary(allPlans.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                pair {
                    Text("Plan").font(.headline)
                } right: {
                    Text("What happened").font(.headline)
                }
                Divider()
                if visiblePlans.isEmpty && comparison.actuals.isEmpty {
                    pair { Text(comparison.plans.isEmpty ? "Nothing planned" : "Calendar events hidden") } right: { Text("Log an actual entry.") }
                        .font(.callout).foregroundStyle(theme.textSecondary)
                }
                ForEach(visiblePlans) { plan in
                    let actual = actualByID[plan.id]
                    pair {
                        Button {
                            if let actual { data.edit(actual) }
                            else { _ = data.record(plan) }
                        } label: {
                            HStack(alignment: .top, spacing: Space.xs) {
                                Image(systemName: actual == nil ? "square" : "checkmark.square.fill")
                                    .foregroundStyle(actual == nil ? theme.textSecondary : theme.positive)
                                row(plan)
                            }.contentShape(Rectangle())
                        }
                        .accessibilityLabel((actual == nil ? "Record " : "Edit actual for ") + plan.title)
                        .accessibilityIdentifier("anchor.actual.copy." + plan.id.uuidString)
                    } right: {
                        if let actual { actualButton(actual, plan: plan, day: period) }
                        else {
                            Button("Record differently") { data.edit(plan) }
                                .font(.caption).foregroundStyle(theme.textSecondary)
                        }
                    }
                    Divider()
                }
                ForEach(comparison.actuals.filter { !localPlanIDs.contains($0.id) }) { actual in
                    let source = planByID[actual.id]
                    pair {
                        Text(hiddenPlanIDs.contains(actual.id) ? "Calendar plan" :
                             source.map { "Planned " + $0.start.formatted(date: .abbreviated, time: .omitted) } ?? (actual.sourcePlanID == nil ? "Unplanned" : "Original plan unavailable"))
                            .font(.caption).foregroundStyle(theme.textSecondary)
                    } right: {
                        actualButton(actual, plan: hiddenPlanIDs.contains(actual.id) ? nil : source, day: period)
                    }
                    Divider()
                }
                summary(comparison, title: "Day differences")
                DisclosureGroup("Week differences", isExpanded: $showsWeek) {
                    if let week = Calendar.current.dateInterval(of: .weekOfYear, for: day) {
                        summary(DayLedgerComparison(period: week, plans: allPlans, actuals: allActuals),
                                title: week.start.formatted(date: .abbreviated, time: .omitted) + " – " + week.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))
                    }
                }.font(.subheadline)
            }
        }
        .padding(Space.md)
        .background(theme.surface, in: .rect(cornerRadius: Radius.lg))
    }

    private func minutePrecision(_ entry: DayLedgerEntry) -> DayLedgerEntry {
        var result = entry
        result.start = Date(timeIntervalSinceReferenceDate: floor(entry.start.timeIntervalSinceReferenceDate / 60) * 60)
        let end = Date(timeIntervalSinceReferenceDate: floor(entry.end.timeIntervalSinceReferenceDate / 60) * 60)
        // Sub-minute activity still belongs to the day where it occurred.
        result.end = max(result.start.addingTimeInterval(1), end)
        return result
    }

    private func pair<Left: View, Right: View>(@ViewBuilder left: () -> Left,
                                               @ViewBuilder right: () -> Right) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            left().frame(maxWidth: .infinity, alignment: .leading)
            right().frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain)
    }

    private func actualButton(_ actual: DayLedgerEntry, plan: DayLedgerEntry?, day: DateInterval) -> some View {
        Button { data.edit(actual) } label: {
            VStack(alignment: .leading, spacing: Space.xxs) {
                row(actual)
                if !actual.notes.isEmpty {
                    Text(actual.notes).font(.caption).foregroundStyle(theme.textSecondary).lineLimit(2)
                }
                if actual.start < day.start || actual.start >= day.end {
                    Text(actual.start, format: .dateTime.month().day()).font(.caption)
                }
                if let plan, !plan.matches(actual) {
                    Text(difference(plan, actual)).font(.caption).foregroundStyle(theme.textSecondary)
                }
            }
        }
        .accessibilityLabel("Edit " + actual.title)
        .accessibilityIdentifier("anchor.actual.edit." + actual.id.uuidString)
    }

    private func row(_ entry: DayLedgerEntry) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(entry.title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
            Text(entry.start.formatted(date: .omitted, time: .shortened) + " – " + entry.end.formatted(date: Calendar.current.isDate(entry.start, inSameDayAs: entry.end) ? .omitted : .abbreviated, time: .shortened))
                .font(.caption.monospacedDigit()).foregroundStyle(theme.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }

    private func difference(_ plan: DayLedgerEntry, _ actual: DayLedgerEntry) -> String {
        var changes: [String] = []
        if plan.title != actual.title { changes.append("Planned: " + plan.title) }
        if actual.start != plan.start {
            changes.append("Planned start " + plan.start.formatted(date: Calendar.current.isDate(plan.start, inSameDayAs: actual.start) ? .omitted : .abbreviated, time: .shortened))
        }
        let minutes = Int((actual.end.timeIntervalSince(actual.start) - plan.end.timeIntervalSince(plan.start)) / 60)
        if minutes != 0 { changes.append("\(abs(minutes)) min " + (minutes > 0 ? "longer" : "shorter")) }
        if actual.notes != plan.notes { changes.append("Notes changed") }
        return changes.joined(separator: " · ")
    }

    private func summary(_ data: DayLedgerComparison, title: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(title).font(.subheadline.bold())
            Text("\(Int(data.plannedSeconds / 60)) min planned · \(Int(data.recordedSeconds / 60)) min in recorded slots")
            Text("\(data.matched) as planned · \(data.changed) changed · \(data.unplanned) unplanned · \(data.unrecorded) unrecorded")
                .foregroundStyle(theme.textSecondary)
            let delta = Int((data.linkedVarianceSeconds / 60).rounded())
            if delta != 0 {
                Text("Recorded slots spanned \(abs(delta)) min " + (delta > 0 ? "more" : "less") + " than planned in this period.")
            }
            if data.unavailablePlans > 0 { Text("\(data.unavailablePlans) with original plan unavailable") }
            if data.unplanned > 0 {
                Text("\(Int((data.unplannedSeconds / 60).rounded())) min went to unplanned entries.")
            }
        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func newEntry(_ period: DateInterval) {
        let end = period.contains(Date()) ? Date() : Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: period.start) ?? period.end
        data.edit(DayLedgerEntry(title: "", start: max(period.start, end.addingTimeInterval(-1800)), end: end))
    }

}

struct CalendarCheckButton: View {
    let block: PlanBlock
    let data: CalendarActualData
    var rowHeight: CGFloat? = nil
    var showsLabel = false

    var body: some View {
        let checked = data.recordedIDs.contains(block.id)
        Button { data.check(block) } label: {
            HStack(spacing: Space.xxs) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(rowHeight == nil ? .body : .caption2)
                if showsLabel {
                    Text(checked ? "Done" : "Mark done").font(.caption2.weight(.medium))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 24, minHeight: rowHeight ?? 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!data.available)
        .help(checked ? "Edit the copy in Done" : "Mark as done and copy to Done")
        .accessibilityLabel((checked ? "Edit done entry for " : "Mark done: ") + block.title)
        .accessibilityIdentifier("anchor.calendar.check." + block.id.uuidString)
    }
}

struct CalendarActualData {
    let entries: [DayLedgerEntry]
    let edit: (DayLedgerEntry) -> Void
    let record: (DayLedgerEntry) -> Bool
    let available: Bool

    let storedLogIDs: Set<UUID>
    let ongoing: [DayLedgerEntry]
    let recordedIDs: Set<UUID>

    init(entries: [DayLedgerEntry], edit: @escaping (DayLedgerEntry) -> Void,
         record: @escaping (DayLedgerEntry) -> Bool, available: Bool, ongoing: [DayLedgerEntry] = [], storedLogIDs: Set<UUID> = []) {
        self.storedLogIDs = storedLogIDs
        self.ongoing = ongoing
        self.entries = entries
        self.edit = edit
        self.record = record
        self.available = available
        self.recordedIDs = Set(entries.map(\.id))
    }

    func calendarEntries(in period: DateInterval) -> [DayLedgerEntry] {
        (entries + ongoing.filter { !recordedIDs.contains($0.id) })
            .filter { $0.start < period.end && $0.end > period.start }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    func check(_ block: PlanBlock) {
        guard available else { return }
        if let existing = entries.first(where: { $0.id == block.id }) { edit(existing); return }
        _ = record(DayLedgerEntry(id: block.id, title: block.title, start: block.plannedStart,
                              end: block.plannedEnd, notes: block.details, sourcePlanID: block.id))
    }
}

struct CalendarActuals<Content: View>: View {
    let blocks: [PlanBlock]
    let sessions: [FocusSession]
    let allBlocks: [PlanBlock]
    var editTimeLog: ((PlanBlock) -> Void)? = nil
    @ViewBuilder let content: (CalendarActualData) -> Content
    @Environment(\.modelContext) private var context
    @Environment(\.anchorTheme) private var theme
    @State private var saved: [DayLedgerEntry] = []
    @State private var error: String?
    @State private var unavailable = false
    @State private var editingTimeLog: PlanBlock?
    @State private var editor: Edit?

    private struct Edit: Identifiable {
        let entry: DayLedgerEntry
        let previous: DayLedgerEntry?
        var id: UUID { entry.id }
    }

    private var store: DayLedgerStore? {
        guard let config = context.container.configurations.first, !config.isStoredInMemoryOnly else { return nil }
        return DayLedgerStore(storeURL: config.url)
    }

    private var actuals: [DayLedgerEntry] {
        var entries = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for block in blocks where block.isUnplannedTimeLog && block.state == .inProgress && block.actualEndedAt == nil {
            entries.removeValue(forKey: block.id)
        }
        let linked = Dictionary(allBlocks.filter { !$0.isUnplannedTimeLog }.compactMap { block in block.sessionID.map { ($0, block.id) } }, uniquingKeysWith: { first, _ in first })
        for session in sessions {
            let id = linked[session.id] ?? session.id
            if entries[id] == nil, let end = session.endedAt, end > session.startedAt {
                let title = session.intent.isEmpty ? session.goal?.title ?? "Focus session" : session.intent
                entries[id] = DayLedgerEntry(id: id, title: title, start: session.startedAt, end: end, sourcePlanID: linked[session.id])
            }
        }
        for block in blocks where entries[block.id] == nil {
            if let start = block.actualStartedAt, let end = block.actualEndedAt, end > start {
                entries[block.id] = DayLedgerEntry(id: block.id, title: block.title, start: start, end: end, notes: block.details, sourcePlanID: block.isUnplannedTimeLog ? nil : block.id)
            }
        }
        return Array(entries.values)
    }

    private var ongoing: [DayLedgerEntry] {
        let now = Date()
        return blocks.compactMap { block in
            guard block.isUnplannedTimeLog, block.state == .inProgress,
                  let start = block.actualStartedAt, block.actualEndedAt == nil else { return nil }
            return DayLedgerEntry(id: block.id, title: block.title, start: start,
                                  end: max(start.addingTimeInterval(1), now), notes: block.details)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").font(.callout)
                Button("Reload entries", action: reload)
            }
            content(CalendarActualData(entries: actuals, edit: edit, record: { persist($0, replacing: nil) }, available: !unavailable, ongoing: ongoing,
                                       storedLogIDs: Set(blocks.filter(\.isUnplannedTimeLog).map(\.id))))
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .actualEntriesChanged)) { _ in reload() }
        .sheet(item: $editingTimeLog) { block in
            LogTimeSheet(day: block.actualStartedAt ?? block.plannedStart, block: block, onSave: reload).anchorTheme()
        }
        .sheet(item: $editor) { item in
            DayActualEditor(entry: item.entry, onRemove: item.previous.map { previous in
                {
                    guard let store else { throw CocoaError(.fileWriteUnknown) }
                    try store.remove(previous)
                    NotificationCenter.default.post(name: .actualEntriesChanged, object: nil)
                }
            }) { updated in
                try save(updated, replacing: item.previous)
            }.anchorTheme()
        }
    }

    private func edit(_ entry: DayLedgerEntry) {
        let previous = saved.first { $0.id == entry.id }
        if let block = blocks.first(where: { $0.id == entry.id && $0.isUnplannedTimeLog }) {
            if let editTimeLog { editTimeLog(block) } else { editingTimeLog = block }
        } else {
            editor = Edit(entry: entry, previous: previous)
        }
    }

    private func reload() {
        do {
            guard let store else { throw CocoaError(.fileReadUnknown) }
            let result = try store.load()
            saved = result.entries
            error = result.hasUnreadableFiles ? "Some actual entries couldn’t be read. The comparison includes the available entries." : nil
            unavailable = false
        } catch {
            unavailable = true
            self.error = "Actual entries could not be loaded on this device."
        }
    }

    private func save(_ entry: DayLedgerEntry, replacing previous: DayLedgerEntry?) throws {
        guard let store else { throw CocoaError(.fileWriteUnknown) }
        try store.save(entry, replacing: previous)
        NotificationCenter.default.post(name: .actualEntriesChanged, object: nil)
    }

    private func persist(_ entry: DayLedgerEntry, replacing previous: DayLedgerEntry?) -> Bool {
        do { try save(entry, replacing: previous); return true }
        catch { reload(); self.error = "Couldn’t save this entry. Reload and try again."; return false }
    }
}

private struct DayActualEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var entry: DayLedgerEntry
    @State private var error: String?
    @State private var confirmsRemoval = false
    var onRemove: (() throws -> Void)? = nil
    let onSave: (DayLedgerEntry) throws -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("What happened?", text: $entry.title).accessibilityIdentifier("anchor.actual.title")
                DatePicker("Started", selection: $entry.start)
                DatePicker("Ended", selection: $entry.end)
                TextField("Notes (optional)", text: $entry.notes, axis: .vertical).lineLimit(2...6)
                if entry.end <= entry.start { Text("Choose an end after the start.").font(.caption) }
                if let error { Text(error).font(.caption) }
                if onRemove != nil {
                    Button("Remove saved actual", role: .destructive) { confirmsRemoval = true }
                        .confirmationDialog("Remove this saved actual?", isPresented: $confirmsRemoval) {
                            Button("Remove saved actual", role: .destructive) {
                                do { try onRemove?(); dismiss() }
                                catch { self.error = "Couldn’t remove this entry. Reopen it and try again." }
                            }
                        } message: { Text("The plan and any original timer recording will remain available.") }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("What happened")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try onSave(entry); dismiss() }
                        catch { self.error = "Couldn’t save. If this entry changed in another window, reopen it to edit the latest version." }
                    }
                    .disabled(entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || entry.end <= entry.start)
                    .accessibilityIdentifier("anchor.actual.save")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 390, minHeight: 300)
        #endif
    }
}
#endif
