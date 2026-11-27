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

        XCTAssertTrue(app.buttons.ci("Focus").exists)
        app.buttons.ci("Focus").click()

        let intention = app.textFields.ci("What are you focusing on?")
        XCTAssertTrue(intention.waitForExistence(timeout: 5))
        intention.click()
        intention.typeText("Mac focus acceptance")
        app.buttons.ci("Start focusing").click()
        XCTAssertTrue(app.staticTexts.ci("Mac focus acceptance").waitForExistence(timeout: 4))

        app.buttons.ci("Log interruption").click()
        let note = app.textFields.ci("What interrupted you?")
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
        app.buttons.ci("Analysis").click()
        let parkedRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[c] %@", "Synthetic interruption")
        ).firstMatch
        XCTAssertTrue(parkedRow.waitForExistence(timeout: 3))

        app.terminate()
        app.launch()
        app.buttons.ci("Analysis").click()
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
        XCTAssertTrue(app.buttons.ci("Add done entry").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.ci("Choose date").exists, "The schedule must allow choosing a day.")

        app.buttons.ci("Add scheduled entry").click()
        let title = app.textFields.ci("What will you do?")
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.click()
        title.typeText("Mac schedule acceptance")
        app.descendants(matching: .any).ci("Entry actions").firstMatch.click()
        app.descendants(matching: .any).ci("More options…").firstMatch.click()
        XCTAssertTrue(app.switches.ci("Repeat weekly").exists || app.checkBoxes.ci("Repeat weekly").exists)
        let sheet = app.sheets.firstMatch
        XCTAssertEqual(sheet.textFields["anchor.plan.editor.title"].value as? String, "Mac schedule acceptance")
        sheet.buttons["anchor.plan.editor.save"].click()

        XCTAssertTrue(app.staticTexts.ci("Mac schedule acceptance").waitForExistence(timeout: 4))
        let actions = app.descendants(matching: .any)["anchor.today.block-actions"].firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 3))
        scrollIntoVisibleTimetable(actions, in: app.scrollViews.firstMatch)
        actions.click()
        XCTAssertTrue(app.buttons.ci("Mark as done").waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any).ci("Edit entry").exists)
        XCTAssertFalse(app.buttons.ci("Explain a change").exists)
        app.buttons.ci("More").click()
        XCTAssertTrue(app.buttons.ci("Explain a change").exists)
        let finish = app.descendants(matching: .any).ci("Finished without timing")
        XCTAssertTrue(finish.waitForExistence(timeout: 2))
        finish.click()

        app.buttons.ci("Analysis").click()
        XCTAssertTrue(app.staticTexts.ci("Insights").waitForExistence(timeout: 4))

        app.terminate()
        app.launch()
        app.buttons.ci("Today").click()
        XCTAssertTrue(app.staticTexts.ci("Mac schedule acceptance").waitForExistence(timeout: 4))
    }

    @MainActor
    func testUsualWeekMaterialisesAndPersists() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = isolatedStore(named: "usual-week")
        app.launch()

        app.buttons.ci("Today").click()
        app.buttons.ci("Add scheduled entry").click()
        let recurringTitle = app.textFields.ci("What will you do?")
        XCTAssertTrue(recurringTitle.waitForExistence(timeout: 3))
        recurringTitle.click()
        recurringTitle.typeText("Mac weekly planning")
        app.descendants(matching: .any).ci("Entry actions").firstMatch.click()
        app.descendants(matching: .any).ci("More options…").firstMatch.click()
        app.checkBoxes.ci("Repeat weekly").click()
        app.sheets.firstMatch.buttons["anchor.plan.editor.save"].click()
        XCTAssertTrue(app.staticTexts.ci("Mac weekly planning").waitForExistence(timeout: 4))

        XCTAssertFalse(app.otherElements["anchor.today.daily-check-in"].exists)

        app.terminate()
        app.launch()
        app.buttons.ci("Today").click()
        XCTAssertTrue(app.staticTexts.ci("Mac weekly planning").waitForExistence(timeout: 4))
    }

    @MainActor
    func testBehaviorProfileSavesImmediatelyAndPersists() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = isolatedStore(named: "behavior-profile")
        app.launch()

        func openPatterns() {
            app.buttons.ci("Settings").click()
            let editor = app.buttons.ci("anchor.settings.patterns")
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            editor.click()
        }
        openPatterns()
        let shortVideos = app.buttons.ci("Short videos")
        XCTAssertTrue(shortVideos.waitForExistence(timeout: 4))
        shortVideos.click()
        XCTAssertTrue(app.staticTexts.ci("anchor.profile.saved").waitForExistence(timeout: 3))
        app.terminate()
        app.launch()
        openPatterns()
        XCTAssertTrue(shortVideos.waitForExistence(timeout: 4))
        XCTAssertEqual(shortVideos.value as? String, "Selected")
    }

    @MainActor
    func testHabitsAreDerivedInAnalysis() {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = "/tmp/anchor-observed-\(UUID().uuidString).store"
        app.launch()
        XCTAssertFalse(app.buttons.ci("Habits").exists)
        app.buttons.ci("Analysis").click()
        XCTAssertTrue(app.staticTexts.ci("Habit insights").waitForExistence(timeout: 4))
    }

    @MainActor
    func testEveryWeekdayCanHaveADifferentSchedule() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = isolatedStore(named: "weekday-schedules")
        app.launch()

        app.buttons.ci("Today").click()
        app.buttons.ci("Add scheduled entry").click()
        let initialTitle = app.textFields.ci("What will you do?")
        XCTAssertTrue(initialTitle.waitForExistence(timeout: 3))
        initialTitle.click()
        initialTitle.typeText("Initial weekly entry")
        app.descendants(matching: .any).ci("Entry actions").firstMatch.click()
        app.descendants(matching: .any).ci("More options…").firstMatch.click()
        app.checkBoxes.ci("Repeat weekly").click()
        app.sheets.firstMatch.buttons["anchor.plan.editor.save"].click()
        app.buttons.ci("anchor.today.tools").click()
        app.descendants(matching: .any).ci("anchor.today.customize").firstMatch.click()
        let usualWeek = app.buttons.ci("anchor.timetable.routines")
        XCTAssertTrue(usualWeek.waitForExistence(timeout: 4))
        usualWeek.click()
        XCTAssertTrue(app.radioButtons.ci("Monday").waitForExistence(timeout: 4))
        XCTAssertTrue(app.radioButtons.ci("Sunday").exists)

        let selectedDay = app.radioButtons.matching(NSPredicate(format: "value == 1")).firstMatch
        XCTAssertTrue(selectedDay.waitForExistence(timeout: 3))
        let firstDay = selectedDay.label
        let addFirstDay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Add to ")).firstMatch
        XCTAssertTrue(addFirstDay.waitForExistence(timeout: 3))
        addFirstDay.click()
        let firstTitle = app.textFields.ci("What will you do?")
        firstTitle.click()
        firstTitle.typeText("\(firstDay) planning")
        app.buttons.ci("Save").click()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "\(firstDay) planning"))
                .firstMatch.waitForExistence(timeout: 4)
        )

        let secondDay = app.radioButtons.matching(NSPredicate(format: "value == 0")).firstMatch
        let secondDayName = secondDay.label
        secondDay.click()
        XCTAssertTrue(app.staticTexts.ci("0 usual items on \(secondDayName)").waitForExistence(timeout: 2))
        let addSecondDay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Add to ")).firstMatch
        XCTAssertTrue(addSecondDay.waitForExistence(timeout: 3))
        addSecondDay.click()
        let secondTitle = app.textFields.ci("What will you do?")
        secondTitle.click()
        secondTitle.typeText("\(secondDayName) planning")
        app.buttons.ci("Save").click()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "\(secondDayName) planning"))
                .firstMatch.waitForExistence(timeout: 4)
        )
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "\(firstDay) planning"))
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

        XCTAssertTrue(app.staticTexts.ci("Insights").waitForExistence(timeout: 6))
        XCTAssertFalse(app.radioButtons.ci("Day review").exists)

        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "To deal with"))
                .firstMatch.waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.buttons.ci("Everything parked").exists)
        XCTAssertTrue(app.buttons.ci("Sessions").exists)

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
        app.buttons.ci("Add scheduled entry").click()
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
        app.typeKey("0", modifierFlags: .command)
        if miniTimer.exists {
            let closeWindow = miniTimer.buttons["_XCUI:CloseWindow"]
            XCTAssertTrue(closeWindow.waitForExistence(timeout: 3))
            closeWindow.click()
        }
        XCTAssertTrue(miniTimer.waitForNonExistence(timeout: 3), "The compact window must close before using Today.")
        app.buttons.ci("Today").click()
        let completedActions = app.buttons.ci("Actions for Menu-bar launch review")
        XCTAssertTrue(completedActions.waitForExistence(timeout: 4))
        scrollIntoVisibleTimetable(completedActions, in: app.scrollViews.firstMatch)
        completedActions.click()
        XCTAssertTrue(app.descendants(matching: .any).ci("Edit entry").waitForExistence(timeout: 3), app.debugDescription)
        app.buttons.ci("More").click()
        XCTAssertFalse(app.descendants(matching: .any).ci("Log actual time…").exists)
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
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Continue with")).firstMatch.click()
        XCTAssertTrue(app.staticTexts.ci("What do you want that time to make room for?").waitForExistence(timeout: 4))
        app.buttons.matching(NSPredicate(format: "label ==[c] %@", "More creativity")).firstMatch.click()
        app.buttons.ci("Continue").click()

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

        XCTAssertTrue(app.radioButtons.ci("System").exists)
        XCTAssertTrue(app.radioButtons.ci("Light").exists)
        XCTAssertTrue(app.radioButtons.ci("Dark").exists)
        app.radioButtons.ci("Dark").click()
        app.buttons.ci("Account and privacy").click()
        XCTAssertTrue(app.staticTexts.ci("Significant Hobbies Hub").waitForExistence(timeout: 4))
        #if ANCHOR_LOCAL_ONLY
        XCTAssertTrue(app.descendants(matching: .any)["anchor.hub.unavailable"].exists)
        XCTAssertFalse(app.buttons.ci("anchor.hub.sign-in-apple").exists)
        XCTAssertFalse(app.buttons.ci("anchor.hub.sign-in-google").exists)
        #else
        XCTAssertTrue(app.staticTexts.ci("Bring Anchor into your Hub").exists)
        #endif
        app.buttons.ci("Done").click()
        app.buttons.ci("Data & continuity").click()
        XCTAssertTrue(app.staticTexts.ci("Local library").waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", "charcoal focus canvas", "charcoal focus canvas")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.ci("Talk to your data").exists)
    }

    @MainActor
    func testTimetablePlacesBlocksOnAnHourGridAndLogsTime() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = isolatedStore(named: "timetable")
        app.launch()

        app.buttons.ci("Today").click()
        app.buttons.ci("Add scheduled entry").click()
        let title = app.textFields.ci("What will you do?")
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.click()
        title.typeText("Timetable acceptance")
        app.buttons.ci("Save").click()

        XCTAssertTrue(app.staticTexts.ci("Timetable acceptance").waitForExistence(timeout: 4))
        XCTAssertTrue(app.descendants(matching: .any)["anchor.today.timetable"].waitForExistence(timeout: 3))
        keepScreenshot(app, named: "anchor-timetable-grid")

        // Customize — the timetable's own options plus the door to usual week.
        let viewport = app.scrollViews.firstMatch
        let customize = app.descendants(matching: .any).ci("anchor.today.customize").firstMatch
        let tools = app.buttons.ci("anchor.today.tools")
        scrollIntoVisibleTimetable(tools, in: viewport)
        tools.click()
        customize.click()
        XCTAssertTrue(app.descendants(matching: .any)["anchor.timetable.start-hour"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["anchor.timetable.lived-trace"].exists)
        app.buttons.ci("anchor.timetable.routines").click()
        XCTAssertTrue(app.staticTexts.ci("Your usual week").waitForExistence(timeout: 3))
        app.buttons.ci("anchor.routines.done").click()
        app.buttons.ci("anchor.timetable.options-done").click()

        // Quick log — "still happening" captures an open entry without a timer.
        let logTime = app.descendants(matching: .any).ci("anchor.today.log-time").firstMatch
        app.buttons.ci("Add done entry").click()
        app.descendants(matching: .any).ci("Entry actions").firstMatch.click()
        logTime.click()
        let logTitle = app.textFields.ci("anchor.log.title")
        XCTAssertTrue(logTitle.waitForExistence(timeout: 3))
        logTitle.click()
        logTitle.typeText("In-flight entry")
        app.checkBoxes.ci("anchor.log.still-happening").click()
        app.buttons.ci("anchor.log.save").click()
        XCTAssertTrue(app.buttons.ci("Edit done entry In-flight entry").waitForExistence(timeout: 4))

        // Finishing the open entry records its real span.
        let liveLog = app.buttons.ci("Edit done entry In-flight entry")
        scrollIntoVisibleTimetable(liveLog, in: viewport)
        liveLog.click()
        let liveToggle = app.checkBoxes.ci("anchor.log.still-happening")
        XCTAssertTrue(liveToggle.waitForExistence(timeout: 3))
        let liveScroll = app.scrollViews.containing(.checkBox, identifier: "anchor.log.still-happening").firstMatch
        for _ in 0..<4 { liveScroll.swipeUp() }
        liveToggle.click()
        XCTAssertTrue(app.datePickers["anchor.log.end"].waitForExistence(timeout: 3))
        app.buttons.ci("anchor.log.save").click()

        // Retroactive log — toggling "Still happening" off records a past span.
        app.buttons.ci("Add done entry").click()
        app.descendants(matching: .any).ci("Entry actions").firstMatch.click()
        logTime.click()
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
        if (ongoingToggle.value as? String) == "1" { ongoingToggle.click() }
        // The "Ended" picker only exists once "Still happening" is off — a
        // missed click would silently save the entry as still in progress.
        XCTAssertTrue(app.datePickers["anchor.log.end"].waitForExistence(timeout: 3))
        app.buttons.ci("anchor.log.save").click()
        XCTAssertTrue(app.buttons.ci("Edit done entry Logged earlier").waitForExistence(timeout: 4))
        keepScreenshot(app, named: "anchor-timetable-logged")

        app.terminate()
        app.launch()
        app.buttons.ci("Today").click()
        XCTAssertTrue(app.buttons.ci("Edit done entry Logged earlier").waitForExistence(timeout: 4))
        XCTAssertTrue(app.descendants(matching: .any)["anchor.today.timetable"].waitForExistence(timeout: 3))
    }

    private func isolatedDirectory(named name: String) throws -> URL {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("anchor-mac-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @MainActor
    private func scrollIntoVisibleTimetable(_ target: XCUIElement, in scrollView: XCUIElement) {
        XCTAssertTrue(scrollView.waitForExistence(timeout: 3), "The Today scroll viewport must exist.")
        for _ in 0..<6 {
            let viewport = scrollView.frame.insetBy(dx: 1, dy: 1)
            let frame = target.frame
            if viewport.contains(frame), target.isHittable { return }
            if frame.minY < viewport.minY {
                scrollView.swipeDown()
            } else if frame.maxY > viewport.maxY {
                scrollView.swipeUp()
            } else {
                break
            }
        }

        let viewport = scrollView.frame.insetBy(dx: 1, dy: 1)
        XCTAssertTrue(
            viewport.contains(target.frame) && target.isHittable,
            "The control must be fully inside the Today scroll viewport and hittable before clicking it."
        )
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
                format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@",
                text,
                text
            )
        ).firstMatch
    }
}
