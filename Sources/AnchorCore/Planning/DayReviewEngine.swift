import Foundation
import SwiftData

public struct PlanBlockRecord: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var templateID: UUID?
    public var sessionID: UUID?
    public var title: String
    public var plannedStart: Date
    public var plannedSeconds: Int
    public var actualStartedAt: Date?
    public var actualEndedAt: Date?
    public var state: PlanBlockState
    public var kind: PlanBlockKind
    public var flexibility: ScheduleFlexibility
    public var behaviorPattern: BehaviorPattern?
    public var lifeDirection: LifeDirection?

    public init(
        id: UUID,
        templateID: UUID? = nil,
        sessionID: UUID? = nil,
        title: String,
        plannedStart: Date,
        plannedSeconds: Int,
        actualStartedAt: Date? = nil,
        actualEndedAt: Date? = nil,
        state: PlanBlockState = .planned,
        kind: PlanBlockKind = .focus,
        flexibility: ScheduleFlexibility = .flexible,
        behaviorPattern: BehaviorPattern? = nil,
        lifeDirection: LifeDirection? = nil
    ) {
        self.id = id
        self.templateID = templateID
        self.sessionID = sessionID
        self.title = title
        self.plannedStart = plannedStart
        self.plannedSeconds = plannedSeconds
        self.actualStartedAt = actualStartedAt
        self.actualEndedAt = actualEndedAt
        self.state = state
        self.kind = kind
        self.flexibility = flexibility
        self.behaviorPattern = behaviorPattern
        self.lifeDirection = lifeDirection
    }
}

public struct DivergenceRecord: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var blockID: UUID
    public var sessionID: UUID?
    public var distractionID: UUID?
    public var occurredAt: Date
    public var kind: DivergenceKind
    public var evidence: DivergenceEvidence
    public var note: String
    public var userConfirmed: Bool

    public init(
        id: UUID,
        blockID: UUID,
        sessionID: UUID? = nil,
        distractionID: UUID? = nil,
        occurredAt: Date,
        kind: DivergenceKind,
        evidence: DivergenceEvidence,
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
}

public struct BehaviorProfileRecord: Sendable, Codable, Equatable {
    public var selectedPatterns: Set<BehaviorPattern>
    public var desiredDirections: Set<LifeDirection>

    public init(
        selectedPatterns: Set<BehaviorPattern> = [],
        desiredDirections: Set<LifeDirection> = []
    ) {
        self.selectedPatterns = selectedPatterns
        self.desiredDirections = desiredDirections
    }
}

public extension PlanBlock {
    func snapshot() -> PlanBlockRecord {
        PlanBlockRecord(
            id: id,
            templateID: templateID,
            sessionID: sessionID,
            title: title,
            plannedStart: plannedStart,
            plannedSeconds: plannedSeconds,
            actualStartedAt: actualStartedAt,
            actualEndedAt: actualEndedAt,
            state: state,
            kind: kind,
            flexibility: flexibility,
            behaviorPattern: behaviorPattern,
            lifeDirection: lifeDirection
        )
    }
}

public extension DivergenceEvent {
    func snapshot() -> DivergenceRecord {
        DivergenceRecord(
            id: id,
            blockID: blockID,
            sessionID: sessionID,
            distractionID: distractionID,
            occurredAt: occurredAt,
            kind: kind,
            evidence: evidence,
            note: note,
            userConfirmed: userConfirmed
        )
    }
}

public extension BehaviorProfile {
    func snapshot() -> BehaviorProfileRecord {
        BehaviorProfileRecord(
            selectedPatterns: selectedPatterns,
            desiredDirections: desiredDirections
        )
    }
}

public extension ModelContext {
    func planBlockRecords(on day: Date, calendar: Calendar = .current) throws -> [PlanBlockRecord] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return try fetch(FetchDescriptor<PlanBlock>())
            .filter { $0.plannedStart >= start && $0.plannedStart < end }
            .sorted { $0.plannedStart < $1.plannedStart }
            .map { $0.snapshot() }
    }

    func divergenceRecords(on day: Date, calendar: Calendar = .current) throws -> [DivergenceRecord] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return try fetch(FetchDescriptor<DivergenceEvent>())
            .filter { $0.occurredAt >= start && $0.occurredAt < end }
            .sorted { $0.occurredAt < $1.occurredAt }
            .map { $0.snapshot() }
    }

    func behaviorProfileRecord() throws -> BehaviorProfileRecord {
        try fetch(FetchDescriptor<BehaviorProfile>()).first?.snapshot() ?? BehaviorProfileRecord()
    }
}

