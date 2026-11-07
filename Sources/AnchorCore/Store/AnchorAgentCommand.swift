#if !os(watchOS)
import Foundation
import Darwin
import PersonalSyncKit
import SwiftData

struct AnchorAgentCommand: Codable, Equatable {
    enum Action: String, Codable {
        case start = "start_focus", pause = "pause_focus", resume = "resume_focus", end = "end_focus", capture = "capture_distraction"
        case copyDay = "copy_day", materializeDay = "materialize_day", reconcileTemplate = "reconcile_template"
        var isPlanner: Bool { self == .copyDay || self == .materializeDay || self == .reconcileTemplate }
    }
    enum Status: String, Codable { case pending, applied, failed }
    struct Arguments: Codable, Equatable {
        var intent: String?
        var minutes: Int?
        var goalID: UUID?
        var projectID: UUID?
        var planBlockID: UUID?
        var notes: String?
        var tagIDStrings: [String]?
        var reason: String?
        var sourceDay: Date?
        var targetDay: Date?
        var day: Date?
        var timeZone: String?
        var templateID: UUID?
        var from: Date?
    }
    struct Result: Codable, Equatable {
        var sessionID: UUID?
        var state: String
        var capturePresented: Bool
        var affectedRecordIDs: [UUID]?
        var affectedRecordCount: Int?
        enum CodingKeys: String, CodingKey { case sessionID, state, capturePresented, affectedRecordIDs, affectedRecordCount }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(sessionID, forKey: .sessionID)
            try c.encode(state, forKey: .state)
            try c.encode(capturePresented, forKey: .capturePresented)
            try c.encodeIfPresent(affectedRecordIDs, forKey: .affectedRecordIDs)
            try c.encodeIfPresent(affectedRecordCount, forKey: .affectedRecordCount)
        }
    }
    var recordType = "agentCommand"
    var id: UUID
    var requestId: String
    var action: Action
    var targetDeviceId: String
    var issuedAt: Date
    var expiresAt: Date
    var expectedSessionID: UUID?
    var status: Status
    var args: Arguments
    var result: Result?
    var error: String?
    var recordName: String { "agentcommand-" + id.uuidString.lowercased() }

    enum CodingKeys: String, CodingKey {
        case recordType, id, requestId, action, targetDeviceId, issuedAt, expiresAt, expectedSessionID, status, args, result, error
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(recordType, forKey: .recordType)
        try c.encode(id, forKey: .id)
        try c.encode(requestId, forKey: .requestId)
        try c.encode(action, forKey: .action)
        try c.encode(targetDeviceId, forKey: .targetDeviceId)
        try c.encode(issuedAt, forKey: .issuedAt)
        try c.encode(expiresAt, forKey: .expiresAt)
        try c.encode(expectedSessionID, forKey: .expectedSessionID)
        try c.encode(status, forKey: .status)
        try c.encode(args, forKey: .args)
        try c.encode(result, forKey: .result)
        try c.encode(error, forKey: .error)
    }

    static var encoder: JSONEncoder {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: date))
        }
        value.outputFormatting = [.sortedKeys]
        return value
    }
    static var decoder: JSONDecoder {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an ISO8601 timestamp")
        }
        return value
    }

    static func decode(_ record: MirrorRecord) throws -> Self {
        guard let data = record.payload,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arguments = json["args"] as? [String: Any] else { throw AnchorMirrorSyncError.invalidRecord }
        let value = try decoder.decode(Self.self, from: data)
        let allowed: Set<String>
        switch value.action {
        case .start: allowed = ["intent", "minutes", "goalID", "projectID", "planBlockID", "notes", "tagIDStrings"]
        case .end: allowed = ["reason"]
        case .copyDay: allowed = ["sourceDay", "targetDay", "timeZone"]
        case .materializeDay: allowed = ["day", "timeZone"]
        case .reconcileTemplate: allowed = ["templateID", "from", "timeZone"]
        default: allowed = []
        }
        guard value.recordType == "agentCommand", value.recordName == record.name,
              !value.requestId.isEmpty, value.requestId.count <= 200,
              !value.targetDeviceId.isEmpty, value.targetDeviceId.count <= 128,
              Set(arguments.keys).isSubset(of: allowed),
              value.expiresAt > value.issuedAt,
              value.expiresAt.timeIntervalSince(value.issuedAt) <= 900 else { throw AnchorMirrorSyncError.invalidRecord }
        if value.action == .start {
            guard value.expectedSessionID == nil,
                  let intent = value.args.intent, !intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, intent.count <= 240,
                  let minutes = value.args.minutes, (0...1440).contains(minutes),
                  (value.args.notes?.count ?? 0) <= 10_000,
                  (value.args.tagIDStrings?.count ?? 0) <= 50,
                  (value.args.tagIDStrings ?? []).allSatisfy({ UUID(uuidString: $0) != nil }) else { throw AnchorMirrorSyncError.invalidRecord }
        } else if value.action.isPlanner {
            guard value.expectedSessionID == nil, let zone = value.args.timeZone, TimeZone(identifier: zone) != nil else { throw AnchorMirrorSyncError.invalidRecord }
            switch value.action {
            case .copyDay: guard value.args.sourceDay != nil, value.args.targetDay != nil else { throw AnchorMirrorSyncError.invalidRecord }
            case .materializeDay: guard value.args.day != nil else { throw AnchorMirrorSyncError.invalidRecord }
            case .reconcileTemplate: guard value.args.templateID != nil, value.args.from != nil else { throw AnchorMirrorSyncError.invalidRecord }
            default: break
            }
        } else if value.expectedSessionID == nil { throw AnchorMirrorSyncError.invalidRecord }
        if let reason = value.args.reason, SessionEndReason(rawValue: reason) == nil { throw AnchorMirrorSyncError.invalidRecord }
        return value
    }
}

