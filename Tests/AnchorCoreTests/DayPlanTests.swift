import Foundation
import SwiftData
import Testing

@testable import AnchorCore

@MainActor
@Suite("Day planning")
struct DayPlanTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test("Recurring templates materialize once on matching days")
    func materializationIsIdempotent() throws {
        let container = try AnchorStore.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let monday = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 UTC
        let template = ScheduleTemplate(
            title: "Walk",
            startMinutesFromMidnight: 8 * 60,
            plannedSeconds: 30 * 60,
            weekdays: [.monday],
            kind: .routine,
            lifeDirection: .movement
        )
        context.insert(template)
        try context.save()

        let service = DayPlanService(context: context, calendar: calendar)
        #expect(try service.materialize(day: monday).count == 1)
        #expect(try service.materialize(day: monday).count == 1)

        let blocks = try context.fetch(FetchDescriptor<PlanBlock>())
        #expect(blocks.count == 1)
        #expect(blocks.first?.templateID == template.id)
        #expect(blocks.first?.lifeDirection == .movement)
    }

    @Test("Editing a routine reconciles only future unstarted occurrences")
    func editingTemplateReconcilesFutureBlocks() throws {
        let container = try AnchorStore.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let monday = Date(timeIntervalSince1970: 1_704_067_200)
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday)!
        let template = ScheduleTemplate(
            title: "Walk",
            startMinutesFromMidnight: 8 * 60,
            plannedSeconds: 30 * 60,
            weekdays: [.monday, .tuesday],
            kind: .routine
        )
        context.insert(template)
        try context.save()

        let service = DayPlanService(context: context, calendar: calendar)
        _ = try service.materialize(day: monday)
        _ = try service.materialize(day: tuesday)

        template.title = "Morning walk"
        template.startMinutesFromMidnight = 9 * 60
        template.plannedSeconds = 45 * 60
        template.weekdays = [.monday]
        try service.reconcileFutureBlocks(for: template, from: monday)

        let blocks = try context.fetch(FetchDescriptor<PlanBlock>())
        #expect(blocks.count == 1)
        #expect(blocks.first?.title == "Morning walk")
        #expect(blocks.first?.plannedSeconds == 45 * 60)
        #expect(calendar.component(.hour, from: blocks.first!.plannedStart) == 9)
    }

    @Test("Stopping a routine removes future planned occurrences and preserves history")
    func archivingTemplatePreservesHistory() throws {
        let container = try AnchorStore.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let monday = Date(timeIntervalSince1970: 1_704_067_200)
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday)!
        let template = ScheduleTemplate(
            title: "Walk",
            startMinutesFromMidnight: 8 * 60,
            plannedSeconds: 30 * 60,
            weekdays: [.monday],
            kind: .routine
        )
        context.insert(template)
        try context.save()

        let service = DayPlanService(context: context, calendar: calendar)
        let historical = try service.materialize(day: monday).first!
        historical.complete(at: monday.addingTimeInterval(30 * 60))
        _ = try service.materialize(day: nextMonday)
        try context.save()

        template.archivedAt = monday
        try service.reconcileFutureBlocks(for: template, from: monday)

        let blocks = try context.fetch(FetchDescriptor<PlanBlock>())
        #expect(blocks.count == 1)
        #expect(blocks.first?.id == historical.id)
        #expect(blocks.first?.state == .completed)
    }

    @Test("A personalized recurring occurrence survives routine changes without rematerializing")
    func templateOverrideSurvivesReconciliation() throws {
        let container = try AnchorStore.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let monday = Date(timeIntervalSince1970: 1_704_067_200)
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday)!
        let template = ScheduleTemplate(
            title: "Walk",
            startMinutesFromMidnight: 8 * 60,
            plannedSeconds: 30 * 60,
            weekdays: [.monday],
            kind: .routine
        )
        context.insert(template)
        try context.save()

        let service = DayPlanService(context: context, calendar: calendar)
        let occurrence = try service.materialize(day: monday).first!
        occurrence.title = "Walk with Maya"
        occurrence.plannedStart = tuesday
        occurrence.isTemplateOverride = true
        try context.save()

        template.title = "Solo walk"
        template.archivedAt = monday
        try service.reconcileFutureBlocks(for: template, from: monday)
        #expect(try service.materialize(day: monday).isEmpty)

        let blocks = try context.fetch(FetchDescriptor<PlanBlock>())
        #expect(blocks.count == 1)
        #expect(blocks.first?.id == occurrence.id)
        #expect(blocks.first?.title == "Walk with Maya")
        #expect(blocks.first?.plannedStart == tuesday)
    }

    @Test("A template does not materialize on the wrong weekday")
    func respectsWeekdays() throws {
        let container = try AnchorStore.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let monday = Date(timeIntervalSince1970: 1_704_067_200)
        context.insert(ScheduleTemplate(
            title: "Sunday review",
            startMinutesFromMidnight: 18 * 60,
            plannedSeconds: 30 * 60,
            weekdays: [.sunday]
        ))
        try context.save()

        #expect(try DayPlanService(context: context, calendar: calendar).materialize(day: monday).isEmpty)
    }

    @Test("Behavior profile round-trips typed selections")
    func behaviorProfileRoundTrip() {
        let profile = BehaviorProfile(
            selectedPatterns: [.shortVideo, .socialFeeds],
            desiredDirections: [.creativity, .sleep]
        )
        #expect(profile.selectedPatterns == [.shortVideo, .socialFeeds])
        #expect(profile.desiredDirections == [.creativity, .sleep])
        #expect(BehaviorPattern.allCases.allSatisfy { !$0.label.isEmpty && !$0.artworkName.isEmpty })
    }

    @Test("Every life direction has an actionable habit suggestion")
    func habitSuggestionsAreComplete() {
        for direction in LifeDirection.allCases {
            let suggestion = direction.habitSuggestion
            #expect(suggestion.direction == direction)
            #expect(!suggestion.title.isEmpty)
            #expect(suggestion.plannedMinutes >= 5)
            #expect((0..<1_440).contains(suggestion.startMinutesFromMidnight))
        }
    }

    @Test("Focus resolves the active, current, upcoming, then last unfinished block")
    func scheduledFocusResolution() {
        let resolver = ScheduledFocusResolver()
        let now = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_704_067_200))!
        let early = PlanBlockRecord(id: UUID(), title: "Walk", plannedStart: now.addingTimeInterval(-7_200), plannedSeconds: 1_800)
        let current = PlanBlockRecord(id: UUID(), title: "Write", plannedStart: now.addingTimeInterval(-600), plannedSeconds: 1_800)
        let upcoming = PlanBlockRecord(id: UUID(), title: "Call", plannedStart: now.addingTimeInterval(3_600), plannedSeconds: 1_800)

        #expect(resolver.nextBlock(from: [upcoming, early, current], now: now, calendar: calendar)?.id == current.id)

        var active = upcoming
        active.state = .inProgress
        #expect(resolver.nextBlock(from: [current, active], now: now, calendar: calendar)?.id == active.id)

        var completedCurrent = current
        completedCurrent.state = .completed
        #expect(resolver.nextBlock(from: [early, completedCurrent, upcoming], now: now, calendar: calendar)?.id == upcoming.id)
        #expect(resolver.nextBlock(from: [early], now: now, calendar: calendar)?.id == early.id)
    }
}

