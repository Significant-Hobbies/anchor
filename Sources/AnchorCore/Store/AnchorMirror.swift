#if !os(watchOS)
import Foundation
import PersonalSyncKit
import SwiftData

/// Record-name convention shared by both mirror transports. Every name is
/// `<kind>-<uuid lowercase>` so a record carries the same identity on the Hub
/// and in the CloudKit private zone, and foreign names are ignored.
enum AnchorMirrorNaming {
    enum Kind: String, Sendable, CaseIterable {
        case goal, project, savedTag, focusSession, distraction
        case machineActivityDay, preferences, behaviorProfile
        case scheduleTemplate, habitCompletion, dayPlanConfirmation
        case planBlock, divergenceEvent

        var prefix: String {
            switch self {
            case .goal: "goal-"
            case .project: "project-"
            case .savedTag: "savedtag-"
            case .focusSession: "session-"
            case .distraction: "distraction-"
            case .machineActivityDay: "machineday-"
            case .preferences: "prefs-"
            case .behaviorProfile: "behavior-"
            case .scheduleTemplate: "schedule-"
            case .habitCompletion: "habit-"
            case .dayPlanConfirmation: "dayplan-"
            case .planBlock: "planblock-"
            case .divergenceEvent: "divergence-"
            }
        }

        func name(for id: UUID) -> String { prefix + id.uuidString.lowercased() }

        /// Historical planner output is append-only: a completed focus session
        /// is a fact, and a clock-skewed tombstone must never erase it.
        var isAppendOnly: Bool { self == .focusSession }
    }

    static func kind(of recordName: String) -> Kind? {
        Kind.allCases.first { recordName.hasPrefix($0.prefix) }
    }

    static func entityID(of recordName: String, kind: Kind) -> UUID? {
        UUID(uuidString: String(recordName.dropFirst(kind.prefix.count)))
    }
}

// MARK: - Payloads

/// One flat Codable envelope per entity. `recordType` travels inside the JSON
/// so the Hub validator and both transports see the identical bytes.
/// Distraction payloads deliberately omit `note` and `keywords`: that content
/// lives in the device-local vault and never leaves it.

struct GoalPayload: Codable, Equatable {
    var recordType = "goal"
    var id: String
    var title: String
    var notes: String
    var createdAt: Date
    var archivedAt: Date?
    var symbolName: String
    var tintIndex: Int
    var themeRaw: String?
    var keywords: [String]

    init(_ goal: Goal) {
        id = goal.id.uuidString
        title = goal.title
        notes = goal.notes
        createdAt = goal.createdAt
        archivedAt = goal.archivedAt
        symbolName = goal.symbolName
        tintIndex = goal.tintIndex
        themeRaw = goal.themeRaw
        keywords = goal.keywords
    }
}

struct ProjectPayload: Codable, Equatable {
    var recordType = "project"
    var id: String
    var name: String
    var notes: String
    var createdAt: Date
    var archivedAt: Date?
    var symbolName: String
    var tintIndex: Int
    var hourlyRate: Double
    var currencyCode: String

    init(_ project: Project) {
        id = project.id.uuidString
        name = project.name
        notes = project.notes
        createdAt = project.createdAt
        archivedAt = project.archivedAt
        symbolName = project.symbolName
        tintIndex = project.tintIndex
        hourlyRate = project.hourlyRate
        currencyCode = project.currencyCode
    }
}

struct SavedTagPayload: Codable, Equatable {
    var recordType = "savedTag"
    var id: String
    var name: String
    var createdAt: Date
    var archivedAt: Date?
    var tintIndex: Int

    init(_ tag: SavedTag) {
        id = tag.id.uuidString
        name = tag.name
        createdAt = tag.createdAt
        archivedAt = tag.archivedAt
        tintIndex = tag.tintIndex
    }
}

struct FocusSessionPayload: Codable, Equatable {
    var recordType = "focusSession"
    var id: String
    var startedAt: Date
    var endedAt: Date?
    var hubAccountID: String?
    var plannedSeconds: Int
    var bankedSeconds: Double
    var runningSince: Date?
    var stateRaw: String
    var endReasonRaw: String?
    var pausedAt: Date?
    var intent: String
    var notes: String
    var tagIDStrings: [String]
    var hourlyRate: Double
    var currencyCode: String
    var computerActiveSeconds: Double
    var computerAwaySeconds: Double
    var goalID: String?
    var projectID: String?

    init(_ session: FocusSession) {
        id = session.id.uuidString
        startedAt = session.startedAt
        endedAt = session.endedAt
        hubAccountID = session.hubAccountID
        plannedSeconds = session.plannedSeconds
        bankedSeconds = session.bankedSeconds
        runningSince = session.runningSince
        stateRaw = session.stateRaw
        endReasonRaw = session.endReasonRaw
        pausedAt = session.pausedAt
        intent = session.intent
        notes = session.notes
        tagIDStrings = session.tagIDStrings
        hourlyRate = session.hourlyRate
        currencyCode = session.currencyCode
        computerActiveSeconds = session.computerActiveSeconds
        computerAwaySeconds = session.computerAwaySeconds
        goalID = session.goal?.id.uuidString
        projectID = session.project?.id.uuidString
    }
}

