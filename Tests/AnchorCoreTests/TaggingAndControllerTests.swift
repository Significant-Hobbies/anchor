import Foundation
import SwiftData
import Testing

@testable import AnchorCore

@Suite("Heuristic tagging")
struct HeuristicTaggerTests {
    let tagger = HeuristicTagger()

    @Test("Specific cues beat general ones", arguments: [
        ("Slack from Ravi about the invoice", DistractionKind.message),
        ("standup ran over", DistractionKind.meeting),
        ("email from the bank", DistractionKind.email),
        ("phone buzzed with a notification", DistractionKind.notification),
        ("started scrolling twitter", DistractionKind.socialFeed),
        ("watched a youtube video", DistractionKind.entertainment),
        ("went down a wikipedia rabbit hole", DistractionKind.rabbitHole),
        ("roommate walked in", DistractionKind.person),
        ("remembered the laundry", DistractionKind.chore),
        ("got hungry", DistractionKind.bodily),
        ("construction noise outside", DistractionKind.environment),
        ("switched to a different project", DistractionKind.otherWork),
        ("worried about the deadline", DistractionKind.wanderingThought),
    ])
    func classifies(note: String, expected: DistractionKind) {
        #expect(tagger.classifyDistraction(note: note).kind == expected)
    }

    @Test("A slack message from a person is a message, not a person interruption")
    func orderingMatters() {
        // "someone" is a `.person` cue and "slack" is a `.message` cue; message
        // is checked first because it is the more specific signal.
        #expect(tagger.classifyDistraction(note: "someone slacked me").kind == .message)
    }

    @Test("Physical arrivals outrank generic chat, while explicit channels remain messages", arguments: [
        ("Roommate walked in to chat", DistractionKind.person),
        ("Colleague stopped by for a chat", DistractionKind.person),
        ("Someone knocked and wanted to chat", DistractionKind.person),
        ("Slack from my roommate", DistractionKind.message),
        ("A message says someone walked in", DistractionKind.message),
        ("Chat with my roommate online", DistractionKind.message),
    ])
    func physicalVersusMessage(note: String, expected: DistractionKind) {
        #expect(tagger.classifyDistraction(note: note).kind == expected)
    }

    @Test("Token refresh supplies missing technical context without overriding the activity", arguments: [
        ("Finish the token refresh", GoalTheme.building),
        ("Complete refresh token handling", GoalTheme.building),
        ("Draft a token refresh guide", GoalTheme.writing),
        ("Study refresh tokens", GoalTheme.learning),
        ("Plan token refresh rollout", GoalTheme.planning),
        ("Refresh the garden labels", GoalTheme.other),
        ("Count subway tokens", GoalTheme.other),
    ])
    func technicalGoalContext(title: String, expected: GoalTheme) {
        #expect(tagger.classifyGoal(title: title).theme == expected)
    }

    @Test("Unrecognised notes land on other with low confidence")
    func fallback() {
        let result = tagger.classifyDistraction(note: "zzzz qqqq")
        #expect(result.kind == .other)
        #expect(result.confidence < 0.5)
        #expect(result.source == .heuristic)
    }

    @Test("Goals sort into themes")
    func goalThemes() {
        #expect(tagger.classifyGoal(title: "Implement the auth API").theme == .building)
        #expect(tagger.classifyGoal(title: "Draft the launch blog post").theme == .writing)
        #expect(tagger.classifyGoal(title: "Study for the exam").theme == .learning)
        #expect(tagger.classifyGoal(title: "Do my taxes").theme == .admin)
        #expect(tagger.classifyGoal(title: "asdfgh").theme == .other)
    }

    @Test("Keywords drop stop words, short words and duplicates")
    func keywords() {
        let keywords = HeuristicTagger.keywords(from: "The Slack message from Ravi about the invoice")
        #expect(!keywords.contains("the"))
        #expect(!keywords.contains("from"))
        #expect(keywords.contains("slack"))
        #expect(keywords.contains("ravi"))
        #expect(keywords.count <= 4)
        #expect(Set(keywords).count == keywords.count)
    }

