import Foundation
import SwiftData

/// A deliberately narrow migration aid for materializing SwiftData record types
/// in CloudKit Development before an additive schema deployment.
///
/// It is unavailable in release builds, uses a dedicated app-group store rather
/// than the owner's real database, and inserts only synthetic values.
public enum CloudKitSchemaSeed {
    public static var isRequested: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["ANCHOR_CLOUDKIT_SCHEMA_SEED"] == "1"
        #else
        false
        #endif
    }

    public static func storeURL(fileManager: FileManager = .default) -> URL? {
        guard isRequested,
              let group = fileManager.containerURL(
                  forSecurityApplicationGroupIdentifier: AnchorStore.appGroupIdentifier
              )
        else { return nil }

        return group.appending(path: "Anchor-CloudKitSchemaSeed.store")
    }

    /// Inserts or enriches one synthetic record for every model. Optional
    /// properties must be non-nil here because CloudKit's just-in-time schema
    /// generation only materializes fields present in an exported record.
    /// No user-authored content is copied into Development.
    @MainActor
    public static func seedIfNeeded(into context: ModelContext) throws {
        let timestamp = Date()

        let project = try firstOrInsert(Project.self, into: context) {
            Project(name: "Schema seed")
        }
        project.archivedAt = timestamp

        let tag = try firstOrInsert(SavedTag.self, into: context) {
            SavedTag(name: "schema-seed")
        }
        tag.archivedAt = timestamp

        let goal = try firstOrInsert(Goal.self, into: context) {
            Goal(title: "Schema seed")
        }
        goal.archivedAt = timestamp
        goal.theme = .other

        let session = try firstOrInsert(FocusSession.self, into: context) {
            FocusSession(goal: goal, intent: "", project: project, plannedSeconds: 60)
        }
        session.goal = goal
        session.project = project
        session.state = .finished
        session.runningSince = timestamp
        session.pausedAt = timestamp
        session.endedAt = timestamp
        session.endReason = .completed

        let distraction = try firstOrInsert(Distraction.self, into: context) {
            Distraction(note: "", session: session)
        }
        distraction.note = ""
        distraction.session = session
        distraction.kind = .other
        distraction.handledAt = timestamp

        _ = try firstOrInsert(MachineActivityDay.self, into: context) {
            MachineActivityDay(day: timestamp)
        }

        _ = try firstOrInsert(AnchorPreferences.self, into: context) {
            AnchorPreferences()
        }

        let profile = try firstOrInsert(BehaviorProfile.self, into: context) {
            BehaviorProfile()
        }
        profile.selectedPatterns = [.socialFeeds]
        profile.desiredDirections = [.focus]

        let schedule = try firstOrInsert(ScheduleTemplate.self, into: context) {
            ScheduleTemplate(
                title: "Schema seed",
                startMinutesFromMidnight: 0,
                plannedSeconds: 60
            )
        }
        schedule.archivedAt = timestamp
        schedule.behaviorPattern = .socialFeeds
        schedule.lifeDirection = .focus
        schedule.isBehaviorHabit = true
        schedule.graduatedAt = timestamp
        schedule.habitLevelStartedAt = timestamp
        schedule.lastProgressPromptedAt = timestamp

        let completion = try firstOrInsert(HabitCompletion.self, into: context) {
            HabitCompletion(habitID: schedule.id, day: timestamp)
        }
        completion.completedAt = timestamp

        let confirmation = try firstOrInsert(DayPlanConfirmation.self, into: context) {
            DayPlanConfirmation(day: timestamp, decision: .adjusted)
        }
        confirmation.confirmedAt = timestamp
        confirmation.deferredAt = timestamp

        let block = try firstOrInsert(PlanBlock.self, into: context) {
            PlanBlock(
                templateID: schedule.id,
                templateOccurrenceDay: timestamp,
                isTemplateOverride: true,
                title: "Schema seed",
                plannedStart: timestamp,
                plannedSeconds: 60,
                behaviorPattern: .socialFeeds,
                lifeDirection: .focus
            )
        }
        block.templateID = schedule.id
        block.templateOccurrenceDay = timestamp
        block.isTemplateOverride = true
        block.sessionID = session.id
        block.actualStartedAt = timestamp
        block.actualEndedAt = timestamp
        block.behaviorPattern = .socialFeeds
        block.lifeDirection = .focus
        block.state = .completed

        let divergence = try firstOrInsert(DivergenceEvent.self, into: context) {
            DivergenceEvent(
                blockID: block.id,
                sessionID: session.id,
                distractionID: distraction.id,
                kind: .unknown
            )
        }
        divergence.sessionID = session.id
        divergence.distractionID = distraction.id

        try context.save()
    }

    @MainActor
    private static func firstOrInsert<Model: PersistentModel>(
        _ type: Model.Type,
        into context: ModelContext,
        make: () -> Model
    ) throws -> Model {
        var descriptor = FetchDescriptor<Model>()
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let model = make()
        context.insert(model)
        return model
    }
}
