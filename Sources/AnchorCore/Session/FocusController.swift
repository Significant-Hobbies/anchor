import CoreData
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

    private let hubOwner: @MainActor () -> String?
    private let context: ModelContext
    private let persistContext: @MainActor (ModelContext) throws -> Void
    private let tagger: TaggingService
    private let completionNotifier: any SessionCompletionNotifying
    private let liveActivityCoordinator: any LiveActivityCoordinating
    private var ticker: Task<Void, Never>?
    private var remoteChangeTask: Task<Void, Never>?
    private var lastMachineObservation: (sessionID: UUID, at: Date)?
    private var pendingMachineActiveSeconds: Double = 0
    private var pendingMachineAwaySeconds: Double = 0

    public init(
        context: ModelContext,
        tagger: TaggingService = TaggingService(),
        completionNotifier: any SessionCompletionNotifying = NoopSessionCompletionNotifier(),
        liveActivityCoordinator: any LiveActivityCoordinating = NoopLiveActivityCoordinator(),
        hubOwner: @escaping @MainActor () -> String? = { nil },
        persistContext: @escaping @MainActor (ModelContext) throws -> Void = { try AnchorStore.save($0) }
    ) {
        self.context = context
        self.persistContext = persistContext
        self.hubOwner = hubOwner
        self.tagger = tagger
        self.completionNotifier = completionNotifier
        self.liveActivityCoordinator = liveActivityCoordinator
        restoreActiveSession()
        observeRemoteStoreChanges()
    }

    /// SwiftData imports CloudKit transactions into the store independently of
    /// this controller's concrete model reference. Re-fetch after every remote
    /// store change so an already-open Mac, phone, or Watch reflects the state
    /// written by another device without requiring an app relaunch.
    private func observeRemoteStoreChanges() {
        remoteChangeTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: .NSPersistentStoreRemoteChange
            ) {
                guard !Task.isCancelled else { return }
                self?.synchronizeActiveSessionFromStore()
            }
        }
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
        session = fetchLatestActiveSession()
        if session != nil {
            scheduleCompletionNotification()
            refresh(at: Date())
            startTicking()
            publishLiveActivityStart()
        } else {
            publishLiveActivityEnd()
        }
    }

    /// Reconcile the controller after SwiftData imports a change from CloudKit.
    ///
    /// A `@Query` sees imported records, but the controller deliberately owns a
    /// concrete active session. Without this bridge, a session created on another
    /// device can exist in the store while the timer surface still says idle.
    public func synchronizeActiveSessionFromStore() {
        do { try AnchorStore.migratePrivateNotes(in: context) }
        catch {
            lastError = "An older-device note could not be secured locally. Check available storage before continuing."
            return
        }
        let imported = fetchLatestActiveSession()

        if session?.id != imported?.id {
            if let previous = session {
                completionNotifier.cancel(sessionID: previous.id)
            }
            session = imported
            resetMachineObservation()
            if imported != nil {
                publishLiveActivityStart()
            } else {
                publishLiveActivityEnd()
            }
        }

        guard let session else {
            stopTicking()
            return
        }

        if session.state == .running {
            scheduleCompletionNotification()
            refresh(at: Date())
            startTicking()
        } else {
            completionNotifier.cancel(sessionID: session.id)
            stopTicking()
            refresh(at: Date())
        }
        publishLiveActivityUpdate()
    }

    private func fetchLatestActiveSession() -> FocusSession? {
        let running = SessionState.running.rawValue
        let paused = SessionState.paused.rawValue
        var descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.stateRaw == running || $0.stateRaw == paused },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Commands

    @discardableResult
    public func start(
        goal: Goal?,
        intent: String,
        minutes: Int,
        project: Project? = nil,
        notes: String = "",
        tagIDStrings: [String] = []
    ) -> FocusSession {
        end(reason: .endedEarly)

        let new = FocusSession(
            goal: goal,
            intent: intent.trimmingCharacters(in: .whitespacesAndNewlines),
            project: project,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            tagIDStrings: tagIDStrings,
            hourlyRate: project?.hourlyRate ?? 0,
            currencyCode: project?.currencyCode ?? "USD",
            plannedSeconds: max(0, minutes * 60),
            startedAt: Date()
        )
        new.hubAccountID = hubOwner()
        context.insert(new)
        session = new
        resetMachineObservation()
        save()
        refreshNow()
        scheduleCompletionNotification()
        startTicking()
        publishLiveActivityStart()

        if let goal { tagGoal(goal) }
        return new
    }

    public func pause() {
        _ = pauseSession()
    }

    private func pauseSession(captured: Distraction? = nil) -> Bool {
        guard let session, session.state == .running else { return false }
        let previousAccount = session.account
        let previousPausedAt = session.pausedAt
        let previousActive = session.computerActiveSeconds
        let previousAway = session.computerAwaySeconds
        let previousPendingActive = pendingMachineActiveSeconds
        let previousPendingAway = pendingMachineAwaySeconds
        let previousObservation = lastMachineObservation
        let now = Date()
        var account = previousAccount
        account.pause(at: now)
        session.apply(account)
        session.state = .paused
        session.pausedAt = now
        captured?.capturedAt = now
        captured?.didReturnToFocus = false
        commitMachineObservation(to: session)
        guard save() else {
            session.apply(previousAccount)
            session.state = .running
            session.pausedAt = previousPausedAt
            session.computerActiveSeconds = previousActive
            session.computerAwaySeconds = previousAway
            pendingMachineActiveSeconds = previousPendingActive
            pendingMachineAwaySeconds = previousPendingAway
            lastMachineObservation = previousObservation
            refreshNow()
            return false
        }
        completionNotifier.cancel(sessionID: session.id)
        refreshNow()
        stopTicking()
        publishLiveActivityUpdate()
        return true
    }

    /// Capture an interruption and step away without ending the current session.
    /// An empty note is a plain break; a recorded interruption only counts as a
    /// return to focus after the owner actually resumes.
    @discardableResult
    public func pauseFromCapture(
        note: String,
        kind: DistractionKind? = nil,
        tagIDStrings: [String] = []
    ) -> Bool {
        guard isRunning else { return false }
        var captured: Distraction?
        if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let distraction = makeDistraction(note: note, kind: kind, tagIDStrings: tagIDStrings) else { return false }
            captured = distraction
        }
        guard pauseSession(captured: captured) else {
            if let captured { discardUncommittedDistraction(captured) }
            return false
        }
        if let captured, kind == nil { tagDistraction(captured) }
        dismissCapture()
        return true
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

        if let pausedAt = session.pausedAt {
            for distraction in parked where distraction.capturedAt >= pausedAt {
                distraction.didReturnToFocus = true
            }
        }

        var account = session.account
        account.resume(at: now)
        session.apply(account)
        session.state = .running
        session.pausedAt = nil
        resetMachineObservation()
        save()
        refreshNow()
        scheduleCompletionNotification()
        startTicking()
        publishLiveActivityUpdate()

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
        save()
        refreshNow()
        scheduleCompletionNotification()
        startTicking()
        publishLiveActivityUpdate()
    }

    public func end(reason: SessionEndReason = .endedEarly) {
        guard let session, session.isActive else { return }
        finish(session, reason: reason, at: Date(), cancelNotification: true)
    }

    private func finish(
        _ session: FocusSession,
        reason: SessionEndReason,
        at stopAt: Date,
        cancelNotification: Bool
    ) {
        var account = session.account
        account.stop(at: stopAt)
        session.apply(account)
        session.state = .finished
        session.endedAt = stopAt
        // Honour the real outcome: if the plan was met, it completed regardless
        // of which button ended it.
        session.endReason = account.hasMetPlan(at: stopAt) ? .completed : reason
        if cancelNotification {
            completionNotifier.cancel(sessionID: session.id)
        }
        commitMachineObservation(to: session)
        self.session = nil
        save()
        stopTicking()
        publishLiveActivityEnd()
    }

    /// Park a distraction and stay in the session. This is the core interaction.
    @discardableResult
    public func park(
        note: String,
        kind: DistractionKind? = nil,
        tagIDStrings: [String] = []
    ) -> Distraction? {
        guard let distraction = makeDistraction(note: note, kind: kind, tagIDStrings: tagIDStrings) else { return nil }
        guard save() else {
            discardUncommittedDistraction(distraction)
            return nil
        }
        publishLiveActivityUpdate()
        if kind == nil { tagDistraction(distraction) }
        return distraction
    }

    private func makeDistraction(note: String, kind: DistractionKind?, tagIDStrings: [String]) -> Distraction? {
        guard let session else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let distraction = Distraction(
            note: trimmed,
            capturedAt: Date(),
            offsetSeconds: session.account.elapsed(at: Date()),
            session: nil,
            didReturnToFocus: true,
            tagIDStrings: tagIDStrings
        )
        if let kind {
            distraction.kind = kind
            distraction.kindIsUserSet = true
            distraction.kindConfidence = 1
        }
        do { try distraction.persistPrivateContent(in: context) }
        catch {
            lastError = "Could not save the private note on this device. Your draft is still available."
            return nil
        }
        distraction.session = session
        context.insert(distraction)
        return distraction
    }

    private func discardUncommittedDistraction(_ distraction: Distraction) {
        // Clear the inverse immediately: ModelContext.delete alone can leave a
        // phantom parked item visible until the next successful save.
        distraction.session = nil
        context.delete(distraction)
        do { try context.localDistractionNotes?.delete(distraction.id) }
        catch {
            lastError = "The note was not confirmed. Your draft remains available; an uncommitted local copy also needs cleanup."
        }
    }

    /// The distraction won. Record it honestly — a tool that only logs your wins
    /// produces analytics you cannot act on.
    @discardableResult
    public func surrender(to note: String, tagIDStrings: [String] = []) -> Bool {
        guard let distraction = park(note: note, tagIDStrings: tagIDStrings) else { return false }
        distraction.didReturnToFocus = false
        end(reason: .abandoned)
        return save()
    }

    public func markHandled(_ distraction: Distraction, handled: Bool = true) {
        distraction.handledAt = handled ? Date() : nil
        save()
    }

    /// Called by the macOS shell with the system's current input-idle duration.
    /// The split is derived from wall-clock intervals and is analytics-only; it
    /// never changes `TimeAccount` or the focus timer.
    public func observeMachineIdle(seconds idleSeconds: Double, at timestamp: Date = Date()) {
        guard let session, session.state == .running else {
            resetMachineObservation()
            return
        }
        defer { lastMachineObservation = (session.id, timestamp) }
        guard let previous = lastMachineObservation,
              previous.sessionID == session.id,
              timestamp >= previous.at
        else { return }

        let interval = timestamp.timeIntervalSince(previous.at)
        guard interval > 0 else { return }
        let away = min(interval, max(0, idleSeconds))
        // Keep presence samples transient while the timer is running. Saving
        // the whole FocusSession every minute can overwrite a newer pause/end
        // imported from iPhone or Watch before CloudKit delivers it.
        pendingMachineAwaySeconds += away
        pendingMachineActiveSeconds += max(0, interval - away)
    }

    // MARK: - Tagging (on-device)

    private func tagDistraction(_ distraction: Distraction) {
        let note = distraction.privateNote
        let goalTitle = session?.goal?.title ?? session?.intent ?? ""
        Task { [weak self, tagger] in
            let result = await tagger.classifyDistraction(note: note, duringGoal: goalTitle)
            guard let self else { return }
            guard !distraction.kindIsUserSet else { return }
            distraction.kind = result.kind
            distraction.kindConfidence = result.confidence
            distraction.privateKeywords = result.keywords
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
        refresh(at: Date())
    }

    /// Internal so controller tests can advance wall-clock time without sleeping.
    func refresh(at timestamp: Date) {
        now = timestamp
        guard let session, session.state == .running else { return }
        guard let completionDate = session.account.plannedCompletionDate else { return }
        guard timestamp >= completionDate else { return }

        // Freeze at the exact planned instant. If the process wakes late after
        // sleep or relaunch, that delay is not counted as extra focused time.
        // Keep the already-scheduled notification alive so the system can show it.
        finish(session, reason: .completed, at: completionDate, cancelNotification: false)
    }

    private func scheduleCompletionNotification() {
        guard let session, session.state == .running else { return }
        guard let completionDate = session.account.plannedCompletionDate else { return }
        completionNotifier.schedule(
            sessionID: session.id,
            intent: session.intent,
            after: completionDate.timeIntervalSinceNow
        )
    }

    private func commitMachineObservation(to session: FocusSession) {
        session.computerActiveSeconds += pendingMachineActiveSeconds
        session.computerAwaySeconds += pendingMachineAwaySeconds
        resetMachineObservation()
    }

    private func resetMachineObservation() {
        lastMachineObservation = nil
        pendingMachineActiveSeconds = 0
        pendingMachineAwaySeconds = 0
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try persistContext(context)
            lastError = nil
            return true
        } catch {
            lastError = "Could not save Anchor data on this device. Your draft has not been confirmed."
            return false
        }
    }

    // MARK: - Live Activity

    private func liveActivitySnapshot() -> LiveActivitySnapshot? {
        guard let session else { return nil }
        return LiveActivitySnapshot(
            sessionID: session.id,
            intent: session.intent,
            state: session.state,
            startedAt: session.startedAt,
            plannedSeconds: session.plannedSeconds,
            bankedSeconds: session.bankedSeconds,
            runningSince: session.runningSince,
            pausedAt: session.pausedAt,
            interruptionCount: session.distractionCount
        )
    }

    private func publishLiveActivityStart() {
        guard let snapshot = liveActivitySnapshot() else { return }
        liveActivityCoordinator.start(with: snapshot)
    }

    private func publishLiveActivityUpdate() {
        guard let snapshot = liveActivitySnapshot() else { return }
        liveActivityCoordinator.update(with: snapshot)
    }

    private func publishLiveActivityEnd() {
        liveActivityCoordinator.end()
    }
}
