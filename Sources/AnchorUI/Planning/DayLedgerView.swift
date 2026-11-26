#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

private extension Notification.Name {
    static let actualEntriesChanged = Notification.Name("anchor.actual-entries.changed")
}

struct DayLedgerView: View {
    let day: Date
    let blocks: [PlanBlock]
    let sessions: [FocusSession]
    @Environment(\.modelContext) private var context
    @Environment(\.anchorTheme) private var theme
    @State private var saved: [DayLedgerEntry] = []
    @State private var error: String?
    @State private var unavailable = false
    @State private var editor: Edit?
    @State private var showsWeek = false

    private struct Edit: Identifiable {
        let entry: DayLedgerEntry
        let previous: DayLedgerEntry?
        var id: UUID { entry.id }
    }

    private var store: DayLedgerStore? {
        guard let config = context.container.configurations.first, !config.isStoredInMemoryOnly else { return nil }
        return DayLedgerStore(storeURL: config.url)
    }

    private var plans: [DayLedgerEntry] {
        blocks.filter { !$0.isUnplannedTimeLog }.map { DayLedgerEntry(id: $0.id, title: $0.title, start: $0.plannedStart, end: $0.plannedEnd, notes: $0.details) }
    }

    private var actuals: [DayLedgerEntry] {
        var entries = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let linked = Dictionary(blocks.compactMap { block in block.sessionID.map { ($0, block.id) } }, uniquingKeysWith: { first, _ in first })
        for session in sessions {
            let id = linked[session.id] ?? session.id
            if entries[id] == nil, let end = session.endedAt, end > session.startedAt {
                let title = session.intent.isEmpty ? session.goal?.title ?? "Focus session" : session.intent
                entries[id] = DayLedgerEntry(id: id, title: title, start: session.startedAt, end: end)
            }
        }
        for block in blocks where entries[block.id] == nil {
            if let start = block.actualStartedAt, let end = block.actualEndedAt, end > start {
                entries[block.id] = DayLedgerEntry(id: block.id, title: block.title, start: start, end: end, notes: block.details)
            }
        }
        return Array(entries.values)
    }

    var body: some View {
        let period = Calendar.current.dateInterval(of: .day, for: day)!
        let allPlans = plans, allActuals = actuals
        let comparison = DayLedgerComparison(period: period, plans: allPlans, actuals: allActuals)
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Text("Plan and actual").font(.title2.weight(.semibold))
                Spacer()
                Button { newEntry(period) } label: { Label("Log actual", systemImage: "plus") }
                    .buttonStyle(QuietButtonStyle(expands: false))
                    .disabled(unavailable)
                    .accessibilityIdentifier("anchor.actual.add")
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").font(.callout)
                Button("Reload entries", action: reload)
            }
            if !unavailable {
                let localPlanIDs = Set(comparison.plans.map(\.id))
                let actualByID = Dictionary(allActuals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                let planByID = Dictionary(allPlans.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                pair {
                    Text("Plan").font(.headline)
                } right: {
                    Text("What happened").font(.headline)
                }
                Divider()
                if comparison.plans.isEmpty && comparison.actuals.isEmpty {
                    pair { Text("Nothing planned") } right: { Text("Log an actual entry.") }
                        .font(.callout).foregroundStyle(theme.textSecondary)
                }
                ForEach(comparison.plans) { plan in
                    let actual = actualByID[plan.id]
                    pair {
                        Button {
                            if let actual { edit(actual) }
                            else { persist(plan, replacing: nil) }
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
                            Button("Record differently") { edit(plan) }
                                .font(.caption).foregroundStyle(theme.textSecondary)
                        }
                    }
                    Divider()
                }
                ForEach(comparison.actuals.filter { !localPlanIDs.contains($0.id) }) { actual in
                    let source = planByID[actual.id]
                    pair {
                        Text(source.map { "Planned " + $0.start.formatted(date: .abbreviated, time: .omitted) } ?? "Unplanned")
                            .font(.caption).foregroundStyle(theme.textSecondary)
                    } right: {
                        actualButton(actual, plan: source, day: period)
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
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .actualEntriesChanged)) { _ in reload() }
        .sheet(item: $editor) { item in
            DayActualEditor(entry: item.entry) { updated in
                try save(updated, replacing: item.previous)
            }.anchorTheme()
        }
    }

    private func pair<Left: View, Right: View>(@ViewBuilder left: () -> Left,
                                               @ViewBuilder right: () -> Right) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            left().frame(maxWidth: .infinity, alignment: .leading)
            right().frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain)
    }

    private func actualButton(_ actual: DayLedgerEntry, plan: DayLedgerEntry?, day: DateInterval) -> some View {
        Button { edit(actual) } label: {
            VStack(alignment: .leading, spacing: Space.xxs) {
                row(actual)
                if actual.start < day.start || actual.start >= day.end {
                    Text(actual.start, format: .dateTime.month().day()).font(.caption)
                }
                if let plan, plan != actual {
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
            Text("\(Int(data.plannedSeconds / 60)) min planned · \(Int(data.recordedSeconds / 60)) min recorded")
            Text("\(data.matched) as planned · \(data.changed) changed · \(data.unplanned) unplanned · \(data.unrecorded) unrecorded")
                .foregroundStyle(theme.textSecondary)
        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func newEntry(_ period: DateInterval) {
        let end = period.contains(Date()) ? Date() : Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: period.start) ?? period.end
        editor = Edit(entry: DayLedgerEntry(title: "", start: max(period.start, end.addingTimeInterval(-1800)), end: end), previous: nil)
    }

    private func edit(_ entry: DayLedgerEntry) { editor = Edit(entry: entry, previous: saved.first { $0.id == entry.id }) }

    private func reload() {
        do {
            guard let store else { throw CocoaError(.fileReadUnknown) }
            saved = try store.load()
            error = nil
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

    private func persist(_ entry: DayLedgerEntry, replacing previous: DayLedgerEntry?) {
        do { try save(entry, replacing: previous) }
        catch { reload(); self.error = "Couldn’t save this entry. Reload and try again." }
    }
}

/// Timetable actions edit the same independent record as Review.
struct LinkedActualEditor: View {
    let block: PlanBlock
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DayLedgerEntry?
    @State private var prior: DayLedgerEntry?
    @State private var failed = false

    private var store: DayLedgerStore? {
        guard let config = context.container.configurations.first, !config.isStoredInMemoryOnly else { return nil }
        return DayLedgerStore(storeURL: config.url)
    }

    var body: some View {
        Group {
            if let draft {
                DayActualEditor(entry: draft) { updated in
                    guard let store else { throw CocoaError(.fileWriteUnknown) }
                    try store.save(updated, replacing: prior)
                    NotificationCenter.default.post(name: .actualEntriesChanged, object: nil)
                }
            } else if failed {
                VStack { Text("Couldn’t read this actual entry."); Button("Close") { dismiss() } }.padding()
            } else { ProgressView() }
        }
        .onAppear {
            do {
                guard let store else { throw CocoaError(.fileReadUnknown) }
                prior = try store.load().first { $0.id == block.id }
                draft = prior ?? DayLedgerEntry(id: block.id, title: block.title, start: block.actualStartedAt ?? block.plannedStart,
                                               end: block.actualEndedAt ?? block.plannedEnd, notes: block.details)
            } catch { failed = true }
        }
    }
}

private struct DayActualEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var entry: DayLedgerEntry
    @State private var error: String?
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
