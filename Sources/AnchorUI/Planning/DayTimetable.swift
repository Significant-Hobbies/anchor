#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

enum TimetableStep: Int, CaseIterable {
    case five = 5, ten = 10, fifteen = 15, thirty = 30
    static let preferenceKey = "anchor.timetable.grid-step-minutes"
}

/// Pure placement math for the day timetable, kept free of SwiftUI so the
/// overlap lanes and visible hour range stay unit-testable.
enum TimetableLayout {
    struct Placement: Sendable, Equatable {
        var lane: Int
        var laneCount: Int
    }

    static func selection(from startY: CGFloat, to endY: CGFloat, hourHeight: CGFloat, range: DateInterval, step: TimetableStep) -> DateInterval {
        let increment = TimeInterval(step.rawValue * 60)
        func snap(_ y: CGFloat) -> TimeInterval {
            min(range.duration, max(0, (y / hourHeight * 3600 / increment).rounded() * increment))
        }
        let start = min(range.duration - increment, snap(min(startY, endY)))
        let end = max(start + increment, snap(max(startY, endY)))
        return DateInterval(start: range.start.addingTimeInterval(start), duration: end - start)
    }

    /// Greedy lane packing inside each overlap cluster. A new cluster begins
    /// when an interval starts at or after the running latest end, so separate
    /// clusters never share lanes. Results are keyed by input index.
    /// `minSpan` stretches each interval's collision box to at least that
    /// length so cards rendered with a minimum pixel height — which can
    /// collide even when their clock times don't overlap — still get lanes.
    static func place(_ intervals: [(TimeInterval, TimeInterval)], minSpan: TimeInterval = 0) -> [Placement] {
        var result = [Placement](repeating: Placement(lane: 0, laneCount: 1), count: intervals.count)
        var laneEnds: [TimeInterval] = []
        var cluster: [Int] = []
        var clusterMaxEnd: TimeInterval = -.infinity

        func finishCluster() {
            let lanes = max(1, laneEnds.count)
            for i in cluster { result[i].laneCount = lanes }
        }

        for i in intervals.indices.sorted(by: { intervals[$0].0 < intervals[$1].0 }) {
            let (start, rawEnd) = intervals[i]
            let end = max(rawEnd, start + minSpan)
            if start >= clusterMaxEnd && !cluster.isEmpty {
                finishCluster()
                cluster.removeAll()
                laneEnds.removeAll()
            }
            clusterMaxEnd = max(clusterMaxEnd, end)
            if let lane = laneEnds.firstIndex(where: { $0 <= start }) {
                laneEnds[lane] = end
                result[i].lane = lane
            } else {
                result[i].lane = laneEnds.count
                laneEnds.append(end)
            }
            cluster.append(i)
        }
        finishCluster()
        return result
    }

    /// The hour window the grid draws. Defaults to a working day
    /// (7:00–22:00, owner-adjustable) and expands to cover every block plus
    /// the current hour when the day being viewed is today.
    static func displayRange(
        for day: Date,
        intervals: [(TimeInterval, TimeInterval)],
        now: Date,
        calendar: Calendar = .current,
        windowStartHour: Int = 7,
        windowEndHour: Int = 22
    ) -> DateInterval {
        let startOfDay = calendar.startOfDay(for: day)
        var startHour = Double(max(0, min(windowStartHour, 23)))
        var endHour = Double(max(Int(startHour) + 1, min(windowEndHour, 24)))
        for (start, end) in intervals {
            startHour = min(startHour, floor(start / 3600))
            endHour = max(endHour, ceil(end / 3600))
        }
        if calendar.isDate(day, inSameDayAs: now) {
            let nowHour = Double(calendar.component(.hour, from: now))
                + Double(calendar.component(.minute, from: now)) / 60
            startHour = min(startHour, floor(nowHour) - 1)
            endHour = max(endHour, ceil(nowHour) + 1)
        }
        startHour = max(0, min(startHour, 23))
        endHour = min(24, max(endHour, startHour + 1))
        return DateInterval(
            start: startOfDay.addingTimeInterval(startHour * 3600),
            end: startOfDay.addingTimeInterval(endHour * 3600)
        )
    }
}