struct DistractionPayload: Codable, Equatable {
    var recordType = "distraction"
    var id: String
    var capturedAt: Date
    var kindRaw: String?
    var kindConfidence: Double
    var kindIsUserSet: Bool
    var offsetSeconds: Double
    var didReturnToFocus: Bool
    var handledAt: Date?
    var sessionID: String?
    var tagIDStrings: [String]

    /// `note` and `keywords` are intentionally absent — they never leave the
    /// device. The Hub validator rejects distraction payloads that carry them.
    init(_ distraction: Distraction) {
        id = distraction.id.uuidString
        capturedAt = distraction.capturedAt
        kindRaw = distraction.kindRaw
        kindConfidence = distraction.kindConfidence
        kindIsUserSet = distraction.kindIsUserSet
        offsetSeconds = distraction.offsetSeconds
        didReturnToFocus = distraction.didReturnToFocus
        handledAt = distraction.handledAt
        sessionID = distraction.session?.id.uuidString
        tagIDStrings = distraction.tagIDStrings
    }
}

struct MachineActivityDayPayload: Codable, Equatable {
    var recordType = "machineActivityDay"
    var id: String
    var day: Date
    var activeSeconds: Double
    var trackedSeconds: Double
    var createdAt: Date

    init(_ record: MachineActivityDay) {
        id = record.id.uuidString
        day = record.day
        activeSeconds = record.activeSeconds
        trackedSeconds = record.trackedSeconds
        createdAt = record.createdAt
    }
}

struct PreferencesPayload: Codable, Equatable {
    var recordType = "preferences"
    var id: String
    var appearanceRaw: String
    var updatedAt: Date

    init(_ preferences: AnchorPreferences) {
        id = preferences.id.uuidString
        appearanceRaw = preferences.appearanceRaw
        updatedAt = preferences.updatedAt
    }
}

struct BehaviorProfilePayload: Codable, Equatable {
    var recordType = "behaviorProfile"
    var id: String
    var selectedPatternRawValues: [String]
    var desiredDirectionRawValues: [String]
    var updatedAt: Date

    init(_ profile: BehaviorProfile) {
        id = profile.id.uuidString
        selectedPatternRawValues = profile.selectedPatternRawValues
        desiredDirectionRawValues = profile.desiredDirectionRawValues
        updatedAt = profile.updatedAt
    }
}

struct ScheduleTemplatePayload: Codable, Equatable {
    var recordType = "scheduleTemplate"
    var id: String
    var projectID: String?
    var title: String
    var details: String
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    var startMinutesFromMidnight: Int
    var plannedSeconds: Int
    var weekdayMask: Int
    var kindRaw: String
    var flexibilityRaw: String
    var behaviorPatternRaw: String?
    var lifeDirectionRaw: String?
    var isBehaviorHabit: Bool
    var habitUsesSuggestedTime: Bool
    var habitVersion: Int
    var graduatedAt: Date?
    var habitLevelStartedAt: Date?
    var lastProgressPromptedAt: Date?

    init(_ template: ScheduleTemplate) {
        id = template.id.uuidString
        projectID = template.projectID?.uuidString
        title = template.title
        details = template.details
        createdAt = template.createdAt
        updatedAt = template.updatedAt
        archivedAt = template.archivedAt
        startMinutesFromMidnight = template.startMinutesFromMidnight
        plannedSeconds = template.plannedSeconds
        weekdayMask = template.weekdayMask
        kindRaw = template.kindRaw
        flexibilityRaw = template.flexibilityRaw
        behaviorPatternRaw = template.behaviorPatternRaw
        lifeDirectionRaw = template.lifeDirectionRaw
        isBehaviorHabit = template.isBehaviorHabit
        habitUsesSuggestedTime = template.habitUsesSuggestedTime
        habitVersion = template.habitVersion
        graduatedAt = template.graduatedAt
        habitLevelStartedAt = template.habitLevelStartedAt
        lastProgressPromptedAt = template.lastProgressPromptedAt
    }
}

struct HabitCompletionPayload: Codable, Equatable {
    var recordType = "habitCompletion"
    var id: String
    var habitID: String
    var day: Date
    var isCompleted: Bool
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(_ completion: HabitCompletion) {
        id = completion.id.uuidString
        habitID = completion.habitID.uuidString
        day = completion.day
        isCompleted = completion.isCompleted
        completedAt = completion.completedAt
        createdAt = completion.createdAt
        updatedAt = completion.updatedAt
    }
}

struct DayPlanConfirmationPayload: Codable, Equatable {
    var recordType = "dayPlanConfirmation"
    var id: String
    var day: Date
    var decisionRaw: String
    var baselineRevision: String
    var confirmedAt: Date?
    var deferredAt: Date?
    var updatedAt: Date

