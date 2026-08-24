import Foundation

/// Turns focus history into files you can open, mail, or hand to a model.
public struct ExportBuilder: Sendable {
    private let engine: AnalyticsEngine

    public init(calendar: Calendar = .current) {
        self.engine = AnalyticsEngine(calendar: calendar)
    }

    // MARK: - Workbook

    /// Raw rows come first so nothing is hidden, followed by focus rollups.
    public func workbook(
        from records: [SessionRecord],
        plans: [PlanBlockRecord] = [],
        divergences: [DivergenceRecord] = [],
        now: Date = Date()
    ) -> Spreadsheet {
        Spreadsheet(sheets: [
            summarySheet(records, now: now),
            plansSheet(plans),
            divergencesSheet(divergences),
            sessionsSheet(records),
            distractionsSheet(records),
            goalsSheet(records),
            distractionKindsSheet(records),
            dailySheet(records, now: now),
        ])
    }

    public func xlsxData(
        from records: [SessionRecord],
        plans: [PlanBlockRecord] = [],
        divergences: [DivergenceRecord] = [],
        now: Date = Date()
    ) -> Data {
        workbook(from: records, plans: plans, divergences: divergences, now: now).xlsxData(modified: now)
    }

    private func plansSheet(_ records: [PlanBlockRecord]) -> Spreadsheet.Sheet {
        Spreadsheet.Sheet(
            name: "Day plan",
            columns: [
                .init("Planned start", width: 20), .init("Title", width: 34),
                .init("Kind", width: 14), .init("Flexibility", width: 14),
                .init("Planned (min)", width: 14), .init("Actual start", width: 20),
                .init("Actual end", width: 20), .init("State", width: 14),
                .init("Pattern", width: 20), .init("Direction", width: 20),
                .init("Block ID", width: 38), .init("Session ID", width: 38),
            ],
            rows: records.map { record in
                [
                    .date(record.plannedStart), .text(record.title), .text(record.kind.label),
                    .text(record.flexibility.label), .number(Double(record.plannedSeconds) / 60),
                    record.actualStartedAt.map(Spreadsheet.Cell.date) ?? .blank,
                    record.actualEndedAt.map(Spreadsheet.Cell.date) ?? .blank,
                    .text(record.state.rawValue), .optionalText(record.behaviorPattern?.label),
                    .optionalText(record.lifeDirection?.label), .text(record.id.uuidString),
                    .optionalText(record.sessionID?.uuidString),
                ]
            }
        )
    }