/// The day as a real timetable: an hour rail on the left, blocks at their
/// clock position sized by duration, a thin "lived" trace beside the rail
/// showing when work actually happened, and a now-line when the day is today.
/// Tapping open space offers to place a new entry at that time.
struct DayTimetable: View {
    struct Entry: Identifiable {
        var id: UUID { block.id }
        let block: PlanBlock
        let projectName: String?
        let linkedSession: FocusSession?
        let hasDifferentActiveSession: Bool
        let isCurrent: Bool
        var outcome: PlannerOutcome? = nil
    }

    @Environment(\.anchorTheme) private var theme

    let day: Date
    let entries: [Entry]
    let actuals: CalendarActualData
    var hourHeight: CGFloat = 56
    var step: TimetableStep = .five
    var windowStartHour: Int = 7
    var windowEndHour: Int = 22
    var showsLivedTrace: Bool = true
    var dimsFinished: Bool = true
    var onCheckIn: (PlanBlock) -> Void = { _ in }
    var onStart: (PlanBlock) -> Void = { _ in }
    var onOpenFocus: () -> Void = {}
    var onComplete: (PlanBlock) -> Void = { _ in }
    var onEdit: (PlanBlock) -> Void = { _ in }
    var onRemove: (PlanBlock) -> Void = { _ in }
    var onExplain: (PlanBlock) -> Void = { _ in }
    var onLogActual: (PlanBlock) -> Void = { _ in }
    var draft: EditorSeed? = nil
    var draftTitle: Binding<String> = .constant("")
    var draftError: String? = nil
    var onSaveDraft: () -> Void = {}
    var onCancelDraft: () -> Void = {}
    var onDraftOptions: (String) -> Void = { _ in }
    var onAddAt: (DateInterval, Bool) -> Void = { _, _ in }
    #if os(macOS)
    @GestureState private var selection: DateInterval?
    #else
    @State private var selection: DateInterval?
    #endif

    static let nowAnchorID = "anchor.timetable.now"

    private let railWidth: CGFloat = 50
    private let minCardHeight: CGFloat = 40
    private var traceWidth: CGFloat { showsLivedTrace ? 12 : 0 }

    /// Seconds a card occupies for lane packing: its rendered height, which is
    /// at least `minCardHeight` (+padding) regardless of the clock-time span.
    private var minCollisionSpan: TimeInterval {
        (minCardHeight + 4) / hourHeight * 3600
    }

    private var timedEntries: [Entry] { entries.filter { $0.block.plannedSeconds < 86_400 } }

    private var dayActuals: [DayLedgerEntry] {
        guard let period = Calendar.current.dateInterval(of: .day, for: day) else { return [] }
        return actuals.calendarEntries(in: period)
    }

    private var doneEntries: [DayLedgerEntry] { dayActuals.filter { $0.end.timeIntervalSince($0.start) < 86_400 } }

    private var range: DateInterval {
        let midnight = Calendar.current.startOfDay(for: day)
        var intervals = timedEntries.map { entry in
            let start = entry.block.plannedStart.timeIntervalSince(midnight)
            return (start, start + Double(entry.block.plannedSeconds))
        }
        intervals += doneEntries.map { ($0.start.timeIntervalSince(midnight), $0.end.timeIntervalSince(midnight)) }
        if let draft {
            let start = draft.start.timeIntervalSince(midnight)
            intervals.append((start, start + Double(draft.minutes * 60)))
        }
        return TimetableLayout.displayRange(
            for: day,
            intervals: intervals,
            now: Date(),
            windowStartHour: windowStartHour,
            windowEndHour: windowEndHour
        )
    }

    private var hourCount: Int {
        max(1, Int(range.duration / 3600))
    }

    private var totalHeight: CGFloat {
        CGFloat(hourCount) * hourHeight
    }