/// Pure reconciliation between what was planned, what Anchor observed, and what
/// the owner explicitly said changed. No adherence score is calculated.
public struct DayReviewEngine: Sendable {
    public struct Review: Sendable, Equatable, Codable {
        public var day: Date
        public var plannedSeconds: Double
        public var actualSeconds: Double
        public var unobservedCompletedBlocks: Int
        public var gaps: [Gap]
        public var suggestions: [Suggestion]
    }

    public struct Gap: Sendable, Equatable, Codable, Identifiable {
        public var id: UUID { blockID }
        public var blockID: UUID
        public var title: String
        public var plannedSeconds: Double
        public var actualSeconds: Double
        public var actualDurationKnown: Bool
        public var varianceSeconds: Double
        public var cause: DivergenceKind
        public var evidence: DivergenceEvidence
        public var evidenceDescription: String

        public var magnitude: Double { abs(varianceSeconds) }
    }

    public struct Suggestion: Sendable, Equatable, Codable, Identifiable {
        public var id: String { "\(blockID.uuidString)-\(kind.rawValue)" }
        public var blockID: UUID
        public var kind: DivergenceKind
        public var title: String
        public var detail: String
    }

    public var calendar: Calendar
    public var meaningfulGapSeconds: Double

    public init(calendar: Calendar = .current, meaningfulGapSeconds: Double = 5 * 60) {
        self.calendar = calendar
        self.meaningfulGapSeconds = meaningfulGapSeconds
    }

    public func review(
        day: Date,
        blocks: [PlanBlockRecord],
        sessions: [SessionRecord],
        divergences: [DivergenceRecord],
        profile: BehaviorProfileRecord = BehaviorProfileRecord()
    ) -> Review {
        let sessionsByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let divergencesByBlock = Dictionary(grouping: divergences, by: \.blockID)
        var planned: Double = 0
        var actual: Double = 0
        var unobservedCompletedBlocks = 0
        var gaps: [Gap] = []

        for block in blocks {
            let plannedSeconds = Double(block.plannedSeconds)
            let session = block.sessionID.flatMap { sessionsByID[$0] }
            let storedActual = storedActualSeconds(block)
            let actualDurationKnown = session != nil || storedActual != nil
            let actualSeconds = session?.focusedSeconds ?? storedActual ?? 0
            planned += plannedSeconds
            actual += actualSeconds
            if !actualDurationKnown && block.state == .completed {
                unobservedCompletedBlocks += 1
            }

            let explicit = divergencesByBlock[block.id]?.sorted { $0.occurredAt > $1.occurredAt }.first
            let capturedCause = session.flatMap(capturedInterruptionCause)
            let cause = explicit?.kind ?? capturedCause?.kind ?? .unknown
            let evidence = explicit?.evidence ?? capturedCause?.evidence ?? .unknown
            let description = explicit.map(explicitDescription)
                ?? capturedCause?.description
                ?? (!actualDurationKnown && block.state == .completed
                    ? "Marked complete without timing; the duration was not observed."
                    : nil)
                ?? "No captured event explains this gap yet."
            let variance = actualDurationKnown ? actualSeconds - plannedSeconds : 0
            let shouldShow = (actualDurationKnown && abs(variance) >= meaningfulGapSeconds)
                || explicit != nil
                || block.state == .skipped
                || (!actualDurationKnown && block.state == .completed)
                || (session?.endReason == .abandoned)

            if shouldShow {
                gaps.append(Gap(
                    blockID: block.id,
                    title: block.title,
                    plannedSeconds: plannedSeconds,
                    actualSeconds: actualSeconds,
                    actualDurationKnown: actualDurationKnown,
                    varianceSeconds: variance,
                    cause: cause,
                    evidence: evidence,
                    evidenceDescription: description
                ))
            }
        }

        let linkedSessionIDs = Set(blocks.compactMap(\.sessionID))
        for session in sessions where !linkedSessionIDs.contains(session.id) {
            let actualSeconds = session.focusedSeconds
            actual += actualSeconds
            let explicit = divergencesByBlock[session.id]?.sorted { $0.occurredAt > $1.occurredAt }.first
            let capturedCause = capturedInterruptionCause(session)
            guard actualSeconds >= meaningfulGapSeconds || capturedCause != nil || explicit != nil else { continue }
            gaps.append(Gap(
                blockID: session.id,
                title: session.intent.isEmpty ? (session.goalTitle.isEmpty ? "Unplanned focus" : session.goalTitle) : session.intent,
                plannedSeconds: 0,
                actualSeconds: actualSeconds,
                actualDurationKnown: true,
                varianceSeconds: actualSeconds,
                cause: explicit?.kind ?? capturedCause?.kind ?? .unknown,
                evidence: explicit?.evidence ?? capturedCause?.evidence ?? .sessionTiming,
                evidenceDescription: explicit.map(explicitDescription)
                    ?? capturedCause?.description
                    ?? "Anchor observed this unplanned session; no cause for the schedule change was recorded."
            ))
        }

        gaps.sort { ($0.magnitude, $0.title) > ($1.magnitude, $1.title) }
        return Review(
            day: calendar.startOfDay(for: day),
            plannedSeconds: planned,
            actualSeconds: actual,
            unobservedCompletedBlocks: unobservedCompletedBlocks,
            gaps: gaps,
            suggestions: Array(gaps.prefix(3).map { suggestion(for: $0, profile: profile) })
        )
    }

