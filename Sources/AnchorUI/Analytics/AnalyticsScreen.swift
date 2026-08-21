// Mac and iPhone screens. The watch is a genuinely different shape — no
// file exporter, no pasteboard, no keyboard shortcuts — so it gets its own
// views in Watch/ rather than a pile of size guards in these.
#if !os(watchOS)
import AnchorCore
import Charts
import SwiftData
import SwiftUI

/// What the data says. Ordered by what you can act on: the headline numbers,
/// then what interrupts you, then when you're actually good at this, then which
/// work you protect.
public struct AnalyticsScreen: View {
    @Environment(\.anchorTheme) private var theme
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var sessions: [FocusSession]
    @Query(sort: \MachineActivityDay.day, order: .reverse) private var machineDays: [MachineActivityDay]

    @State private var range: Range = .month
    @State private var summary: String?
    @State private var isSummarising = false
    @State private var exporting: ExportFormat?

    public init() {}

    public enum Range: String, CaseIterable, Identifiable {
        case week, month, all
        public var id: String { rawValue }

        var label: String {
            switch self {
            case .week: "7 days"
            case .month: "30 days"
            case .all: "All time"
            }
        }

        var days: Int? {
            switch self {
            case .week: 7
            case .month: 30
            case .all: nil
            }
        }
    }

    private var engine: AnalyticsEngine { AnalyticsEngine() }

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var tileMinimumWidth: CGFloat { sizeClass == .compact ? 148 : 190 }
    #else
    private var tileMinimumWidth: CGFloat { 190 }
    #endif

    private var records: [SessionRecord] {
        let all = sessions.map { $0.snapshot() }
        guard let days = range.days,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        else { return all }
        return all.filter { $0.startedAt >= cutoff }
    }

    private var previousRecords: [SessionRecord] {
        guard let days = range.days,
              let currentStart = Calendar.current.date(byAdding: .day, value: -days, to: Date()),
              let previousStart = Calendar.current.date(byAdding: .day, value: -days, to: currentStart)
        else { return [] }
        return sessions.map { $0.snapshot() }.filter {
            $0.startedAt >= previousStart && $0.startedAt < currentStart
        }
    }

    private var machineRecords: [MachineActivityRecord] {
        let all = machineDays.map { $0.snapshot() }
        guard let days = range.days,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        else { return all }
        return all.filter { $0.day >= cutoff }
    }

