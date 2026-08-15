import Foundation

/// Turns focus history into files you can open, mail, or hand to a model.
public struct ExportBuilder: Sendable {
    private let engine: AnalyticsEngine

    public init(calendar: Calendar = .current) {
        self.engine = AnalyticsEngine(calendar: calendar)
    }

    // MARK: - Workbook

    /// Six sheets: the raw rows first so nothing is hidden, then the rollups.
    public func workbook(from records: [SessionRecord], now: Date = Date()) -> Spreadsheet {
        Spreadsheet(sheets: [
            summarySheet(records, now: now),
            sessionsSheet(records),
            distractionsSheet(records),
            goalsSheet(records),
            distractionKindsSheet(records),
            dailySheet(records, now: now),
        ])
    }

    public func xlsxData(from records: [SessionRecord], now: Date = Date()) -> Data {
        workbook(from: records, now: now).xlsxData(modified: now)
    }

    private func summarySheet(_ records: [SessionRecord], now: Date) -> Spreadsheet.Sheet {
        let stats = engine.overview(records, now: now)
        let rows: [[Spreadsheet.Cell]] = [
            [.text("Sessions"), .integer(stats.sessionCount)],
            [.text("Completed"), .integer(stats.completedCount)],
            [.text("Abandoned"), .integer(stats.abandonedCount)],
            [.text("Completion rate"), .percent(stats.completionRate)],
            [.text("Focused hours"), .number(stats.focusedHours)],
            [.text("Median session (minutes)"), .number(stats.medianSessionSeconds / 60)],
            [.text("Interruptions"), .integer(stats.distractionCount)],
            [.text("Interruptions per focused hour"), .number(stats.interruptionsPerHour)],
            [.text("Recovered after parking"), .percent(stats.recoveryRate)],
            [.text("Current streak (days)"), .integer(stats.currentStreakDays)],
            [.text("Best streak (days)"), .integer(stats.bestStreakDays)],
            [.text("Exported"), .date(now)],
        ]
        return Spreadsheet.Sheet(
            name: "Summary",
            columns: [.init("Measure", width: 30), .init("Value", width: 18)],
            rows: rows
        )
    }

    private func sessionsSheet(_ records: [SessionRecord]) -> Spreadsheet.Sheet {
        let rows = records.map { record -> [Spreadsheet.Cell] in
            [
                .date(record.startedAt),
                record.endedAt.map(Spreadsheet.Cell.date) ?? .blank,
                .text(record.goalTitle.isEmpty ? "Unassigned" : record.goalTitle),
                .optionalText(record.goalTheme?.label),
                .text(record.intent),
                .number(Double(record.plannedSeconds) / 60),
                .number(record.focusedSeconds / 60),
                .text(record.state.rawValue),
                .optionalText(record.endReason?.label),
                .integer(record.distractions.count),
                .number(record.interruptionRate),
                .text(record.id.uuidString),
            ]
        }
        return Spreadsheet.Sheet(
            name: "Sessions",
            columns: [
                .init("Started", width: 20), .init("Ended", width: 20),
                .init("Goal", width: 28), .init("Theme", width: 16),
                .init("Intent", width: 34), .init("Planned (min)", width: 14),
                .init("Focused (min)", width: 14), .init("State", width: 12),
                .init("Outcome", width: 14), .init("Interruptions", width: 14),
                .init("Per focused hour", width: 17), .init("Session ID", width: 38),
            ],
            rows: rows
        )
    }

    private func distractionsSheet(_ records: [SessionRecord]) -> Spreadsheet.Sheet {
        let rows = records.flatMap { record in
            record.distractions.map { distraction -> [Spreadsheet.Cell] in
                [
                    .date(distraction.capturedAt),
                    .text(distraction.note),
                    .text(distraction.kind.label),
                    .text(distraction.origin.label),
                    .text(distraction.keywords.joined(separator: ", ")),
                    .text(record.goalTitle.isEmpty ? "Unassigned" : record.goalTitle),
                    .number(distraction.offsetSeconds / 60),
                    .text(distraction.didReturnToFocus ? "Returned" : "Broke the session"),
                    .text(distraction.isHandled ? "Handled" : "Open"),
                    .percent(distraction.confidence),
                ]
            }
        }
        return Spreadsheet.Sheet(
            name: "Distractions",
            columns: [
                .init("When", width: 20), .init("Note", width: 44),
                .init("Category", width: 18), .init("Origin", width: 16),
                .init("Keywords", width: 26), .init("Goal", width: 26),
                .init("Minutes into session", width: 20), .init("Outcome", width: 18),
                .init("Follow-up", width: 12), .init("Tag confidence", width: 15),
            ],
            rows: rows
        )
    }

