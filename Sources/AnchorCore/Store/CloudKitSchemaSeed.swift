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

    /// Inserts one minimal record for every model absent from the seed store.
    /// No user-authored content is copied into Development.
    @MainActor
    public static func seedIfNeeded(into context: ModelContext) throws {
        if isEmpty(Project.self, in: context) {
            context.insert(Project(name: "Schema seed"))
        }
        if isEmpty(SavedTag.self, in: context) {
            context.insert(SavedTag(name: "schema-seed"))
        }
        if isEmpty(Goal.self, in: context) {
            context.insert(Goal(title: "Schema seed"))
        }
        if isEmpty(FocusSession.self, in: context) {
            let session = FocusSession(goal: nil, intent: "", plannedSeconds: 60)
            session.state = .finished
            session.runningSince = nil
            session.endedAt = session.startedAt
            session.endReason = .completed
            context.insert(session)
        }
        if isEmpty(Distraction.self, in: context) {
            context.insert(Distraction(note: ""))
        }
        if isEmpty(MachineActivityDay.self, in: context) {
            context.insert(MachineActivityDay(day: Date()))
        }
        if isEmpty(AnchorPreferences.self, in: context) {
            context.insert(AnchorPreferences())
        }
        if isEmpty(BehaviorProfile.self, in: context) {
            context.insert(BehaviorProfile())
        }
        if isEmpty(ScheduleTemplate.self, in: context) {
            context.insert(
                ScheduleTemplate(
                    title: "Schema seed",
                    startMinutesFromMidnight: 0,
                    plannedSeconds: 60
                )
            )
        }
        if isEmpty(HabitCompletion.self, in: context) {
            context.insert(HabitCompletion(habitID: UUID(), day: Date()))
        }
        if isEmpty(DayPlanConfirmation.self, in: context) {
            context.insert(DayPlanConfirmation(day: Date(), decision: .later))
        }
        if isEmpty(PlanBlock.self, in: context) {
            context.insert(PlanBlock(title: "Schema seed", plannedStart: Date(), plannedSeconds: 60))
        }
        if isEmpty(DivergenceEvent.self, in: context) {
            context.insert(DivergenceEvent(blockID: UUID(), kind: .unknown))
        }

        try context.save()
    }

    private static func isEmpty<Model: PersistentModel>(
        _ type: Model.Type,
        in context: ModelContext
    ) -> Bool {
        ((try? context.fetchCount(FetchDescriptor<Model>())) ?? 0) == 0
    }
}
