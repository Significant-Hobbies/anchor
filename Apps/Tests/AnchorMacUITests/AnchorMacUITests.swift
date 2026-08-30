import XCTest

final class AnchorMacUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFocusInterruptionAndReturnJourneyPersists() throws {
        let app = XCUIApplication()
        let storePath = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("anchor-mac-focus-\(UUID().uuidString).store")
            .path
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = storePath
        app.launch()

        app.buttons["Focus"].click()
        let adHoc = app.buttons["anchor.focus.start-unplanned"]
        XCTAssertTrue(adHoc.waitForExistence(timeout: 5))
        adHoc.click()

        let intention = app.textFields["Ship the auth flow"]
        XCTAssertTrue(intention.waitForExistence(timeout: 5))
        intention.click()
        intention.typeText("Mac focus acceptance")
        app.buttons["Start focusing"].click()
        XCTAssertTrue(app.staticTexts["Mac focus acceptance"].waitForExistence(timeout: 4))

        app.buttons["Lock a distraction"].click()
        let note = app.textFields["Slack from Ravi about the invoice"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.click()
        note.typeText("Synthetic interruption")
        app.buttons["Park it — back to work"].click()
        app.buttons["Back to work"].click()
        XCTAssertTrue(app.staticTexts["Synthetic interruption"].waitForExistence(timeout: 3))

        app.buttons["Pause"].click()
        app.buttons["Resume"].click()
        let decline = app.buttons["Nothing — just a break"]
        XCTAssertTrue(decline.waitForExistence(timeout: 3))
        decline.click()

        app.buttons["End session"].click()
        app.buttons["History"].click()
        app.radioButtons["Interruptions"].click()
        let parkedRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Synthetic interruption")
        ).firstMatch
        XCTAssertTrue(parkedRow.waitForExistence(timeout: 3))

