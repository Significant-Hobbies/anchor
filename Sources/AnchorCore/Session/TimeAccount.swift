import Foundation

/// The whole timing model, as a value type.
///
/// A session is not "a countdown that ticks". It is a bank of already-earned
/// seconds (`banked`) plus, when running, an open interval that started at
/// `runningSince`. Elapsed time is therefore always derived from the wall clock,
/// which means the number stays correct across app relaunch, device sleep,
/// and syncing the same session between a Mac and a phone.
///
/// Nothing here touches SwiftData, so it is exhaustively unit-testable.
public struct TimeAccount: Equatable, Sendable, Codable {
    /// Target length of the session, in seconds. Zero means open-ended.
    public var plannedSeconds: Int
    /// Active seconds accrued before the current run.
    public var bankedSeconds: Double
    /// Start of the currently open run, or `nil` when paused/finished.
    public var runningSince: Date?

    public init(plannedSeconds: Int, bankedSeconds: Double = 0, runningSince: Date? = nil) {
        self.plannedSeconds = plannedSeconds
        self.bankedSeconds = max(0, bankedSeconds)
        self.runningSince = runningSince
    }

    public var isRunning: Bool { runningSince != nil }
    public var isOpenEnded: Bool { plannedSeconds <= 0 }

    /// The wall-clock instant when the current running interval will satisfy
    /// the plan. Paused and open-ended sessions have no completion date.
    public var plannedCompletionDate: Date? {
        guard !isOpenEnded, let runningSince else { return nil }
        let secondsStillNeeded = max(0, Double(plannedSeconds) - bankedSeconds)
        return runningSince.addingTimeInterval(secondsStillNeeded)
    }

    /// Active seconds so far. Excludes every paused stretch.
    public func elapsed(at now: Date) -> Double {
        guard let runningSince else { return bankedSeconds }
        // Guard against a backwards clock (NTP correction, manual change).
        let openInterval = max(0, now.timeIntervalSince(runningSince))
        return bankedSeconds + openInterval
    }

    /// Seconds left before the planned duration is met. Never negative.
    /// Open-ended sessions always report zero remaining.
    public func remaining(at now: Date) -> Double {
        guard !isOpenEnded else { return 0 }
        return max(0, Double(plannedSeconds) - elapsed(at: now))
    }

    /// 0...1 completion against the plan. Open-ended sessions report 0.
    public func fraction(at now: Date) -> Double {
        guard !isOpenEnded else { return 0 }
        return min(1, max(0, elapsed(at: now) / Double(plannedSeconds)))
    }

    /// True once the planned duration has been served.
    public func hasMetPlan(at now: Date) -> Bool {
        !isOpenEnded && elapsed(at: now) >= Double(plannedSeconds)
    }

    // MARK: - Transitions

    /// Close the open interval and bank it. Idempotent when already paused.
    public mutating func pause(at now: Date) {
        guard runningSince != nil else { return }
        bankedSeconds = elapsed(at: now)
        runningSince = nil
    }

    /// Open a new interval. Idempotent when already running.
    public mutating func resume(at now: Date) {
        guard runningSince == nil else { return }
        runningSince = now
    }

    /// Bank everything and stop. Used when the session ends for any reason.
    public mutating func stop(at now: Date) {
        pause(at: now)
    }

    /// Extend the plan, e.g. the user chooses "5 more minutes" at the bell.
    public mutating func extend(by seconds: Int) {
        guard !isOpenEnded, seconds > 0 else { return }
        plannedSeconds += seconds
    }
}
