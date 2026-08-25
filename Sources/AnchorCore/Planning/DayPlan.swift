import Foundation
import SwiftData

// MARK: - Behavioral profile

/// A private, editable description of the patterns a person wants to notice and
/// the parts of life they want to make room for. These raw values deliberately
/// stay out of Hub summaries.
@Model
public final class BehaviorProfile {
    public var id: UUID = UUID()
    public var selectedPatternRawValues: [String] = []
    public var desiredDirectionRawValues: [String] = []
    public var updatedAt: Date = Date()

    public init(
        id: UUID = UUID(),
        selectedPatterns: Set<BehaviorPattern> = [],
        desiredDirections: Set<LifeDirection> = [],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.selectedPatterns = selectedPatterns
        self.desiredDirections = desiredDirections
        self.updatedAt = updatedAt
    }

    public var selectedPatterns: Set<BehaviorPattern> {
        get { Set(selectedPatternRawValues.compactMap(BehaviorPattern.init(rawValue:))) }
        set { selectedPatternRawValues = newValue.map(\.rawValue).sorted() }
    }

    public var desiredDirections: Set<LifeDirection> {
        get { Set(desiredDirectionRawValues.compactMap(LifeDirection.init(rawValue:))) }
        set { desiredDirectionRawValues = newValue.map(\.rawValue).sorted() }
    }
}

public enum BehaviorPattern: String, CaseIterable, Codable, Hashable, Sendable {
    case television, streaming, films, shortVideo, socialFeeds, newsScroll
    case webBrowsing, rabbitHoles, consoleGaming, handheldGaming, music, podcasts
    case snacking, takeaway, sweets, coffee, alcohol, onlineShopping, windowShopping
    case napping, lyingIn, texting, videoCalls, hangingOut

    public var label: String {
        switch self {
        case .television: "Watching TV"
        case .streaming: "Streaming a series"
        case .films: "Watching films"
        case .shortVideo: "Short videos"
        case .socialFeeds: "Social feeds"
        case .newsScroll: "Reading the news"
        case .webBrowsing: "Browsing the web"
        case .rabbitHoles: "Rabbit holes"
        case .consoleGaming: "Console gaming"
        case .handheldGaming: "Handheld gaming"
        case .music: "Listening to music"
        case .podcasts: "Listening to podcasts"
        case .snacking: "Snacking"
        case .takeaway: "Ordering takeaway"
        case .sweets: "Something sweet"
        case .coffee: "Having coffee"
        case .alcohol: "Having a drink"
        case .onlineShopping: "Shopping online"
        case .windowShopping: "Browsing shops"
        case .napping: "Taking a nap"
        case .lyingIn: "Lying in"
        case .texting: "Texting"
        case .videoCalls: "Video calling"
        case .hangingOut: "Hanging out"
        }
    }

    /// Matches the original Indulge asset filename and asset-catalog name.
    public var artworkName: String { "Pattern-\(rawValue)" }

    public var symbolName: String {
        switch self {
        case .television: "tv"
        case .streaming: "play.rectangle.on.rectangle"
        case .films: "film"
        case .shortVideo: "play.square.stack"
        case .socialFeeds: "person.2.wave.2"
        case .newsScroll: "newspaper"
        case .webBrowsing: "globe"
        case .rabbitHoles: "arrow.down.to.line.compact"
        case .consoleGaming: "gamecontroller"
        case .handheldGaming: "arcade.stick.console"
        case .music: "music.note"
        case .podcasts: "waveform"
        case .snacking: "takeoutbag.and.cup.and.straw"
        case .takeaway: "scooter"
        case .sweets: "birthday.cake"
        case .coffee: "cup.and.saucer"
        case .alcohol: "wineglass"
        case .onlineShopping: "cart"
        case .windowShopping: "bag"
        case .napping: "bed.double"
        case .lyingIn: "zzz"
        case .texting: "message"
        case .videoCalls: "video"
        case .hangingOut: "person.3"
        }
    }
}