    init(_ confirmation: DayPlanConfirmation) {
        id = confirmation.id.uuidString
        day = confirmation.day
        decisionRaw = confirmation.decisionRaw
        baselineRevision = confirmation.baselineRevision
        confirmedAt = confirmation.confirmedAt
        deferredAt = confirmation.deferredAt
        updatedAt = confirmation.updatedAt
    }
}

struct PlanBlockPayload: Codable, Equatable {
    var recordType = "planBlock"
    var id: String
    var templateID: String?
    var templateOccurrenceDay: Date?
    var isTemplateOverride: Bool
    var sessionID: String?
    var projectID: String?
    var title: String
    var details: String
    var plannedStart: Date
    var plannedSeconds: Int
    var actualStartedAt: Date?
    var actualEndedAt: Date?
    var stateRaw: String
    var kindRaw: String
    var flexibilityRaw: String
    var behaviorPatternRaw: String?
    var lifeDirectionRaw: String?
    var reminderExternalIdentifier: String?
    var reminderLastSyncedAt: Date?
    var externalEventKey: String?
    var createdAt: Date
    var updatedAt: Date

    init(_ block: PlanBlock) {
        id = block.id.uuidString
        templateID = block.templateID?.uuidString
        templateOccurrenceDay = block.templateOccurrenceDay
        isTemplateOverride = block.isTemplateOverride
        sessionID = block.sessionID?.uuidString
        projectID = block.projectID?.uuidString
        title = block.title
        details = block.details
        plannedStart = block.plannedStart
        plannedSeconds = block.plannedSeconds
        actualStartedAt = block.actualStartedAt
        actualEndedAt = block.actualEndedAt
        stateRaw = block.stateRaw
        kindRaw = block.kindRaw
        flexibilityRaw = block.flexibilityRaw
        behaviorPatternRaw = block.behaviorPatternRaw
        lifeDirectionRaw = block.lifeDirectionRaw
        reminderExternalIdentifier = block.reminderExternalIdentifier
        reminderLastSyncedAt = block.reminderLastSyncedAt
        externalEventKey = block.externalEventKey
        createdAt = block.createdAt
        updatedAt = block.updatedAt
    }
}

struct DivergenceEventPayload: Codable, Equatable {
    var recordType = "divergenceEvent"
    var id: String
    var blockID: String
    var sessionID: String?
    var distractionID: String?
    var occurredAt: Date
    var kindRaw: String
    var evidenceRaw: String
    var note: String
    var userConfirmed: Bool

    init(_ event: DivergenceEvent) {
        id = event.id.uuidString
        blockID = event.blockID.uuidString
        sessionID = event.sessionID?.uuidString
        distractionID = event.distractionID?.uuidString
        occurredAt = event.occurredAt
        kindRaw = event.kindRaw
        evidenceRaw = event.evidenceRaw
        note = event.note
        userConfirmed = event.userConfirmed
    }
}

/// The pre-mirror Hub summary shape. Already-synced history imports as
/// finished sessions so an account's old Hub records still land locally.
struct LegacySessionSummaryPayload: Codable {
    var title: String
    var startedAt: Date
    var endedAt: Date
    var durationSeconds: Int
    var outcome: String?
    var interruptionCount: Int?
}

// MARK: - Snapshot + apply

@MainActor
enum AnchorMirror {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func record<Payload: Encodable>(
        _ name: String, _ payload: Payload, now: Date
    ) throws -> MirrorRecord {
        MirrorRecord(name: name, modifiedAt: now, payload: try encoder.encode(payload))
    }