    private var placements: [UUID: TimetableLayout.Placement] {
        let placed = TimetableLayout.place(
            timedEntries.map { entry in
                let start = entry.block.plannedStart.timeIntervalSince(range.start)
                return (start, start + Double(entry.block.plannedSeconds))
            },
            minSpan: minCollisionSpan
        )
        var result: [UUID: TimetableLayout.Placement] = [:]
        for (index, entry) in timedEntries.enumerated() {
            result[entry.id] = placed[index]
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            let longPlans = entries.filter { $0.block.plannedSeconds >= 86_400 }
            let longActuals = dayActuals.filter { $0.end.timeIntervalSince($0.start) >= 86_400 }
            if !longPlans.isEmpty || !longActuals.isEmpty {
                HStack(alignment: .top, spacing: Space.xxs) {
                    VStack { ForEach(longPlans) { blockCard($0, height: 70).frame(height: 70) } }
                        .frame(maxWidth: .infinity)
                    VStack { ForEach(longActuals) { doneCard($0).frame(height: 70) } }
                        .frame(maxWidth: .infinity)
                }.padding(.leading, railWidth + traceWidth)
            }
            grid
        }
    }

    private func blockCard(_ entry: Entry, height: CGFloat, compact: Bool = false) -> some View {
        TimetableBlockCard(entry: entry, height: height, compact: compact, actuals: actuals, dimsFinished: dimsFinished,
                           onCheckIn: { onCheckIn(entry.block) }, onStart: { onStart(entry.block) },
                           onOpenFocus: onOpenFocus, onComplete: { onComplete(entry.block) },
                           onEdit: { onEdit(entry.block) }, onRemove: { onRemove(entry.block) },
                           onExplain: { onExplain(entry.block) }, onLogActual: { onLogActual(entry.block) })
    }

    private func doneCard(_ item: DayLedgerEntry) -> some View {
        Button { actuals.edit(item) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                if actuals.recordedIDs.contains(item.id) {
                    Text(item.start, style: .time).font(.caption2.monospacedDigit())
                } else {
                    Text("In progress").font(.caption2)
                }
            }
            .padding(Space.xxs)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.surfaceRaised, in: .rect(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
        .disabled(!actuals.available)
        .accessibilityLabel("Edit done entry " + item.title)
    }

    private var grid: some View {
        GeometryReader { proxy in
            let gridX = railWidth + traceWidth
            let gridWidth = max(1, (proxy.size.width - gridX - Space.xxs) / 2)
            let doneX = gridX + gridWidth + Space.xxs
            let recorded = doneEntries
            let lanes = TimetableLayout.place(recorded.map {
                (max(0, $0.start.timeIntervalSince(range.start)), min(range.duration, $0.end.timeIntervalSince(range.start)))
            }, minSpan: minCollisionSpan)
            ZStack(alignment: .topLeading) {
                hourMarks(width: proxy.size.width)

                selectionSurface
                    .frame(width: gridWidth, height: totalHeight)
                    .offset(x: gridX)
                    .accessibilityHidden(true)

                if showsLivedTrace {
                    livedTraces
                }

                ForEach(timedEntries) { entry in
                    let placement = placements[entry.id] ?? TimetableLayout.Placement(lane: 0, laneCount: 1)
                    let laneGap = Space.xxs
                    let laneWidth = (gridWidth - CGFloat(placement.laneCount - 1) * laneGap) / CGFloat(placement.laneCount)
                    blockCard(entry, height: cardHeight(for: entry), compact: laneWidth < 180)
                    .frame(width: laneWidth, height: cardHeight(for: entry), alignment: .topLeading)
                    .offset(
                        x: gridX + CGFloat(placement.lane) * (laneWidth + laneGap),
                        y: cardTop(for: entry)
                    )
                }

                Rectangle().fill(theme.hairline)
                    .frame(width: 1, height: totalHeight)
                    .offset(x: doneX - Space.xxs / 2)
                    .allowsHitTesting(false)

                ForEach(Array(recorded.enumerated()), id: \.element.id) { index, item in
                    let lane = lanes[index]
                    let width = max(1, (gridWidth - CGFloat(lane.laneCount - 1) * Space.xxs) / CGFloat(lane.laneCount))
                    let y = max(0, offset(for: item.start))
                    let height = max(minCardHeight, min(totalHeight, offset(for: item.end)) - y - 4)
                    doneCard(item)
                    .frame(width: width, height: height)
                    .offset(x: doneX + CGFloat(lane.lane) * (width + Space.xxs), y: y + 2)
                }

                if let selection {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.accent.opacity(0.22))
                        .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(theme.accent) }
                        .overlay(alignment: .topLeading) {
                            Text("\(selection.start.formatted(date: .omitted, time: .shortened)) – \(selection.end.formatted(date: .omitted, time: .shortened))")
                                .font(.caption2.monospacedDigit()).padding(.horizontal, 4)
                                .background(theme.surfaceRaised, in: .rect(cornerRadius: 3))
                                .fixedSize()
                        }
                        .frame(width: gridWidth, height: selection.duration / 3600 * hourHeight)
                        .offset(x: gridX, y: offset(for: selection.start))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                if Calendar.current.isDateInToday(day) {
                    Color.clear
                        .frame(height: 1)
                        .id(Self.nowAnchorID)
                        .offset(y: max(0, offset(for: Date()) - hourHeight))
                        .allowsHitTesting(false)
                    nowLine(width: proxy.size.width)
                }
                if let draft {
                    InlineEntryEditor(seed: draft, title: draftTitle, error: draftError,
                                      save: onSaveDraft, cancel: onCancelDraft, options: onDraftOptions)
                        .frame(width: proxy.size.width - gridX)
                        .padding(.top, max(0, offset(for: draft.start)))
                        .padding(.leading, gridX)
                        .id(draft.id)
                }
            }
        }
        .frame(height: max(totalHeight, draft.map { offset(for: $0.start) + 92 } ?? 0))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("anchor.today.timetable")
    }

