import Foundation
import SwiftData

/// One run at a goal. Owns the distractions that hit during it.
@Model
public final class FocusSession {
    public var id: UUID = UUID()
    public var startedAt: Date = Date()
    public var endedAt: Date?

    // MARK: Timing (mirrors `TimeAccount`, flattened for a primitive schema)
    public var plannedSeconds: Int = 0
    public var bankedSeconds: Double = 0
    public var runningSince: Date?

    public var stateRaw: String = SessionState.running.rawValue
    public var endReasonRaw: String?

    /// When the current pause began. Persisted so that "how long were you away?"
    /// survives quitting the app mid-pause, which is the common case — you paused
    /// precisely because you were leaving.
    public var pausedAt: Date?

    /// What the user typed as the intention for *this* run. Often sharper than
    /// the goal title, and it is what the on-device model reads when tagging.
    public var intent: String = ""

    public var goal: Goal?

    @Relationship(deleteRule: .cascade, inverse: \Distraction.session)
    public var distractions: [Distraction]?

    public init(
        id: UUID = UUID(),
        goal: Goal?,
        intent: String = "",
        plannedSeconds: Int,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.goal = goal
        self.intent = intent
        self.plannedSeconds = plannedSeconds
        self.startedAt = startedAt
        self.runningSince = startedAt
        self.stateRaw = SessionState.running.rawValue
    }

    // MARK: - Derived

    public var state: SessionState {
        get { SessionState(rawValue: stateRaw) ?? .running }
        set { stateRaw = newValue.rawValue }
    }

    public var endReason: SessionEndReason? {
        get { endReasonRaw.flatMap(SessionEndReason.init(rawValue:)) }
        set { endReasonRaw = newValue?.rawValue }
    }

    /// The pure timing value. Write it back with ``apply(_:)``.
    public var account: TimeAccount {
        TimeAccount(
            plannedSeconds: plannedSeconds,
            bankedSeconds: bankedSeconds,
            runningSince: runningSince
        )
    }

    public func apply(_ account: TimeAccount) {
        plannedSeconds = account.plannedSeconds
        bankedSeconds = account.bankedSeconds
        runningSince = account.runningSince
    }

    public var isActive: Bool { state == .running || state == .paused }

    public var distractionCount: Int { distractions?.count ?? 0 }

    /// Active focus seconds, frozen once the session has ended.
    public func focusedSeconds(at now: Date = Date()) -> Double {
        isActive ? account.elapsed(at: now) : bankedSeconds
    }
}

public enum SessionState: String, Codable, Sendable, CaseIterable {
    case running
    case paused
    case finished
}

public enum SessionEndReason: String, Codable, Sendable, CaseIterable {
    /// Served the full planned duration.
    case completed
    /// User stopped early on purpose.
    case endedEarly
    /// User abandoned it for a distraction they chose not to park.
    case abandoned

    public var label: String {
        switch self {
        case .completed: "Completed"
        case .endedEarly: "Ended early"
        case .abandoned: "Abandoned"
        }
    }
}