    /// Every syncable entity plus tombstones for names the ledger still knows.
    /// Records arrive with `modifiedAt = now`; the runtime stamps each one with
    /// its first-seen write time, so unchanged entities keep their original
    /// emission time across restarts.
    static func records(
        in context: ModelContext,
        tombstonesFor knownNames: Set<String>,
        now: Date = .now
    ) throws -> [MirrorRecord] {
        var live = Set<String>()
        var records: [MirrorRecord] = []
        func emit<Payload: Encodable>(
            _ payload: Payload, name: String
        ) throws {
            live.insert(name)
            records.append(try record(name, payload, now: now))
        }

        for goal in try context.fetch(FetchDescriptor<Goal>()) {
            try emit(GoalPayload(goal), name: AnchorMirrorNaming.Kind.goal.name(for: goal.id))
        }
        for project in try context.fetch(FetchDescriptor<Project>()) {
            try emit(ProjectPayload(project), name: AnchorMirrorNaming.Kind.project.name(for: project.id))
        }
        for tag in try context.fetch(FetchDescriptor<SavedTag>()) {
            try emit(SavedTagPayload(tag), name: AnchorMirrorNaming.Kind.savedTag.name(for: tag.id))
        }
        for session in try context.fetch(FetchDescriptor<FocusSession>()) {
            try emit(FocusSessionPayload(session), name: AnchorMirrorNaming.Kind.focusSession.name(for: session.id))
        }
        for distraction in try context.fetch(FetchDescriptor<Distraction>()) {
            try emit(DistractionPayload(distraction), name: AnchorMirrorNaming.Kind.distraction.name(for: distraction.id))
        }
        for day in try context.fetch(FetchDescriptor<MachineActivityDay>()) {
            try emit(MachineActivityDayPayload(day), name: AnchorMirrorNaming.Kind.machineActivityDay.name(for: day.id))
        }
        for preferences in try context.fetch(FetchDescriptor<AnchorPreferences>()) {
            try emit(PreferencesPayload(preferences), name: AnchorMirrorNaming.Kind.preferences.name(for: preferences.id))
        }
        for profile in try context.fetch(FetchDescriptor<BehaviorProfile>()) {
            try emit(BehaviorProfilePayload(profile), name: AnchorMirrorNaming.Kind.behaviorProfile.name(for: profile.id))
        }
        for template in try context.fetch(FetchDescriptor<ScheduleTemplate>()) {
            try emit(ScheduleTemplatePayload(template), name: AnchorMirrorNaming.Kind.scheduleTemplate.name(for: template.id))
        }
        for completion in try context.fetch(FetchDescriptor<HabitCompletion>()) {
            try emit(HabitCompletionPayload(completion), name: AnchorMirrorNaming.Kind.habitCompletion.name(for: completion.id))
        }
        for confirmation in try context.fetch(FetchDescriptor<DayPlanConfirmation>()) {
            try emit(DayPlanConfirmationPayload(confirmation), name: AnchorMirrorNaming.Kind.dayPlanConfirmation.name(for: confirmation.id))
        }
        for block in try context.fetch(FetchDescriptor<PlanBlock>()) {
            try emit(PlanBlockPayload(block), name: AnchorMirrorNaming.Kind.planBlock.name(for: block.id))
        }
        for event in try context.fetch(FetchDescriptor<DivergenceEvent>()) {
            try emit(DivergenceEventPayload(event), name: AnchorMirrorNaming.Kind.divergenceEvent.name(for: event.id))
        }

        for name in knownNames.subtracting(live) where AnchorMirrorNaming.kind(of: name) != nil {
            records.append(MirrorRecord(name: name, modifiedAt: now, payload: nil))
        }
        return records
    }

    /// Apply pulled winners into the local store. Scalar state lands first;
    /// session/distraction relationships resolve in a second pass so ordering
    /// inside the batch never matters. Returns whether the store changed.
    static func apply(_ records: [MirrorRecord], in context: ModelContext) throws -> Bool {
        var index = try Index(context: context)
        var deletedDistractionIDs: [UUID] = []
        var changed = false

        for record in records {
            guard let kind = AnchorMirrorNaming.kind(of: record.name) else { continue }
            if let payload = record.payload {
                changed = try upsert(kind: kind, name: record.name, payload: payload, index: &index, context: context) || changed
            } else {
                changed = try tombstone(
                    kind: kind, name: record.name, index: &index,
                    context: context, deletedDistractions: &deletedDistractionIDs
                ) || changed
            }
        }

        // Relationships resolve last: a pulled session can precede its goal in
        // the same batch, and a pulled distraction can precede its session.
        for record in records where record.payload != nil {
            switch AnchorMirrorNaming.kind(of: record.name) {
            case .focusSession:
                let session = try sessionFromPayload(record.payload!, name: record.name, index: &index, context: context).session
                guard let payload = try? decode(FocusSessionPayload.self, from: record.payload!) else { continue }
                session.goal = payload.goalID.flatMap(UUID.init(uuidString:)).flatMap { index.goals[$0.uuidString] }
                session.project = payload.projectID.flatMap(UUID.init(uuidString:)).flatMap { index.projects[$0.uuidString] }
            case .distraction:
                guard let payload = try? decode(DistractionPayload.self, from: record.payload!),
                      let id = UUID(uuidString: payload.id),
                      let distraction = index.distractions[id.uuidString]
                else { continue }
                distraction.session = payload.sessionID.flatMap(UUID.init(uuidString:)).flatMap { index.sessions[$0.uuidString] }
            default:
                continue
            }
        }

        guard changed else { return false }
        try context.save()
        // Notes vault entries for tombstoned distractions (including ones lost
        // to a session cascade) are local files — remove them with the row.
        for id in deletedDistractionIDs {
            try? context.localDistractionNotes?.delete(id)
        }
        return true
    }

    private static func decode<Payload: Decodable>(
        _ type: Payload.Type, from data: Data
    ) throws -> Payload {
        try decoder.decode(type, from: data)
    }

    private static func uuid(_ name: String, kind: AnchorMirrorNaming.Kind) -> UUID? {
        AnchorMirrorNaming.entityID(of: name, kind: kind)
    }