    private func offset(for date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(range.start) / 3600) * hourHeight
    }

    private func interval(for drag: DragGesture.Value) -> DateInterval {
        TimetableLayout.selection(from: drag.startLocation.y, to: drag.location.y, hourHeight: hourHeight, range: range, step: step)
    }

    private var selectionSurface: some View {
        #if os(macOS)
        let surface = Color.clear.contentShape(Rectangle())
        return surface.gesture(DragGesture(minimumDistance: 0)
            .updating($selection) { drag, selected, _ in selected = interval(for: drag) }
            .onEnded { drag in onAddAt(interval(for: drag), abs(drag.translation.height) >= 3) })
        #else
        return TimetableTouchSurface { start, end in
            selection = TimetableLayout.selection(from: start, to: end, hourHeight: hourHeight, range: range, step: step)
        } finish: { start, end, dragged in
            selection = nil
            onAddAt(TimetableLayout.selection(from: start, to: end, hourHeight: hourHeight, range: range, step: step), dragged)
        } cancel: {
            selection = nil
        }
        #endif
    }

    private func cardTop(for entry: Entry) -> CGFloat {
        max(0, offset(for: entry.block.plannedStart)) + 2
    }

    private func cardHeight(for entry: Entry) -> CGFloat {
        let visibleSeconds = min(range.end, entry.block.plannedEnd).timeIntervalSince(max(range.start, entry.block.plannedStart))
        let span = visibleSeconds / 3600 * hourHeight
        return max(minCardHeight, span - 4)
    }

    private func hourMarks(width: CGFloat) -> some View {
        ForEach(0...hourCount, id: \.self) { tick in
            let y = CGFloat(tick) * hourHeight
            HStack(alignment: .top, spacing: Space.xxs) {
                Text(range.start.addingTimeInterval(TimeInterval(tick) * 3600).formatted(.dateTime.hour()))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(theme.textTertiary)
                    .frame(width: railWidth - 4, alignment: .trailing)
                Rectangle()
                    .fill(theme.hairline)
                    .frame(height: 1)
            }
            .frame(width: width, alignment: .topLeading)
            .offset(y: y)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }

    private var livedTraces: some View {
        ForEach(timedEntries.filter { $0.block.actualStartedAt != nil }) { entry in
            let start = entry.block.actualStartedAt!
            let end = entry.block.actualEndedAt ?? Date()
            let top = max(0, offset(for: start))
            let bottom = min(totalHeight, max(top + 10, offset(for: end)))
            DayRailShape()
                .stroke(
                    entry.block.state == .inProgress ? theme.accent : theme.positive.opacity(0.85),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .frame(width: traceWidth - 4, height: bottom - top)
                .offset(x: railWidth + 2, y: top)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }

    private func nowLine(width: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let y = min(max(0, offset(for: context.date)), totalHeight)
            HStack(spacing: 0) {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 7, height: 7)
                    .offset(x: railWidth - 3)
                Rectangle()
                    .fill(theme.accent.opacity(0.85))
                    .frame(height: 1.5)
            }
            .frame(width: width, alignment: .topLeading)
            .offset(y: y)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }
}

#if os(iOS)
/// Let UIKit arbitrate the open grid's touch gestures with the containing scroll view.
/// A moving finger fails the hold recognizer so the scroll view takes over immediately.
private struct TimetableTouchSurface: UIViewRepresentable {
    let preview: (CGFloat, CGFloat) -> Void
    let finish: (CGFloat, CGFloat, Bool) -> Void
    let cancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(surface: self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hold(_:)))
        hold.minimumPressDuration = 0.3
        hold.allowableMovement = 8
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.require(toFail: hold)
        view.addGestureRecognizer(hold)
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) { context.coordinator.surface = self }

    final class Coordinator: NSObject {
        var surface: TimetableTouchSurface
        private var start: CGFloat = 0
        init(surface: TimetableTouchSurface) { self.surface = surface }

        @objc func tap(_ sender: UITapGestureRecognizer) {
            let y = sender.location(in: sender.view).y
            surface.finish(y, y, false)
        }

        @objc func hold(_ sender: UILongPressGestureRecognizer) {
            let y = sender.location(in: sender.view).y
            switch sender.state {
            case .began:
                start = y
                surface.preview(start, y)
            case .changed:
                surface.preview(start, y)
            case .ended:
                surface.finish(start, y, true)
            case .cancelled, .failed:
                surface.cancel()
            default:
                break
            }
        }
    }
}
#endif

