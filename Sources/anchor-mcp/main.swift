import AnchorCore
import Foundation
import SwiftData

/// Anchor's MCP server: lets Codex (or any MCP client) ask questions about your
/// focus history in plain language, without you exporting anything first.
///
/// Transport is stdio with newline-delimited JSON-RPC 2.0, which is what MCP
/// stdio clients speak. The store is opened read-only-in-spirit: this process
/// never writes, so running it alongside the app is safe.
///
/// Register it with:
///   codex mcp add anchor -- /path/to/anchor-mcp

// MARK: - Store access

@MainActor
final class AnchorQueryService {
    private let context: ModelContext
    private let engine = AnalyticsEngine()
    private let builder = ExportBuilder()

    init() throws {
        // CloudKit is deliberately off here: this is a short-lived CLI process
        // with no entitlements, and it only needs to read the local file the
        // app already syncs.
        let container = try AnchorStore.makeContainer(kind: .localOnly)
        self.context = ModelContext(container)
    }

    func records(sinceDays days: Int?) throws -> [SessionRecord] {
        let since = days.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) }
        return try context.sessionRecords(since: since)
    }

    func overview(sinceDays days: Int?) throws -> [String: JSONValue] {
        let stats = engine.overview(try records(sinceDays: days))
        return [
            "sessions": .int(stats.sessionCount),
            "completed": .int(stats.completedCount),
            "abandoned": .int(stats.abandonedCount),
            "completionRate": .double(stats.completionRate),
            "focusedHours": .double(stats.focusedHours),
            "medianSessionMinutes": .double(stats.medianSessionSeconds / 60),
            "longestSessionMinutes": .double(stats.longestSessionSeconds / 60),
            "uninterruptedRate": .double(stats.uninterruptedRate),
            "deepSessionCount": .int(stats.deepSessionCount),
            "interruptions": .int(stats.distractionCount),
            "interruptionsPerFocusedHour": .double(stats.interruptionsPerHour),
            "recoveryRate": .double(stats.recoveryRate),
            "currentStreakDays": .int(stats.currentStreakDays),
            "bestStreakDays": .int(stats.bestStreakDays),
        ]
    }

    func sessions(sinceDays days: Int?, limit: Int) throws -> [JSONValue] {
        try records(sinceDays: days).prefix(limit).map { record in
            .object([
                "startedAt": .string(ISO8601DateFormatter().string(from: record.startedAt)),
                "goal": .string(record.goalTitle.isEmpty ? "Unassigned" : record.goalTitle),
                "theme": record.goalTheme.map { .string($0.label) } ?? .null,
                "intent": .string(record.intent),
                "project": record.projectTitle.isEmpty ? .null : .string(record.projectTitle),
                "notes": .string(record.notes),
                "tags": .array(record.tags.map(JSONValue.string)),
                "plannedMinutes": .double(Double(record.plannedSeconds) / 60),
                "focusedMinutes": .double(record.focusedMinutes),
                "hourlyRate": .double(record.hourlyRate),
                "currency": .string(record.currencyCode),
                "trackedValue": .double(record.earnedAmount),
                "computerActiveMinutes": .double(record.computerActiveSeconds / 60),
                "computerAwayMinutes": .double(record.computerAwaySeconds / 60),
                "outcome": record.endReason.map { .string($0.rawValue) } ?? .string(record.state.rawValue),
                "interruptions": .int(record.distractions.count),
                "interruptionNotes": .array(record.distractions.map { .string($0.note) }),
            ])
        }
    }

    func distractionPatterns(sinceDays days: Int?) throws -> [String: JSONValue] {
        let rows = try records(sinceDays: days)
        let kinds = engine.byDistractionKind(rows).map { stat in
            JSONValue.object([
                "category": .string(stat.kind.label),
                "origin": .string(stat.origin.label),
                "count": .int(stat.count),
                "brokeSession": .int(stat.brokeSessionCount),
                "breakRate": .double(stat.breakRate),
                "medianMinutesIntoSession": .double(stat.medianOffsetSeconds / 60),
            ])
        }
        let origins = engine.byOrigin(rows).map { origin, count in
            JSONValue.object(["origin": .string(origin.label), "count": .int(count)])
        }
        let recurring = engine.recurringDistractions(rows).prefix(15).map { label, count, kind in
            JSONValue.object([
                "keyword": .string(label),
                "count": .int(count),
                "category": .string(kind.label),
            ])
        }
        return [
            "byCategory": .array(kinds),
            "byOrigin": .array(origins),
            "recurringThemes": .array(Array(recurring)),
        ]
    }

    func goalProgress(sinceDays days: Int?) throws -> [JSONValue] {
        try engine.byGoal(records(sinceDays: days)).map { stat in
            .object([
                "goal": .string(stat.title),
                "theme": stat.theme.map { .string($0.label) } ?? .null,
                "sessions": .int(stat.sessionCount),
                "focusedHours": .double(stat.focusedHours),
                "completed": .int(stat.completedCount),
                "interruptions": .int(stat.distractionCount),
                "interruptionsPerFocusedHour": .double(stat.interruptionsPerHour),
            ])
        }
    }

    func bestHours(sinceDays days: Int?) throws -> [JSONValue] {
        try engine.byHour(records(sinceDays: days))
            .filter { $0.focusedSeconds > 0 || $0.distractionCount > 0 }
            .map { bucket in
                .object([
                    "hour": .int(bucket.hour),
                    "focusedHours": .double(bucket.focusedSeconds / 3600),
                    "interruptions": .int(bucket.distractionCount),
                ])
            }
    }

    func workPatterns(sinceDays days: Int?) throws -> [String: JSONValue] {
        let rows = try records(sinceDays: days)
        func encode(_ stats: [AnalyticsEngine.WorkStat]) -> JSONValue {
            .array(stats.map { stat in
                .object([
                    "name": .string(stat.label),
                    "sessions": .int(stat.sessionCount),
                    "focusedHours": .double(stat.focusedSeconds / 3600),
                    "completionRate": .double(stat.completionRate),
                    "interruptionsPerFocusedHour": .double(stat.interruptionsPerHour),
                ])
            })
        }
        let billing = engine.billingTotals(rows).map { total in
            JSONValue.object([
                "currency": .string(total.currencyCode),
                "amount": .double(total.amount),
                "billableHours": .double(total.billableSeconds / 3600),
                "sessions": .int(total.sessionCount),
            ])
        }
        let timing = engine.distractionTiming(rows).map { phase in
            JSONValue.object([
                "phase": .string(phase.phase.label),
                "count": .int(phase.count),
                "endedSessions": .int(phase.brokeSessionCount),
            ])
        }
        return [
            "projects": encode(engine.byProject(rows)),
            "tags": encode(engine.byTag(rows)),
            "billing": .array(billing),
            "distractionTiming": .array(timing),
        ]
    }

    func machinePresence(sinceDays days: Int?) throws -> [String: JSONValue] {
        let since = days.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) }
        var descriptor = FetchDescriptor<MachineActivityDay>(sortBy: [SortDescriptor(\.day, order: .reverse)])
        if let since { descriptor.predicate = #Predicate { $0.day >= since } }
        let presence = engine.machinePresence(try context.fetch(descriptor).map { $0.snapshot() })
        return [
            "machineActiveHours": .double(presence.activeSeconds / 3600),
            "loggedActiveHours": .double(presence.trackedSeconds / 3600),
            "untrackedActiveHours": .double(presence.untrackedSeconds / 3600),
            "loggedRate": .double(presence.trackedRate),
            "privacy": .string("Aggregate keyboard/mouse presence only; no apps, windows, websites, keys, or pointer locations."),
        ]
    }

    func searchDistractions(query: String, limit: Int) throws -> [JSONValue] {
        let needle = query.lowercased()
        return try records(sinceDays: nil)
            .flatMap { record in record.distractions.map { (record, $0) } }
            .filter { _, distraction in
                distraction.note.lowercased().contains(needle)
                    || distraction.keywords.contains { $0.contains(needle) }
                    || distraction.tags.contains { $0.lowercased().contains(needle) }
                    || distraction.kind.label.lowercased().contains(needle)
            }
            .prefix(limit)
            .map { record, distraction in
                .object([
                    "capturedAt": .string(ISO8601DateFormatter().string(from: distraction.capturedAt)),
                    "note": .string(distraction.note),
                    "category": .string(distraction.kind.label),
                    "goal": .string(record.goalTitle),
                    "project": record.projectTitle.isEmpty ? .null : .string(record.projectTitle),
                    "tags": .array(distraction.tags.map(JSONValue.string)),
                    "minutesIntoSession": .double(distraction.offsetSeconds / 60),
                    "returnedToFocus": .bool(distraction.didReturnToFocus),
                ])
            }
    }

    func exportJSON(sinceDays days: Int?) throws -> String {
        let data = try builder.jsonData(from: records(sinceDays: days))
        return String(decoding: data, as: UTF8.self)
    }

    func writeWorkbook(to path: String, sinceDays days: Int?) throws -> String {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let data = builder.xlsxData(from: try records(sinceDays: days))
        try data.write(to: url)
        return url.path
    }
}

