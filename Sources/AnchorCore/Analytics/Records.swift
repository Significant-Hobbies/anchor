import Foundation
import SwiftData

/// Plain snapshots of the persisted graph.
///
/// Analytics, spreadsheet export and the MCP server all read these instead of
/// touching SwiftData directly. That keeps the query logic pure and testable,
/// and means the MCP server can run in a plain command-line process without
/// dragging the whole app's main-actor world along with it.
public struct SessionRecord: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var goalTitle: String
    public var goalTheme: GoalTheme?
    public var intent: String
    public var startedAt: Date
    public var endedAt: Date?
    public var plannedSeconds: Int
    public var focusedSeconds: Double
    public var state: SessionState
    public var endReason: SessionEndReason?
    public var distractions: [DistractionRecord]
    public var projectTitle: String
    public var notes: String
    public var tags: [String]
    public var hourlyRate: Double
    public var currencyCode: String
    public var computerActiveSeconds: Double
    public var computerAwaySeconds: Double

    public init(
        id: UUID,
        goalTitle: String,
        goalTheme: GoalTheme?,
        intent: String,
        startedAt: Date,
        endedAt: Date?,
        plannedSeconds: Int,
        focusedSeconds: Double,
        state: SessionState,
        endReason: SessionEndReason?,
        distractions: [DistractionRecord],
        projectTitle: String = "",
        notes: String = "",
        tags: [String] = [],
        hourlyRate: Double = 0,
        currencyCode: String = "USD",
        computerActiveSeconds: Double = 0,
        computerAwaySeconds: Double = 0
    ) {
        self.id = id
        self.goalTitle = goalTitle
        self.goalTheme = goalTheme
        self.intent = intent
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedSeconds = plannedSeconds
        self.focusedSeconds = focusedSeconds
        self.state = state
        self.endReason = endReason
        self.distractions = distractions
        self.projectTitle = projectTitle
        self.notes = notes
        self.tags = tags
        self.hourlyRate = hourlyRate
        self.currencyCode = currencyCode
        self.computerActiveSeconds = computerActiveSeconds
        self.computerAwaySeconds = computerAwaySeconds
    }

    public var focusedMinutes: Double { focusedSeconds / 60 }
    public var earnedAmount: Double { focusedSeconds / 3600 * hourlyRate }
    public var computerObservedSeconds: Double { computerActiveSeconds + computerAwaySeconds }
    public var computerActiveRate: Double? {
        computerObservedSeconds > 0 ? computerActiveSeconds / computerObservedSeconds : nil
    }

    /// Interruptions per hour of actual focus — the comparable number, since a
    /// 25-minute session with two interruptions is worse than a 2-hour one with three.
    public var interruptionRate: Double {
        guard focusedSeconds > 60 else { return 0 }
        return Double(distractions.count) / (focusedSeconds / 3600)
    }

    /// True when the session ran its full planned length.
    public var didComplete: Bool { endReason == .completed }
}

public struct MachineActivityRecord: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var day: Date
    public var activeSeconds: Double
    public var trackedSeconds: Double

    public init(id: UUID, day: Date, activeSeconds: Double, trackedSeconds: Double) {
        self.id = id
        self.day = day
        self.activeSeconds = activeSeconds
        self.trackedSeconds = trackedSeconds
    }

    public var untrackedSeconds: Double { max(0, activeSeconds - trackedSeconds) }
}

public struct DistractionRecord: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var note: String
    public var kind: DistractionKind
    public var keywords: [String]
    public var capturedAt: Date
    public var offsetSeconds: Double
    public var didReturnToFocus: Bool
    public var isHandled: Bool
    public var confidence: Double
    public var tags: [String]

    public init(
        id: UUID,
        note: String,
        kind: DistractionKind,
        keywords: [String],
        capturedAt: Date,
        offsetSeconds: Double,
        didReturnToFocus: Bool,
        isHandled: Bool,
        confidence: Double,
        tags: [String] = []
    ) {
        self.id = id
        self.note = note
        self.kind = kind
        self.keywords = keywords
        self.capturedAt = capturedAt
        self.offsetSeconds = offsetSeconds
        self.didReturnToFocus = didReturnToFocus
        self.isHandled = isHandled
        self.confidence = confidence
        self.tags = tags
    }

    public var origin: DistractionOrigin { kind.origin }
}

// MARK: - Mapping

public extension Distraction {
    func snapshot(tagNamesByID: [String: String] = [:]) -> DistractionRecord {
        DistractionRecord(
            id: id,
            note: privateNote,
            kind: displayKind,
            keywords: privateKeywords,
            capturedAt: capturedAt,
            offsetSeconds: offsetSeconds,
            didReturnToFocus: didReturnToFocus,
            isHandled: isHandled,
            confidence: kindConfidence,
            tags: tagIDStrings.compactMap { tagNamesByID[$0] }
        )
    }
}

public extension FocusSession {
    func snapshot(at now: Date = Date(), tagNamesByID: [String: String] = [:]) -> SessionRecord {
        SessionRecord(
            id: id,
            goalTitle: goal?.title ?? "",
            goalTheme: goal?.theme,
            intent: intent,
            startedAt: startedAt,
            endedAt: endedAt,
            plannedSeconds: plannedSeconds,
            focusedSeconds: focusedSeconds(at: now),
            state: state,
            endReason: endReason,
            distractions: (distractions ?? [])
                .sorted { $0.capturedAt < $1.capturedAt }
                .map { $0.snapshot(tagNamesByID: tagNamesByID) },
            projectTitle: project?.name ?? "",
            notes: notes,
            tags: tagIDStrings.compactMap { tagNamesByID[$0] },
            hourlyRate: hourlyRate,
            currencyCode: currencyCode,
            computerActiveSeconds: computerActiveSeconds,
            computerAwaySeconds: computerAwaySeconds
        )
    }
}

public extension MachineActivityDay {
    func snapshot() -> MachineActivityRecord {
        MachineActivityRecord(
            id: id,
            day: day,
            activeSeconds: activeSeconds,
            trackedSeconds: trackedSeconds
        )
    }
}

public extension ModelContext {
    /// Every session, newest first, as snapshots.
    func sessionRecords(since: Date? = nil, at now: Date = Date()) throws -> [SessionRecord] {
        let tagNamesByID = Dictionary(
            uniqueKeysWithValues: try fetch(FetchDescriptor<SavedTag>()).map { ($0.storageID, $0.name) }
        )
        var descriptor = FetchDescriptor<FocusSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        if let since {
            descriptor.predicate = #Predicate { $0.startedAt >= since }
        }
        let sessions = try fetch(descriptor)
        for session in sessions {
            for distraction in session.distractions ?? [] {
                _ = try localDistractionNotes?.read(distraction.id)
            }
        }
        return sessions.map { $0.snapshot(at: now, tagNamesByID: tagNamesByID) }
    }
}