public enum LifeDirection: String, CaseIterable, Codable, Hashable, Sendable {
    case sleep, presence, relationships, creativity, movement, calm, focus, selfTrust

    public var label: String {
        switch self {
        case .sleep: "Better sleep"
        case .presence: "More presence"
        case .relationships: "Closer relationships"
        case .creativity: "More creativity"
        case .movement: "More movement"
        case .calm: "A calmer mind"
        case .focus: "Deeper focus"
        case .selfTrust: "More self-trust"
        }
    }

    public var symbolName: String {
        switch self {
        case .sleep: "moon.zzz.fill"
        case .presence: "eye.fill"
        case .relationships: "person.2.fill"
        case .creativity: "paintbrush.fill"
        case .movement: "figure.walk"
        case .calm: "water.waves"
        case .focus: "scope"
        case .selfTrust: "checkmark.seal.fill"
        }
    }

    public var artworkName: String { "Direction-\(rawValue)" }
}

// MARK: - Schedule models

/// A reusable rule that materializes one dated block on matching days.
@Model
public final class ScheduleTemplate {
    public var id: UUID = UUID()
    public var title: String = ""
    public var details: String = ""
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var archivedAt: Date?
    public var startMinutesFromMidnight: Int = 540
    public var plannedSeconds: Int = 1_500
    /// Monday is bit 0 through Sunday at bit 6. Zero means every day.
    public var weekdayMask: Int = 0
    public var kindRaw: String = PlanBlockKind.focus.rawValue
    public var flexibilityRaw: String = ScheduleFlexibility.flexible.rawValue
    public var behaviorPatternRaw: String?
    public var lifeDirectionRaw: String?
    /// Behavior-change habits are intentionally separate from ordinary recurring
    /// schedule items. Only these templates participate in the five-slot policy.
    public var isBehaviorHabit: Bool = false
    public var habitVersion: Int = 1
    public var graduatedAt: Date?
    public var habitLevelStartedAt: Date?
    public var lastProgressPromptedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        startMinutesFromMidnight: Int,
        plannedSeconds: Int,
        weekdays: Set<ScheduleWeekday> = [],
        kind: PlanBlockKind = .focus,
        flexibility: ScheduleFlexibility = .flexible,
        behaviorPattern: BehaviorPattern? = nil,
        lifeDirection: LifeDirection? = nil,
        isBehaviorHabit: Bool = false,
        habitVersion: Int = 1,
        graduatedAt: Date? = nil,
        habitLevelStartedAt: Date? = nil,
        lastProgressPromptedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startMinutesFromMidnight = min(1_439, max(0, startMinutesFromMidnight))
        self.plannedSeconds = max(60, plannedSeconds)
        self.weekdays = weekdays
        self.kind = kind
        self.flexibility = flexibility
        self.behaviorPattern = behaviorPattern
        self.lifeDirection = lifeDirection
        self.isBehaviorHabit = isBehaviorHabit
        self.habitVersion = max(1, habitVersion)
        self.graduatedAt = graduatedAt
        self.habitLevelStartedAt = habitLevelStartedAt
        self.lastProgressPromptedAt = lastProgressPromptedAt
    }

    public var kind: PlanBlockKind {
        get { PlanBlockKind(rawValue: kindRaw) ?? .focus }
        set { kindRaw = newValue.rawValue }
    }

    public var flexibility: ScheduleFlexibility {
        get { ScheduleFlexibility(rawValue: flexibilityRaw) ?? .flexible }
        set { flexibilityRaw = newValue.rawValue }
    }

    public var behaviorPattern: BehaviorPattern? {
        get { behaviorPatternRaw.flatMap(BehaviorPattern.init(rawValue:)) }
        set { behaviorPatternRaw = newValue?.rawValue }
    }

    public var lifeDirection: LifeDirection? {
        get { lifeDirectionRaw.flatMap(LifeDirection.init(rawValue:)) }
        set { lifeDirectionRaw = newValue?.rawValue }
    }

    public var weekdays: Set<ScheduleWeekday> {
        get {
            guard weekdayMask != 0 else { return Set(ScheduleWeekday.allCases) }
            return Set(ScheduleWeekday.allCases.filter { weekdayMask & $0.bit != 0 })
        }
        set {
            weekdayMask = newValue.count == ScheduleWeekday.allCases.count
                ? 0
                : newValue.reduce(0) { $0 | $1.bit }
        }
    }

    public var isArchived: Bool { archivedAt != nil }
    public var isActiveBehaviorHabit: Bool {
        isBehaviorHabit && archivedAt == nil && graduatedAt == nil
    }
    public var currentHabitLevelStartedAt: Date { habitLevelStartedAt ?? createdAt }

    public func applies(to day: Date, calendar: Calendar = .current) -> Bool {
        !isArchived && weekdays.contains(ScheduleWeekday(day: day, calendar: calendar))
    }
}

