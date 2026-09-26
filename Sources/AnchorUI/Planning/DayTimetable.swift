#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

/// Pure placement math for the day timetable, kept free of SwiftUI so the
/// overlap lanes and visible hour range stay unit-testable.
enum TimetableLayout {
    struct Placement: Sendable, Equatable {
        var lane: Int
        var laneCount: Int
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
        if calendar.isDateInToday(day) {
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
    }

    @Environment(\.anchorTheme) private var theme

    let day: Date
    let entries: [Entry]
    var hourHeight: CGFloat = 56
    var windowStartHour: Int = 7
    var windowEndHour: Int = 22
    var showsLivedTrace: Bool = true
    var dimsFinished: Bool = true
    var onStart: (PlanBlock) -> Void = { _ in }
    var onOpenFocus: () -> Void = {}
    var onComplete: (PlanBlock) -> Void = { _ in }
    var onEdit: (PlanBlock) -> Void = { _ in }
    var onExplain: (PlanBlock) -> Void = { _ in }
    var onLogActual: (PlanBlock) -> Void = { _ in }
    var onAddAt: (Date) -> Void = { _ in }

    static let nowAnchorID = "anchor.timetable.now"

    private let railWidth: CGFloat = 50
    private let minCardHeight: CGFloat = 40
    private var traceWidth: CGFloat { showsLivedTrace ? 12 : 0 }

    /// Seconds a card occupies for lane packing: its rendered height, which is
    /// at least `minCardHeight` (+padding) regardless of the clock-time span.
    private var minCollisionSpan: TimeInterval {
        (minCardHeight + 4) / hourHeight * 3600
    }

    private var range: DateInterval {
        TimetableLayout.displayRange(
            for: day,
            intervals: entries.map { entry in
                let start = entry.block.plannedStart.timeIntervalSince(Calendar.current.startOfDay(for: day))
                return (start, start + Double(entry.block.plannedSeconds))
            },
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
            entries.map { entry in
                let start = entry.block.plannedStart.timeIntervalSince(range.start)
                return (start, start + Double(entry.block.plannedSeconds))
            },
            minSpan: minCollisionSpan
        )
        var result: [UUID: TimetableLayout.Placement] = [:]
        for (index, entry) in entries.enumerated() {
            result[entry.id] = placed[index]
        }
        return result
    }

    var body: some View {
        GeometryReader { proxy in
            let gridX = railWidth + traceWidth
            let gridWidth = max(120, proxy.size.width - gridX - Space.xxs)
            ZStack(alignment: .topLeading) {
                hourMarks(width: proxy.size.width)

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        onAddAt(date(forYOffset: location.y))
                    }
                    .frame(width: gridWidth, height: totalHeight)
                    .offset(x: gridX)
                    // Deliberately not an accessibility element: a full-grid
                    // overlay swallows hit-tests for the block cards beneath
                    // it. Tap-to-add stays mouse/trackpad-only; explicit Add
                    // controls cover everyone else.
                    .accessibilityHidden(true)

                if showsLivedTrace {
                    livedTraces
                }

                ForEach(entries) { entry in
                    let placement = placements[entry.id] ?? TimetableLayout.Placement(lane: 0, laneCount: 1)
                    let laneGap = Space.xxs
                    let laneWidth = (gridWidth - CGFloat(placement.laneCount - 1) * laneGap) / CGFloat(placement.laneCount)
                    TimetableBlockCard(
                        entry: entry,
                        height: cardHeight(for: entry),
                        dimsFinished: dimsFinished,
                        onStart: { onStart(entry.block) },
                        onOpenFocus: onOpenFocus,
                        onComplete: { onComplete(entry.block) },
                        onEdit: { onEdit(entry.block) },
                        onExplain: { onExplain(entry.block) },
                        onLogActual: { onLogActual(entry.block) }
                    )
                    .frame(width: laneWidth, height: cardHeight(for: entry), alignment: .topLeading)
                    .offset(
                        x: gridX + CGFloat(placement.lane) * (laneWidth + laneGap),
                        y: cardTop(for: entry)
                    )
                }

                if Calendar.current.isDateInToday(day) {
                    Color.clear
                        .frame(height: 1)
                        .id(Self.nowAnchorID)
                        .offset(y: max(0, offset(for: Date()) - hourHeight))
                        .allowsHitTesting(false)
                    nowLine(width: proxy.size.width)
                }
            }
        }
        .frame(height: totalHeight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("anchor.today.timetable")
    }