    // MARK: Upserts

    private static func upsert(
        kind: AnchorMirrorNaming.Kind,
        name: String,
        payload: Data,
        index: inout Index,
        context: ModelContext
    ) throws -> Bool {
        switch kind {
        case .goal:
            let value = try decode(GoalPayload.self, from: payload)
            if let existing = index.goals[value.id] {
                guard GoalPayload(existing) != value else { return false }
                assign(value, to: existing)
                return true
            }
            let goal = Goal(id: UUID(uuidString: value.id) ?? UUID(), title: "")
            assign(value, to: goal)
            context.insert(goal)
            index.goals[goal.id.uuidString] = goal
            return true
        case .project:
            let value = try decode(ProjectPayload.self, from: payload)
            if let existing = index.projects[value.id] {
                guard ProjectPayload(existing) != value else { return false }
                assign(value, to: existing)
                return true
            }
            let project = Project(id: UUID(uuidString: value.id) ?? UUID(), name: "")
            assign(value, to: project)
            context.insert(project)
            index.projects[project.id.uuidString] = project
            return true
        case .savedTag:
            let value = try decode(SavedTagPayload.self, from: payload)
            if let existing = index.savedTags[value.id] {
                guard SavedTagPayload(existing) != value else { return false }
                assign(value, to: existing)
                return true
            }
            let tag = SavedTag(id: UUID(uuidString: value.id) ?? UUID(), name: "")
            assign(value, to: tag)
            context.insert(tag)
            index.savedTags[tag.id.uuidString] = tag
            return true
        case .focusSession:
            return try sessionFromPayload(payload, name: name, index: &index, context: context).changed
        case .distraction:
            let value = try decode(DistractionPayload.self, from: payload)
            if let existing = index.distractions[value.id] {
                guard DistractionPayload(existing) != value else { return false }
                assign(value, to: existing)
                return true
            }
            let distraction = Distraction(id: UUID(uuidString: value.id) ?? UUID(), note: "")
            assign(value, to: distraction)
            context.insert(distraction)
            index.distractions[distraction.id.uuidString] = distraction
            return true
        case .machineActivityDay:
            let value = try decode(MachineActivityDayPayload.self, from: payload)
            if let existing = index.machineDays[value.id] {
                guard MachineActivityDayPayload(existing) != value else { return false }
                assign(value, to: existing)
                return true
            }
            let day = MachineActivityDay(id: UUID(uuidString: value.id) ?? UUID(), day: value.day)
            assign(value, to: day)
            context.insert(day)
            index.machineDays[day.id.uuidString] = day
            return true
        case .preferences:
            let value = try decode(PreferencesPayload.self, from: payload)
            if let existing = index.preferences[value.id] {
                guard PreferencesPayload(existing) != value else { return false }
                assign(value, to: existing)
                return true
            }
            let preferences = AnchorPreferences(id: UUID(uuidString: value.id) ?? UUID())
            assign(value, to: preferences)
            context.insert(preferences)
            index.preferences[preferences.id.uuidString] = preferences
            return true
        case .behaviorProfile:
            let value = try decode(BehaviorProfilePayload.self, from: payload)
            if let existing = index.behaviorProfiles[value.id] {
                guard BehaviorProfilePayload(existing) != value else { return false }
                assign(value, to: existing)
                return true
            }
            let profile = BehaviorProfile(id: UUID(uuidString: value.id) ?? UUID())
            assign(value, to: profile)
            context.insert(profile)
            index.behaviorProfiles[profile.id.uuidString] = profile
            return true
        case .scheduleTemplate:
            let value = try decode(ScheduleTemplatePayload.self, from: payload)
            if let existing = index.scheduleTemplates[value.id] {
                guard ScheduleTemplatePayload(existing) != value else { return false }
                assign(value, to: existing)
                return true
            }
            let template = ScheduleTemplate(
                id: UUID(uuidString: value.id) ?? UUID(),
                title: "", startMinutesFromMidnight: 540, plannedSeconds: 1_500
            )
            assign(value, to: template)
            context.insert(template)
            index.scheduleTemplates[template.id.uuidString] = template
            return true
        case .habitCompletion:
            let value = try decode(HabitCompletionPayload.self, from: payload)
            if let existing = index.habitCompletions[value.id] {
                guard HabitCompletionPayload(existing) != value else { return false }
                assign(value, to: existing)
                return true
            }
            let completion = HabitCompletion(
                id: UUID(uuidString: value.id) ?? UUID(),
                habitID: UUID(uuidString: value.habitID) ?? UUID(),
                day: value.day
            )
            assign(value, to: completion)
            context.insert(completion)
            index.habitCompletions[completion.id.uuidString] = completion
            return true
        case .dayPlanConfirmation:
            let value = try decode(DayPlanConfirmationPayload.self, from: payload)
            if let existing = index.dayPlanConfirmations[value.id] {
                guard DayPlanConfirmationPayload(existing) != value else { return false }
                assign(value, to: existing)
                return true
            }
            let confirmation = DayPlanConfirmation(
                id: UUID(uuidString: value.id) ?? UUID(),
                day: value.day, decision: .later
            )
            assign(value, to: confirmation)
            context.insert(confirmation)
            index.dayPlanConfirmations[confirmation.id.uuidString] = confirmation
            return true
        case .planBlock:
            let value = try decode(PlanBlockPayload.self, from: payload)
            if let existing = index.planBlocks[value.id] {
                guard PlanBlockPayload(existing) != value else { return false }
                assign(value, to: existing)
                return true
            }
            let block = PlanBlock(
                id: UUID(uuidString: value.id) ?? UUID(),
                title: "", plannedStart: value.plannedStart, plannedSeconds: value.plannedSeconds
            )
            assign(value, to: block)
            context.insert(block)
            index.planBlocks[block.id.uuidString] = block
            return true
        case .divergenceEvent:
            let value = try decode(DivergenceEventPayload.self, from: payload)
            if let existing = index.divergenceEvents[value.id] {
                guard DivergenceEventPayload(existing) != value else { return false }
                assign(value, to: existing)
                return true
            }
            let event = DivergenceEvent(
                id: UUID(uuidString: value.id) ?? UUID(),
                blockID: UUID(uuidString: value.blockID) ?? UUID(),
                kind: .unknown
            )
            assign(value, to: event)
            context.insert(event)
            index.divergenceEvents[event.id.uuidString] = event
            return true
        }
    }