@Suite("Day review")
struct DayReviewTests {
    private let engine = DayReviewEngine(calendar: Fixture.calendar)

    @Test("Review compares planned and actual without an adherence score")
    func plannedVersusActual() {
        let session = Fixture.session(focused: 2_700, planned: 1_800)
        let block = PlanBlockRecord(
            id: UUID(),
            sessionID: session.id,
            title: "Write",
            plannedStart: Fixture.day0,
            plannedSeconds: 1_800,
            state: .completed
        )
        let review = engine.review(day: Fixture.day0, blocks: [block], sessions: [session], divergences: [])

        #expect(review.plannedSeconds == 1_800)
        #expect(review.actualSeconds == 2_700)
        #expect(review.gaps.count == 1)
        #expect(review.gaps.first?.cause == .unknown)
        #expect(review.suggestions.first?.detail.contains("does not have enough evidence") == true)
    }

    @Test("Explicit deliberate replanning remains neutral")
    func deliberateReplan() {
        let blockID = UUID()
        let block = PlanBlockRecord(
            id: blockID,
            title: "Read",
            plannedStart: Fixture.day0,
            plannedSeconds: 1_800,
            state: .skipped,
            kind: .routine
        )
        let event = DivergenceRecord(
            id: UUID(),
            blockID: blockID,
            occurredAt: Fixture.day0,
            kind: .deliberateReplan,
            evidence: .userConfirmed,
            note: "Helped a friend instead."
        )
        let review = engine.review(day: Fixture.day0, blocks: [block], sessions: [], divergences: [event])

        #expect(review.gaps.first?.cause == .deliberateReplan)
        #expect(review.gaps.first?.evidenceDescription == "Helped a friend instead.")
        #expect(review.suggestions.first?.title == "Let the plan reflect the choice")
    }