/// One intention at a concrete time on one concrete day.
@Model
public final class PlanBlock {
    public var id: UUID = UUID()
    public var templateID: UUID?
    /// The day this block originally represented in its recurring template.
    /// It stays stable if the owner moves that one occurrence.
    public var templateOccurrenceDay: Date?
    /// A personalized occurrence is historical user intent, not disposable
    /// template output. Later routine edits and archival must leave it alone.
    public var isTemplateOverride: Bool = false
    public var sessionID: UUID?
    public var title: String = ""
    public var details: String = ""
    public var plannedStart: Date = Date()
    public var plannedSeconds: Int = 1_500
    public var actualStartedAt: Date?
    public var actualEndedAt: Date?
    public var stateRaw: String = PlanBlockState.planned.rawValue
    public var kindRaw: String = PlanBlockKind.focus.rawValue
    public var flexibilityRaw: String = ScheduleFlexibility.flexible.rawValue
    public var behaviorPatternRaw: String?
    public var lifeDirectionRaw: String?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(
        id: UUID = UUID(),
        templateID: UUID? = nil,
        templateOccurrenceDay: Date? = nil,
        isTemplateOverride: Bool = false,
        title: String,
        details: String = "",
        plannedStart: Date,
        plannedSeconds: Int,
        kind: PlanBlockKind = .focus,
        flexibility: ScheduleFlexibility = .flexible,
        behaviorPattern: BehaviorPattern? = nil,
        lifeDirection: LifeDirection? = nil
    ) {
        self.id = id
        self.templateID = templateID
        self.templateOccurrenceDay = templateOccurrenceDay
        self.isTemplateOverride = isTemplateOverride
        self.title = title
        self.details = details
        self.plannedStart = plannedStart
        self.plannedSeconds = max(60, plannedSeconds)
        self.kind = kind
        self.flexibility = flexibility
        self.behaviorPattern = behaviorPattern
        self.lifeDirection = lifeDirection
    }

    public convenience init(template: ScheduleTemplate, day: Date, calendar: Calendar = .current) {
        let startOfDay = calendar.startOfDay(for: day)
        let start = calendar.date(
            byAdding: .minute,
            value: template.startMinutesFromMidnight,
            to: startOfDay
        ) ?? startOfDay
        self.init(
            templateID: template.id,
            templateOccurrenceDay: startOfDay,
            title: template.title,
            details: template.details,
            plannedStart: start,
            plannedSeconds: template.plannedSeconds,
            kind: template.kind,
            flexibility: template.flexibility,
            behaviorPattern: template.behaviorPattern,
            lifeDirection: template.lifeDirection
        )
    }

    public var state: PlanBlockState {
        get { PlanBlockState(rawValue: stateRaw) ?? .planned }
        set { stateRaw = newValue.rawValue; updatedAt = Date() }
    }

    public var kind: PlanBlockKind {
        get { PlanBlockKind(rawValue: kindRaw) ?? .focus }
        set { kindRaw = newValue.rawValue }
    }