        app.terminate()
        app.launch()
        app.buttons["History"].click()
        app.radioButtons["Interruptions"].click()
        XCTAssertTrue(parkedRow.waitForExistence(timeout: 3))
    }

    @MainActor
    func testTodayCreatesCompletesReviewsAndPersistsABlock() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = isolatedStore(named: "schedule")
        app.launch()

        app.buttons["Today"].click()
        XCTAssertTrue(app.staticTexts["Give the day one anchor"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.datePickers.count, 0, "Today must not browse other dates; History owns that.")

        app.buttons["Add the first block"].click()
        let title = app.textFields["What will you do?"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.click()
        title.typeText("Mac schedule acceptance")
        XCTAssertTrue(app.switches["Repeat weekly"].exists || app.checkBoxes["Repeat weekly"].exists)
        app.buttons["Save"].click()

        XCTAssertTrue(app.staticTexts["Mac schedule acceptance"].waitForExistence(timeout: 4))
        let actions = app.descendants(matching: .any)["anchor.today.block-actions"].firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 3))
        actions.click()
        XCTAssertTrue(app.buttons["Start now"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Edit or move"].exists)
        XCTAssertTrue(app.buttons["Explain a change"].exists)
        let finish = app.buttons["Finished without timing"]
        XCTAssertTrue(finish.waitForExistence(timeout: 2))
        finish.click()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "1 finished"))
                .firstMatch.waitForExistence(timeout: 3)
        )

        app.buttons["History"].click()
        XCTAssertTrue(app.radioButtons["Day review"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Reviewing today"].exists)
        let comparison = app.descendants(matching: .any)["anchor.history.day-comparison"]
        XCTAssertTrue(comparison.waitForExistence(timeout: 3))
        XCTAssertTrue(String(describing: comparison.value).contains("1 untimed"))

        app.terminate()
        app.launch()
        app.buttons["Today"].click()
        XCTAssertTrue(app.staticTexts["Mac schedule acceptance"].waitForExistence(timeout: 4))
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "1 finished"))
                .firstMatch.waitForExistence(timeout: 3)
        )
    }

    @MainActor
    func testUsualWeekMaterialisesWhileHabitStaysFlexibleAndPersists() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = isolatedStore(named: "usual-week")
        app.launch()

        app.buttons["Today"].click()
        let setup = app.buttons["Set up usual week"]
        XCTAssertTrue(setup.waitForExistence(timeout: 5))
        setup.click()
        XCTAssertTrue(app.staticTexts["Your usual week"].waitForExistence(timeout: 3))
        let addRoutine = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Add to ")).firstMatch
        XCTAssertTrue(addRoutine.waitForExistence(timeout: 3))
        addRoutine.click()

        let recurringTitle = app.textFields["What will you do?"]
        XCTAssertTrue(recurringTitle.waitForExistence(timeout: 3))
        recurringTitle.click()
        recurringTitle.typeText("Mac weekly planning")
        app.buttons["Save"].click()
        XCTAssertTrue(app.staticTexts["Mac weekly planning"].waitForExistence(timeout: 4))
        app.buttons["Done"].click()
        XCTAssertTrue(app.staticTexts["Mac weekly planning"].waitForExistence(timeout: 4))

        let useUsual = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Use usual")
        ).firstMatch
        XCTAssertTrue(useUsual.waitForExistence(timeout: 3))
        useUsual.click()
        XCTAssertFalse(app.otherElements["anchor.today.daily-check-in"].exists)

        app.buttons["Habits"].click()
        XCTAssertTrue(app.staticTexts["This week"].waitForExistence(timeout: 4))
        app.buttons["Add a habit"].click()
        let habitTitle = app.textFields["What will you do?"]
        XCTAssertTrue(habitTitle.waitForExistence(timeout: 3))
        habitTitle.click()
        habitTitle.typeText("Mac reset walk")
        app.buttons["Save"].click()
        XCTAssertTrue(element(containing: "Mac reset walk", in: app).waitForExistence(timeout: 4))

        app.terminate()
        app.launch()
        app.buttons["Habits"].click()
        XCTAssertTrue(element(containing: "Mac reset walk", in: app).waitForExistence(timeout: 4))
        app.buttons["Today"].click()
        XCTAssertTrue(app.staticTexts["Mac weekly planning"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.descendants(matching: .any)["anchor.today.habits"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Mac reset walk"].waitForExistence(timeout: 4))
    }

    @MainActor
    func testBehaviorProfileSavesImmediatelyAndPersists() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = isolatedStore(named: "behavior-profile")
        app.launch()

        app.buttons["Habits"].click()
        let editor = app.buttons["anchor.habits.behavior-profile"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()

        let shortVideos = app.buttons["Short videos"]
        XCTAssertTrue(shortVideos.waitForExistence(timeout: 4))
        shortVideos.click()
        XCTAssertTrue(app.staticTexts["anchor.profile.saved"].waitForExistence(timeout: 3))
        app.buttons["Done"].click()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.value as? String, "1 pattern · 0 directions")

        app.terminate()
        app.launch()
        app.buttons["Habits"].click()
        XCTAssertTrue(editor.waitForExistence(timeout: 4))
        XCTAssertEqual(editor.value as? String, "1 pattern · 0 directions")
    }

    @MainActor
    func testHabitsCanBeAddedEditedAndRescheduled() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = isolatedStore(named: "habit-management")
        app.launch()

        app.buttons["Habits"].click()
        XCTAssertTrue(app.buttons["anchor.habits.add"].waitForExistence(timeout: 5))
        app.buttons["anchor.habits.add"].click()
        let title = app.textFields["What will you do?"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.click()
        title.typeText("Two-day reset")
        app.buttons["Save"].click()

        XCTAssertTrue(element(containing: "Two-day reset", in: app).waitForExistence(timeout: 4))
        XCTAssertTrue(element(containing: "this week", in: app).exists)
        XCTAssertTrue(element(containing: "Any time", in: app).exists)
        XCTAssertTrue(app.buttons["Edit"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Adjust"].firstMatch.exists)
        app.buttons["Edit"].firstMatch.click()
        let editedTitle = app.textFields["What will you do?"]
        editedTitle.click()
        editedTitle.typeKey("a", modifierFlags: .command)
        editedTitle.typeText("Two-day reset edited")
        app.buttons["Save"].click()
        XCTAssertTrue(element(containing: "Two-day reset edited", in: app).waitForExistence(timeout: 4))

        app.buttons["Today"].click()
        XCTAssertTrue(app.descendants(matching: .any)["anchor.today.habits"].waitForExistence(timeout: 4))
        app.buttons["anchor.today.habit.done"].click()
        XCTAssertTrue(element(containing: "Completed today", in: app).waitForExistence(timeout: 3))
        app.buttons["anchor.today.habit.undo"].click()
        app.buttons["anchor.today.habit.place"].click()
        let placeHabitTitle = app.staticTexts["Place habit"]
        XCTAssertTrue(placeHabitTitle.waitForExistence(timeout: 3))
        app.buttons["Save"].click()
        XCTAssertTrue(placeHabitTitle.waitForNonExistence(timeout: 4))
        XCTAssertTrue(app.buttons["anchor.today.habit.place"].waitForNonExistence(timeout: 4))

        keepScreenshot(app, named: "anchor-build19-mac-flexible-habits-today")
    }

    @MainActor
    func testEveryWeekdayCanHaveADifferentSchedule() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = isolatedStore(named: "weekday-schedules")
        app.launch()

        app.buttons["Today"].click()
        app.buttons["Set up usual week"].click()
        XCTAssertTrue(app.radioButtons["Monday"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.radioButtons["Sunday"].exists)

        let selectedDay = app.radioButtons.matching(NSPredicate(format: "value == 1")).firstMatch
        XCTAssertTrue(selectedDay.waitForExistence(timeout: 3))
        let firstDay = selectedDay.label
        let addFirstDay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Add to ")).firstMatch
        XCTAssertTrue(addFirstDay.waitForExistence(timeout: 3))
        addFirstDay.click()
        let firstTitle = app.textFields["What will you do?"]
        firstTitle.click()
        firstTitle.typeText("\(firstDay) planning")
        app.buttons["Save"].click()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(firstDay) planning"))
                .firstMatch.waitForExistence(timeout: 4)
        )

        let secondDay = app.radioButtons.matching(NSPredicate(format: "value == 0")).firstMatch
        let secondDayName = secondDay.label
        secondDay.click()
        XCTAssertTrue(app.staticTexts["0 usual items on \(secondDayName)"].waitForExistence(timeout: 2))
        let addSecondDay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Add to ")).firstMatch
        XCTAssertTrue(addSecondDay.waitForExistence(timeout: 3))
        addSecondDay.click()
        let secondTitle = app.textFields["What will you do?"]
        secondTitle.click()
        secondTitle.typeText("\(secondDayName) planning")
        app.buttons["Save"].click()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(secondDayName) planning"))
                .firstMatch.waitForExistence(timeout: 4)
        )
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(firstDay) planning"))
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

        app.buttons["Settings"].click()
        let manage = app.buttons["anchor.settings.manage-metadata"]
        for _ in 0..<6 where !manage.exists { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(manage.waitForExistence(timeout: 3))
        manage.click()

        let project = app.textFields["anchor.metadata.new-project"]
        project.click()
        project.typeText("Launch")
        app.buttons["anchor.metadata.add-project"].click()
        let tag = app.textFields["anchor.metadata.new-tag"]
        tag.click()
        tag.typeText("Deep work")
        app.buttons["anchor.metadata.add-tag"].click()

        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "Launch")).firstMatch.exists)
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "Deep work")).firstMatch.exists)
        XCTAssertTrue(app.buttons["Archive Launch"].exists)
        XCTAssertTrue(app.buttons["Archive Deep work"].exists)

        let projectName = app.textFields.matching(NSPredicate(format: "value == %@", "Launch")).firstMatch
        projectName.click()
        projectName.typeKey("a", modifierFlags: .command)
        projectName.typeText("Launch plan")
        app.buttons["Done"].click()

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

        XCTAssertTrue(app.radioButtons["Day review"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Reviewing today"].exists)

        app.radioButtons["Interruptions"].click()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "To deal with"))
                .firstMatch.waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.buttons["Everything parked"].exists)
        XCTAssertTrue(app.buttons["Sessions"].exists)

        app.radioButtons["Trends"].click()
        XCTAssertTrue(app.staticTexts["When you focus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Weekday rhythm"].exists)

        let export = app.buttons["Excel workbook"]
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<12 where !export.exists {
            scrollView.swipeUp()
        }
        XCTAssertTrue(export.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Excel workbook"].exists)
        XCTAssertTrue(app.buttons["Sessions CSV"].exists)
        XCTAssertTrue(app.buttons["Distractions CSV"].exists)
        XCTAssertTrue(app.buttons["JSON"].exists)
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
        XCTAssertTrue(miniTimer.staticTexts["Set your anchor"].exists)

        let intent = miniTimer.textFields["What are you working on?"]
        XCTAssertTrue(intent.waitForExistence(timeout: 2))
        intent.click()
        intent.typeText("Compact timer acceptance")
        miniTimer.buttons["Start focusing"].click()
        XCTAssertTrue(miniTimer.staticTexts["Compact timer acceptance"].waitForExistence(timeout: 3))

        miniTimer.buttons["Pause"].click()
        miniTimer.buttons["Resume"].click()
        XCTAssertTrue(miniTimer.staticTexts["What pulled you away?"].waitForExistence(timeout: 3))
        XCTAssertTrue(miniTimer.buttons["Nothing — just a break"].waitForExistence(timeout: 3))
        miniTimer.typeKey(.escape, modifierFlags: [])
        app.typeKey("0", modifierFlags: .command)
        XCTAssertTrue(miniTimer.waitForExistence(timeout: 3))
        let end = miniTimer.buttons["End"]
        XCTAssertTrue(end.waitForExistence(timeout: 3))
        let endIsHittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: end
        )
        XCTAssertEqual(XCTWaiter.wait(for: [endIsHittable], timeout: 3), .completed)
        end.click()
        XCTAssertTrue(miniTimer.staticTexts["Set your anchor"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testMiniTimerStartsTheScheduledBlockWithoutRetypingIt() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = isolatedStore(named: "mini-timer-schedule")
        app.launch()

        app.buttons["Today"].click()
        app.buttons["Add the first block"].click()
        let title = app.textFields["What will you do?"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.click()
        title.typeText("Menu-bar launch review")
        app.buttons["Save"].click()
        XCTAssertTrue(element(containing: "Menu-bar launch review", in: app).waitForExistence(timeout: 4))

        app.typeKey("0", modifierFlags: .command)
        let miniTimer = app.windows["Mini Timer"]
        XCTAssertTrue(miniTimer.waitForExistence(timeout: 4))
        XCTAssertTrue(miniTimer.staticTexts["Menu-bar launch review"].waitForExistence(timeout: 3))
        miniTimer.buttons["Start this block"].click()
        XCTAssertTrue(miniTimer.buttons["Lock a distraction"].waitForExistence(timeout: 3))
        miniTimer.buttons["End"].click()
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

        XCTAssertTrue(app.staticTexts["Plan the day. Learn what moved it."].waitForExistence(timeout: 4))
        app.buttons["Choose what to protect"].click()
        XCTAssertTrue(app.staticTexts["What tends to take more time than you want?"].waitForExistence(timeout: 4))
        app.buttons.matching(NSPredicate(format: "label == %@", "Short videos")).firstMatch.click()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Continue with")).firstMatch.click()
        XCTAssertTrue(app.staticTexts["What do you want that time to make room for?"].waitForExistence(timeout: 4))
        app.buttons.matching(NSPredicate(format: "label == %@", "More creativity")).firstMatch.click()
        app.buttons["Show me how Anchor protects it"].click()

        XCTAssertTrue(app.staticTexts["Turn that time into something concrete."].waitForExistence(timeout: 4))
        app.buttons["Shape these habits"].click()
        XCTAssertTrue(app.staticTexts["Choose when each habit is available."].waitForExistence(timeout: 4))

        let monday = app.buttons["Monday"]
        XCTAssertTrue(monday.waitForExistence(timeout: 2))
        XCTAssertEqual(monday.value as? String, "Selected")
        monday.click()
        XCTAssertEqual(monday.value as? String, "Not selected")

        app.buttons["Save habits and continue"].click()

        XCTAssertTrue(app.staticTexts["One account for your Significant Hobbies."].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["anchor.hub.sign-in-apple"].exists)
        XCTAssertTrue(app.buttons["anchor.hub.sign-in-google"].exists)
        app.buttons["anchor.onboarding.hub-continue-locally"].click()

        XCTAssertTrue(app.staticTexts["Protect one thing."].waitForExistence(timeout: 4))

        let goal = app.textFields.firstMatch
        XCTAssertTrue(goal.waitForExistence(timeout: 2))
        goal.click()
        goal.typeKey("a", modifierFlags: .command)
        goal.typeKey(.delete, modifierFlags: [])
        goal.typeText("Draft the launch note")
        app.buttons["Try the park-and-return loop"].click()

        XCTAssertTrue(app.staticTexts["Draft the launch note"].waitForExistence(timeout: 4))
        XCTAssertTrue(
            app.staticTexts["anchor.onboarding.platform-guidance"]
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

        XCTAssertTrue(app.staticTexts["Plan the day. Learn what moved it."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Return to Anchor"].exists)
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

        let google = app.buttons["anchor.hub.sign-in-google"]
        XCTAssertTrue(google.waitForExistence(timeout: 5))
        google.click()
        XCTAssertTrue(
            app.activityIndicators["anchor.hub.sign-in-google"]
                .waitForExistence(timeout: 3)
        )
        // The AuthenticationServices sheet is remote-hosted inside Anchor's
        // accessibility tree. Prefer its explicit Cancel action; Escape is the
        // keyboard fallback when the host does not expose that action.
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.waitForExistence(timeout: 5) {
            cancel.click()
        } else {
            app.typeKey(.escape, modifierFlags: [])
        }

        XCTAssertTrue(google.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["One account for your Significant Hobbies."].exists)
        XCTAssertEqual(app.state, .runningForeground)
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

        app.buttons["Settings"].click()

        XCTAssertTrue(app.staticTexts["Significant Hobbies Hub"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Bring Anchor into your Hub"].exists)
        XCTAssertTrue(app.radioButtons["System"].exists)
        XCTAssertTrue(app.radioButtons["Light"].exists)
        XCTAssertTrue(app.radioButtons["Dark"].exists)
        app.radioButtons["Dark"].click()
        XCTAssertTrue(
            app.staticTexts["Uses the charcoal focus canvas on this device."]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.staticTexts["This build stores appearance on this device only"].exists)
        XCTAssertFalse(app.staticTexts["Talk to your data"].exists)
        XCTAssertTrue(app.staticTexts["Local library"].exists)
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
                format: "label CONTAINS %@ OR value CONTAINS %@",
                text,
                text
            )
        ).firstMatch
    }
}