    @Test("Untimed completion stays complete without inventing a duration")
    func untimedCompletionIsUnknown() {
        let block = PlanBlockRecord(
            id: UUID(),
            title: "Call family",
            plannedStart: Fixture.day0,
            plannedSeconds: 3_600,
            state: .completed,
            kind: .commitment
        )

        let review = engine.review(day: Fixture.day0, blocks: [block], sessions: [], divergences: [])

        #expect(review.actualSeconds == 0)
        #expect(review.unobservedCompletedBlocks == 1)
        #expect(review.gaps.first?.actualDurationKnown == false)
        #expect(review.gaps.first?.varianceSeconds == 0)
        #expect(review.gaps.first?.evidenceDescription.contains("duration was not observed") == true)
        #expect(review.suggestions.first?.title == "Keep the completion, not a made-up duration")
    }

    @Test("Unplanned sessions still appear in the followed day")
    func unplannedSessionIsObserved() {
        let session = Fixture.session(focused: 1_200, planned: 1_800)
        let explanation = DivergenceRecord(
            id: UUID(),
            blockID: session.id,
            sessionID: session.id,
            occurredAt: Fixture.day0,
            kind: .deliberateReplan,
            evidence: .userConfirmed,
            note: "Handled an urgent task instead."
        )

        let review = engine.review(day: Fixture.day0, blocks: [], sessions: [session], divergences: [explanation])

        #expect(review.plannedSeconds == 0)
        #expect(review.actualSeconds == 1_200)
        #expect(review.gaps.first?.blockID == session.id)
        #expect(review.gaps.first?.plannedSeconds == 0)
        #expect(review.gaps.first?.actualDurationKnown == true)
        #expect(review.gaps.first?.cause == .deliberateReplan)
        #expect(review.gaps.first?.evidenceDescription == "Handled an urgent task instead.")
    }

    @Test("Captured distractions provide evidence but do not invent a note")
    func capturedInterruptionEvidence() {
        let distraction = Fixture.distraction("Slack", kind: .message)
        let session = Fixture.session(
            focused: 600,
            planned: 1_800,
            reason: .abandoned,
            distractions: [distraction]
        )
        let block = PlanBlockRecord(
            id: UUID(),
            sessionID: session.id,
            title: "Design",
            plannedStart: Fixture.day0,
            plannedSeconds: 1_800
        )
        let review = engine.review(day: Fixture.day0, blocks: [block], sessions: [session], divergences: [])

        #expect(review.gaps.first?.cause == .externalInterruption)
        #expect(review.gaps.first?.evidence == .capturedInterruption)
        #expect(review.gaps.first?.evidenceDescription == "1 captured interruption during this session.")
    }

    @Test("Selected life direction can shape a grounded replacement suggestion")
    func replacementSuggestion() {
        let blockID = UUID()
        let block = PlanBlockRecord(
            id: blockID,
            title: "Morning plan",
            plannedStart: Fixture.day0,
            plannedSeconds: 1_800,
            state: .skipped
        )
        let event = DivergenceRecord(
            id: UUID(),
            blockID: blockID,
            occurredAt: Fixture.day0,
            kind: .internalPull,
            evidence: .userConfirmed
        )
        let review = engine.review(
            day: Fixture.day0,
            blocks: [block],
            sessions: [],
            divergences: [event],
            profile: BehaviorProfileRecord(
                selectedPatterns: [.shortVideo],
                desiredDirections: [.creativity]
            )
        )
        #expect(review.suggestions.first?.detail.contains("More creativity") == true)
        #expect(review.suggestions.first?.detail.contains("Short videos") == true)
    }
}