    public var flexibility: ScheduleFlexibility {
        get { ScheduleFlexibility(rawValue: flexibilityRaw) ?? .flexible }
        set { flexibilityRaw = newValue.rawValue }
    }

    public var behaviorPattern: BehaviorPattern? {
        get { behaviorPatternRaw.flatMap(BehaviorPattern.init(rawValue:)) }
        set { behaviorPatternRaw = newValue?.rawValue }
    }

    public var lifeDirection: LifeDirection? {
        get { lifeDirectionRaw.flatMap(LifeDirection.init(rawValue:)) }
        set { lifeDirectionRaw = newValue?.rawValue }
    }

    public var plannedEnd: Date { plannedStart.addingTimeInterval(Double(plannedSeconds)) }

    public func begin(at date: Date = Date()) {
        actualStartedAt = date
        actualEndedAt = nil
        state = .inProgress
    }

    public func complete(at date: Date = Date()) {
        if actualStartedAt != nil { actualEndedAt = date }
        state = .completed
    }
}

/// Explicit evidence about why reality diverged from a planned block.
@Model
public final class DivergenceEvent {
    public var id: UUID = UUID()
    public var blockID: UUID = UUID()
    public var sessionID: UUID?
    public var distractionID: UUID?
    public var occurredAt: Date = Date()
    public var kindRaw: String = DivergenceKind.unknown.rawValue
    public var evidenceRaw: String = DivergenceEvidence.userConfirmed.rawValue
    public var note: String = ""
    public var userConfirmed: Bool = true

    public init(
        id: UUID = UUID(),
        blockID: UUID,
        sessionID: UUID? = nil,
        distractionID: UUID? = nil,
        occurredAt: Date = Date(),
        kind: DivergenceKind,
        evidence: DivergenceEvidence = .userConfirmed,
        note: String = "",
        userConfirmed: Bool = true
    ) {
        self.id = id
        self.blockID = blockID
        self.sessionID = sessionID
        self.distractionID = distractionID
        self.occurredAt = occurredAt
        self.kind = kind
        self.evidence = evidence
        self.note = note
        self.userConfirmed = userConfirmed
    }

    public var kind: DivergenceKind {
        get { DivergenceKind(rawValue: kindRaw) ?? .unknown }
        set { kindRaw = newValue.rawValue }
    }

    public var evidence: DivergenceEvidence {
        get { DivergenceEvidence(rawValue: evidenceRaw) ?? .userConfirmed }
        set { evidenceRaw = newValue.rawValue }
    }
}

public enum PlanBlockKind: String, CaseIterable, Codable, Sendable {
    case focus, routine, commitment, rest, enjoyment

    public var label: String {
        switch self {
        case .focus: "Focus"
        case .routine: "Routine"
        case .commitment: "Commitment"
        case .rest: "Rest"
        case .enjoyment: "Enjoyment"
        }
    }

    public var symbolName: String {
        switch self {
        case .focus: "scope"
        case .routine: "repeat"
        case .commitment: "calendar"
        case .rest: "moon.zzz"
        case .enjoyment: "sparkles"
        }
    }
}

public enum ScheduleFlexibility: String, CaseIterable, Codable, Sendable {
    case fixed, flexible, optional

    public var label: String {
        switch self {
        case .fixed: "Fixed time"
        case .flexible: "Can move"
        case .optional: "Optional"
        }
    }
}

public enum PlanBlockState: String, CaseIterable, Codable, Sendable {
    case planned, inProgress, completed, skipped, moved
}

public enum DivergenceKind: String, CaseIterable, Codable, Sendable {
    case estimateOverrun, deliberateReplan, internalPull, externalInterruption, humanNeed, unknown

    public var label: String {
        switch self {
        case .estimateOverrun: "It needed more time"
        case .deliberateReplan: "I changed the plan"
        case .internalPull: "I went toward something else"
        case .externalInterruption: "Something came to me"
        case .humanNeed: "I needed food, rest, or recovery"
        case .unknown: "I’m not sure"
        }
    }