    /// Sessions accept both the canonical payload and the legacy Hub summary
    /// shape so history synced before the mirror still lands.
    @discardableResult
    private static func sessionFromPayload(
        _ data: Data,
        name: String,
        index: inout Index,
        context: ModelContext
    ) throws -> (session: FocusSession, changed: Bool) {
        // `try?` — the legacy summary shape lacks the canonical fields and
        // must fall through to the summary decode instead of throwing.
        if let value = try? decode(FocusSessionPayload.self, from: data),
           value.recordType == "focusSession",
           let id = UUID(uuidString: value.id) {
            if let existing = index.sessions[id.uuidString] {
                guard FocusSessionPayload(existing) != value else { return (existing, false) }
                assign(value, to: existing)
                return (existing, true)
            }
            let session = FocusSession(id: id, goal: nil, plannedSeconds: value.plannedSeconds)
            assign(value, to: session)
            context.insert(session)
            index.sessions[id.uuidString] = session
            return (session, true)
        }
        if let summary = try? decode(LegacySessionSummaryPayload.self, from: data) {
            let id = AnchorPlatformRecord.stableUUID(String(name.dropFirst(AnchorMirrorNaming.Kind.focusSession.prefix.count)))
            if let existing = index.sessions[id.uuidString] { return (existing, false) }
            let session = FocusSession(id: id, goal: nil, intent: summary.title, plannedSeconds: summary.durationSeconds, startedAt: summary.startedAt)
            session.endedAt = summary.endedAt
            session.bankedSeconds = Double(summary.durationSeconds)
            session.runningSince = nil
            session.state = .finished
            session.endReason = SessionEndReason(rawValue: summary.outcome ?? "completed") ?? .completed
            context.insert(session)
            index.sessions[id.uuidString] = session
            return (session, true)
        }
        throw CocoaError(.coderReadCorrupt)
    }

    // MARK: Field assignment

    private static func assign(_ value: GoalPayload, to goal: Goal) {
        goal.id = UUID(uuidString: value.id) ?? goal.id
        goal.title = value.title
        goal.notes = value.notes
        goal.createdAt = value.createdAt
        goal.archivedAt = value.archivedAt
        goal.symbolName = value.symbolName
        goal.tintIndex = value.tintIndex
        goal.themeRaw = value.themeRaw
        goal.keywords = value.keywords
    }

    private static func assign(_ value: ProjectPayload, to project: Project) {
        project.name = value.name
        project.notes = value.notes
        project.createdAt = value.createdAt
        project.archivedAt = value.archivedAt
        project.symbolName = value.symbolName
        project.tintIndex = value.tintIndex
        project.hourlyRate = value.hourlyRate
        project.currencyCode = value.currencyCode
    }

    private static func assign(_ value: SavedTagPayload, to tag: SavedTag) {
        tag.name = value.name
        tag.createdAt = value.createdAt
        tag.archivedAt = value.archivedAt
        tag.tintIndex = value.tintIndex
    }

    private static func assign(_ value: FocusSessionPayload, to session: FocusSession) {
        session.startedAt = value.startedAt
        session.endedAt = value.endedAt
        session.hubAccountID = value.hubAccountID
        session.plannedSeconds = value.plannedSeconds
        session.bankedSeconds = value.bankedSeconds
        session.runningSince = value.runningSince
        session.stateRaw = value.stateRaw
        session.endReasonRaw = value.endReasonRaw
        session.pausedAt = value.pausedAt
        session.intent = value.intent
        session.notes = value.notes
        session.tagIDStrings = value.tagIDStrings
        session.hourlyRate = value.hourlyRate
        session.currencyCode = value.currencyCode
        session.computerActiveSeconds = value.computerActiveSeconds
        session.computerAwaySeconds = value.computerAwaySeconds
    }