/// The hand-drawn vertical trace: the planned day sits on straight grid lines,
/// while time that actually happened is drawn with this slight bend — the same
/// "drawn" material the rest of the core loop shares.
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

private struct TimetableBlockCard: View {
    @Environment(\.anchorTheme) private var theme
    @State private var showsActions = false
    @State private var showsMore = false

    let entry: DayTimetable.Entry
    let height: CGFloat
    let compact: Bool
    let actuals: CalendarActualData
    var dimsFinished: Bool = true
    let onCheckIn: () -> Void
    let onStart: () -> Void
    let onOpenFocus: () -> Void
    let onComplete: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void
    let onExplain: () -> Void
    let onLogActual: () -> Void

    private var block: PlanBlock { entry.block }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(stateTint)
                .frame(width: 3)
                .padding(.vertical, 5)
                .padding(.leading, 5)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top, spacing: Space.xxs) {
                    CalendarCheckButton(block: block, data: actuals)
                    Button { showsActions = true } label: {
                        Text(block.title)
                            .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(actionLabel)
                    if !compact { actionsButton }

                }
                if height >= 56 {
                    let dateStyle: Date.FormatStyle.DateStyle = Calendar.current.isDate(block.plannedStart, inSameDayAs: block.plannedEnd) ? .omitted : .abbreviated
                    Text("\(block.plannedStart.formatted(date: dateStyle, time: .shortened)) – \(block.plannedEnd.formatted(date: dateStyle, time: .shortened))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
                if height >= 92 {
                    metaLine
                }
            }
            .padding(.leading, Space.xs)
            .padding(.trailing, 2)
            .padding(.vertical, Space.xxs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            Button { showsActions = true } label: {
                RoundedRectangle(cornerRadius: Radius.sm).fill(cardFill).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityHidden(true)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.sm)
                .strokeBorder(
                    entry.isCurrent || block.state == .inProgress ? theme.accent.opacity(0.4) : theme.hairline,
                    style: StrokeStyle(
                        lineWidth: entry.isCurrent || block.state == .inProgress ? 1.4 : 1,
                        dash: block.state == .skipped || block.state == .moved ? [4, 3] : []
                    )
                ).allowsHitTesting(false)
        }
        .opacity(cardOpacity)
        .popover(isPresented: $showsActions, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                if showsMore {
                    actionRow("Back", icon: "chevron.left") { showsMore = false }
                    Divider()
                    secondaryChoices
                } else {
                    if entry.linkedSession?.isActive == true {
                        actionRow("Open timer", icon: "timer") { choose(onOpenFocus) }
                    } else if block.state == .inProgress {
                        actionRow("Finish now", icon: "checkmark") { choose(onComplete) }
                    } else if block.state == .planned && !entry.hasDifferentActiveSession {
                        actionRow("Start focus", icon: "play") { choose(onStart) }
                    }
                    actionRow(block.externalEventKey == nil ? "Edit entry" : "Edit event", icon: "pencil") { choose(onEdit) }
                    actionRow("More", icon: "ellipsis") { showsMore = true }
                }
            }
            .padding(Space.xs)
            .frame(width: 200)
            .anchorTheme()
            .presentationCompactAdaptation(.popover)
        }
        .onChange(of: showsActions) { _, open in if !open { showsMore = false } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("anchor.today.block.\(block.id.uuidString)")
    }

    @ViewBuilder
    private var actionsButton: some View {
        Button { showsActions = true } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(theme.textSecondary)
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(actionLabel)
        .accessibilityIdentifier("anchor.today.block-actions")
    }

    private func actionRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Space.xxs)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var metaLine: some View {
        HStack(spacing: Space.xxs) {
            if let projectName = entry.projectName {
                Text(projectName)
                Text("·")
            }
            Text(block.kind.label)
            Text("·")
            Text(block.flexibility.label)
            if block.templateID != nil {
                Text("·")
                Label("recurring", systemImage: "repeat")
            }
            if let direction = block.lifeDirection {
                Text("·")
                Text(direction.label)
            }
        }
        .font(.caption2)
        .foregroundStyle(theme.textTertiary)
        .lineLimit(1)
    }

    @ViewBuilder
    private var secondaryChoices: some View {
        actionRow(entry.outcome.map { "Check in · " + $0.rawValue } ?? "Check in…", icon: "list.clipboard") { choose(onCheckIn) }
        if entry.linkedSession?.isActive != true {
            if block.state == .planned {
                actionRow("Finished without timing", icon: "checkmark") { choose(onComplete) }
            }
            if block.sessionID == nil {
                actionRow("Log actual time…", icon: "clock") { choose(onLogActual) }
            }
        }
        actionRow("Explain a change", icon: "text.bubble") { choose(onExplain) }
        if block.externalEventKey != nil {
            Divider()
            actionRow("Remove from Anchor…", icon: "trash") { choose(onRemove) }
        }
    }

    private func choose(_ action: () -> Void) {
        showsActions = false
        action()
    }

    private var stateTint: Color {
        if let outcome = entry.outcome {
            return switch outcome {
            case .blocked: theme.caution
            case .unsuccessful: theme.negative
            case .successful: theme.positive
            }
        }
        return switch block.state {
        case .completed: theme.positive
        case .skipped, .moved: theme.textTertiary
        default: theme.accent
        }
    }

    private var cardFill: Color {
        entry.isCurrent || block.state == .inProgress ? theme.surfaceRaised : theme.surface
    }

    private var cardOpacity: Double {
        guard dimsFinished else { return 1 }
        return switch block.state {
        case .completed: 0.62
        case .skipped, .moved: 0.45
        default: 1
        }
    }

    private var actionLabel: String {
        if entry.linkedSession?.isActive == true || block.state == .inProgress {
            let outcome = entry.outcome.map { ". " + $0.rawValue } ?? ""
            let activity = entry.linkedSession?.isActive == true ? "Timer active" : "In progress"
            return "\(activity). Actions for \(block.title)\(outcome)"
        }
        if let outcome = entry.outcome { return "\(outcome.rawValue). Actions for \(block.title)" }
        if entry.hasDifferentActiveSession { return "Actions for \(block.title); another session is active" }
        return "Actions for \(block.title)"
    }
}
#endif