struct AnchorAgentDevice: Encodable {
    struct Session: Encodable {
        var id: UUID
        var intent: String
        var goalID: UUID?
        var projectID: UUID?
        var plannedSeconds: Int
        var startedAt: Date
        var bankedSeconds: Double
        var runningSince: Date?
        var state: String
        enum CodingKeys: String, CodingKey { case id, intent, goalID, projectID, plannedSeconds, startedAt, bankedSeconds, runningSince, state }
        init(_ value: FocusSession) {
            id = value.id; intent = value.intent; goalID = value.goal?.id; projectID = value.project?.id
            plannedSeconds = value.plannedSeconds; startedAt = value.startedAt; bankedSeconds = value.bankedSeconds
            runningSince = value.runningSince; state = value.stateRaw
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id); try c.encode(intent, forKey: .intent)
            try c.encode(goalID, forKey: .goalID); try c.encode(projectID, forKey: .projectID)
            try c.encode(plannedSeconds, forKey: .plannedSeconds); try c.encode(startedAt, forKey: .startedAt)
            try c.encode(bankedSeconds, forKey: .bankedSeconds); try c.encode(runningSince, forKey: .runningSince)
            try c.encode(state, forKey: .state)
        }
    }
    var recordType = "agentDevice"
    var id: UUID
    var deviceId: String
    var platform: String
    var updatedAt: Date
    var observedAt: Date
    var session: Session?
    var activeSessionID: UUID?
    var state: String
    var capturePresented: Bool
    var capabilities = ["start_focus", "pause_focus", "resume_focus", "end_focus", "capture_distraction", "copy_day", "materialize_day", "reconcile_template"]
    enum CodingKeys: String, CodingKey { case recordType, id, deviceId, platform, updatedAt, observedAt, session, activeSessionID, state, capturePresented, capabilities }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(recordType, forKey: .recordType); try c.encode(id, forKey: .id)
        try c.encode(deviceId, forKey: .deviceId); try c.encode(platform, forKey: .platform)
        try c.encode(updatedAt, forKey: .updatedAt); try c.encode(observedAt, forKey: .observedAt)
        try c.encode(session, forKey: .session); try c.encode(activeSessionID, forKey: .activeSessionID)
        try c.encode(state, forKey: .state); try c.encode(capturePresented, forKey: .capturePresented)
        try c.encode(capabilities, forKey: .capabilities)
    }
}

