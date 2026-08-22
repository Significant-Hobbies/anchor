import Foundation

/// A wall-clock snapshot of the active session, published to whatever surface
/// needs a glanceable representation (currently the iPhone Live Activity).
///
/// This is a pure value type with no ActivityKit dependency, so the controller
/// can publish it from `AnchorCore` and the test suite can assert against it
/// without a simulator. The widget renders time from the dates here — never
/// from a tick counter — so it stays correct across sleep, relaunch, and the
/// same session being picked up on another device.
public struct LiveActivitySnapshot: Equatable, Hashable, Sendable, Codable {
    public let sessionID: UUID
    public let intent: String
    public let state: SessionState
    public let startedAt: Date
    public let plannedSeconds: Int
    public let bankedSeconds: Double
    public let runningSince: Date?
    public let pausedAt: Date?
    public let interruptionCount: Int

    public init(
        sessionID: UUID,
        intent: String,
        state: SessionState,
        startedAt: Date,
        plannedSeconds: Int,
        bankedSeconds: Double,
        runningSince: Date?,
        pausedAt: Date?,
        interruptionCount: Int
    ) {
        self.sessionID = sessionID
        self.intent = intent
        self.state = state
        self.startedAt = startedAt
        self.plannedSeconds = plannedSeconds
        self.bankedSeconds = bankedSeconds
        self.runningSince = runningSince
        self.pausedAt = pausedAt
        self.interruptionCount = interruptionCount
    }

    public var isOpenEnded: Bool { plannedSeconds <= 0 }

    /// The wall-clock instant when the plan will be met. The widget counts down
    /// to this date; `nil` for open-ended or paused sessions.
    public var plannedCompletionDate: Date? {
        guard !isOpenEnded, let runningSince else { return nil }
        let stillNeeded = max(0, Double(plannedSeconds) - bankedSeconds)
        return runningSince.addingTimeInterval(stillNeeded)
    }

    /// A wall-clock start suitable for an elapsed timer. Moving the current run
    /// backwards by already-banked focus keeps an open-ended session continuous
    /// across pause and resume instead of visually resetting it to zero.
    public var elapsedReferenceDate: Date? {
        runningSince?.addingTimeInterval(-bankedSeconds)
    }

    /// The value a non-running Live Activity should display. Planned sessions
    /// freeze on remaining time; open-ended sessions freeze on elapsed time.
    public var frozenDisplaySeconds: Double {
        isOpenEnded
            ? bankedSeconds
            : max(0, Double(plannedSeconds) - bankedSeconds)
    }
}

/// Keeps Live Activity lifecycle outside the session state machine, mirroring
/// `SessionCompletionNotifying`. Tests use a recording implementation; the iOS
/// app injects the ActivityKit implementation; Mac and watch use the no-op.
@MainActor
public protocol LiveActivityCoordinating: AnyObject {
    /// Begin a new Live Activity for the given snapshot. Replaces any existing
    /// activity — only one Anchor session is active at a time.
    func start(with snapshot: LiveActivitySnapshot)
    /// Push an updated snapshot to the existing Live Activity.
    func update(with snapshot: LiveActivitySnapshot)
    /// End and dismiss the Live Activity. Safe to call when none is active.
    func end()
}

@MainActor
public final class NoopLiveActivityCoordinator: LiveActivityCoordinating {
    public init() {}
    public func start(with snapshot: LiveActivitySnapshot) {}
    public func update(with snapshot: LiveActivitySnapshot) {}
    public func end() {}
}

// MARK: - ActivityKit (iOS only)

#if os(iOS)
import ActivityKit

/// The static attributes for an Anchor Live Activity. Set once at start; the
/// dynamic state travels in `ContentState`.
public struct FocusActivityAttributes: ActivityAttributes {
    public typealias ContentState = FocusActivityContentState

    public var sessionID: UUID

    public init(sessionID: UUID) {
        self.sessionID = sessionID
    }
}

/// The dynamic content the widget renders. Wraps the snapshot so the widget
/// extension depends only on `AnchorCore` value types, not on the controller.
public struct FocusActivityContentState: Codable, Hashable {
    public var snapshot: LiveActivitySnapshot

    public init(snapshot: LiveActivitySnapshot) {
        self.snapshot = snapshot
    }
}

/// The real iOS coordinator. All ActivityKit calls are guarded so that an
/// unavailable or disabled authorization never blocks session actions or
/// persistence — Live Activities are supplementary, not required.
@MainActor
public final class ActivityKitLiveActivityCoordinator: LiveActivityCoordinating {
    private var activity: Activity<FocusActivityAttributes>?
    private var updateTask: Task<Void, Never>?

    public init() {
        activity = Activity<FocusActivityAttributes>.activities.first
    }

    public func start(with snapshot: LiveActivitySnapshot) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            end()
            return
        }

        let existing = Activity<FocusActivityAttributes>.activities
        if let matching = existing.first(where: { $0.attributes.sessionID == snapshot.sessionID }) {
            activity = matching
            endActivities(existing.filter { $0.id != matching.id })
            update(with: snapshot)
            return
        }

        endActivities(existing)
        let attributes = FocusActivityAttributes(sessionID: snapshot.sessionID)
        let staleDate = snapshot.plannedCompletionDate
        let content = ActivityContent(
            state: FocusActivityContentState(snapshot: snapshot),
            staleDate: staleDate
        )
        do {
            // No push type: this is a purely local Live Activity.
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            // Safe degradation: the timer and completion notification still work.
        }
    }

    public func update(with snapshot: LiveActivitySnapshot) {
        let current = activity ?? Activity<FocusActivityAttributes>.activities.first {
            $0.attributes.sessionID == snapshot.sessionID
        }
        guard let current else {
            start(with: snapshot)
            return
        }
        guard current.attributes.sessionID == snapshot.sessionID else {
            start(with: snapshot)
            return
        }
        activity = current
        let staleDate = snapshot.plannedCompletionDate
        let box = SendableActivity(current)
        updateTask?.cancel()
        updateTask = Task { @MainActor [box] in
            let content = ActivityContent(
                state: FocusActivityContentState(snapshot: snapshot),
                staleDate: staleDate
            )
            await box.value.update(content)
        }
    }

    public func end() {
        var existing = Activity<FocusActivityAttributes>.activities
        if let activity, !existing.contains(where: { $0.id == activity.id }) {
            existing.append(activity)
        }
        self.activity = nil
        updateTask?.cancel()
        updateTask = nil
        endActivities(existing)
    }

    private func endActivities(_ activities: [Activity<FocusActivityAttributes>]) {
        guard !activities.isEmpty else { return }
        let boxes = activities.map(SendableActivity.init)
        Task { @MainActor [boxes] in
            for box in boxes {
                await box.value.end(nil, dismissalPolicy: .default)
            }
        }
    }
}

/// `Activity` is a non-`Sendable` class in the SDK, so it cannot be captured
/// directly in a `@Sendable` `Task` closure under Swift 6 strict concurrency.
/// This wrapper is `@unchecked Sendable` because the coordinator is
/// `@MainActor`-isolated and all access to the activity happens on the main
/// actor — the async `update`/`end` calls are dispatched from and return to it.
private struct SendableActivity: @unchecked Sendable {
    let value: Activity<FocusActivityAttributes>
    init(_ value: Activity<FocusActivityAttributes>) { self.value = value }
}
#endif