    @Test("Origin classification splits external pulls from internal ones")
    func origins() {
        #expect(DistractionKind.message.origin == .external)
        #expect(DistractionKind.person.origin == .external)
        #expect(DistractionKind.socialFeed.origin == .internal)
        #expect(DistractionKind.rabbitHole.origin == .internal)
        #expect(DistractionKind.chore.origin == .mixed)
    }
}

@Suite("Tagging service")
struct TaggingServiceTests {
    @Test("With the on-device model disabled it falls back to rules")
    func fallsBackWhenModelDisabled() async {
        let service = TaggingService(allowsOnDeviceModel: false)
        let result = await service.classifyDistraction(note: "Slack from Ravi", duringGoal: "Ship auth")
        #expect(result.kind == .message)
        #expect(result.source == .heuristic)

        let goal = await service.classifyGoal(title: "Implement the API", notes: "")
        #expect(goal.theme == .building)
        #expect(goal.source == .heuristic)
    }

    @Test("Summaries are absent rather than invented when the model is off")
    func summaryIsOptional() async {
        let service = TaggingService(allowsOnDeviceModel: false)
        #expect(await service.summarise("Sessions: 3") == nil)
    }

    @Test("Model keywords are cleaned, and empty output keeps the rule-based ones")
    func normalisation() {
        #expect(
            TaggingService.normalise(["  Slack ", "RAVI", "a", "slack"], fallback: ["x"])
                == ["slack", "ravi"]
        )
        // A model that returns nothing usable must not wipe the fallback.
        #expect(TaggingService.normalise([], fallback: ["kept"]) == ["kept"])
        #expect(TaggingService.normalise(["a", "bb"], fallback: ["kept"]) == ["kept"])
    }
}

@MainActor
@Suite("Focus controller")
struct FocusControllerTests {
    final class RecordingNotifier: SessionCompletionNotifying {
        var scheduled: [(UUID, String, TimeInterval)] = []
        var cancelled: [UUID] = []

        func schedule(sessionID: UUID, intent: String, after delay: TimeInterval) {
            scheduled.append((sessionID, intent, delay))
        }

        func cancel(sessionID: UUID) {
            cancelled.append(sessionID)
        }
    }

    /// Real SwiftData, in memory — the controller's job is coordinating the
    /// store, so stubbing it out would test nothing.
    func makeController(
        completionNotifier: any SessionCompletionNotifying = NoopSessionCompletionNotifier()
    ) throws -> (FocusController, ModelContext) {
        let container = try AnchorStore.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        return (
            FocusController(
                context: context,
                tagger: TaggingService(allowsOnDeviceModel: false),
                completionNotifier: completionNotifier
            ),
            context
        )
    }

    @Test("Starting a session makes it current and running")
    func startSession() throws {
        let (controller, _) = try makeController()
        let goal = Goal(title: "Ship auth")
        controller.start(goal: goal, intent: "Finish the token refresh", minutes: 25)

        #expect(controller.hasSession)
        #expect(controller.isRunning)
        #expect(controller.session?.plannedSeconds == 1500)
        #expect(controller.session?.intent == "Finish the token refresh")
    }

    @Test("Starting a second session closes the first")
    func startingReplacesPrevious() throws {
        let (controller, context) = try makeController()
        controller.start(goal: nil, intent: "First", minutes: 25)
        controller.start(goal: nil, intent: "Second", minutes: 25)

        let sessions = try context.fetch(FetchDescriptor<FocusSession>())
        #expect(sessions.count == 2)
        #expect(sessions.filter { $0.isActive }.count == 1)
        #expect(controller.session?.intent == "Second")
    }