    private func storedActualSeconds(_ block: PlanBlockRecord) -> Double? {
        guard let start = block.actualStartedAt, let end = block.actualEndedAt else { return nil }
        return max(0, end.timeIntervalSince(start))
    }

    private func capturedInterruptionCause(
        _ session: SessionRecord
    ) -> (kind: DivergenceKind, evidence: DivergenceEvidence, description: String)? {
        guard !session.distractions.isEmpty else { return nil }
        let counts = Dictionary(grouping: session.distractions, by: \.origin).mapValues(\.count)
        let origin = counts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key.rawValue > rhs.key.rawValue : lhs.value < rhs.value
        }?.key ?? .mixed
        let kind: DivergenceKind = switch origin {
        case .external: .externalInterruption
        case .internal: .internalPull
        case .mixed: .unknown
        }
        return (
            kind,
            .capturedInterruption,
            "\(session.distractions.count) captured interruption\(session.distractions.count == 1 ? "" : "s") during this session."
        )
    }

    private func explicitDescription(_ record: DivergenceRecord) -> String {
        let trimmed = record.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Cause confirmed by you." : trimmed
    }

    private func suggestion(for gap: Gap, profile: BehaviorProfileRecord) -> Suggestion {
        if !gap.actualDurationKnown
            && gap.evidence == .unknown
            && gap.evidenceDescription.contains("duration was not observed") {
            return Suggestion(
                blockID: gap.blockID,
                kind: .unknown,
                title: "Keep the completion, not a made-up duration",
                detail: "Anchor knows this happened but not how long it took. Time it next time only if the duration matters."
            )
        }
        let minutes = max(5, Int((gap.magnitude / 60).rounded()))
        switch gap.cause {
        case .estimateOverrun:
            return Suggestion(
                blockID: gap.blockID,
                kind: gap.cause,
                title: "Give \(gap.title) a little more room",
                detail: "The evidence supports trying about \(minutes) more minutes next time."
            )
        case .deliberateReplan:
            return Suggestion(
                blockID: gap.blockID,
                kind: gap.cause,
                title: "Let the plan reflect the choice",
                detail: "If this change still feels right, adjust the future block instead of counting it as failure."
            )
        case .internalPull:
            let replacement = profile.desiredDirections.sorted { $0.rawValue < $1.rawValue }.first?.label
            let noticedPattern = profile.selectedPatterns.sorted { $0.rawValue < $1.rawValue }.first?.label
            return Suggestion(
                blockID: gap.blockID,
                kind: gap.cause,
                title: "Make the alternative easier to reach",
                detail: replacement.map { replacement in
                    noticedPattern.map { "You chose \($0) as a pattern to notice. Put \(replacement) within reach before this block begins." }
                        ?? "Put \(replacement) beside this vulnerable part of the day."
                } ?? noticedPattern.map { "You chose \($0) as a pattern to notice. Decide on one satisfying alternative before this block begins." }
                    ?? "Choose one satisfying alternative before this block begins."
            )
        case .externalInterruption:
            return Suggestion(
                blockID: gap.blockID,
                kind: gap.cause,
                title: "Protect or buffer this block",
                detail: "Try a small buffer, a quieter setting, or a clearer availability boundary."
            )
        case .humanNeed:
            return Suggestion(
                blockID: gap.blockID,
                kind: gap.cause,
                title: "Plan for being human",
                detail: "Leave food, rest, transition, or recovery time around this block."
            )
        case .unknown:
            return Suggestion(
                blockID: gap.blockID,
                kind: gap.cause,
                title: "Keep this gap unknown for now",
                detail: "Clarify it once before changing the schedule; Anchor does not have enough evidence yet."
            )
        }
    }
}
