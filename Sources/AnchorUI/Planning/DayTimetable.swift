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
    static func place(_ intervals: [(Double, Double)]) -> [Placement] {
        var result = [Placement](repeating: Placement(lane: 0, laneCount: 1), count: intervals.count)
        var laneEnds: [TimeInterval] = []
        var cluster: [Int] = []
        var clusterMaxEnd: TimeInterval = -.infinity

        func finishCluster() {
            let lanes = max(1, laneEnds.count)
            for i in cluster { result[i].laneCount = lanes }
        }

        for i in intervals.indices.sorted(by: { intervals[$0].0 < intervals[$1].0 }) {
            let (start, end) = intervals[i]
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

    static let minimumRowHeight: CGFloat = 13
    static let rowGap: CGFloat = 1

    static func cardBounds(from start: CGFloat, to end: CGFloat, in totalHeight: CGFloat) -> (start: Double, end: Double) {
        let y = max(0, start)
        let height = max(minimumRowHeight, min(totalHeight, end) - y - rowGap)
        let top = min(y, totalHeight - height)
        return (top, top + height)
    }

    static func displayRange(for day: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .day, for: day)!
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

    @Environment(\.calendarActivityTags) private var activityTags
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
    var onDropEntry: (CalendarDrag, TimetableColumn, Date) -> Bool = { _, _, _ in false }
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
    var onAddAt: (DateInterval, Bool, TimetableColumn) -> Void = { _, _, _ in }
    @State private var draftHeight: CGFloat = 92
    @State private var gridFrame = CGRect.zero
    @State private var interaction = CalendarEntryInteraction()
    #if os(macOS)
    @GestureState private var selection: (interval: DateInterval, column: TimetableColumn)?
    #else
    @State private var selection: (interval: DateInterval, column: TimetableColumn)?
    #endif

    static func hourAnchor(for time: Date, on day: Date) -> Date {
        let midnight = Calendar.current.startOfDay(for: day)
        let hour = max(0, floor(time.timeIntervalSince(midnight) / 3600))
        return midnight.addingTimeInterval(hour * 3600)
    }

    private let railWidth: CGFloat = 50
    private var traceWidth: CGFloat { showsLivedTrace ? 12 : 0 }

    private var timedEntries: [Entry] { entries.filter { $0.block.plannedSeconds < 86_400 } }

    private var dayActuals: [DayLedgerEntry] {
        guard let period = Calendar.current.dateInterval(of: .day, for: day) else { return [] }
        return actuals.calendarEntries(in: period)
    }

    private var doneEntries: [DayLedgerEntry] { dayActuals.filter { $0.end.timeIntervalSince($0.start) < 86_400 } }

    private var range: DateInterval {
        TimetableLayout.displayRange(for: day)
    }

    private var hourCount: Int {
        max(1, Int(range.duration / 3600))
    }

    private var totalHeight: CGFloat {
        CGFloat(range.duration / 3600) * hourHeight
    }

    private var placements: [UUID: TimetableLayout.Placement] {
        let placed = TimetableLayout.place(timedEntries.map {
            cardBounds(start: $0.block.plannedStart, end: $0.block.plannedEnd)
        })
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
                    VStack {
                        ForEach(longPlans) { item in
                            blockCard(item, height: 70).frame(height: 70)
                                .modifier(CalendarEntryGesture(interaction: interaction) { point, resize, keepsTime in
                                    drop(CalendarDrag(id: item.id, source: .plan, resizing: resize, keepsTime: keepsTime), at: point)
                                })
                        }
                    }
                        .frame(maxWidth: .infinity)
                    VStack {
                        ForEach(longActuals) { item in
                            doneCard(item).frame(height: 70)
                                .modifier(CalendarEntryGesture(interaction: interaction) { point, resize, keepsTime in
                                    drop(CalendarDrag(id: item.id, source: .actual, resizing: resize, keepsTime: keepsTime), at: point)
                                })
                        }
                    }
                        .frame(maxWidth: .infinity)
                }.padding(.leading, railWidth + traceWidth)
            }
            grid
        }.coordinateSpace(name: "anchor.day.grid")
    }

    private func blockCard(_ entry: Entry, height: CGFloat, compact: Bool = false) -> some View {
        TimetableBlockCard(interaction: interaction, entry: entry, height: height, compact: compact, category: activityTags[entry.block.title] ?? .suggestion(for: entry.block.title), actuals: actuals, dimsFinished: dimsFinished,
                           onCheckIn: { onCheckIn(entry.block) }, onStart: { onStart(entry.block) },
                           onOpenFocus: onOpenFocus, onComplete: { onComplete(entry.block) },
                           onEdit: { onEdit(entry.block) }, onRemove: { onRemove(entry.block) },
                           onExplain: { onExplain(entry.block) }, onLogActual: { onLogActual(entry.block) })
    }

    private func doneCard(_ item: DayLedgerEntry, height: CGFloat = 70) -> some View {
        let category = activityTags[item.title] ?? .suggestion(for: item.title)
        return Button { if interaction.acceptsTap { actuals.edit(item) } } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    Image(systemName: category.calendarSymbol).font(.caption2).accessibilityHidden(true)
                    Text(item.title).font(height < 38 ? .caption2.weight(.semibold) : .subheadline.weight(.semibold)).lineLimit(height < 38 ? 1 : 2)
                }
                if height >= 38 {
                    if actuals.recordedIDs.contains(item.id) {
                        Text("\(category.rawValue.capitalized) · \(item.start.formatted(date: .omitted, time: .shortened))").font(.caption2.monospacedDigit()).lineLimit(1)
                    } else {
                        Text("In progress").font(.caption2)
                    }
                }
            }
            .padding(.horizontal, Space.xxs)
            .padding(.vertical, height < 38 ? 0 : Space.xxs)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, Space.xxs)
            .foregroundStyle(Color.black.opacity(0.91))
            .background(category.calendarColor, in: .rect(cornerRadius: Radius.sm))

        }
        .help(category.rawValue.capitalized)
        .accessibilityValue(category.rawValue.capitalized)
        .buttonStyle(.plain)
        .disabled(!actuals.available && !actuals.storedLogIDs.contains(item.id))
        .accessibilityLabel("Edit done entry " + item.title)
    }

    private var grid: some View {
        GeometryReader { proxy in
            let gridX = railWidth + traceWidth
            let gridWidth = max(1, (proxy.size.width - gridX - Space.xxs) / 2)
            let doneX = gridX + gridWidth + Space.xxs
            let recorded = doneEntries
            let lanes = TimetableLayout.place(recorded.map {
                cardBounds(start: $0.start, end: $0.end)
            })
            ZStack(alignment: .topLeading) {
                hourMarks(width: proxy.size.width)

                selectionSurface(.scheduled)
                    .frame(width: gridWidth, height: totalHeight)
                    .offset(x: gridX)
                    .accessibilityHidden(true)

                if actuals.available {
                    selectionSurface(.done)
                        .frame(width: gridWidth, height: totalHeight)
                        .offset(x: doneX)
                        .accessibilityHidden(true)
                }

                if showsLivedTrace {
                    livedTraces
                }

                ForEach(timedEntries) { entry in
                    let placement = placements[entry.id] ?? TimetableLayout.Placement(lane: 0, laneCount: 1)
                    let bounds = cardBounds(start: entry.block.plannedStart, end: entry.block.plannedEnd)
                    let height = bounds.end - bounds.start
                    let laneGap = Space.xxs
                    let laneWidth = (gridWidth - CGFloat(placement.laneCount - 1) * laneGap) / CGFloat(placement.laneCount)
                    blockCard(entry, height: height, compact: laneWidth < 180)
                    .frame(width: laneWidth, height: height, alignment: .topLeading)
                    .modifier(CalendarEntryGesture(interaction: interaction) { point, resize, keepsTime in
                        drop(CalendarDrag(id: entry.id, source: .plan, resizing: resize, keepsTime: keepsTime), at: point)
                    })
                    .offset(
                        x: gridX + CGFloat(placement.lane) * (laneWidth + laneGap),
                        y: bounds.start
                    )
                }

                Rectangle().fill(theme.hairline)
                    .frame(width: 1, height: totalHeight)
                    .offset(x: doneX - Space.xxs / 2)
                    .allowsHitTesting(false)

                ForEach(Array(recorded.enumerated()), id: \.element.id) { index, item in
                    let lane = lanes[index]
                    let width = max(1, (gridWidth - CGFloat(lane.laneCount - 1) * Space.xxs) / CGFloat(lane.laneCount))
                    let bounds = cardBounds(start: item.start, end: item.end)
                    let height = bounds.end - bounds.start
                    doneCard(item, height: height)
                    .frame(width: width, height: height)
                    .modifier(CalendarEntryGesture(interaction: interaction) { point, resize, keepsTime in
                        drop(CalendarDrag(id: item.id, source: .actual, resizing: resize, keepsTime: keepsTime), at: point)
                    })
                    .offset(x: doneX + CGFloat(lane.lane) * (width + Space.xxs), y: bounds.start)
                }

                if let selection {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(theme.accent.opacity(0.22))
                        .overlay { RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(theme.accent) }
                        .overlay(alignment: .topLeading) {
                            Text("\(selection.interval.start.formatted(date: .omitted, time: .shortened)) – \(selection.interval.end.formatted(date: .omitted, time: .shortened))")
                                .font(.caption2.monospacedDigit()).padding(.horizontal, 4)
                                .background(theme.surfaceRaised, in: .rect(cornerRadius: Radius.sm))
                                .fixedSize()
                        }
                        .frame(width: gridWidth, height: selection.interval.duration / 3600 * hourHeight)
                        .offset(x: selection.column == .done ? doneX : gridX, y: offset(for: selection.interval.start))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                if Calendar.current.isDateInToday(day) {
                    nowLine(width: proxy.size.width)
                }
                if let draft {
                    InlineEntryEditor(seed: draft, compact: gridWidth < 235, title: draftTitle, error: draftError,
                                      save: onSaveDraft, cancel: onCancelDraft, options: onDraftOptions)
                        .frame(width: gridWidth)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { draftHeight = $0 }
                        .padding(.top, max(0, offset(for: draft.start)))
                        .padding(.leading, draft.column == .done ? doneX : gridX)
                        .id(draft.id)
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("anchor.day.grid")) } action: { gridFrame = $0 }
        }
        .frame(height: max(totalHeight, draft.map { offset(for: $0.start) + draftHeight } ?? 0))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("anchor.today.timetable")
    }

    private func drop(_ item: CalendarDrag, at location: CGPoint) {
        let point = CGPoint(x: location.x - gridFrame.minX, y: location.y - gridFrame.minY)
        let gridX = railWidth + traceWidth
        let doneX = gridX + (gridFrame.width - gridX + Space.xxs) / 2
        guard point.x >= gridX, point.x <= doneX + (doneX - gridX), point.y >= 0, point.y <= totalHeight else { return }
        let increment = Double(step.rawValue * 60)
        let offset = (point.y / hourHeight * 3600 / increment).rounded() * increment
        let limit = range.duration - (item.resizing ? 0 : increment)
        _ = onDropEntry(item, point.x < doneX ? .scheduled : .done, range.start.addingTimeInterval(min(limit, max(0, offset))))
    }

    private func offset(for date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(range.start) / 3600) * hourHeight
    }

    private func interval(for drag: DragGesture.Value) -> DateInterval {
        TimetableLayout.selection(from: drag.startLocation.y, to: drag.location.y, hourHeight: hourHeight, range: range, step: step)
    }

    private func selectionSurface(_ column: TimetableColumn) -> some View {
        #if os(macOS)
        let surface = Color.clear.contentShape(Rectangle())
        return surface.gesture(DragGesture(minimumDistance: 0)
            .updating($selection) { drag, selected, _ in selected = (interval(for: drag), column) }
            .onEnded { drag in onAddAt(interval(for: drag), abs(drag.translation.height) >= 3, column) })
        #else
        return TimetableTouchSurface { start, end in
            selection = (TimetableLayout.selection(from: start, to: end, hourHeight: hourHeight, range: range, step: step), column)
        } finish: { start, end, dragged in
            selection = nil
            onAddAt(TimetableLayout.selection(from: start, to: end, hourHeight: hourHeight, range: range, step: step), dragged, column)
        } cancel: {
            selection = nil
        }
        #endif
    }

    private func cardBounds(start: Date, end: Date) -> (start: Double, end: Double) {
        TimetableLayout.cardBounds(from: offset(for: start), to: offset(for: end), in: totalHeight)
    }

    private func hourMarks(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0...hourCount, id: \.self) { tick in
                let time = range.start.addingTimeInterval(Double(tick) * 3600)
                HStack(alignment: .center, spacing: Space.xxs) {
                    Text(time.formatted(.dateTime.hour()))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: railWidth - 4, alignment: .trailing)
                    Rectangle()
                        .fill(theme.hairline)
                        .frame(height: 1)
                }
                .frame(width: width, height: 1, alignment: .center)
                .background(alignment: .topLeading) {
                    let hour = Calendar.current.component(.hour, from: time)
                    if tick < hourCount && (hour < windowStartHour || hour >= windowEndHour) {
                        Rectangle().fill(theme.textPrimary.opacity(0.035))
                            .frame(width: max(0, width - railWidth), height: hourHeight)
                            .offset(x: railWidth)
                    }
                }
                .frame(height: tick < hourCount ? hourHeight : 1, alignment: .top)
                .id(time)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
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

    let interaction: CalendarEntryInteraction
    let entry: DayTimetable.Entry
    let height: CGFloat
    let compact: Bool
    let category: ActivityCategory
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

    private var actionsArrow: Edge {
        #if os(macOS)
        .trailing
        #else
        .top
        #endif
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: Space.xxs) {
                    CalendarCheckButton(block: block, data: actuals, rowHeight: height < 38 ? height : compact && height < 56 ? 18 : nil,
                                        showsLabel: !compact && height >= 38 && block.plannedEnd <= Date(), acceptsTap: { interaction.acceptsTap })
                    Button { if interaction.acceptsTap { showsActions = true } } label: {
                        Label(block.title, systemImage: category.calendarSymbol)
                            .font(height < 38 ? .caption2.weight(.semibold) : compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                            .foregroundStyle(Color.black.opacity(0.91))
                            .lineLimit(height < 56 ? 1 : 2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(actionLabel)
                    .accessibilityValue(category.rawValue.capitalized)
                    if !compact && height >= 38 { actionsButton }

                }
                if height >= (compact ? 38 : 56) {
                    let dateStyle: Date.FormatStyle.DateStyle = Calendar.current.isDate(block.plannedStart, inSameDayAs: block.plannedEnd) ? .omitted : .abbreviated
                    Text("\(category.rawValue.capitalized) · \(block.plannedStart.formatted(date: dateStyle, time: .shortened)) – \(block.plannedEnd.formatted(date: dateStyle, time: .shortened))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.black.opacity(0.76))
                        .lineLimit(1)
                }
                if height >= 92 {
                    metaLine
                }
            }
            .padding(.leading, Space.xs)
            .padding(.trailing, 2)
            .padding(.vertical, height < 56 ? 0 : Space.xxs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            Button { if interaction.acceptsTap { showsActions = true } } label: {
                RoundedRectangle(cornerRadius: Radius.sm).fill(category.calendarColor)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityHidden(true)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.sm)
                .strokeBorder(
                    entry.outcome != nil ? stateTint : entry.isCurrent || block.state == .inProgress ? theme.accent.opacity(0.4) : theme.hairline,
                    style: StrokeStyle(
                        lineWidth: entry.isCurrent || block.state == .inProgress ? 1.4 : 1,
                        dash: block.state == .skipped || block.state == .moved ? [4, 3] : []
                    )
                ).allowsHitTesting(false)
        }
        .help(category.rawValue.capitalized)
        .foregroundStyle(Color.black.opacity(0.91))
        .opacity(cardOpacity)
        .popover(isPresented: $showsActions, arrowEdge: actionsArrow) {
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
                    }
                    let recorded = actuals.recordedIDs.contains(block.id)
                    actionRow(recorded ? "Edit done entry" : "Mark as done", icon: "checkmark.square") {
                        choose { actuals.check(block) }
                    }.disabled(!actuals.available)
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
        Button { if interaction.acceptsTap { showsActions = true } } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(Color.black.opacity(0.72))
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
        .foregroundStyle(Color.black.opacity(0.76))
        .lineLimit(1)
    }

    @ViewBuilder
    private var secondaryChoices: some View {
        if block.state == .planned && !entry.hasDifferentActiveSession && entry.linkedSession?.isActive != true && !actuals.recordedIDs.contains(block.id) {
            TimelineView(.explicit([Date.distantPast, block.plannedEnd])) { _ in
                if Date() < block.plannedEnd {
                    actionRow("Start focus", icon: "play") { choose(onStart) }
                }
            }
        }
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