    @Test("Parking a distraction keeps the session alive")
    func parkKeepsSessionRunning() throws {
        let (controller, _) = try makeController()
        controller.start(goal: nil, intent: "Ship auth", minutes: 25)
        controller.park(note: "Slack from Ravi", kind: .message)

        #expect(controller.hasSession)
        #expect(controller.isRunning)
        #expect(controller.parked.count == 1)
        #expect(controller.parked.first?.kind == .message)
        // A hand-picked category is locked so the model never overwrites it.
        #expect(controller.parked.first?.kindIsUserSet == true)
    }

    @Test("Empty notes are not parked")
    func emptyNotesIgnored() throws {
        let (controller, _) = try makeController()
        controller.start(goal: nil, intent: "Ship auth", minutes: 25)
        #expect(controller.park(note: "   ") == nil)
        #expect(controller.parked.isEmpty)
    }

    @Test("Parking without a session does nothing")
    func parkRequiresSession() throws {
        let (controller, _) = try makeController()
        #expect(controller.park(note: "Slack") == nil)
    }

    @Test("Surrendering records the loss and ends the session as abandoned")
    func surrender() throws {
        let (controller, context) = try makeController()
        controller.start(goal: nil, intent: "Ship auth", minutes: 25)
        controller.surrender(to: "Went to twitter")

        #expect(!controller.hasSession)
        let sessions = try context.fetch(FetchDescriptor<FocusSession>())
        #expect(sessions.first?.endReason == .abandoned)
        #expect(sessions.first?.distractions?.first?.didReturnToFocus == false)
    }

    @Test("Ending early is recorded as such, and pause banks the time")
    func pauseAndEnd() throws {
        let (controller, context) = try makeController()
        controller.start(goal: nil, intent: "Ship auth", minutes: 25)
        controller.pause()
        #expect(controller.isPaused)
        #expect(!controller.isRunning)

        controller.resume()
        #expect(controller.isRunning)

        controller.end(reason: .endedEarly)
        let sessions = try context.fetch(FetchDescriptor<FocusSession>())
        #expect(sessions.first?.endReason == .endedEarly)
        #expect(sessions.first?.state == .finished)
        #expect(!controller.hasSession)
    }

    @Test("A session that served its plan is recorded as completed even if stopped by hand")
    func honestOutcome() throws {
        let (controller, context) = try makeController()
        // A zero-minute plan is met immediately, which lets this assert the
        // outcome logic without waiting on a real clock.
        controller.start(goal: nil, intent: "Quick", minutes: 0)
        // Open-ended plans never "meet" — give it a real one-second plan instead.
        controller.session?.plannedSeconds = 1
        controller.session?.bankedSeconds = 5
        controller.session?.runningSince = nil
        controller.end(reason: .endedEarly)

        let sessions = try context.fetch(FetchDescriptor<FocusSession>())
        #expect(sessions.first?.endReason == .completed)
    }

    @Test("An in-flight session is restored when the app relaunches")
    func restoresActiveSession() throws {
        let container = try AnchorStore.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let first = FocusController(context: context, tagger: TaggingService(allowsOnDeviceModel: false))
        first.start(goal: nil, intent: "Ship auth", minutes: 25)
        first.park(note: "Slack", kind: .message)

        // A fresh controller over the same store stands in for a relaunch.
        let second = FocusController(context: context, tagger: TaggingService(allowsOnDeviceModel: false))
        #expect(second.hasSession)
        #expect(second.session?.intent == "Ship auth")
        #expect(second.parked.count == 1)
    }

    @Test("A session imported after launch becomes the active timer")
    func adoptsImportedActiveSession() throws {
        let (controller, context) = try makeController()
        #expect(!controller.hasSession)

        let imported = FocusSession(
            goal: nil,
            intent: "Started on the Mac",
            plannedSeconds: 1_500
        )
        context.insert(imported)
        try context.save()

        controller.synchronizeActiveSessionFromStore()

        #expect(controller.session?.id == imported.id)
        #expect(controller.isRunning)
    }

    @Test("A remotely finished session clears the active timer")
    func clearsImportedFinishedSession() throws {
        let (controller, context) = try makeController()
        controller.start(goal: nil, intent: "Started on the Mac", minutes: 25)

        controller.session?.state = .finished
        controller.session?.endedAt = Date()
        try context.save()
        controller.synchronizeActiveSessionFromStore()

        #expect(!controller.hasSession)
    }