// MARK: - Server

@MainActor
struct MCPServer {
    let service: AnchorQueryService?
    let startupError: String?

    init() {
        do {
            service = try AnchorQueryService()
            startupError = nil
        } catch {
            // Still serve: a client that connects should get a clear message
            // rather than a dead pipe.
            service = nil
            startupError = "Could not open the Anchor store: \(error.localizedDescription)"
        }
    }

    static let tools: [JSONValue] = [
        tool(
            "focus_overview",
            "Headline focus statistics: hours focused, sessions, completion rate, interruption rate, streaks.",
            ["since_days": intProperty("How many days back to look. Omit for all time.")]
        ),
        tool(
            "list_sessions",
            "Recent focus sessions with their goal, planned and actual length, outcome, and the interruptions captured during each.",
            [
                "since_days": intProperty("How many days back to look. Omit for all time."),
                "limit": intProperty("Maximum sessions to return. Defaults to 50."),
            ]
        ),
        tool(
            "distraction_patterns",
            "What interrupts this person most: counts by category, the internal/external split, how often each category ends a session, and recurring themes.",
            ["since_days": intProperty("How many days back to look. Omit for all time.")]
        ),
        tool(
            "goal_progress",
            "Time and interruptions per goal, so you can see which work is actually protected.",
            ["since_days": intProperty("How many days back to look. Omit for all time.")]
        ),
        tool(
            "best_hours",
            "Focused time and interruptions bucketed by hour of day.",
            ["since_days": intProperty("How many days back to look. Omit for all time.")]
        ),
        tool(
            "work_patterns",
            "Project and tag performance, billable value, and when distractions land within sessions.",
            ["since_days": intProperty("How many days back to look. Omit for all time.")]
        ),
        tool(
            "machine_presence",
            "Privacy-safe active, logged, and untracked computer time recorded by the Mac app.",
            ["since_days": intProperty("How many days back to look. Omit for all time.")]
        ),
        tool(
            "search_distractions",
            "Find captured distractions matching a word or phrase.",
            [
                "query": ["type": .string("string"), "description": .string("Text to search for in notes, keywords and categories.")],
                "limit": intProperty("Maximum results. Defaults to 25."),
            ],
            required: ["query"]
        ),
        tool(
            "export_workbook",
            "Write the full focus history to an .xlsx workbook at the given path and return the path.",
            [
                "path": ["type": .string("string"), "description": .string("Destination file path, e.g. ~/Desktop/anchor.xlsx")],
                "since_days": intProperty("How many days back to include. Omit for all time."),
            ],
            required: ["path"]
        ),
    ]

