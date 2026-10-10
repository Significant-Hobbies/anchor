import XCTest

final class AnchorMacUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFocusInterruptionAndReturnJourneyPersists() throws {
        let app = XCUIApplication()
        let fixtureDirectory = try isolatedDirectory(named: "focus")
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: fixtureDirectory)
        }
        let storePath = fixtureDirectory.appendingPathComponent("anchor.store").path
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = storePath
        app.launch()

        app.buttons.ci("Focus").click()
        let adHoc = app.buttons.ci("anchor.focus.start-unplanned")
        XCTAssertTrue(adHoc.waitForExistence(timeout: 5))
        adHoc.click()

        let intention = app.textFields.ci("Ship the auth flow")
        XCTAssertTrue(intention.waitForExistence(timeout: 5))
        intention.click()
        intention.typeText("Mac focus acceptance")
        app.buttons.ci("Start focusing").click()
        XCTAssertTrue(app.staticTexts.ci("Mac focus acceptance").waitForExistence(timeout: 4))

        app.buttons.ci("Lock a distraction").click()
        let note = app.textFields.ci("Slack from Ravi about the invoice")
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.click()
        note.typeText("Synthetic interruption")
        app.buttons.ci("anchor.capture.pause").click()
        let resume = app.buttons.ci("Resume")
        XCTAssertTrue(resume.waitForExistence(timeout: 3))
        keepScreenshot(app, named: "anchor-build25-mac-paused")
        resume.click()
        let decline = app.buttons.ci("Nothing — just a break")
        XCTAssertTrue(decline.waitForExistence(timeout: 3))
        decline.click()

        app.buttons.ci("End session").click()
        app.buttons.ci("History").click()
        app.radioButtons.ci("Interruptions").click()
        let parkedRow = app.buttons.matching(
            NSPredicate(format: "label  %@", "Synthetic interruption")
        ).firstMatch
        XCTAssertTrue(parkedRow.waitForExistence(timeout: 3))

        app.terminate()
        app.launch()
        app.buttons.ci("History").click()
        app.radioButtons.ci("Interruptions").click()
        XCTAssertTrue(parkedRow.waitForExistence(timeout: 3))
        keepScreenshot(app, named: "anchor-build25-mac-interruption-reopened")
    }

    @MainActor
    func testTodayCreatesCompletesReviewsAndPersistsABlock() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = isolatedStore(named: "schedule")
        app.launch()

        app.buttons.ci("Today").click()
        XCTAssertTrue(app.staticTexts.ci("Give the day one anchor").waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.datePickers.count, 0, "The schedule must allow choosing a day.")

        app.buttons.ci("Add the first entry").click()
        let title = app.textFields.ci("What will you do?")
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.click()
        title.typeText("Mac schedule acceptance")
        XCTAssertTrue(app.switches.ci("Repeat weekly").exists || app.checkBoxes.ci("Repeat weekly").exists)
        app.buttons.ci("Save").click()

        XCTAssertTrue(app.staticTexts.ci("Mac schedule acceptance").waitForExistence(timeout: 4))
        let actions = app.descendants(matching: .any)["anchor.today.block-actions"].firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 3))
        // Don't gate on isHittable — a fresh card can sit at the scroll fold
        // while scroll-to-now settles; click() scrolls it into view itself.
        actions.click()
        XCTAssertTrue(app.buttons.ci("Start now").waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons.ci("Edit or move").exists)
        XCTAssertTrue(app.buttons.ci("Explain a change").exists)
        let finish = app.buttons.ci("Finished without timing")
        XCTAssertTrue(finish.waitForExistence(timeout: 2))
        finish.click()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "value  %@", "1 finished"))
                .firstMatch.waitForExistence(timeout: 3)
        )

        app.buttons.ci("History").click()
        XCTAssertTrue(app.radioButtons.ci("Day review").waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts.ci("Reviewing today").exists)
        let comparison = app.descendants(matching: .any)["anchor.history.day-comparison"]
        XCTAssertTrue(comparison.waitForExistence(timeout: 3))
        XCTAssertTrue(String(describing: comparison.value).contains("1 untimed"))

        app.terminate()
        app.launch()
        app.buttons.ci("Today").click()
        XCTAssertTrue(app.staticTexts.ci("Mac schedule acceptance").waitForExistence(timeout: 4))
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "value  %@", "1 finished"))
                .firstMatch.waitForExistence(timeout: 3)
        )
    }

    @MainActor
    func testUsualWeekMaterialisesWhileHabitStaysFlexibleAndPersists() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = isolatedStore(named: "usual-week")
        app.launch()

        app.buttons.ci("Today").click()
        app.buttons.ci("Add the first entry").click()
        let recurringTitle = app.textFields.ci("What will you do?")
        XCTAssertTrue(recurringTitle.waitForExistence(timeout: 3))
        recurringTitle.click()
        recurringTitle.typeText("Mac weekly planning")
        app.checkBoxes.ci("Repeat weekly").click()
        app.buttons.ci("Save").click()
        XCTAssertTrue(app.staticTexts.ci("Mac weekly planning").waitForExistence(timeout: 4))

        XCTAssertFalse(app.otherElements["anchor.today.daily-check-in"].exists)

        app.buttons.ci("Habits").click()
        XCTAssertTrue(app.staticTexts.ci("Your habits").waitForExistence(timeout: 4))
        app.buttons.ci("Add a habit").click()
        let habitTitle = app.textFields.ci("What will you do?")
        XCTAssertTrue(habitTitle.waitForExistence(timeout: 3))
        habitTitle.click()
        habitTitle.typeText("Mac reset walk")
        app.buttons.ci("Save").click()
        XCTAssertTrue(element(containing: "Mac reset walk", in: app).waitForExistence(timeout: 4))

        app.terminate()
        app.launch()
        app.buttons.ci("Habits").click()
        XCTAssertTrue(element(containing: "Mac reset walk", in: app).waitForExistence(timeout: 4))
        app.buttons.ci("Today").click()
        XCTAssertTrue(app.staticTexts.ci("Mac weekly planning").waitForExistence(timeout: 4))
        // Unscheduled habits stay on Habits — Today is the timetable only.
        XCTAssertFalse(app.descendants(matching: .any)["anchor.today.habits"].exists)
        XCTAssertFalse(app.staticTexts.ci("Mac reset walk").exists)
    }

    @MainActor
    func testBehaviorProfileSavesImmediatelyAndPersists() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = isolatedStore(named: "behavior-profile")
        app.launch()

        app.buttons.ci("Habits").click()
        let editor = app.buttons.ci("anchor.habits.behavior-profile")
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()

        let shortVideos = app.buttons.ci("Short videos")
        XCTAssertTrue(shortVideos.waitForExistence(timeout: 4))
        shortVideos.click()
        XCTAssertTrue(app.staticTexts.ci("anchor.profile.saved").waitForExistence(timeout: 3))
        app.buttons.ci("Done").click()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.value as? String, "1 pattern · 0 directions")

        app.terminate()
        app.launch()
        app.buttons.ci("Habits").click()
        XCTAssertTrue(editor.waitForExistence(timeout: 4))
        XCTAssertEqual(editor.value as? String, "1 pattern · 0 directions")
    }

    @MainActor
    func testHabitsCanBeAddedEditedAndRescheduled() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = isolatedStore(named: "habit-management")
        app.launch()

        app.buttons.ci("Habits").click()
        XCTAssertTrue(app.buttons.ci("anchor.habits.add").waitForExistence(timeout: 5))
        app.buttons.ci("anchor.habits.add").click()
        let title = app.textFields.ci("What will you do?")
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.click()
        title.typeText("Two-day reset")
        app.buttons.ci("Save").click()

        XCTAssertTrue(element(containing: "Two-day reset", in: app).waitForExistence(timeout: 4))
        XCTAssertTrue(element(containing: "this week", in: app).exists)
        XCTAssertTrue(element(containing: "Any time", in: app).exists)
        let checkOff = app.buttons.ci("anchor.habits.complete")
        XCTAssertTrue(checkOff.exists)
        checkOff.click()
        XCTAssertTrue(app.buttons.ci("Undo check-off").waitForExistence(timeout: 3))
        app.terminate()
        app.launch()
        app.buttons.ci("Habits").click()
        XCTAssertTrue(app.buttons.ci("Undo check-off").waitForExistence(timeout: 4))
        app.buttons.ci("Undo check-off").click()
        XCTAssertTrue(app.buttons.ci("anchor.habits.complete").exists)

        let habitMenu = app.menuButtons["More actions for Two-day reset"]
        XCTAssertTrue(habitMenu.waitForExistence(timeout: 4))
        habitMenu.click()
        let editHabit = app.menuItems.ci("Edit habit")
        XCTAssertTrue(editHabit.waitForExistence(timeout: 3))
        editHabit.click()
        let editedTitle = app.textFields.ci("What will you do?")
        editedTitle.click()
        editedTitle.typeKey("a", modifierFlags: .command)
        editedTitle.typeText("Two-day reset edited")
        app.buttons.ci("Save").click()
        XCTAssertTrue(element(containing: "Two-day reset edited", in: app).waitForExistence(timeout: 4))

        // Habits live on the Habits tab; Today stays free of them until one is
        // scheduled at a time, which places it on the timetable.
        app.buttons.ci("Today").click()
        XCTAssertFalse(app.descendants(matching: .any)["anchor.today.habits"].exists)

        app.buttons.ci("Habits").click()
        let schedule = app.buttons.ci("Schedule")
        XCTAssertTrue(schedule.waitForExistence(timeout: 4))
        schedule.click()
        let placeHabitTitle = app.staticTexts.ci("Place habit")
        XCTAssertTrue(placeHabitTitle.waitForExistence(timeout: 3))
        app.buttons.ci("Save").click()
        XCTAssertTrue(placeHabitTitle.waitForNonExistence(timeout: 4))

        app.buttons.ci("Today").click()
        XCTAssertTrue(app.descendants(matching: .any)["anchor.today.timetable"].waitForExistence(timeout: 4))
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "value  %@", "Two-day reset edited"))
                .firstMatch.waitForExistence(timeout: 4)
        )

        keepScreenshot(app, named: "anchor-build19-mac-scheduled-habit-today")
    }

    @MainActor
    func testHabitCanBeArchivedInspectedAndRestored() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = isolatedStore(named: "habit-archive")
        app.launch()

        app.buttons.ci("Habits").click()
        XCTAssertTrue(app.buttons.ci("anchor.habits.add").waitForExistence(timeout: 5))
        app.buttons.ci("anchor.habits.add").click()
        let title = app.textFields.ci("What will you do?")
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.click()
        title.typeText("Evening reset")
        app.buttons.ci("Save").click()

        let habitMenu = app.menuButtons["More actions for Evening reset"]
        XCTAssertTrue(habitMenu.waitForExistence(timeout: 4))
        habitMenu.click()
        XCTAssertTrue(app.menuItems.ci("Archive habit").waitForExistence(timeout: 3))
        app.menuItems.ci("Archive habit").click()

        let archivedToggle = app.buttons.ci("anchor.habits.archived-toggle")
        XCTAssertTrue(archivedToggle.waitForExistence(timeout: 4))
        XCTAssertEqual(archivedToggle.value as? String, "expanded")
        XCTAssertTrue(app.buttons.ci("Inspect Evening reset").waitForExistence(timeout: 3))

        app.buttons.ci("Inspect Evening reset").click()
        XCTAssertTrue(app.textFields.ci("What will you do?").waitForExistence(timeout: 3))
        app.buttons.ci("Cancel").click()

        XCTAssertTrue(app.buttons.ci("Restore").waitForExistence(timeout: 3))
        app.buttons.ci("Restore").click()
        XCTAssertTrue(element(containing: "Evening reset", in: app).waitForExistence(timeout: 4))
        XCTAssertTrue(archivedToggle.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testEveryWeekdayCanHaveADifferentSchedule() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = isolatedStore(named: "weekday-schedules")
        app.launch()

        app.buttons.ci("Today").click()
        app.buttons.ci("Add the first entry").click()
        let initialTitle = app.textFields.ci("What will you do?")
        XCTAssertTrue(initialTitle.waitForExistence(timeout: 3))
        initialTitle.click()
        initialTitle.typeText("Initial weekly entry")
        app.checkBoxes.ci("Repeat weekly").click()
        app.buttons.ci("Save").click()
        app.buttons.ci("anchor.today.customize").click()
        let usualWeek = app.buttons.ci("anchor.timetable.routines")
        XCTAssertTrue(usualWeek.waitForExistence(timeout: 4))
        usualWeek.click()
        XCTAssertTrue(app.radioButtons.ci("Monday").waitForExistence(timeout: 4))
        XCTAssertTrue(app.radioButtons.ci("Sunday").exists)

        let selectedDay = app.radioButtons.matching(NSPredicate(format: "value == 1")).firstMatch
        XCTAssertTrue(selectedDay.waitForExistence(timeout: 3))
        let firstDay = selectedDay.label
        let addFirstDay = app.buttons.matching(NSPredicate(format: "label  %@", "Add to ")).firstMatch
        XCTAssertTrue(addFirstDay.waitForExistence(timeout: 3))
        addFirstDay.click()
        let firstTitle = app.textFields.ci("What will you do?")
        firstTitle.click()
        firstTitle.typeText("\(firstDay) planning")
        app.buttons.ci("Save").click()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label  %@", "\(firstDay) planning"))
                .firstMatch.waitForExistence(timeout: 4)
        )

        let secondDay = app.radioButtons.matching(NSPredicate(format: "value == 0")).firstMatch
        let secondDayName = secondDay.label
        secondDay.click()
        XCTAssertTrue(app.staticTexts.ci("0 usual items on \(secondDayName)").waitForExistence(timeout: 2))
        let addSecondDay = app.buttons.matching(NSPredicate(format: "label  %@", "Add to ")).firstMatch
        XCTAssertTrue(addSecondDay.waitForExistence(timeout: 3))
        addSecondDay.click()
        let secondTitle = app.textFields.ci("What will you do?")
        secondTitle.click()
        secondTitle.typeText("\(secondDayName) planning")
        app.buttons.ci("Save").click()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label  %@", "\(secondDayName) planning"))
                .firstMatch.waitForExistence(timeout: 4)
        )
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label  %@", "\(firstDay) planning"))
                .firstMatch.isHittable
        )

        keepScreenshot(app, named: "anchor-build19-mac-weekday-schedule")
    }

    @MainActor
    func testProjectsAndTagsCanBeManaged() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = isolatedStore(named: "metadata-library")
        app.launch()

        app.buttons.ci("Settings").click()
        let manage = app.buttons.ci("anchor.settings.manage-metadata")
        for _ in 0..<6 where !manage.exists { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(manage.waitForExistence(timeout: 3))
        manage.click()

        let project = app.textFields.ci("anchor.metadata.new-project")
        project.click()
        project.typeText("Launch")
        app.buttons.ci("anchor.metadata.add-project").click()
        let tag = app.textFields.ci("anchor.metadata.new-tag")
        tag.click()
        tag.typeText("Deep work")
        app.buttons.ci("anchor.metadata.add-tag").click()

        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "Launch")).firstMatch.exists)
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "Deep work")).firstMatch.exists)
        XCTAssertTrue(app.buttons.ci("Archive Launch").exists)
        XCTAssertTrue(app.buttons.ci("Archive Deep work").exists)

        let projectName = app.textFields.matching(NSPredicate(format: "value == %@", "Launch")).firstMatch
        projectName.click()
        projectName.typeKey("a", modifierFlags: .command)
        projectName.typeText("Launch plan")
        app.buttons.ci("Done").click()

        XCTAssertTrue(manage.waitForExistence(timeout: 3))
        manage.click()
        XCTAssertTrue(
            app.textFields.matching(NSPredicate(format: "value == %@", "Launch plan"))
                .firstMatch.waitForExistence(timeout: 3)
        )

        keepScreenshot(app, named: "anchor-build19-mac-projects-tags")
    }

    @MainActor
    func testSeededHistoryExposesReviewInterruptionsTrendsAndExports() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_DEMO_DATA"] = "1"
        app.launchEnvironment["ANCHOR_INITIAL_TAB"] = "history"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = isolatedStore(named: "history")
        app.launch()

        XCTAssertTrue(app.radioButtons.ci("Day review").waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts.ci("Reviewing today").exists)

        app.radioButtons.ci("Interruptions").click()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label  %@", "To deal with"))
                .firstMatch.waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.buttons.ci("Everything parked").exists)
        XCTAssertTrue(app.buttons.ci("Sessions").exists)

        app.radioButtons.ci("Trends").click()
        XCTAssertTrue(app.staticTexts.ci("When you focus").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.ci("Weekday rhythm").exists)

        let export = app.buttons.ci("Excel workbook")
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<12 where !export.exists {
            scrollView.swipeUp()
        }
        XCTAssertTrue(export.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons.ci("Excel workbook").exists)
        XCTAssertTrue(app.buttons.ci("Sessions CSV").exists)
        XCTAssertTrue(app.buttons.ci("Distractions CSV").exists)
        XCTAssertTrue(app.buttons.ci("JSON").exists)
    }

    @MainActor
    func testMiniTimerRunsTheCompactFocusLoop() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = isolatedStore(named: "mini-timer")
        app.launch()

        app.typeKey("0", modifierFlags: .command)
        let miniTimer = app.windows["Mini Timer"]
        XCTAssertTrue(miniTimer.waitForExistence(timeout: 4))
        XCTAssertTrue(miniTimer.staticTexts.ci("Set your anchor").exists)

        let intent = miniTimer.textFields.ci("What are you working on?")
        XCTAssertTrue(intent.waitForExistence(timeout: 2))
        intent.click()
        intent.typeText("Compact timer acceptance")
        miniTimer.buttons.ci("Start focusing").click()
        XCTAssertTrue(miniTimer.staticTexts.ci("Compact timer acceptance").waitForExistence(timeout: 3))

        miniTimer.buttons.ci("Pause").click()
        miniTimer.buttons.ci("Resume").click()
        XCTAssertTrue(miniTimer.staticTexts.ci("What pulled you away?").waitForExistence(timeout: 3))
        XCTAssertTrue(miniTimer.buttons.ci("Nothing — just a break").waitForExistence(timeout: 3))
        miniTimer.typeKey(.escape, modifierFlags: [])
        app.typeKey("0", modifierFlags: .command)
        XCTAssertTrue(miniTimer.waitForExistence(timeout: 3))
        let end = miniTimer.buttons.ci("End")
        XCTAssertTrue(end.waitForExistence(timeout: 3))
        let endIsHittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: end
        )
        XCTAssertEqual(XCTWaiter.wait(for: [endIsHittable], timeout: 3), .completed)
        end.click()
        XCTAssertTrue(miniTimer.staticTexts.ci("Set your anchor").waitForExistence(timeout: 3))
    }

    @MainActor
    func testMiniTimerStartsTheScheduledBlockWithoutRetypingIt() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = isolatedStore(named: "mini-timer-schedule")
        app.launch()

        app.buttons.ci("Today").click()
        app.buttons.ci("Add the first entry").click()
        let title = app.textFields.ci("What will you do?")
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.click()
        title.typeText("Menu-bar launch review")
        app.buttons.ci("Save").click()
        XCTAssertTrue(app.staticTexts.ci("Menu-bar launch review").waitForExistence(timeout: 4))

        app.typeKey("0", modifierFlags: .command)
        let miniTimer = app.windows["Mini Timer"]
        XCTAssertTrue(miniTimer.waitForExistence(timeout: 4))
        XCTAssertTrue(miniTimer.staticTexts.ci("Menu-bar launch review").waitForExistence(timeout: 3))
        miniTimer.buttons.ci("Start this block").click()
        XCTAssertTrue(miniTimer.buttons.ci("Lock a distraction").waitForExistence(timeout: 3))
        miniTimer.buttons.ci("End").click()
        app.buttons.ci("Today").click()
        let completedActions = app.buttons.ci("Actions for Menu-bar launch review")
        XCTAssertTrue(completedActions.waitForExistence(timeout: 4))
        completedActions.click()
        XCTAssertTrue(app.buttons.ci("Edit or move").waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons.ci("Log actual time…").exists)
    }

    @MainActor
    func testInterruptionFirstOnboardingUsesMacGuidance() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_DEMO"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] =
            URL(fileURLWithPath: "/tmp", isDirectory: true)
                .appendingPathComponent("anchor-mac-onboarding-\(UUID().uuidString).store")
                .path
        app.launch()

        XCTAssertTrue(app.staticTexts.ci("Plan the day. Learn what moved it.").waitForExistence(timeout: 4))
        app.buttons.ci("Choose what to protect").click()
        XCTAssertTrue(app.staticTexts.ci("What tends to take more time than you want?").waitForExistence(timeout: 4))
        app.buttons.matching(NSPredicate(format: "label ==[c] %@", "Short videos")).firstMatch.click()
        app.buttons.matching(NSPredicate(format: "label  %@", "Continue with")).firstMatch.click()
        XCTAssertTrue(app.staticTexts.ci("What do you want that time to make room for?").waitForExistence(timeout: 4))
        app.buttons.matching(NSPredicate(format: "label ==[c] %@", "More creativity")).firstMatch.click()
        app.buttons.ci("Show me how Anchor protects it").click()

        XCTAssertTrue(app.staticTexts.ci("Turn that time into something concrete.").waitForExistence(timeout: 4))
        app.buttons.ci("Shape these habits").click()
        XCTAssertTrue(app.staticTexts.ci("Choose when each habit is available.").waitForExistence(timeout: 4))

        let monday = app.buttons.ci("Monday")
        XCTAssertTrue(monday.waitForExistence(timeout: 2))
        XCTAssertEqual(monday.value as? String, "Selected")
        monday.click()
        XCTAssertEqual(monday.value as? String, "Not selected")

        app.buttons.ci("Save habits and continue").click()

        XCTAssertTrue(app.staticTexts.ci("One account for your Significant Hobbies.").waitForExistence(timeout: 4))
        #if ANCHOR_LOCAL_ONLY
        XCTAssertFalse(app.buttons.ci("anchor.hub.sign-in-apple").exists)
        XCTAssertFalse(app.buttons.ci("anchor.hub.sign-in-google").exists)
        XCTAssertTrue(app.descendants(matching: .any)["anchor.hub.unavailable"].exists)
        #else
        XCTAssertTrue(app.buttons.ci("anchor.hub.sign-in-apple").exists)
        XCTAssertTrue(app.buttons.ci("anchor.hub.sign-in-google").exists)
        #endif
        app.buttons.ci("anchor.onboarding.hub-continue-locally").click()

        XCTAssertTrue(app.staticTexts.ci("Protect one thing.").waitForExistence(timeout: 4))

        let goal = app.textFields.firstMatch
        XCTAssertTrue(goal.waitForExistence(timeout: 2))
        goal.click()
        goal.typeKey("a", modifierFlags: .command)
        goal.typeKey(.delete, modifierFlags: [])
        goal.typeText("Draft the launch note")
        app.buttons.ci("Try the park-and-return loop").click()

        XCTAssertTrue(app.staticTexts.ci("Draft the launch note").waitForExistence(timeout: 4))
        XCTAssertTrue(
            app.staticTexts.ci("anchor.onboarding.platform-guidance")
                .waitForExistence(timeout: 2)
        )
    }

    @MainActor
    func testExistingPlannerDataStillShowsCurrentOnboarding() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_DEMO_DATA"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] =
            URL(fileURLWithPath: "/tmp", isDirectory: true)
                .appendingPathComponent("anchor-mac-existing-owner-\(UUID().uuidString).store")
                .path
        app.launchArguments += ["-anchor.product-tour.seen.v4", "NO"]
        app.launch()

        XCTAssertTrue(app.staticTexts.ci("Plan the day. Learn what moved it.").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.ci("Return to Anchor").exists)
    }

    @MainActor
    func testGoogleSignInStartsAndCancelsWithoutLosingTheAccountStep() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_DEMO"] = "1"
        app.launchEnvironment["ANCHOR_ONBOARDING_INITIAL_STEP"] = "account"
        app.launchEnvironment["ANCHOR_STORE_PATH"] =
            URL(fileURLWithPath: "/tmp", isDirectory: true)
                .appendingPathComponent("anchor-mac-google-auth-\(UUID().uuidString).store")
                .path
        app.launch()

        #if ANCHOR_LOCAL_ONLY
        XCTAssertTrue(
            app.descendants(matching: .any)["anchor.hub.unavailable"]
                .waitForExistence(timeout: 5)
        )
        return
        #else
        let google = app.buttons.ci("anchor.hub.sign-in-google")
        XCTAssertTrue(google.waitForExistence(timeout: 5))
        google.click()
        XCTAssertTrue(
            app.activityIndicators["anchor.hub.sign-in-google"]
                .waitForExistence(timeout: 3)
        )
        // The AuthenticationServices sheet is remote-hosted inside Anchor's
        // accessibility tree. Prefer its explicit Cancel action; Escape is the
        // keyboard fallback when the host does not expose that action.
        let cancel = app.buttons.ci("Cancel").firstMatch
        if cancel.waitForExistence(timeout: 5) {
            cancel.click()
        } else {
            app.typeKey(.escape, modifierFlags: [])
        }

        XCTAssertTrue(google.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.ci("One account for your Significant Hobbies.").exists)
        XCTAssertEqual(app.state, .runningForeground)
        #endif
    }

    @MainActor
    func testSettingsKeepsMacPreferencesHonest() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] =
            URL(fileURLWithPath: "/tmp", isDirectory: true)
                .appendingPathComponent("anchor-mac-settings-\(UUID().uuidString).store")
                .path
        app.launch()

        app.buttons.ci("Settings").click()

        XCTAssertTrue(app.staticTexts.ci("Significant Hobbies Hub").waitForExistence(timeout: 4))
        #if ANCHOR_LOCAL_ONLY
        XCTAssertTrue(app.descendants(matching: .any)["anchor.hub.unavailable"].exists)
        XCTAssertFalse(app.buttons.ci("anchor.hub.sign-in-apple").exists)
        XCTAssertFalse(app.buttons.ci("anchor.hub.sign-in-google").exists)
        #else
        XCTAssertTrue(app.staticTexts.ci("Bring Anchor into your Hub").exists)
        #endif
        XCTAssertTrue(app.radioButtons.ci("System").exists)
        XCTAssertTrue(app.radioButtons.ci("Light").exists)
        XCTAssertTrue(app.radioButtons.ci("Dark").exists)
        app.radioButtons.ci("Dark").click()
        XCTAssertTrue(
            app.staticTexts.ci("Uses the charcoal focus canvas on this device.")
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.staticTexts.ci("This build stores appearance on this device only").exists)
        XCTAssertFalse(app.staticTexts.ci("Talk to your data").exists)
        XCTAssertTrue(app.staticTexts.ci("Local library").exists)
    }

    @MainActor
    func testTimetablePlacesBlocksOnAnHourGridAndLogsTime() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = isolatedStore(named: "timetable")
        app.launch()

        app.buttons.ci("Today").click()
        app.buttons.ci("Add the first entry").click()
        let title = app.textFields.ci("What will you do?")
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.click()
        title.typeText("Timetable acceptance")
        app.buttons.ci("Save").click()

        XCTAssertTrue(app.staticTexts.ci("Timetable acceptance").waitForExistence(timeout: 4))
        XCTAssertTrue(app.descendants(matching: .any)["anchor.today.timetable"].waitForExistence(timeout: 3))
        keepScreenshot(app, named: "anchor-timetable-grid")

        // Customize — the timetable's own options plus the door to usual week.
        app.buttons.ci("anchor.today.customize").click()
        XCTAssertTrue(app.descendants(matching: .any)["anchor.timetable.start-hour"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["anchor.timetable.lived-trace"].exists)
        app.buttons.ci("anchor.timetable.routines").click()
        XCTAssertTrue(app.staticTexts.ci("Your usual week").waitForExistence(timeout: 3))
        app.buttons.ci("anchor.routines.done").click()
        app.buttons.ci("anchor.timetable.options-done").click()

        // Quick log — "still happening" captures an open entry without a timer.
        app.buttons.ci("anchor.today.log-time").click()
        let logTitle = app.textFields.ci("anchor.log.title")
        XCTAssertTrue(logTitle.waitForExistence(timeout: 3))
        logTitle.click()
        logTitle.typeText("In-flight entry")
        app.buttons.ci("anchor.log.save").click()
        XCTAssertTrue(app.staticTexts.ci("In-flight entry").waitForExistence(timeout: 4))
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "value  %@", "1 now"))
                .firstMatch.waitForExistence(timeout: 3)
        )

        // Finishing the open entry records its real span.
        let inFlightActions = app.buttons.ci("Actions for In-flight entry")
        XCTAssertTrue(inFlightActions.waitForExistence(timeout: 3))
        inFlightActions.click()
        let finish = app.buttons.ci("Finish now")
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        finish.click()

        // Retroactive log — toggling "Still happening" off records a past span.
        app.buttons.ci("anchor.today.log-time").click()
        let retroTitle = app.textFields.ci("anchor.log.title")
        XCTAssertTrue(retroTitle.waitForExistence(timeout: 3))
        retroTitle.click()
        retroTitle.typeText("Logged earlier")
        // The timing section sits at the bottom of the sheet's scroll view —
        // the checkbox reports a frame there while still clipped, and a plain
        // click lands on dead space. Scroll the sheet down first.
        let ongoingToggle = app.checkBoxes.ci("anchor.log.still-happening")
        XCTAssertTrue(ongoingToggle.waitForExistence(timeout: 2))
        let sheetScroll = app.scrollViews
            .containing(.checkBox, identifier: "anchor.log.still-happening")
            .firstMatch
        for _ in 0..<4 { sheetScroll.swipeUp() }
        ongoingToggle.click()
        // The "Ended" picker only exists once "Still happening" is off — a
        // missed click would silently save the entry as still in progress.
        XCTAssertTrue(app.datePickers["anchor.log.end"].waitForExistence(timeout: 3))
        app.buttons.ci("anchor.log.save").click()
        XCTAssertTrue(app.staticTexts.ci("Logged earlier").waitForExistence(timeout: 4))
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "value  %@", "2 finished"))
                .firstMatch.waitForExistence(timeout: 3)
        )
        keepScreenshot(app, named: "anchor-timetable-logged")

        // Logged entries count as observed time — no "untimed" in the review.
        app.buttons.ci("History").click()
        let comparison = app.descendants(matching: .any)["anchor.history.day-comparison"]
        XCTAssertTrue(comparison.waitForExistence(timeout: 3))
        XCTAssertFalse(String(describing: comparison.value).contains("untimed"))

        app.terminate()
        app.launch()
        app.buttons.ci("Today").click()
        XCTAssertTrue(app.staticTexts.ci("Logged earlier").waitForExistence(timeout: 4))
        XCTAssertTrue(app.descendants(matching: .any)["anchor.today.timetable"].waitForExistence(timeout: 3))
    }

    private func isolatedDirectory(named name: String) throws -> URL {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("anchor-mac-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func isolatedStore(named name: String) -> String {
        URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("anchor-mac-\(name)-\(UUID().uuidString).store")
            .path
    }

    @MainActor
    private func keepScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func element(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label  %@ OR value CONTAINS %@",
                text,
                text
            )
        ).firstMatch
    }
}