    private func divergencesSheet(_ records: [DivergenceRecord]) -> Spreadsheet.Sheet {
        Spreadsheet.Sheet(
            name: "Schedule changes",
            columns: [
                .init("When", width: 20), .init("Cause", width: 28),
                .init("Evidence", width: 22), .init("User confirmed", width: 16),
                .init("Note", width: 44), .init("Block ID", width: 38),
                .init("Session ID", width: 38), .init("Distraction ID", width: 38),
            ],
            rows: records.map { record in
                [
                    .date(record.occurredAt), .text(record.kind.label), .text(record.evidence.rawValue),
                    .text(record.userConfirmed ? "Yes" : "No"), .text(record.note),
                    .text(record.blockID.uuidString), .optionalText(record.sessionID?.uuidString),
                    .optionalText(record.distractionID?.uuidString),
                ]
            }
        )
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
                .text(record.projectTitle),
                .text(record.tags.joined(separator: ", ")),
                .text(record.notes),
                .number(record.hourlyRate),
                .text(record.currencyCode),
                .number(record.earnedAmount),
                .number(Double(record.plannedSeconds) / 60),
                .number(record.focusedSeconds / 60),
                .number(record.computerActiveSeconds / 60),
                .number(record.computerAwaySeconds / 60),
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
                .init("Intent", width: 34), .init("Project", width: 24),
                .init("Tags", width: 24), .init("Notes", width: 42),
                .init("Hourly rate", width: 14), .init("Currency", width: 11),
                .init("Tracked value", width: 15),
                .init("Planned (min)", width: 14),
                .init("Focused (min)", width: 14),
                .init("Computer active (min)", width: 21),
                .init("Computer away (min)", width: 20),
                .init("State", width: 12),
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
                    .text(distraction.tags.joined(separator: ", ")),
                    .text(record.goalTitle.isEmpty ? "Unassigned" : record.goalTitle),
                    .text(record.projectTitle),
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
                .init("Keywords", width: 26), .init("Tags", width: 24),
                .init("Goal", width: 26), .init("Project", width: 24),
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
        var lines = ["started,ended,goal,theme,intent,project,tags,notes,hourly_rate,currency,tracked_value,planned_minutes,focused_minutes,computer_active_minutes,computer_away_minutes,state,outcome,interruptions,session_id"]
        for record in records {
            lines.append(Self.csvRow([
                formatter.string(from: record.startedAt),
                record.endedAt.map(formatter.string(from:)) ?? "",
                record.goalTitle,
                record.goalTheme?.rawValue ?? "",
                record.intent,
                record.projectTitle,
                record.tags.joined(separator: " "),
                record.notes,
                String(format: "%.2f", record.hourlyRate),
                record.currencyCode,
                String(format: "%.2f", record.earnedAmount),
                String(format: "%.2f", Double(record.plannedSeconds) / 60),
                String(format: "%.2f", record.focusedSeconds / 60),
                String(format: "%.2f", record.computerActiveSeconds / 60),
                String(format: "%.2f", record.computerAwaySeconds / 60),
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
        var lines = ["captured_at,note,category,origin,keywords,tags,goal,project,minutes_into_session,returned_to_focus,handled,session_id"]
        for record in records {
            for distraction in record.distractions {
                lines.append(Self.csvRow([
                    formatter.string(from: distraction.capturedAt),
                    distraction.note,
                    distraction.kind.rawValue,
                    distraction.origin.rawValue,
                    distraction.keywords.joined(separator: " "),
                    distraction.tags.joined(separator: " "),
                    record.goalTitle,
                    record.projectTitle,
                    String(format: "%.2f", distraction.offsetSeconds / 60),
                    distraction.didReturnToFocus ? "true" : "false",
                    distraction.isHandled ? "true" : "false",
                    record.id.uuidString,
                ]))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public func plansCSV(from records: [PlanBlockRecord]) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["planned_start,title,kind,flexibility,planned_minutes,actual_start,actual_end,state,pattern,direction,block_id,session_id"]
        for record in records {
            lines.append(Self.csvRow([
                formatter.string(from: record.plannedStart), record.title, record.kind.rawValue,
                record.flexibility.rawValue, String(format: "%.2f", Double(record.plannedSeconds) / 60),
                record.actualStartedAt.map(formatter.string(from:)) ?? "",
                record.actualEndedAt.map(formatter.string(from:)) ?? "", record.state.rawValue,
                record.behaviorPattern?.rawValue ?? "", record.lifeDirection?.rawValue ?? "",
                record.id.uuidString, record.sessionID?.uuidString ?? "",
            ]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public func divergencesCSV(from records: [DivergenceRecord]) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["occurred_at,cause,evidence,user_confirmed,note,block_id,session_id,distraction_id"]
        for record in records {
            lines.append(Self.csvRow([
                formatter.string(from: record.occurredAt), record.kind.rawValue, record.evidence.rawValue,
                record.userConfirmed ? "true" : "false", record.note, record.blockID.uuidString,
                record.sessionID?.uuidString ?? "", record.distractionID?.uuidString ?? "",
            ]))
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

    public func jsonData(
        from records: [SessionRecord],
        plans: [PlanBlockRecord] = [],
        divergences: [DivergenceRecord] = [],
        profile: BehaviorProfileRecord = BehaviorProfileRecord(),
        now: Date = Date()
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(
            ExportBundle(
                exportedAt: now,
                overview: engine.overview(records, now: now),
                sessions: records,
                plans: plans,
                divergences: divergences,
                profile: profile
            )
        )
    }
}

public struct ExportBundle: Codable, Sendable {
    public var exportedAt: Date
    public var overview: AnalyticsEngine.Overview
    public var sessions: [SessionRecord]
    public var plans: [PlanBlockRecord]
    public var divergences: [DivergenceRecord]
    public var profile: BehaviorProfileRecord
}
