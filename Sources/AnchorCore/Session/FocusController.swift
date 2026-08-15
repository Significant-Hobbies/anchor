import Foundation
import Observation
import SwiftData

/// The app's brain: owns the one active session, and is the only thing allowed
/// to mutate it. Every surface (Mac window, menu bar, iOS app) drives this.
@MainActor
@Observable
public final class FocusController {
    // MARK: State

    public private(set) var session: FocusSession?
    /// Ticks while a session runs. Views read this so they recompute each second
    /// without each view owning its own timer.
    public private(set) var now: Date = Date()

    /// Set when the planned duration is met and the user has not yet answered
    /// the bell. Drives the "done — extend or finish?" moment.
    public private(set) var hasReachedPlan: Bool = false

    /// Raised when a distraction is being captured. The capture sheet binds to this.
    public var isCapturing: Bool = false

    /// Why the capture sheet is open, which changes what it asks.
    public private(set) var captureReason: CaptureReason = .manual

    public enum CaptureReason: Equatable, Sendable {
        /// The user reached for it mid-session.
        case manual
        /// They just came back from a pause. Seconds spent away.
        case returnedFromPause(awaySeconds: Double)
    }

    public private(set) var lastError: String?

    private let context: ModelContext
    private let tagger: TaggingService
    private var ticker: Task<Void, Never>?

    public init(context: ModelContext, tagger: TaggingService = TaggingService()) {
        self.context = context
        self.tagger = tagger
        restoreActiveSession()
    }

    // MARK: - Derived

    public var isRunning: Bool { session?.state == .running }
    public var isPaused: Bool { session?.state == .paused }
    public var hasSession: Bool { session != nil }

    public var elapsed: Double { session?.account.elapsed(at: now) ?? 0 }
    public var remaining: Double { session?.account.remaining(at: now) ?? 0 }
    public var fraction: Double { session?.account.fraction(at: now) ?? 0 }

    /// Distractions parked during the current session, newest first.
    public var parked: [Distraction] {
        (session?.distractions ?? []).sorted { $0.capturedAt > $1.capturedAt }
    }

    // MARK: - Lifecycle