    private func offset(for date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(range.start) / 3600) * hourHeight
    }

    private func date(forYOffset y: CGFloat) -> Date {
        let snapped = (y / hourHeight * 3600 / 900).rounded() * 900
        return range.start.addingTimeInterval(snapped)
    }

    private func cardTop(for entry: Entry) -> CGFloat {
        max(0, offset(for: entry.block.plannedStart)) + 2
    }

    private func cardHeight(for entry: Entry) -> CGFloat {
        let span = Double(entry.block.plannedSeconds) / 3600 * hourHeight
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
        ForEach(entries.filter { $0.block.actualStartedAt != nil }) { entry in
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

    let entry: DayTimetable.Entry
    let height: CGFloat
    var dimsFinished: Bool = true
    let onStart: () -> Void
    let onOpenFocus: () -> Void
    let onComplete: () -> Void
    let onEdit: () -> Void
    let onExplain: () -> Void
    let onLogActual: () -> Void

    private var block: PlanBlock { entry.block }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(stateTint)
                .frame(width: 3)
                .padding(.vertical, 5)
                .padding(.leading, 5)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top, spacing: Space.xxs) {
                    Text(block.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(height < 58 ? 1 : 2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    actionsButton
                }
                if height >= 56 {
                    Text("\(block.plannedStart.formatted(date: .omitted, time: .shortened)) – \(block.plannedEnd.formatted(date: .omitted, time: .shortened))")
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
        .background(cardFill, in: .rect(cornerRadius: Radius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.sm)
                .strokeBorder(
                    entry.isCurrent || block.state == .inProgress ? theme.accent.opacity(0.4) : theme.hairline,
                    style: StrokeStyle(
                        lineWidth: entry.isCurrent || block.state == .inProgress ? 1.4 : 1,
                        dash: block.state == .skipped || block.state == .moved ? [4, 3] : []
                    )
                )
        }
        .opacity(cardOpacity)
        .contentShape(Rectangle())
        .onTapGesture { showsActions = true }
        #if os(macOS)
        .popover(isPresented: $showsActions, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                actionChoices
            }
            .padding(Space.xs)
            .frame(minWidth: 200)
            .anchorTheme()
        }
        #else
        .confirmationDialog(
            block.title,
            isPresented: $showsActions,
            titleVisibility: .visible
        ) {
            actionChoices
        }
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("anchor.today.block.\(block.id.uuidString)")
    }

    @ViewBuilder
    private var actionsButton: some View {
        #if os(macOS)
        Button { showsActions.toggle() } label: {
            Label(actionLabel, systemImage: stateSymbol)
                .labelStyle(.iconOnly)
                .font(.body)
                .foregroundStyle(stateTint)
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(actionLabel)
        .accessibilityIdentifier("anchor.today.block-actions")
        #else
        Menu {
            actionChoices
        } label: {
            Label(actionLabel, systemImage: stateSymbol)
                .labelStyle(.iconOnly)
                .font(.body)
                .foregroundStyle(stateTint)
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .accessibilityLabel(actionLabel)
        .accessibilityIdentifier("anchor.today.block-actions")
        #endif
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
                Label("Recurring", systemImage: "repeat")
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
    private var actionChoices: some View {
        if entry.linkedSession?.isActive == true {
            Button("Open timer") { choose(onOpenFocus) }
        } else {
            switch block.state {
            case .planned:
                if !entry.hasDifferentActiveSession {
                    Button("Start now") { choose(onStart) }
                }
                Button("Edit or move") { choose(onEdit) }
                Button("Finished without timing") { choose(onComplete) }
                Button("Log actual time…") { choose(onLogActual) }
            case .inProgress:
                Button("Finish now") { choose(onComplete) }
                Button("Log actual time…") { choose(onLogActual) }
            case .completed, .skipped, .moved:
                Button("Edit or move") { choose(onEdit) }
                Button("Log actual time…") { choose(onLogActual) }
            }
        }
        Button("Explain a change") { choose(onExplain) }
    }

    private func choose(_ action: () -> Void) {
        showsActions = false
        action()
    }

    private var stateSymbol: String {
        if entry.linkedSession?.isActive == true { return "timer" }
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
        if entry.hasDifferentActiveSession { return "Actions for \(block.title); another session is active" }
        if entry.linkedSession?.isActive == true { return "Open timer for \(block.title)" }
        return "Actions for \(block.title)"
    }
}
#endif