    public var symbolName: String {
        switch self {
        case .estimateOverrun: "hourglass"
        case .deliberateReplan: "arrow.triangle.branch"
        case .internalPull: "arrow.turn.down.right"
        case .externalInterruption: "bell.badge"
        case .humanNeed: "heart"
        case .unknown: "questionmark.circle"
        }
    }
}

public enum DivergenceEvidence: String, CaseIterable, Codable, Sendable {
    case userConfirmed, capturedInterruption, sessionTiming, scheduleChange, unknown
}

public enum ScheduleWeekday: Int, CaseIterable, Codable, Hashable, Sendable {
    case monday = 0, tuesday, wednesday, thursday, friday, saturday, sunday

    public init(day: Date, calendar: Calendar = .current) {
        let appleWeekday = calendar.component(.weekday, from: day) // Sunday = 1
        self = ScheduleWeekday(rawValue: (appleWeekday + 5) % 7) ?? .monday
    }

    public var bit: Int { 1 << rawValue }

    public var shortLabel: String {
        switch self {
        case .monday: "M"
        case .tuesday: "T"
        case .wednesday: "W"
        case .thursday: "T"
        case .friday: "F"
        case .saturday: "S"
        case .sunday: "S"
        }
    }

    public var label: String {
        switch self {
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        case .sunday: "Sunday"
        }
    }
}

// MARK: - Materialization

@MainActor
public struct DayPlanService {
    private let context: ModelContext
    public var calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    /// Materialize matching templates once for a day. No unique constraint is
    /// used because that would make the schema invalid for CloudKit.
    @discardableResult
    public func materialize(day: Date) throws -> [PlanBlock] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let allBlocks = try context.fetch(FetchDescriptor<PlanBlock>())
        let existing = allBlocks.filter {
            $0.plannedStart >= start && $0.plannedStart < end
        }
        let existingTemplateIDs = Set(allBlocks.filter {
            let occurrenceDay = $0.templateOccurrenceDay ?? $0.plannedStart
            return occurrenceDay >= start && occurrenceDay < end
        }.compactMap(\.templateID))
        let templates = try context.fetch(FetchDescriptor<ScheduleTemplate>())
        var blocks = existing

        for template in templates where template.applies(to: day, calendar: calendar) {
            guard !existingTemplateIDs.contains(template.id) else { continue }
            let block = PlanBlock(template: template, day: day, calendar: calendar)
            context.insert(block)
            blocks.append(block)
        }
        if context.hasChanges { try context.save() }
        return blocks.sorted { $0.plannedStart < $1.plannedStart }
    }

    /// Keep derivative, still-unstarted occurrences aligned with an edited or
    /// archived routine. Completed, skipped, moved, and in-progress history is
    /// preserved as the day was actually lived.
    public func reconcileFutureBlocks(for template: ScheduleTemplate, from date: Date = Date()) throws {
        let start = calendar.startOfDay(for: date)
        let future = try context.fetch(FetchDescriptor<PlanBlock>()).filter {
            let occurrenceDay = $0.templateOccurrenceDay ?? $0.plannedStart
            return $0.templateID == template.id
                && occurrenceDay >= start
                && $0.state == .planned
                && !$0.isTemplateOverride
        }

        for block in future {
            let occurrenceDay = block.templateOccurrenceDay ?? block.plannedStart
            guard template.applies(to: occurrenceDay, calendar: calendar) else {
                context.delete(block)
                continue
            }
            let day = calendar.startOfDay(for: occurrenceDay)
            block.title = template.title
            block.details = template.details
            block.plannedStart = calendar.date(
                byAdding: .minute,
                value: template.startMinutesFromMidnight,
                to: day
            ) ?? day
            block.plannedSeconds = template.plannedSeconds
            block.kind = template.kind
            block.flexibility = template.flexibility
            block.behaviorPattern = template.behaviorPattern
            block.lifeDirection = template.lifeDirection
            block.updatedAt = Date()
        }
        if context.hasChanges { try context.save() }
    }
}