    /// Resume whatever was in flight when the app last quit. A session that was
    /// running keeps running — wall-clock timing means the elapsed count is
    /// still correct even if the app was closed for an hour.
    private func restoreActiveSession() {
        let running = SessionState.running.rawValue
        let paused = SessionState.paused.rawValue
        var descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.stateRaw == running || $0.stateRaw == paused },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        session = (try? context.fetch(descriptor))?.first
        if session != nil {
            refreshNow()
            startTicking()
        }
    }

    // MARK: - Commands

    @discardableResult
    public func start(goal: Goal?, intent: String, minutes: Int) -> FocusSession {
        end(reason: .endedEarly)

        let new = FocusSession(
            goal: goal,
            intent: intent.trimmingCharacters(in: .whitespacesAndNewlines),
            plannedSeconds: max(0, minutes * 60),
            startedAt: Date()
        )
        context.insert(new)
        session = new
        hasReachedPlan = false
        save()
        refreshNow()
        startTicking()

        if let goal { tagGoal(goal) }
        return new
    }

    public func pause() {
        guard let session, session.state == .running else { return }
        let now = Date()
        var account = session.account
        account.pause(at: now)
        session.apply(account)
        session.state = .paused
        session.pausedAt = now
        save()
        refreshNow()
        stopTicking()
    }

    /// Resuming always asks what pulled you away.
    ///
    /// A pause is the honest signal that something interrupted you — more honest
    /// than remembering to press the lock button first. Asking here is what turns
    /// the ordinary pause/resume habit into data, so the analytics reflect the
    /// interruptions you actually had rather than only the ones you logged.
    public func resume() {
        guard let session, session.state == .paused else { return }
        let now = Date()
        let awaySeconds = session.pausedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0

        var account = session.account
        account.resume(at: now)
        session.apply(account)
        session.state = .running
        session.pausedAt = nil
        save()
        refreshNow()
        startTicking()

        captureReason = .returnedFromPause(awaySeconds: awaySeconds)
        isCapturing = true
    }

    /// Open the capture sheet directly, mid-session.
    public func beginManualCapture() {
        guard hasSession else { return }
        captureReason = .manual
        isCapturing = true
    }

    /// Close it without recording anything — the pause really was just a break.
    public func dismissCapture() {
        isCapturing = false
        captureReason = .manual
    }

    public func extend(byMinutes minutes: Int) {
        guard let session, session.isActive else { return }
        var account = session.account
        account.extend(by: minutes * 60)
        if account.runningSince == nil { account.resume(at: Date()) }
        session.apply(account)
        session.state = .running
        hasReachedPlan = false
        save()
        refreshNow()
        startTicking()
    }

    public func end(reason: SessionEndReason = .endedEarly) {
        guard let session, session.isActive else { return }
        let stopAt = Date()
        var account = session.account
        account.stop(at: stopAt)
        session.apply(account)
        session.state = .finished
        session.endedAt = stopAt
        // Honour the real outcome: if the plan was met, it completed regardless
        // of which button ended it.
        session.endReason = account.hasMetPlan(at: stopAt) ? .completed : reason
        self.session = nil
        hasReachedPlan = false
        save()
        stopTicking()
    }

    /// Park a distraction and stay in the session. This is the core interaction.
    @discardableResult
    public func park(note: String, kind: DistractionKind? = nil) -> Distraction? {
        guard let session else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let distraction = Distraction(
            note: trimmed,
            capturedAt: Date(),
            offsetSeconds: session.account.elapsed(at: Date()),
            session: session,
            didReturnToFocus: true
        )
        if let kind {
            distraction.kind = kind
            distraction.kindIsUserSet = true
            distraction.kindConfidence = 1
        }
        context.insert(distraction)
        save()

        if kind == nil { tagDistraction(distraction) }
        return distraction
    }

    /// The distraction won. Record it honestly — a tool that only logs your wins
    /// produces analytics you cannot act on.
    public func surrender(to note: String) {
        let distraction = park(note: note)
        distraction?.didReturnToFocus = false
        end(reason: .abandoned)
        save()
    }

    public func markHandled(_ distraction: Distraction, handled: Bool = true) {
        distraction.handledAt = handled ? Date() : nil
        save()
    }

    // MARK: - Tagging (on-device)

    private func tagDistraction(_ distraction: Distraction) {
        let note = distraction.note
        let goalTitle = session?.goal?.title ?? session?.intent ?? ""
        Task { [weak self, tagger] in
            let result = await tagger.classifyDistraction(note: note, duringGoal: goalTitle)
            guard let self else { return }
            guard !distraction.kindIsUserSet else { return }
            distraction.kind = result.kind
            distraction.kindConfidence = result.confidence
            distraction.keywords = result.keywords
            self.save()
        }
    }

    private func tagGoal(_ goal: Goal) {
        guard goal.theme == nil else { return }
        let title = goal.title
        let notes = goal.notes
        Task { [weak self, tagger] in
            let result = await tagger.classifyGoal(title: title, notes: notes)
            guard let self else { return }
            goal.theme = result.theme
            goal.keywords = result.keywords
            if goal.symbolName == "target" { goal.symbolName = result.theme.symbolName }
            self.save()
        }
    }

    // MARK: - Ticking

    /// A cooperative loop rather than a `Timer`: it cancels itself when the
    /// controller goes away (the `weak self` guard ends the loop), so there is
    /// no `deinit` cleanup to get wrong, and no run-loop mode to configure.
    private func startTicking() {
        stopTicking()
        guard isRunning else { return }
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.isRunning else { return }
                self.refreshNow()
            }
        }
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }

    private func refreshNow() {
        now = Date()
        guard let session, session.isActive else { return }
        if !hasReachedPlan, session.account.hasMetPlan(at: now) {
            hasReachedPlan = true
        }
    }

    private func save() {
        do {
            try context.save()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