    @Test("Resuming always asks what pulled you away")
    func resumeAsksForDistraction() throws {
        let (controller, _) = try makeController()
        controller.start(goal: nil, intent: "Ship auth", minutes: 25)
        #expect(!controller.isCapturing)

        controller.pause()
        // Pausing itself must not interrupt — you are already gone by then.
        #expect(!controller.isCapturing)
        #expect(controller.session?.pausedAt != nil)

        controller.resume()
        #expect(controller.isCapturing)
        #expect(controller.captureReason != .manual)
        // The pause marker is cleared so a second resume can't double-report.
        #expect(controller.session?.pausedAt == nil)
    }

    @Test("Saying it was just a break records nothing")
    func dismissingCaptureRecordsNothing() throws {
        let (controller, _) = try makeController()
        controller.start(goal: nil, intent: "Ship auth", minutes: 25)
        controller.pause()
        controller.resume()

        controller.dismissCapture()
        #expect(!controller.isCapturing)
        #expect(controller.captureReason == .manual)
        #expect(controller.parked.isEmpty)
        // Dismissing must not disturb the session it interrupted.
        #expect(controller.isRunning)
    }

    @Test("A distraction logged on resume lands at the moment you stopped")
    func resumeCaptureUsesPausePoint() throws {
        let (controller, _) = try makeController()
        controller.start(goal: nil, intent: "Ship auth", minutes: 25)
        controller.session?.bankedSeconds = 300
        controller.pause()
        controller.resume()
        let parked = controller.park(note: "Roommate came in")

        // Paused time is excluded from elapsed, so the offset is where the
        // session actually stopped rather than where it restarted.
        #expect(parked != nil)
        #expect((parked?.offsetSeconds ?? 0) >= 300)
        #expect((parked?.offsetSeconds ?? 0) < 320)
    }

    @Test("Manual capture is distinguishable from a resume prompt")
    func manualCaptureReason() throws {
        let (controller, _) = try makeController()
        controller.start(goal: nil, intent: "Ship auth", minutes: 25)
        controller.beginManualCapture()
        #expect(controller.isCapturing)
        #expect(controller.captureReason == .manual)
    }

    @Test("Extending a running plan keeps the session active")
    func extendRunningPlan() throws {
        let (controller, _) = try makeController()
        controller.start(goal: nil, intent: "Ship auth", minutes: 25)
        controller.extend(byMinutes: 5)
        #expect(controller.session?.plannedSeconds == 1800)
        #expect(controller.isRunning)
    }

    @Test("A planned session stops itself at the exact finish instant")
    func autoCompletesAtPlan() throws {
        let (controller, context) = try makeController()
        controller.start(goal: nil, intent: "Ship auth", minutes: 25)
        let start = Date(timeIntervalSince1970: 10_000)
        controller.session?.plannedSeconds = 60
        controller.session?.bankedSeconds = 15
        controller.session?.runningSince = start

        controller.refresh(at: start.addingTimeInterval(44.9))
        #expect(controller.hasSession)
        controller.refresh(at: start.addingTimeInterval(90))

        #expect(!controller.hasSession)
        let finished = try #require(context.fetch(FetchDescriptor<FocusSession>()).first)
        #expect(finished.state == .finished)
        #expect(finished.endReason == .completed)
        #expect(finished.endedAt == start.addingTimeInterval(45))
        #expect(finished.bankedSeconds == 60)
    }

    @Test("Open-ended and paused sessions never auto-complete")
    func autoCompletionBoundaries() throws {
        let (controller, _) = try makeController()
        controller.start(goal: nil, intent: "Explore", minutes: 0)
        controller.refresh(at: Date().addingTimeInterval(86_400))
        #expect(controller.hasSession)

        controller.session?.plannedSeconds = 60
        controller.session?.bankedSeconds = 20
        controller.session?.runningSince = nil
        controller.session?.state = .paused
        controller.refresh(at: Date().addingTimeInterval(86_400))
        #expect(controller.isPaused)
    }