    private static func assign(_ value: DistractionPayload, to distraction: Distraction) {
        distraction.capturedAt = value.capturedAt
        distraction.kindRaw = value.kindRaw
        distraction.kindConfidence = value.kindConfidence
        distraction.kindIsUserSet = value.kindIsUserSet
        distraction.offsetSeconds = value.offsetSeconds
        distraction.didReturnToFocus = value.didReturnToFocus
        distraction.handledAt = value.handledAt
        distraction.tagIDStrings = value.tagIDStrings
    }

    private static func assign(_ value: MachineActivityDayPayload, to day: MachineActivityDay) {
        day.day = value.day
        day.activeSeconds = value.activeSeconds
        day.trackedSeconds = value.trackedSeconds
        day.createdAt = value.createdAt
    }

    private static func assign(_ value: PreferencesPayload, to preferences: AnchorPreferences) {
        preferences.appearanceRaw = value.appearanceRaw
        preferences.updatedAt = value.updatedAt
    }

    private static func assign(_ value: BehaviorProfilePayload, to profile: BehaviorProfile) {
        profile.selectedPatternRawValues = value.selectedPatternRawValues
        profile.desiredDirectionRawValues = value.desiredDirectionRawValues
        profile.updatedAt = value.updatedAt
    }

    private static func assign(_ value: ScheduleTemplatePayload, to template: ScheduleTemplate) {
        template.projectID = value.projectID.flatMap(UUID.init(uuidString:))
        template.title = value.title
        template.details = value.details
        template.createdAt = value.createdAt
        template.updatedAt = value.updatedAt
        template.archivedAt = value.archivedAt
        template.startMinutesFromMidnight = value.startMinutesFromMidnight
        template.plannedSeconds = value.plannedSeconds
        template.weekdayMask = value.weekdayMask
        template.kindRaw = value.kindRaw
        template.flexibilityRaw = value.flexibilityRaw
        template.behaviorPatternRaw = value.behaviorPatternRaw
        template.lifeDirectionRaw = value.lifeDirectionRaw
        template.isBehaviorHabit = value.isBehaviorHabit
        template.habitUsesSuggestedTime = value.habitUsesSuggestedTime
        template.habitVersion = value.habitVersion
        template.graduatedAt = value.graduatedAt
        template.habitLevelStartedAt = value.habitLevelStartedAt
        template.lastProgressPromptedAt = value.lastProgressPromptedAt
    }

    private static func assign(_ value: HabitCompletionPayload, to completion: HabitCompletion) {
        completion.habitID = UUID(uuidString: value.habitID) ?? completion.habitID
        completion.day = value.day
        completion.isCompleted = value.isCompleted
        completion.completedAt = value.completedAt
        completion.createdAt = value.createdAt
        completion.updatedAt = value.updatedAt
    }

    private static func assign(_ value: DayPlanConfirmationPayload, to confirmation: DayPlanConfirmation) {
        confirmation.day = value.day
        confirmation.decisionRaw = value.decisionRaw
        confirmation.baselineRevision = value.baselineRevision
        confirmation.confirmedAt = value.confirmedAt
        confirmation.deferredAt = value.deferredAt
        confirmation.updatedAt = value.updatedAt
    }

    private static func assign(_ value: PlanBlockPayload, to block: PlanBlock) {
        block.templateID = value.templateID.flatMap(UUID.init(uuidString:))
        block.templateOccurrenceDay = value.templateOccurrenceDay
        block.isTemplateOverride = value.isTemplateOverride
        block.sessionID = value.sessionID.flatMap(UUID.init(uuidString:))
        block.projectID = value.projectID.flatMap(UUID.init(uuidString:))
        block.title = value.title
        block.details = value.details
        block.plannedStart = value.plannedStart
        block.plannedSeconds = value.plannedSeconds
        block.actualStartedAt = value.actualStartedAt
        block.actualEndedAt = value.actualEndedAt
        block.stateRaw = value.stateRaw
        block.kindRaw = value.kindRaw
        block.flexibilityRaw = value.flexibilityRaw
        block.behaviorPatternRaw = value.behaviorPatternRaw
        block.lifeDirectionRaw = value.lifeDirectionRaw
        block.reminderExternalIdentifier = value.reminderExternalIdentifier
        block.reminderLastSyncedAt = value.reminderLastSyncedAt
        block.externalEventKey = value.externalEventKey
        block.createdAt = value.createdAt
        block.updatedAt = value.updatedAt
    }