/// Terminal failure is written BEFORE side effects. If the process crashes, retry
/// reports indeterminate failure instead of executing an action a second time.
struct AnchorAgentCommandStore {
    struct State: Codable {
        var owner: String
        var commands: [String: AnchorAgentCommand] = [:]
        /// Fixed reason codes keyed by validated UUID only. Never retain rejected payloads.
        var quarantinedIDs: [String: String]?
    }
    let fileURL: URL
    init(directory: URL) { fileURL = directory.appending(path: "anchor-agent-command-receipts.json") }
    func load(owner: String) throws -> State {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return State(owner: owner) }
        let state = try AnchorAgentCommand.decoder.decode(State.self, from: Data(contentsOf: fileURL))
        guard state.owner == owner else { throw HubHistoryOwnershipError.differentAccount }
        return state
    }
    func save(_ state: State) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try AnchorAgentCommand.encoder.encode(state).write(to: fileURL, options: .atomic)
    }
    private func withExclusiveAccess<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(fileURL.appendingPathExtension("lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw CocoaError(.fileLocking) }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try body()
    }
    private static func matchesDevice(_ left: String, _ right: String) -> Bool {
        if let leftID = UUID(uuidString: left), let rightID = UUID(uuidString: right) { return leftID == rightID }
        return left == right
    }
    func ingest(_ records: [MirrorRecord], owner: String, deviceID: String) throws {
        try withExclusiveAccess { try ingestUnlocked(records, owner: owner, deviceID: deviceID) }
    }
    private func ingestUnlocked(_ records: [MirrorRecord], owner: String, deviceID: String) throws {
        var state = try load(owner: owner)
        for record in records where record.name.hasPrefix("agentcommand-") {
            if let recordOwner = record.hubOwnerID, recordOwner != owner { throw HubHistoryOwnershipError.differentAccount }
            // Tombstones and records for another/native-newer device are not
            // executable work here. Probe routing before strict action decoding.
            guard let payload = record.payload else { continue }
            let json = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any]
            guard let target = json?["targetDeviceId"] as? String, Self.matchesDevice(target, deviceID),
                  json?["status"] as? String == "pending" else { continue }
            var command: AnchorAgentCommand
            do { command = try AnchorAgentCommand.decode(record) }
            catch {
                if let id = UUID(uuidString: String(record.name.dropFirst("agentcommand-".count))) {
                    state.quarantinedIDs = state.quarantinedIDs ?? [:]
                    state.quarantinedIDs?[id.uuidString] = "unsupportedOrMalformed"
                }
                continue
            }
            command.targetDeviceId = deviceID
            command.result = nil
            command.error = nil
            guard state.commands[command.id.uuidString] == nil else { continue }
            // requestId is also idempotent within this account/device.
            if state.commands.values.contains(where: { $0.requestId == command.requestId }) {
                command.status = .failed
                command.error = "A command with this request identifier was already received."
            }
            state.commands[command.id.uuidString] = command
        }
        try save(state)
    }
    func records(owner: String, now: Date = .now) throws -> [MirrorRecord] {
        try load(owner: owner).commands.values.map { command in
            MirrorRecord(name: command.recordName, modifiedAt: now, payload: try AnchorAgentCommand.encoder.encode(command), hubOwnerID: owner)
        }
    }

    @MainActor
    func reconcile(owner: String, deviceID: String, controller: FocusController, context: ModelContext,
                   approvedPlannerNames: Set<String>, consentEnabledAt: Date? = nil, now: Date = .now) throws {
        try withExclusiveAccess {
            try reconcileUnlocked(owner: owner, deviceID: deviceID, controller: controller, context: context,
                                  approvedPlannerNames: approvedPlannerNames, consentEnabledAt: consentEnabledAt, now: now)
        }
    }
    @MainActor
    private func reconcileUnlocked(owner: String, deviceID: String, controller: FocusController, context: ModelContext,
                                   approvedPlannerNames: Set<String>, consentEnabledAt: Date?, now: Date) throws {
        var state = try load(owner: owner)
        for original in state.commands.values.sorted(by: { $0.issuedAt < $1.issuedAt }) where original.status == .pending {
            guard Self.matchesDevice(original.targetDeviceId, deviceID) else { continue }
            var command = original
            command.status = .failed
            command.error = "Execution was interrupted or could not be durably confirmed; this request will not be replayed."
            state.commands[command.id.uuidString] = command
            try save(state)
            var plannerDidBeginMutation = false
            do {
                guard command.expiresAt > now, command.issuedAt <= now.addingTimeInterval(30) else { throw CommandFailure.expired }
                if let consentEnabledAt, command.issuedAt < consentEnabledAt { throw CommandFailure.consent }
                guard !context.hasChanges else { throw CommandFailure.unsaved }
                var affectedRecordIDs: [UUID]?
                if command.action.isPlanner {
                    guard controller.session == nil else { throw CommandFailure.state }
                    plannerDidBeginMutation = true
                    var calendar = Calendar(identifier: .gregorian)
                    calendar.timeZone = TimeZone(identifier: command.args.timeZone!)!
                    let service = DayPlanService(context: context, calendar: calendar)
                    let blocks = try context.fetch(FetchDescriptor<PlanBlock>())
                    let beforeIDs = Set(blocks.map(\.id))
                    func approvedBlock(_ value: PlanBlock) -> Bool { approvedPlannerNames.contains(AnchorMirrorNaming.Kind.planBlock.name(for: value.id)) }
                    switch command.action {
                    case .copyDay:
                        guard blocks.filter({ calendar.isDate($0.plannedStart, inSameDayAs: command.args.sourceDay!) }).allSatisfy(approvedBlock) else { throw CommandFailure.reference }
                        _ = try service.copyDay(from: command.args.sourceDay!, to: command.args.targetDay!)
                    case .materializeDay:
                        let templates = try context.fetch(FetchDescriptor<ScheduleTemplate>()).filter { !$0.isBehaviorHabit && $0.applies(to: command.args.day!, calendar: calendar) }
                        guard templates.allSatisfy({ approvedPlannerNames.contains(AnchorMirrorNaming.Kind.scheduleTemplate.name(for: $0.id)) }) else { throw CommandFailure.reference }
                        _ = try service.materialize(day: command.args.day!)
                    case .reconcileTemplate:
                        guard let template = try context.fetch(FetchDescriptor<ScheduleTemplate>()).first(where: { $0.id == command.args.templateID }),
                              approvedPlannerNames.contains(AnchorMirrorNaming.Kind.scheduleTemplate.name(for: template.id)),
                              blocks.filter({ $0.templateID == template.id && $0.state == .planned && !$0.isTemplateOverride && ($0.templateOccurrenceDay ?? $0.plannedStart) >= calendar.startOfDay(for: command.args.from!) }).allSatisfy(approvedBlock) else { throw CommandFailure.reference }
                        affectedRecordIDs = blocks.filter {
                            $0.templateID == template.id && $0.state == .planned && !$0.isTemplateOverride
                                && ($0.templateOccurrenceDay ?? $0.plannedStart) >= calendar.startOfDay(for: command.args.from!)
                                && approvedBlock($0)
                        }.map(\.id)
                        try service.reconcileFutureBlocks(for: template, from: command.args.from!)
                    default: break
                    }
                    if affectedRecordIDs == nil { affectedRecordIDs = try context.fetch(FetchDescriptor<PlanBlock>()).map(\.id).filter { !beforeIDs.contains($0) } }
                } else if command.action == .start {
                    guard controller.session == nil else { throw CommandFailure.state }
                    func approved(_ id: UUID?, kind: AnchorMirrorNaming.Kind) throws {
                        if let id, !approvedPlannerNames.contains(kind.name(for: id)) { throw CommandFailure.reference }
                    }
                    try approved(command.args.goalID, kind: .goal)
                    try approved(command.args.projectID, kind: .project)
                    try approved(command.args.planBlockID, kind: .planBlock)
                    for id in command.args.tagIDStrings ?? [] { try approved(UUID(uuidString: id), kind: .savedTag) }
                    let goal = try context.fetch(FetchDescriptor<Goal>()).first { $0.id == command.args.goalID }
                    let project = try context.fetch(FetchDescriptor<Project>()).first { $0.id == command.args.projectID }
                    let block = try context.fetch(FetchDescriptor<PlanBlock>()).first { $0.id == command.args.planBlockID }
                    guard (command.args.goalID == nil || goal != nil), (command.args.projectID == nil || project != nil),
                          (command.args.planBlockID == nil || block != nil) else { throw CommandFailure.reference }
                    guard controller.start(goal: goal, intent: command.args.intent!, minutes: command.args.minutes!, project: project,
                                           notes: command.args.notes ?? "", tagIDStrings: command.args.tagIDStrings ?? [], planBlock: block) != nil else { throw CommandFailure.save }
                } else {
                    guard let session = controller.session, session.id == command.expectedSessionID,
                          session.hubAccountID == owner else { throw CommandFailure.state }
                    switch command.action {
                    case .pause:
                        guard controller.isRunning else { throw CommandFailure.state }
                        controller.pause()
                        guard controller.isPaused else { throw CommandFailure.save }
                    case .resume:
                        guard controller.isPaused else { throw CommandFailure.state }
                        controller.resume()
                        guard controller.isRunning && controller.isCapturing else { throw CommandFailure.save }
                    case .end:
                        guard controller.end(reason: command.args.reason.flatMap(SessionEndReason.init(rawValue:)) ?? .endedEarly) else { throw CommandFailure.save }
                    case .capture: controller.beginManualCapture()
                    case .start, .copyDay, .materializeDay, .reconcileTemplate: break
                    }
                }
                command.status = .applied
                command.error = nil
                command.result = .init(sessionID: controller.session?.id ?? command.expectedSessionID,
                                       state: controller.session?.state.rawValue ?? (command.action == .end ? "finished" : "idle"),
                                       capturePresented: controller.isCapturing, affectedRecordIDs: affectedRecordIDs.map { Array($0.prefix(500)) },
                                       affectedRecordCount: affectedRecordIDs?.count)
            } catch {
                if plannerDidBeginMutation { context.rollback() }
                command.error = (error as? CommandFailure)?.rawValue ?? "The command could not be applied."
            }
            state.commands[command.id.uuidString] = command
            try save(state)
        }
    }
    private enum CommandFailure: String, Error {
        case expired = "The command expired or was issued in the future."
        case consent = "The command was issued before the current planner-sharing approval."
        case unsaved = "Local edits are waiting to be saved."
        case state = "The expected focus session or state no longer matches."
        case reference = "A referenced planner item is missing or has not been approved for this account."
        case save = "The focus change could not be saved."
    }
}
#endif
