import Foundation
import SwiftData
import Testing
@testable import AnchorCore

@Suite("Device-only note migration", .serialized)
@MainActor struct NoteMigrationFixtureTests {
    func fixture() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "anchor-private-note-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "Anchor.store")
    }

    func rawContainer(_ url: URL) throws -> ModelContainer {
        try ModelContainer(for: AnchorStore.schema, configurations: AnchorStore.configuration(kind: .localOnly, url: url))
    }

    func seedLegacy(_ url: URL, note: String = "Synthetic private note") throws -> UUID {
        let context = ModelContext(try rawContainer(url))
        let session = FocusSession(goal: nil, intent: "Synthetic session", plannedSeconds: 1500)
        context.insert(session)
        let distraction = Distraction(note: "", session: session)
        distraction.privateDraft = nil
        distraction.note = note
        distraction.keywords = ["synthetic", "private"]
        context.insert(distraction)
        try context.save()
        return distraction.id
    }

    @Test func migrationPreservesNotesIDsAndKeywordsAcrossReopen() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let id = try seedLegacy(url)
        for _ in 0..<2 {
            let context = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
            let d = try #require(context.fetch(FetchDescriptor<Distraction>()).first)
            #expect(d.id == id)
            #expect(d.privateNote == "Synthetic private note")
            #expect(d.privateKeywords == ["synthetic", "private"])
            #expect(d.note.isEmpty && d.keywords.isEmpty)
            #expect(try context.sessionRecords().first?.distractions.first?.note == d.privateNote)
        }
        let vault = LocalDistractionNotes(storeURL: url)
        #expect(try vault.directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func failedMigrationPreservesSourceAndNeverOpensMirrorOrEmptyStore() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let id = try seedLegacy(url)
        try Data("blocked vault".utf8).write(to: LocalDistractionNotes(storeURL: url).directory)
        #expect(throws: AnchorStore.PrivateNoteMigrationFailure.self) {
            _ = try AnchorStore.makeContainer(kind: .persistent, url: url)
        }
        let fallback = AnchorStore.makeLocalResilientContainer(url: url)
        #expect(fallback.kind == .localOnly)
        let context = ModelContext(fallback.container)
        let d = try #require(context.fetch(FetchDescriptor<Distraction>()).first)
        #expect(d.id == id && d.note == "Synthetic private note")
        #expect(AnchorStore.privateNoteStorageWarning != nil)
    }

    @Test func captureEditRestartAndDeleteKeepMirroredFieldsEmpty() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var id: UUID!
        do {
            let context = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
            let controller = FocusController(context: context, tagger: TaggingService(allowsOnDeviceModel: false))
            controller.start(goal: nil, intent: "Write", minutes: 25)
            #expect(controller.pauseFromCapture(note: "Doorbell", kind: .person))
            let d = try #require(context.fetch(FetchDescriptor<Distraction>()).first)
            id = d.id
            #expect(d.note.isEmpty)
            controller.resume()
            controller.dismissCapture()
            d.privateNote = "Edited private note"
            d.privateKeywords = ["edited"]
            try AnchorStore.save(context)
            #expect(d.note.isEmpty && d.keywords.isEmpty)
            controller.end()
        }
        let context = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        let d = try #require(context.fetch(FetchDescriptor<Distraction>()).first)
        #expect(d.id == id && d.privateNote == "Edited private note" && d.privateKeywords == ["edited"])
        #expect(try context.sessionRecords().first?.distractions.first?.note == "Edited private note")
        try AnchorStore.deleteDistraction(d, in: context)
        #expect(try context.fetchCount(FetchDescriptor<Distraction>()) == 0)
        #expect(try LocalDistractionNotes(storeURL: url).read(id) == nil)
    }

    @Test func failedCaptureRetainsSessionAndDoesNotConfirmOrInsertNote() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let context = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        let controller = FocusController(context: context, tagger: TaggingService(allowsOnDeviceModel: false))
        controller.start(goal: nil, intent: "Write", minutes: 25)
        controller.beginManualCapture()
        try Data("blocked vault".utf8).write(to: LocalDistractionNotes(storeURL: url).directory)
        #expect(!controller.pauseFromCapture(note: "Still a draft", kind: .person))
        #expect(controller.isRunning && controller.isCapturing)
        #expect(controller.lastError != nil)
        #expect(try context.fetchCount(FetchDescriptor<Distraction>()) == 0)
        controller.end()
    }

    @Test func oldDeviceConflictPreservesBothVersionsWithoutOverwritingLocalEdit() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let id = try seedLegacy(url)
        let context = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        let d = try #require(context.fetch(FetchDescriptor<Distraction>()).first)
        d.privateNote = "New local edit"
        try AnchorStore.save(context)
        d.note = "Late old-device version"
        try context.save() // Synthetic imported legacy transaction, no provider.
        try AnchorStore.migratePrivateNotes(in: context)
        #expect(d.privateNote == "New local edit" && d.note.isEmpty)
        let record = try #require(try LocalDistractionNotes(storeURL: url).read(id))
        #expect(record.legacyAlternates.contains { $0.note == "Late old-device version" })
    }

    @Test func corruptVaultIsReportedRatherThanExportedAsAnEmptyNote() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let id = try seedLegacy(url)
        let context = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        let vault = LocalDistractionNotes(storeURL: url)
        try Data("invalid json".utf8).write(to: vault.directory.appending(path: id.uuidString + ".json"))
        #expect(throws: (any Error).self) { _ = try context.sessionRecords() }
        #expect(throws: AnchorStore.PrivateNoteMigrationFailure.self) { _ = try AnchorStore.makeContainer(kind: .localOnly, url: url) }
    }
    @Test func failedEditDoesNotReplaceOrQueueTheOriginalLocalNote() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let id = try seedLegacy(url)
        let context = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        let d = try #require(context.fetch(FetchDescriptor<Distraction>()).first)
        let vault = LocalDistractionNotes(storeURL: url)
        let savedDirectory = vault.directory.appendingPathExtension("saved")
        try FileManager.default.moveItem(at: vault.directory, to: savedDirectory)
        try Data("blocked".utf8).write(to: vault.directory)
        #expect(throws: (any Error).self) { try d.updatePrivateNote("Failed draft", in: context) }
        #expect(d.privateDraft == nil)
        try FileManager.default.removeItem(at: vault.directory)
        try FileManager.default.moveItem(at: savedDirectory, to: vault.directory)
        #expect(d.privateNote == "Synthetic private note")
        try AnchorStore.save(context)
        #expect(try vault.read(id)?.current.note == "Synthetic private note")
        try d.updatePrivateNote("Retried edit", in: context)
        try AnchorStore.save(context)
        #expect(try vault.read(id)?.current.note == "Retried edit")
    }

    @Test func exactOldSourceStoreMigratesWithoutSchemaOrTimingLoss() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let fixtureURL = try #require(Bundle.module.url(forResource: "LegacyNotes", withExtension: "store"))
        try FileManager.default.copyItem(at: fixtureURL, to: url)
        let raw = ModelContext(try rawContainer(url))
        let original = try #require(raw.fetch(FetchDescriptor<Distraction>()).first)
        let id = original.id
        #expect(original.note == "Synthetic old-source private note")
        let sessionID = original.session?.id
        let banked = original.session?.bankedSeconds
        let context = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        let d = try #require(context.fetch(FetchDescriptor<Distraction>()).first)
        #expect(d.id == id && d.session?.id == sessionID)
        #expect(d.session?.state == .paused && d.session?.bankedSeconds == banked)
        #expect(d.privateNote == "Synthetic old-source private note")
        #expect(d.privateKeywords == ["synthetic", "old-source"])
        #expect(d.note.isEmpty && d.keywords.isEmpty)
        let controller = FocusController(context: context, tagger: TaggingService(allowsOnDeviceModel: false))
        controller.resume()
        #expect(controller.isRunning && controller.isCapturing)
        controller.dismissCapture()
        #expect(try context.fetchCount(FetchDescriptor<Distraction>()) == 1)
        controller.end()
    }

    @Test func failedMetadataCommitAfterVaultWriteCanRetryWithoutPhantomCapture() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let context = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        var failNext = false
        let controller = FocusController(context: context, tagger: TaggingService(allowsOnDeviceModel: false), persistContext: { context in
            if failNext { failNext = false; throw CocoaError(.fileWriteOutOfSpace) }
            try AnchorStore.save(context)
        })
        controller.start(goal: nil, intent: "Write", minutes: 25)
        controller.beginManualCapture()
        failNext = true
        #expect(controller.park(note: "Retry this private draft", kind: .person) == nil)
        #expect(controller.isCapturing && controller.isRunning && controller.lastError != nil)
        #expect(controller.parked.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<Distraction>()) == 0)
        let vault = LocalDistractionNotes(storeURL: url)
        #expect(try FileManager.default.contentsOfDirectory(atPath: vault.directory.path).isEmpty)
        #expect(controller.park(note: "Retry this private draft", kind: .person) != nil)
        controller.end()
        let reopened = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        let notes = try reopened.fetch(FetchDescriptor<Distraction>())
        #expect(notes.count == 1 && notes.first?.privateNote == "Retry this private draft")
    }

    @Test func failedCapturePauseCommitRestoresRunningStateAndRetainsPromptForRetry() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let context = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        var failNext = false
        let controller = FocusController(context: context, tagger: TaggingService(allowsOnDeviceModel: false), persistContext: { context in
            if failNext { failNext = false; throw CocoaError(.fileWriteOutOfSpace) }
            try AnchorStore.save(context)
        })
        let session = try #require(controller.start(goal: nil, intent: "Write", minutes: 25))
        let account = session.account
        controller.beginManualCapture()
        failNext = true
        #expect(!controller.pauseFromCapture(note: "Doorbell", kind: .person))
        #expect(controller.isRunning && controller.isCapturing && controller.lastError != nil)
        #expect(session.account == account && session.pausedAt == nil)
        #expect(controller.parked.isEmpty)
        #expect(controller.pauseFromCapture(note: "Doorbell", kind: .person))
        #expect(controller.isPaused && !controller.isCapturing)
        #expect(try context.fetchCount(FetchDescriptor<Distraction>()) == 1)
        controller.resume()
        controller.dismissCapture()
        #expect(controller.parked.first?.didReturnToFocus == true)
        controller.end()
    }

    @Test func realReadOnlySwiftDataFailureDoesNotClaimPauseSuccess() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        do {
            let context = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
            let session = FocusSession(goal: nil, intent: "Read-only negative control", plannedSeconds: 1500)
            context.insert(session)
            try context.save()
        }
        let configuration = ModelConfiguration(schema: AnchorStore.schema, url: url, allowsSave: false, cloudKitDatabase: .none)
        let context = ModelContext(try ModelContainer(for: AnchorStore.schema, configurations: configuration))
        let controller = FocusController(context: context, tagger: TaggingService(allowsOnDeviceModel: false))
        controller.beginManualCapture()
        #expect(!controller.pauseFromCapture(note: "Unconfirmed draft", kind: .person))
        #expect(controller.isRunning && controller.isCapturing && controller.lastError != nil)
        #expect(controller.parked.isEmpty)
        let reopened = ModelContext(try rawContainer(url))
        #expect(try reopened.fetchCount(FetchDescriptor<Distraction>()) == 0)
        #expect(try reopened.fetch(FetchDescriptor<FocusSession>()).first?.state == .running)
    }


    @Test func surrenderFailureMustPreserveActiveSessionAndAvoidPartialCapture() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let context = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        context.autosaveEnabled = false
        @MainActor final class FailurePlan { var enabled = false }
        let failure = FailurePlan()
        let notifier = FocusControllerTests.RecordingNotifier()
        let activity = LiveActivityLifecycleTests.RecordingCoordinator()
        let controller = FocusController(context: context, tagger: TaggingService(allowsOnDeviceModel: false), completionNotifier: notifier, liveActivityCoordinator: activity, persistContext: { context in
            if failure.enabled {
                if try context.fetch(FetchDescriptor<FocusSession>()).contains(where: { $0.state == .finished }) { throw CocoaError(.fileWriteOutOfSpace) }
            }
            try AnchorStore.save(context)
        })
        let session = try #require(controller.start(goal: nil, intent: "Synthetic surrender failure", minutes: 25))
        controller.beginManualCapture()
        failure.enabled = true
        #expect(!controller.surrender(to: "Synthetic draft"))
        #expect(controller.session?.id == session.id)
        #expect(controller.isRunning)
        #expect(controller.parked.isEmpty)
        let reopened = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        #expect(try reopened.fetchCount(FetchDescriptor<Distraction>()) == 0)
        #expect(try reopened.fetch(FetchDescriptor<FocusSession>()).last?.state == .running)
        failure.enabled = false
        #expect(controller.surrender(to: "Synthetic draft"))
        #expect(controller.session == nil)
        let afterRetry = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        let notes = try afterRetry.fetch(FetchDescriptor<Distraction>())
        #expect(notes.count == 1 && notes.first?.privateNote == "Synthetic draft")
        #expect(notes.first?.didReturnToFocus == false)
        #expect(notes.first?.session?.endReason == .abandoned)
    }

    @Test func failedEndAndReplacementKeepOriginalSessionUntilRetryCommits() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let context = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        context.autosaveEnabled = false
        @MainActor final class FailurePlan { var enabled = false }
        let failure = FailurePlan()
        let notifier = FocusControllerTests.RecordingNotifier()
        let activity = LiveActivityLifecycleTests.RecordingCoordinator()
        let controller = FocusController(context: context, tagger: TaggingService(allowsOnDeviceModel: false), completionNotifier: notifier, liveActivityCoordinator: activity, persistContext: { context in
            if failure.enabled { throw CocoaError(.fileWriteOutOfSpace) }
            try AnchorStore.save(context)
        })
        let session = try #require(controller.start(goal: nil, intent: "Original", minutes: 25))
        let before = session.account
        let observation = Date()
        controller.observeMachineIdle(seconds: 0, at: observation)
        controller.observeMachineIdle(seconds: 3, at: observation.addingTimeInterval(10))
        failure.enabled = true
        let activityBefore = activity.calls
        #expect(!controller.end())
        #expect(notifier.cancelled.isEmpty && activity.calls == activityBefore)
        #expect(controller.isRunning && controller.session?.id == session.id)
        #expect(session.account == before && session.endedAt == nil && session.endReason == nil)
        #expect(session.computerActiveSeconds == 0 && session.computerAwaySeconds == 0)
        let replacement = controller.start(goal: nil, intent: "Must not replace", minutes: 10)
        #expect(replacement == nil && controller.session?.id == session.id)
        #expect(notifier.cancelled.isEmpty && activity.calls == activityBefore)
        let reopened = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        let sessions = try reopened.fetch(FetchDescriptor<FocusSession>())
        #expect(sessions.count == 1 && sessions.first?.state == .running)
        failure.enabled = false
        #expect(controller.end())
        #expect(controller.session == nil)
        #expect(notifier.cancelled == [session.id] && activity.calls.last == .end)
        #expect(session.computerActiveSeconds == 7 && session.computerAwaySeconds == 3)
        let afterRetry = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        #expect(try afterRetry.fetch(FetchDescriptor<FocusSession>()).first?.endReason == .endedEarly)
    }

    @Test func failedResumeKeepsPausedStateAndDoesNotPublishSuccess() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let pausedAt = Date().addingTimeInterval(-120)
        do {
            let context = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
            let session = FocusSession(goal: nil, intent: "Synthetic paused session", plannedSeconds: 1500, startedAt: pausedAt.addingTimeInterval(-60))
            var account = session.account
            account.pause(at: pausedAt)
            session.apply(account)
            session.state = .paused
            session.pausedAt = pausedAt
            context.insert(session)
            let distraction = Distraction(note: "", session: session)
            distraction.capturedAt = pausedAt
            distraction.didReturnToFocus = false
            context.insert(distraction)
            try context.save()
        }
        let config = ModelConfiguration(schema: AnchorStore.schema, url: url, allowsSave: false, cloudKitDatabase: .none)
        let context = ModelContext(try ModelContainer(for: AnchorStore.schema, configurations: config))
        context.autosaveEnabled = false
        let notifier = FocusControllerTests.RecordingNotifier()
        let activity = LiveActivityLifecycleTests.RecordingCoordinator()
        let controller = FocusController(context: context, tagger: TaggingService(allowsOnDeviceModel: false), completionNotifier: notifier, liveActivityCoordinator: activity)
        let session = try #require(controller.session)
        let before = session.account
        let beforeCalls = activity.calls
        let beforeSchedules = notifier.scheduled.count
        controller.resume()
        #expect(controller.isPaused && !controller.isCapturing && controller.lastError != nil)
        #expect(session.account == before && session.pausedAt == pausedAt)
        #expect(controller.parked.first?.didReturnToFocus == false)
        #expect(activity.calls == beforeCalls && notifier.scheduled.count == beforeSchedules)
        let reopened = ModelContext(try rawContainer(url))
        #expect(try reopened.fetch(FetchDescriptor<FocusSession>()).first?.state == .paused)
        #expect(try reopened.fetch(FetchDescriptor<Distraction>()).first?.didReturnToFocus == false)
    }


    @Test func resumeRetryCommitsOnceAndSurvivesReopen() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let context = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        context.autosaveEnabled = false
        @MainActor final class FailurePlan { var enabled = false }
        let failure = FailurePlan()
        let notifier = FocusControllerTests.RecordingNotifier()
        let activity = LiveActivityLifecycleTests.RecordingCoordinator()
        let controller = FocusController(context: context, tagger: TaggingService(allowsOnDeviceModel: false), completionNotifier: notifier, liveActivityCoordinator: activity, persistContext: { context in
            if failure.enabled { throw CocoaError(.fileWriteOutOfSpace) }
            try AnchorStore.save(context)
        })
        let session = try #require(controller.start(goal: nil, intent: "Synthetic resume retry", minutes: 25))
        controller.beginManualCapture()
        #expect(controller.pauseFromCapture(note: "Synthetic interruption", kind: .person))
        let account = session.account
        let pausedAt = session.pausedAt
        let activityBefore = activity.calls
        let schedulesBefore = notifier.scheduled.count
        failure.enabled = true
        controller.resume()
        controller.resume()
        #expect(controller.isPaused && !controller.isCapturing)
        #expect(session.account == account && session.pausedAt == pausedAt)
        #expect(controller.parked.count == 1 && controller.parked.first?.didReturnToFocus == false)
        #expect(activity.calls == activityBefore && notifier.scheduled.count == schedulesBefore)
        let afterFailure = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        #expect(try afterFailure.fetch(FetchDescriptor<FocusSession>()).first?.state == .paused)
        #expect(try afterFailure.fetch(FetchDescriptor<Distraction>()).first?.didReturnToFocus == false)
        failure.enabled = false
        controller.resume()
        #expect(controller.isRunning && controller.isCapturing && controller.lastError == nil)
        #expect(session.account.bankedSeconds == account.bankedSeconds)
        #expect(session.pausedAt == nil && session.account.runningSince != nil)
        #expect(controller.parked.count == 1 && controller.parked.first?.didReturnToFocus == true)
        let callsAfterSuccess = activity.calls
        let schedulesAfterSuccess = notifier.scheduled.count
        #expect(schedulesAfterSuccess == schedulesBefore + 1)
        controller.resume()
        #expect(activity.calls == callsAfterSuccess && notifier.scheduled.count == schedulesAfterSuccess)
        controller.dismissCapture()
        #expect(!controller.isCapturing && controller.parked.count == 1)
        let reopened = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        let saved = try #require(reopened.fetch(FetchDescriptor<FocusSession>()).first)
        #expect(saved.state == .running && saved.account == session.account)
        #expect(try reopened.fetch(FetchDescriptor<Distraction>()).count == 1)
        #expect(try reopened.fetch(FetchDescriptor<Distraction>()).first?.didReturnToFocus == true)
        controller.end()
    }

    @Test func failedStartPublishesNothingAndRetryCreatesOnlyOneSession() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let context = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        context.autosaveEnabled = false
        @MainActor final class FailurePlan { var enabled = true }
        let failure = FailurePlan()
        let notifier = FocusControllerTests.RecordingNotifier()
        let activity = LiveActivityLifecycleTests.RecordingCoordinator()
        let controller = FocusController(context: context, tagger: TaggingService(allowsOnDeviceModel: false), completionNotifier: notifier, liveActivityCoordinator: activity, persistContext: { context in
            if failure.enabled { throw CocoaError(.fileWriteOutOfSpace) }
            try AnchorStore.save(context)
        })
        let before = activity.calls
        let failed = controller.start(goal: nil, intent: "Synthetic draft", minutes: 25)
        #expect(failed == nil)
        #expect(!controller.hasSession && controller.lastError != nil)
        #expect(notifier.scheduled.isEmpty && activity.calls == before)
        // A later unrelated save must not resurrect the failed insertion.
        failure.enabled = false
        try AnchorStore.save(context)
        let afterFailure = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        #expect(try afterFailure.fetch(FetchDescriptor<FocusSession>()).isEmpty)
        controller.start(goal: nil, intent: "Synthetic draft", minutes: 25)
        #expect(controller.isRunning && controller.lastError == nil)
        #expect(notifier.scheduled.count == 1)
        let reopened = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        let saved = try reopened.fetch(FetchDescriptor<FocusSession>())
        #expect(saved.count == 1 && saved.first?.intent == "Synthetic draft")
        controller.end()
    }

    @Test func failedExtensionPreservesPausedAccountAndRetryAddsTimeOnce() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let context = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        context.autosaveEnabled = false
        @MainActor final class FailurePlan { var enabled = false }
        let failure = FailurePlan()
        let notifier = FocusControllerTests.RecordingNotifier()
        let activity = LiveActivityLifecycleTests.RecordingCoordinator()
        let controller = FocusController(context: context, tagger: TaggingService(allowsOnDeviceModel: false), completionNotifier: notifier, liveActivityCoordinator: activity, persistContext: { context in
            if failure.enabled { throw CocoaError(.fileWriteOutOfSpace) }
            try AnchorStore.save(context)
        })
        controller.start(goal: nil, intent: "Synthetic extension", minutes: 25)
        controller.pause()
        let session = try #require(controller.session)
        let before = session.account
        let pausedAt = session.pausedAt
        let calls = activity.calls
        let schedules = notifier.scheduled.count
        failure.enabled = true
        controller.extend(byMinutes: 5)
        controller.extend(byMinutes: 5)
        #expect(controller.isPaused && controller.lastError != nil)
        #expect(session.account == before && session.pausedAt == pausedAt)
        #expect(activity.calls == calls && notifier.scheduled.count == schedules)
        failure.enabled = false
        try AnchorStore.save(context)
        let afterFailure = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        #expect(try afterFailure.fetch(FetchDescriptor<FocusSession>()).first?.account == before)
        controller.extend(byMinutes: 5)
        #expect(controller.isRunning && controller.lastError == nil)
        #expect(session.account.plannedSeconds == before.plannedSeconds + 300)
        #expect(session.account.bankedSeconds == before.bankedSeconds)
        let reopened = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        #expect(try reopened.fetch(FetchDescriptor<FocusSession>()).first?.account == session.account)
        controller.end()
    }

    @Test func failedReplacementCreationKeepsCommittedPreviousHistory() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let context = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        context.autosaveEnabled = false
        @MainActor final class FailurePlan { var saves = 0; var failAt = 3 }
        let failure = FailurePlan()
        let controller = FocusController(context: context, tagger: TaggingService(allowsOnDeviceModel: false), persistContext: { context in
            failure.saves += 1
            if failure.saves == failure.failAt { throw CocoaError(.fileWriteOutOfSpace) }
            try AnchorStore.save(context)
        })
        let original = try #require(controller.start(goal: nil, intent: "Original", minutes: 25))
        // Replacement first commits the old end, then fails creating the new record.
        let replacement = controller.start(goal: nil, intent: "Replacement draft", minutes: 15)
        #expect(replacement == nil && !controller.hasSession && controller.lastError != nil)
        #expect(original.state == .finished && original.endReason == .endedEarly)
        try AnchorStore.save(context)
        let reopened = ModelContext(try AnchorStore.makeContainer(kind: .localOnly, url: url))
        let saved = try reopened.fetch(FetchDescriptor<FocusSession>())
        #expect(saved.count == 1 && saved.first?.id == original.id && saved.first?.state == .finished)
        let retry = try #require(controller.start(goal: nil, intent: "Replacement draft", minutes: 15))
        #expect(retry.id != original.id && controller.isRunning)
        #expect(try context.fetchCount(FetchDescriptor<FocusSession>()) == 2)
        controller.end()
    }

}