    private static func assign(_ value: DivergenceEventPayload, to event: DivergenceEvent) {
        event.blockID = UUID(uuidString: value.blockID) ?? event.blockID
        event.sessionID = value.sessionID.flatMap(UUID.init(uuidString:))
        event.distractionID = value.distractionID.flatMap(UUID.init(uuidString:))
        event.occurredAt = value.occurredAt
        event.kindRaw = value.kindRaw
        event.evidenceRaw = value.evidenceRaw
        event.note = value.note
        event.userConfirmed = value.userConfirmed
    }

    // MARK: Tombstones

    private static func tombstone(
        kind: AnchorMirrorNaming.Kind,
        name: String,
        index: inout Index,
        context: ModelContext,
        deletedDistractions: inout [UUID]
    ) throws -> Bool {
        guard let id = uuid(name, kind: kind) else { return false }
        let key = id.uuidString
        switch kind {
        case .goal:
            guard let entity = index.goals.removeValue(forKey: key) else { return false }
            context.delete(entity)
        case .project:
            guard let entity = index.projects.removeValue(forKey: key) else { return false }
            context.delete(entity)
        case .savedTag:
            guard let entity = index.savedTags.removeValue(forKey: key) else { return false }
            context.delete(entity)
        case .focusSession:
            guard let entity = index.sessions.removeValue(forKey: key) else { return false }
            deletedDistractions += (entity.distractions ?? []).map(\.id)
            context.delete(entity)
        case .distraction:
            guard let entity = index.distractions.removeValue(forKey: key) else { return false }
            deletedDistractions.append(entity.id)
            context.delete(entity)
        case .machineActivityDay:
            guard let entity = index.machineDays.removeValue(forKey: key) else { return false }
            context.delete(entity)
        case .preferences:
            guard let entity = index.preferences.removeValue(forKey: key) else { return false }
            context.delete(entity)
        case .behaviorProfile:
            guard let entity = index.behaviorProfiles.removeValue(forKey: key) else { return false }
            context.delete(entity)
        case .scheduleTemplate:
            guard let entity = index.scheduleTemplates.removeValue(forKey: key) else { return false }
            context.delete(entity)
        case .habitCompletion:
            guard let entity = index.habitCompletions.removeValue(forKey: key) else { return false }
            context.delete(entity)
        case .dayPlanConfirmation:
            guard let entity = index.dayPlanConfirmations.removeValue(forKey: key) else { return false }
            context.delete(entity)
        case .planBlock:
            guard let entity = index.planBlocks.removeValue(forKey: key) else { return false }
            context.delete(entity)
        case .divergenceEvent:
            guard let entity = index.divergenceEvents.removeValue(forKey: key) else { return false }
            context.delete(entity)
        }
        return true
    }

    // MARK: Fetch index

    /// All rows of every syncable type, indexed by stable id. Personal-scale
    /// stores make a full index cheaper than per-record fetches.
    private struct Index {
        var goals: [String: Goal]
        var projects: [String: Project]
        var savedTags: [String: SavedTag]
        var sessions: [String: FocusSession]
        var distractions: [String: Distraction]
        var machineDays: [String: MachineActivityDay]
        var preferences: [String: AnchorPreferences]
        var behaviorProfiles: [String: BehaviorProfile]
        var scheduleTemplates: [String: ScheduleTemplate]
        var habitCompletions: [String: HabitCompletion]
        var dayPlanConfirmations: [String: DayPlanConfirmation]
        var planBlocks: [String: PlanBlock]
        var divergenceEvents: [String: DivergenceEvent]

        init(context: ModelContext) throws {
            goals = try Self.index(context.fetch(FetchDescriptor<Goal>()))
            projects = try Self.index(context.fetch(FetchDescriptor<Project>()))
            savedTags = try Self.index(context.fetch(FetchDescriptor<SavedTag>()))
            sessions = try Self.index(context.fetch(FetchDescriptor<FocusSession>()))
            distractions = try Self.index(context.fetch(FetchDescriptor<Distraction>()))
            machineDays = try Self.index(context.fetch(FetchDescriptor<MachineActivityDay>()))
            preferences = try Self.index(context.fetch(FetchDescriptor<AnchorPreferences>()))
            behaviorProfiles = try Self.index(context.fetch(FetchDescriptor<BehaviorProfile>()))
            scheduleTemplates = try Self.index(context.fetch(FetchDescriptor<ScheduleTemplate>()))
            habitCompletions = try Self.index(context.fetch(FetchDescriptor<HabitCompletion>()))
            dayPlanConfirmations = try Self.index(context.fetch(FetchDescriptor<DayPlanConfirmation>()))
            planBlocks = try Self.index(context.fetch(FetchDescriptor<PlanBlock>()))
            divergenceEvents = try Self.index(context.fetch(FetchDescriptor<DivergenceEvent>()))
        }

        private static func index<Model: Identifiable>(
            _ models: [Model]
        ) -> [String: Model] where Model.ID == UUID {
            Dictionary(models.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }
}
#endif