    public var body: some View {
        ScrollView {
            let records = self.records
            let overview = engine.overview(records)

            VStack(alignment: .leading, spacing: Space.lg) {
                rangePicker

                if records.isEmpty {
                    EmptyStateView(
                        symbol: "chart.bar.doc.horizontal",
                        title: "Nothing to show yet",
                        message: "Run a focus session and this fills in — where your hours go, and what keeps taking them."
                    )
                } else {
                    tiles(overview)
                    periodComparison(records, previous: previousRecords)
                    machinePresenceCard(machineRecords)
                    billingCard(records)
                    summaryCard(records)
                    sessionPatterns(overview)
                    dailyChart(records)
                    workTable(
                        title: "Projects",
                        subtitle: "Time, completion, and interruption load",
                        stats: engine.byProject(records)
                    )
                    workTable(
                        title: "Tags",
                        subtitle: "Compare the contexts you chose across projects",
                        stats: engine.byTag(records)
                    )
                    distractionLeaderboard(records)
                    distractionTiming(records)
                    originSplit(records)
                    hourChart(records)
                    weekdayChart(records)
                    goalTable(records)
                    exportCard(records)
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .background(theme.canvas)
        .fileExporter(
            isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
            document: exporting.map { ExportDocument(data: $0.makeData(from: records), contentType: $0.contentType) },
            contentType: exporting?.contentType ?? .json,
            defaultFilename: exporting?.defaultFileName()
        ) { _ in
            exporting = nil
        }
    }

    private func periodComparison(_ records: [SessionRecord], previous: [SessionRecord]) -> some View {
        let current = engine.overview(records)
        let prior = engine.overview(previous)
        return Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader("Compared with the prior period", subtitle: range == .all ? "Choose 7 or 30 days to compare" : "Same-length period immediately before this one")
                if range == .all {
                    Text("Period comparison is available for 7- and 30-day views.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                } else if previous.isEmpty {
                    Text("No sessions in the prior period yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                } else {
                    comparisonRow("Focused time", current: current.focusedSeconds, previous: prior.focusedSeconds, format: Format.duration)
                    comparisonRow("Sessions", current: Double(current.sessionCount), previous: Double(prior.sessionCount)) { "\(Int($0.rounded()))" }
                    comparisonRow("Completion", current: current.completionRate, previous: prior.completionRate, format: Format.percent)
                    comparisonRow("Interruptions / hour", current: current.interruptionsPerHour, previous: prior.interruptionsPerHour) { String(format: "%.1f", $0) }
                }
            }
        }
    }

    private func comparisonRow(
        _ label: String,
        current: Double,
        previous: Double,
        format: (Double) -> String
    ) -> some View {
        let delta = previous == 0 ? nil : (current - previous) / abs(previous)
        return HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(theme.textSecondary)
            Spacer()
            Text(format(current))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
            Text(delta.map { String(format: "%+.0f%%", $0 * 100) } ?? "new")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textTertiary)
                .frame(width: 48, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func machinePresenceCard(_ records: [MachineActivityRecord]) -> some View {
        #if os(macOS)
        let presence = engine.machinePresence(records)
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader("Active versus logged", subtitle: "Keyboard/mouse presence only — no app or window tracking")
                if presence.activeSeconds < 1 {
                    Text("Anchor starts collecting privacy-safe activity totals while it runs in the menu bar.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                } else {
                    HStack(spacing: Space.lg) {
                        presenceMetric("Machine active", Format.duration(presence.activeSeconds), theme.textPrimary)
                        presenceMetric("Logged", Format.duration(presence.trackedSeconds), theme.positive)
                        presenceMetric("Untracked", Format.duration(presence.untrackedSeconds), theme.caution)
                    }
                    ProportionBar(fraction: presence.trackedRate, tint: theme.positive)
                    Text("\(Format.percent(presence.trackedRate)) of active computer time had a running Anchor session.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
        #endif
    }

    private func presenceMetric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.system(size: 10)).foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func billingCard(_ records: [SessionRecord]) -> some View {
        let totals = engine.billingTotals(records)
        return Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader("Tracked value", subtitle: "Focused time × the project rate preserved on each session")
                if totals.isEmpty {
                    Text("Set an hourly rate for a project in Settings to turn tracked time into billable value.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                } else {
                    ForEach(totals) { total in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Format.money(total.amount, currencyCode: total.currencyCode))
                                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                                    .foregroundStyle(theme.positive)
                                Text("\(Format.duration(total.billableSeconds)) across \(total.sessionCount) sessions")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.textTertiary)
                            }
                            Spacer()
                            Text(total.currencyCode)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private func sessionPatterns(_ overview: AnalyticsEngine.Overview) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader("Session depth", subtitle: "Whether the time was protected, not merely recorded")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: Space.sm)], spacing: Space.sm) {
                    presenceMetric("Uninterrupted", Format.percent(overview.uninterruptedRate), theme.positive)
                    presenceMetric("45m+ sessions", "\(overview.deepSessionCount)", theme.accent)
                    presenceMetric("Longest", Format.duration(overview.longestSessionSeconds), theme.textPrimary)
                    presenceMetric("Abandoned", "\(overview.abandonedCount)", theme.negative)
                }
            }
        }
    }

    // MARK: Range

    private var rangePicker: some View {
        HStack(spacing: Space.xs) {
            ForEach(Range.allCases) { option in
                Button {
                    withAnimation(Motion.snappy) {
                        range = option
                        summary = nil
                    }
                } label: {
                    Chip(option.label, isSelected: range == option)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: Headline

    private func tiles(_ overview: AnalyticsEngine.Overview) -> some View {
        // One minimum can't serve both: 190 gives three even columns at the Mac's
        // 820pt content cap, but on a phone it leaves room for only one, turning
        // six tiles into a full-screen-tall stack. Compact gets 148, which fits two.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: tileMinimumWidth), spacing: Space.sm)],
            spacing: Space.sm
        ) {
            StatTile(
                label: "Focused",
                value: Format.duration(overview.focusedSeconds),
                detail: "\(overview.sessionCount) sessions",
                symbol: "hourglass"
            )
            StatTile(
                label: "Completed",
                value: Format.percent(overview.completionRate),
                detail: "\(overview.completedCount) ran full length",
                symbol: "checkmark.seal",
                tint: theme.positive
            )
            StatTile(
                label: "Interruptions",
                value: String(format: "%.1f", overview.interruptionsPerHour),
                detail: "per focused hour · \(overview.distractionCount) total",
                symbol: "bolt.horizontal",
                tint: theme.caution
            )
            StatTile(
                label: "Recovered",
                value: Format.percent(overview.recoveryRate),
                detail: "parked, then kept going",
                symbol: "arrow.uturn.backward",
                tint: theme.accent
            )
            StatTile(
                label: "Streak",
                value: "\(overview.currentStreakDays)d",
                detail: "best \(overview.bestStreakDays)d",
                symbol: "flame"
            )
            StatTile(
                label: "Typical session",
                value: Format.duration(overview.medianSessionSeconds),
                detail: "median length",
                symbol: "timer"
            )
        }
    }

    /// On-device summary. Absent rather than fabricated when the model is unavailable.
    @ViewBuilder
    private func summaryCard(_ records: [SessionRecord]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Space.xs) {
                SectionHeader("In a sentence", subtitle: "Written on-device by Apple Intelligence")

                if let summary {
                    Text(summary)
                        .font(.system(size: 14))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if isSummarising {
                    HStack(spacing: Space.xs) {
                        ProgressView().controlSize(.small)
                        Text("Reading your \(range.label.lowercased())…")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.textSecondary)
                    }
                } else {
                    let availability = TaggingService.availability
                    if availability.isAvailable {
                        Button("Summarise this period") {
                            Task { await summarise(records) }
                        }
                        .buttonStyle(QuietButtonStyle(expands: false))
                    } else {
                        Text(availability.explanation)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func summarise(_ records: [SessionRecord]) async {
        isSummarising = true
        defer { isSummarising = false }
        summary = await TaggingService().summarise(engine.brief(records))
    }

    // MARK: Charts

    private func dailyChart(_ records: [SessionRecord]) -> some View {
        let start = Calendar.current.date(
            byAdding: .day,
            value: -((range.days ?? 30) - 1),
            to: Date()
        ) ?? Date()
        let buckets = engine.byDay(
            records,
            from: range.days == nil ? (records.map(\.startedAt).min() ?? Date()) : start,
            to: Date()
        )

        // Two units on one plot: hours as bars, interruption counts as a line.
        // Swift Charts has a single y-scale, so the line is mapped onto the hours
        // axis and the trailing axis is labelled with the inverse — which keeps
        // the shapes comparable without either series lying about its magnitude.
        let maxHours = max(0.5, buckets.map { $0.focusedSeconds / 3600 }.max() ?? 1)
        let maxBreaks = max(1, Double(buckets.map(\.distractionCount).max() ?? 1))
        let breakScale = maxHours / maxBreaks

        return Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader(
                    "Focus and interruptions by day",
                    subtitle: "Hours focused against the number of times you were pulled away"
                )
                Chart {
                    ForEach(buckets) { bucket in
                        BarMark(
                            x: .value("Day", bucket.day, unit: .day),
                            y: .value("Hours", bucket.focusedSeconds / 3600)
                        )
                        .foregroundStyle(theme.accent.gradient)
                        .cornerRadius(3)
                    }
                    ForEach(buckets) { bucket in
                        LineMark(
                            x: .value("Day", bucket.day, unit: .day),
                            y: .value("Interruptions", Double(bucket.distractionCount) * breakScale)
                        )
                        .foregroundStyle(theme.negative)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                        .symbol {
                            Circle()
                                .fill(theme.negative)
                                .frame(width: 5, height: 5)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(theme.hairline)
                        AxisValueLabel {
                            if let hours = value.as(Double.self) {
                                Text("\(Int(hours))h").foregroundStyle(theme.textTertiary)
                            }
                        }
                    }
                    AxisMarks(position: .trailing) { value in
                        AxisValueLabel {
                            if let scaled = value.as(Double.self) {
                                Text("\(Int((scaled / breakScale).rounded()))")
                                    .foregroundStyle(theme.negative.opacity(0.75))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .frame(height: 190)

                HStack(spacing: Space.md) {
                    legendDot(theme.accent, "Hours focused")
                    legendDot(theme.negative, "Interruptions")
                }
            }
        }
    }

    private func distractionLeaderboard(_ records: [SessionRecord]) -> some View {
        let stats = engine.byDistractionKind(records)
        let maximum = Double(stats.first?.count ?? 1)

        return Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader(
                    "What interrupts you",
                    subtitle: "Ranked by how often, marked by how often it wins"
                )
                if stats.isEmpty {
                    Text("No interruptions captured in this period.")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                } else {
                    ForEach(stats.prefix(8)) { stat in
                        HStack(spacing: Space.sm) {
                            KindGlyph(stat.kind, size: 30)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(stat.kind.label)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(theme.textPrimary)
                                    Spacer()
                                    Text("\(stat.count)")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(theme.textPrimary)
                                }
                                ProportionBar(
                                    fraction: Double(stat.count) / max(1, maximum),
                                    tint: theme.color(for: stat.kind)
                                )
                                HStack(spacing: Space.xs) {
                                    Text(stat.origin.label)
                                    if stat.brokeSessionCount > 0 {
                                        Text("· ended \(stat.brokeSessionCount) session\(stat.brokeSessionCount == 1 ? "" : "s")")
                                            .foregroundStyle(theme.negative)
                                    }
                                    Text("· typically \(Format.duration(stat.medianOffsetSeconds)) in")
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textTertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func originSplit(_ records: [SessionRecord]) -> some View {
        let split = engine.byOrigin(records)
        let total = max(1, split.reduce(0) { $0 + $1.count })

        return Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader(
                    "Where it comes from",
                    subtitle: "External is a settings problem. Internal is a habit."
                )
                if split.isEmpty {
                    Text("Nothing captured yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                } else {
                    // A single stacked bar reads faster than a pie for two or three parts.
                    GeometryReader { proxy in
                        HStack(spacing: 2) {
                            ForEach(split, id: \.origin) { entry in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(theme.color(for: entry.origin).gradient)
                                    .frame(width: max(4, proxy.size.width * Double(entry.count) / Double(total)))
                            }
                        }
                    }
                    .frame(height: 18)

                    FlowRow(spacing: Space.sm) {
                        ForEach(split, id: \.origin) { entry in
                            HStack(spacing: Space.xxs) {
                                Circle()
                                    .fill(theme.color(for: entry.origin))
                                    .frame(width: 7, height: 7)
                                Text("\(entry.origin.label) · \(Format.percent(Double(entry.count) / Double(total)))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.textSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func hourChart(_ records: [SessionRecord]) -> some View {
        let buckets = engine.byHour(records).filter { $0.focusedSeconds > 0 || $0.distractionCount > 0 }

        return Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader("When you focus", subtitle: "Hours focused against interruptions taken")
                if buckets.isEmpty {
                    Text("Not enough data yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                } else {
                    let maxHours = max(0.5, buckets.map { $0.focusedSeconds / 3600 }.max() ?? 1)
                    let maxBreaks = max(1, Double(buckets.map(\.distractionCount).max() ?? 1))
                    let breakScale = maxHours / maxBreaks

                    Chart {
                        ForEach(buckets) { bucket in
                            BarMark(
                                x: .value("Hour", bucket.hour),
                                y: .value("Hours focused", bucket.focusedSeconds / 3600)
                            )
                            .foregroundStyle(theme.accent.opacity(0.85))
                            .cornerRadius(3)
                        }
                        ForEach(buckets) { bucket in
                            LineMark(
                                x: .value("Hour", bucket.hour),
                                y: .value("Interruptions", Double(bucket.distractionCount) * breakScale)
                            )
                            .foregroundStyle(theme.negative)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)
                            .symbol {
                                Circle()
                                    .fill(theme.negative)
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(theme.hairline)
                            AxisValueLabel {
                                if let hours = value.as(Double.self) {
                                    Text("\(Int(hours))h").foregroundStyle(theme.textTertiary)
                                }
                            }
                        }
                        AxisMarks(position: .trailing) { value in
                            AxisValueLabel {
                                if let scaled = value.as(Double.self) {
                                    Text("\(Int((scaled / breakScale).rounded()))")
                                        .foregroundStyle(theme.negative.opacity(0.75))
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: 3)) { value in
                            AxisValueLabel {
                                if let hour = value.as(Int.self) {
                                    Text(Format.hour(hour)).foregroundStyle(theme.textTertiary)
                                }
                            }
                        }
                    }
                    .frame(height: 170)

                    HStack(spacing: Space.md) {
                        legendDot(theme.accent, "Focused hours")
                        legendDot(theme.negative, "Interruptions")
                    }
                }
            }
        }
    }

    private func weekdayChart(_ records: [SessionRecord]) -> some View {
        let buckets = engine.byWeekday(records)
        return Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader("Weekday rhythm", subtitle: "Which days reliably hold focused work")
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("Weekday", weekdayLabel(bucket.weekday)),
                        y: .value("Focused hours", bucket.focusedSeconds / 3600)
                    )
                    .foregroundStyle(theme.accent.gradient)
                    .cornerRadius(3)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(theme.hairline)
                        AxisValueLabel {
                            if let hours = value.as(Double.self) {
                                Text("\(Int(hours))h").foregroundStyle(theme.textTertiary)
                            }
                        }
                    }
                }
                .frame(height: 150)
            }
        }
    }

    private func weekdayLabel(_ weekday: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        guard symbols.indices.contains(weekday - 1) else { return "?" }
        return symbols[weekday - 1]
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: Space.xxs) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 11)).foregroundStyle(theme.textSecondary)
        }
    }

    private func goalTable(_ records: [SessionRecord]) -> some View {
        let goals = engine.byGoal(records).prefix(6)
        let maximum = goals.first?.focusedSeconds ?? 1

        return Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader("Where the hours went", subtitle: "Grouped by goal")
                ForEach(Array(goals.enumerated()), id: \.element.id) { index, stat in
                    HStack(spacing: Space.sm) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(stat.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(theme.textPrimary)
                                    .lineLimit(1)
                                if let theme = stat.theme {
                                    Chip(theme.label, symbol: theme.symbolName)
                                        .font(.system(size: 10))
                                }
                                Spacer()
                                Text(Format.duration(stat.focusedSeconds))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(theme.textPrimary)
                            }
                            ProportionBar(
                                fraction: stat.focusedSeconds / max(1, maximum),
                                tint: AnchorTheme.tint(index)
                            )
                            Text("\(stat.sessionCount) sessions · \(stat.distractionCount) interruptions")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                }
            }
        }
    }

    private func workTable(
        title: String,
        subtitle: String,
        stats: [AnalyticsEngine.WorkStat]
    ) -> some View {
        let shown = Array(stats.prefix(8))
        let maximum = shown.first?.focusedSeconds ?? 1
        return Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader(title, subtitle: subtitle)
                if shown.isEmpty {
                    Text("No \(title.lowercased()) used in this period.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                } else {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, stat in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(stat.label)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(theme.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text(Format.duration(stat.focusedSeconds))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(theme.textPrimary)
                            }
                            ProportionBar(
                                fraction: stat.focusedSeconds / max(1, maximum),
                                tint: AnchorTheme.tint(index)
                            )
                            Text(
                                "\(stat.sessionCount) sessions · \(Format.percent(stat.completionRate)) completed · \(String(format: "%.1f", stat.interruptionsPerHour))/h"
                            )
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textTertiary)
                        }
                    }
                }
            }
        }
    }

    private func distractionTiming(_ records: [SessionRecord]) -> some View {
        let phases = engine.distractionTiming(records)
        let maximum = max(1, phases.map(\.count).max() ?? 1)
        return Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader("When focus breaks", subtitle: "Early, middle, or final third of the planned session")
                HStack(alignment: .bottom, spacing: Space.sm) {
                    ForEach(phases) { phase in
                        VStack(spacing: Space.xxs) {
                            Text("\(phase.count)")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme.textPrimary)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(theme.caution.gradient)
                                .frame(height: max(6, 70 * Double(phase.count) / Double(maximum)))
                            Text(phase.phase.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(theme.textSecondary)
                            if phase.brokeSessionCount > 0 {
                                Text("\(phase.brokeSessionCount) ended")
                                    .font(.system(size: 9))
                                    .foregroundStyle(theme.negative)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func exportCard(_ records: [SessionRecord]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader(
                    "Export",
                    subtitle: "Or ask an AI directly — Anchor ships an MCP server"
                )
                FlowRow(spacing: Space.xs) {
                    ForEach(ExportFormat.allCases) { format in
                        Button {
                            exporting = format
                        } label: {
                            Chip(format.label, symbol: format.symbolName)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("The MCP server exposes your history to Codex and other clients, read-only and on this machine. Codex Computer History can add its own activity context without Anchor uploading raw activity.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
#endif