    private func goalsSheet(_ records: [SessionRecord]) -> Spreadsheet.Sheet {
        let rows = engine.byGoal(records).map { stat -> [Spreadsheet.Cell] in
            [
                .text(stat.title),
                .optionalText(stat.theme?.label),
                .integer(stat.sessionCount),
                .number(stat.focusedHours),
                .integer(stat.completedCount),
                .integer(stat.distractionCount),
                .number(stat.interruptionsPerHour),
            ]
        }
        return Spreadsheet.Sheet(
            name: "By goal",
            columns: [
                .init("Goal", width: 32), .init("Theme", width: 16),
                .init("Sessions", width: 12), .init("Focused hours", width: 15),
                .init("Completed", width: 12), .init("Interruptions", width: 14),
                .init("Per focused hour", width: 17),
            ],
            rows: rows
        )
    }

    private func distractionKindsSheet(_ records: [SessionRecord]) -> Spreadsheet.Sheet {
        let rows = engine.byDistractionKind(records).map { stat -> [Spreadsheet.Cell] in
            [
                .text(stat.kind.label),
                .text(stat.origin.label),
                .integer(stat.count),
                .integer(stat.brokeSessionCount),
                .percent(stat.breakRate),
                .number(stat.medianOffsetSeconds / 60),
            ]
        }
        return Spreadsheet.Sheet(
            name: "By distraction",
            columns: [
                .init("Category", width: 22), .init("Origin", width: 16),
                .init("Times", width: 10), .init("Broke the session", width: 18),
                .init("Break rate", width: 13), .init("Median minutes in", width: 18),
            ],
            rows: rows
        )
    }

    private func dailySheet(_ records: [SessionRecord], now: Date) -> Spreadsheet.Sheet {
        let start = records.map(\.startedAt).min() ?? now
        let rows = engine.byDay(records, from: start, to: now).map { bucket -> [Spreadsheet.Cell] in
            [
                .date(bucket.day),
                .number(bucket.focusedSeconds / 3600),
                .integer(bucket.sessionCount),
                .integer(bucket.distractionCount),
            ]
        }
        return Spreadsheet.Sheet(
            name: "By day",
            columns: [
                .init("Day", width: 16), .init("Focused hours", width: 15),
                .init("Sessions", width: 12), .init("Interruptions", width: 14),
            ],
            rows: rows
        )
    }

    // MARK: - CSV

    public func sessionsCSV(from records: [SessionRecord]) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["started,ended,goal,theme,intent,planned_minutes,focused_minutes,state,outcome,interruptions,session_id"]
        for record in records {
            lines.append(Self.csvRow([
                formatter.string(from: record.startedAt),
                record.endedAt.map(formatter.string(from:)) ?? "",
                record.goalTitle,
                record.goalTheme?.rawValue ?? "",
                record.intent,
                String(format: "%.2f", Double(record.plannedSeconds) / 60),
                String(format: "%.2f", record.focusedSeconds / 60),
                record.state.rawValue,
                record.endReason?.rawValue ?? "",
                String(record.distractions.count),
                record.id.uuidString,
            ]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public func distractionsCSV(from records: [SessionRecord]) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["captured_at,note,category,origin,keywords,goal,minutes_into_session,returned_to_focus,handled,session_id"]
        for record in records {
            for distraction in record.distractions {
                lines.append(Self.csvRow([
                    formatter.string(from: distraction.capturedAt),
                    distraction.note,
                    distraction.kind.rawValue,
                    distraction.origin.rawValue,
                    distraction.keywords.joined(separator: " "),
                    record.goalTitle,
                    String(format: "%.2f", distraction.offsetSeconds / 60),
                    distraction.didReturnToFocus ? "true" : "false",
                    distraction.isHandled ? "true" : "false",
                    record.id.uuidString,
                ]))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// RFC 4180 quoting: wrap anything containing a comma, quote or newline, and
    /// double any embedded quotes. Distraction notes are free text, so this matters.
    static func csvRow(_ fields: [String]) -> String {
        fields.map { field in
            if field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
                return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return field
        }
        .joined(separator: ",")
    }

    // MARK: - JSON (what the MCP server and any other agent reads)

    public func jsonData(from records: [SessionRecord], now: Date = Date()) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(
            ExportBundle(
                exportedAt: now,
                overview: engine.overview(records, now: now),
                sessions: records
            )
        )
    }
}

public struct ExportBundle: Codable, Sendable {
    public var exportedAt: Date
    public var overview: AnalyticsEngine.Overview
    public var sessions: [SessionRecord]
}