    static func intProperty(_ description: String) -> [String: JSONValue] {
        ["type": .string("integer"), "description": .string(description)]
    }

    static func tool(
        _ name: String,
        _ description: String,
        _ properties: [String: [String: JSONValue]],
        required: [String] = []
    ) -> JSONValue {
        .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": .object([
                "type": .string("object"),
                "properties": .object(properties.mapValues { JSONValue.object($0) }),
                "required": .array(required.map { .string($0) }),
            ]),
        ])
    }

    func handle(_ request: JSONValue) -> JSONValue? {
        guard case .object(let payload) = request else { return nil }
        let method = payload["method"]?.stringValue ?? ""
        let id = payload["id"]

        // Notifications carry no id and expect no reply.
        guard let id, id != .null else { return nil }

        switch method {
        case "initialize":
            let clientVersion = payload["params"]?["protocolVersion"]?.stringValue
            return success(id: id, result: .object([
                "protocolVersion": .string(clientVersion ?? "2025-06-18"),
                "capabilities": .object(["tools": .object([:])]),
                "serverInfo": .object([
                    "name": .string("anchor"),
                    "version": .string("1.0.0"),
                ]),
            ]))

        case "tools/list":
            return success(id: id, result: .object(["tools": .array(Self.tools)]))

        case "tools/call":
            return handleToolCall(id: id, params: payload["params"])

        case "ping":
            return success(id: id, result: .object([:]))

        default:
            return failure(id: id, code: -32601, message: "Unknown method: \(method)")
        }
    }

    private func handleToolCall(id: JSONValue, params: JSONValue?) -> JSONValue {
        guard let name = params?["name"]?.stringValue else {
            return failure(id: id, code: -32602, message: "Missing tool name")
        }
        guard let service else {
            return toolResult(id: id, text: startupError ?? "Anchor store unavailable.", isError: true)
        }

        let arguments = params?["arguments"]
        let sinceDays = arguments?["since_days"]?.intValue

        do {
            let payload: JSONValue
            switch name {
            case "focus_overview":
                payload = .object(try service.overview(sinceDays: sinceDays))
            case "list_sessions":
                payload = .array(try service.sessions(
                    sinceDays: sinceDays,
                    limit: arguments?["limit"]?.intValue ?? 50
                ))
            case "distraction_patterns":
                payload = .object(try service.distractionPatterns(sinceDays: sinceDays))
            case "goal_progress":
                payload = .array(try service.goalProgress(sinceDays: sinceDays))
            case "best_hours":
                payload = .array(try service.bestHours(sinceDays: sinceDays))
            case "work_patterns":
                payload = .object(try service.workPatterns(sinceDays: sinceDays))
            case "machine_presence":
                payload = .object(try service.machinePresence(sinceDays: sinceDays))
            case "search_distractions":
                guard let query = arguments?["query"]?.stringValue, !query.isEmpty else {
                    return toolResult(id: id, text: "search_distractions needs a query.", isError: true)
                }
                payload = .array(try service.searchDistractions(
                    query: query,
                    limit: arguments?["limit"]?.intValue ?? 25
                ))
            case "export_workbook":
                guard let path = arguments?["path"]?.stringValue, !path.isEmpty else {
                    return toolResult(id: id, text: "export_workbook needs a path.", isError: true)
                }
                let written = try service.writeWorkbook(to: path, sinceDays: sinceDays)
                payload = .object(["writtenTo": .string(written)])
            default:
                return failure(id: id, code: -32602, message: "Unknown tool: \(name)")
            }
            return toolResult(id: id, text: payload.encodedString(pretty: true), isError: false)
        } catch {
            return toolResult(id: id, text: "Anchor query failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func toolResult(id: JSONValue, text: String, isError: Bool) -> JSONValue {
        success(id: id, result: .object([
            "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
            "isError": .bool(isError),
        ]))
    }

    private func success(id: JSONValue, result: JSONValue) -> JSONValue {
        .object(["jsonrpc": .string("2.0"), "id": id, "result": result])
    }

    private func failure(id: JSONValue, code: Int, message: String) -> JSONValue {
        .object([
            "jsonrpc": .string("2.0"),
            "id": id,
            "error": .object(["code": .int(code), "message": .string(message)]),
        ])
    }
}

// MARK: - Entry point

/// `anchor-mcp --diagnose` reports whether Apple Intelligence is usable on this
/// machine and shows how a handful of sample notes actually get categorised.
/// Tagging quality is otherwise invisible until it has already mislabelled a
/// week of your data.
@MainActor
func runDiagnostics() async {
    let availability = TaggingService.availability
    print("Apple Intelligence: \(availability)")
    print(availability.explanation)
    print("Store: \(AnchorStore.storeURL().path)")
    print("")

    let cases: [(String, DistractionKind)] = [
        ("Slack from Ravi about the invoice", .message),
        ("Roommate walked in to chat", .person),
        ("Phone buzzed with a delivery alert", .notification),
        ("Opened Hacker News without thinking", .socialFeed),
        ("Ended up reading three Wikipedia pages on typography", .rabbitHole),
        ("Remembered I never replied to the landlord", .wanderingThought),
        ("Jumped over to fix an unrelated bug", .otherWork),
        ("Standup ran over", .meeting),
    ]
    let service = TaggingService()
    var correct = 0
    for (note, expected) in cases {
        let result = await service.classifyDistraction(note: note, duringGoal: "Ship the auth rewrite")
        let ok = result.kind == expected
        if ok { correct += 1 }
        print("\(ok ? "ok  " : "MISS") \(note)")
        print("     got \(result.kind.rawValue) (expected \(expected.rawValue)) via \(result.source.rawValue)")
    }
    print("\nDistractions: \(correct)/\(cases.count)")

    let goals: [(String, GoalTheme)] = [
        ("Finish the token refresh", .building),
        ("Draft the launch post", .writing),
        ("Study for the exam", .learning),
        ("Do my taxes", .admin),
    ]
    var goalsCorrect = 0
    for (title, expected) in goals {
        let result = await service.classifyGoal(title: title, notes: "")
        let ok = result.theme == expected
        if ok { goalsCorrect += 1 }
        print("\(ok ? "ok  " : "MISS") \(title) -> \(result.theme.rawValue) (expected \(expected.rawValue))")
    }
    print("Goals: \(goalsCorrect)/\(goals.count)")
}

/// The stdio loop. Blocking reads on the main actor are correct here: the
/// process exists only to answer one request at a time over a pipe.
@MainActor
func runServer() {
    let server = MCPServer()
    while let line = readLine(strippingNewline: true) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        guard let request = JSONValue(jsonString: trimmed) else {
            let error = JSONValue.object([
                "jsonrpc": .string("2.0"),
                "id": .null,
                "error": .object(["code": .int(-32700), "message": .string("Parse error")]),
            ])
            print(error.encodedString())
            fflush(stdout)
            continue
        }
        if let response = server.handle(request) {
            print(response.encodedString())
            fflush(stdout)
        }
    }
}

// MARK: - Entry point

if CommandLine.arguments.contains("--diagnose") {
    await runDiagnostics()
} else {
    runServer()
}