    @Test("An overdue running session completes safely when restored")
    func overdueRestoreCompletes() throws {
        let container = try AnchorStore.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let start = Date().addingTimeInterval(-600)
        let session = FocusSession(goal: nil, intent: "Old timer", plannedSeconds: 60, startedAt: start)
        context.insert(session)
        try context.save()

        let controller = FocusController(
            context: context,
            tagger: TaggingService(allowsOnDeviceModel: false)
        )
        #expect(!controller.hasSession)
        #expect(session.endReason == .completed)
        #expect(session.endedAt == start.addingTimeInterval(60))
    }

    @Test("Completion notifications follow start, pause, resume, and manual end")
    func notificationLifecycle() throws {
        let notifier = RecordingNotifier()
        let (controller, _) = try makeController(completionNotifier: notifier)
        let session = controller.start(goal: nil, intent: "Paid work", minutes: 25)
        #expect(notifier.scheduled.count == 1)
        #expect(notifier.scheduled.first?.0 == session.id)
        #expect(notifier.scheduled.first?.1 == "Paid work")

        controller.pause()
        #expect(notifier.cancelled == [session.id])
        controller.resume()
        #expect(notifier.scheduled.count == 2)
        controller.end(reason: .endedEarly)
        #expect(notifier.cancelled == [session.id, session.id])
    }

    @Test("Machine presence stays transient until the local timer changes state")
    func machinePresence() throws {
        let (controller, _) = try makeController()
        controller.start(goal: nil, intent: "Work", minutes: 25)
        let start = Date(timeIntervalSince1970: 20_000)
        controller.observeMachineIdle(seconds: 0, at: start)
        controller.observeMachineIdle(seconds: 3, at: start.addingTimeInterval(10))

        #expect(controller.session?.computerActiveSeconds == 0)
        #expect(controller.session?.computerAwaySeconds == 0)

        controller.pause()
        #expect(controller.session?.computerActiveSeconds == 7)
        #expect(controller.session?.computerAwaySeconds == 3)
    }

    @Test("Snapshots carry the session and its distractions into the analytics layer")
    func snapshotting() throws {
        let (controller, context) = try makeController()
        let goal = Goal(title: "Ship auth")
        goal.theme = .building
        controller.start(goal: goal, intent: "Token refresh", minutes: 25)
        controller.park(note: "Slack from Ravi", kind: .message)
        controller.end(reason: .endedEarly)

        let records = try context.sessionRecords()
        #expect(records.count == 1)
        #expect(records.first?.goalTitle == "Ship auth")
        #expect(records.first?.goalTheme == .building)
        #expect(records.first?.distractions.count == 1)
        #expect(records.first?.distractions.first?.kind == .message)
    }

    @Test("Projects, saved tags, and entry text survive the full record path")
    func explicitMetadataRoundTrips() throws {
        let (controller, context) = try makeController()
        let project = Project(name: "Anchor", tintIndex: 2)
        let tag = SavedTag(name: "deep work", tintIndex: 1)
        context.insert(project)
        context.insert(tag)

        controller.start(
            goal: nil,
            intent: "Build reusable tags",
            minutes: 25,
            project: project,
            notes: "Keep the schema CloudKit-safe.",
            tagIDStrings: [tag.storageID]
        )
        controller.park(
            note: "Slack about another project",
            kind: .message,
            tagIDStrings: [tag.storageID]
        )
        controller.end(reason: .endedEarly)

        let record = try #require(context.sessionRecords().first)
        #expect(record.projectTitle == "Anchor")
        #expect(record.notes == "Keep the schema CloudKit-safe.")
        #expect(record.tags == ["deep work"])
        #expect(record.distractions.first?.note == "Slack about another project")
        #expect(record.distractions.first?.tags == ["deep work"])
    }
}
