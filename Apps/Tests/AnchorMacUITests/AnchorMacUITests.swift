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
        XCTAssertTrue(
            app.descendants(matching: .any).matching(NSPredicate(format: "value CONTAINS %@", "1 untimed"))
                .firstMatch.waitForExistence(timeout: 3)
        )

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
    func testUsualWeekAndHabitMaterialiseAndPersist() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] = isolatedStore(named: "usual-week")
        app.launch()

        app.buttons["Today"].click()
        let setup = app.buttons["Set up usual week"]
        XCTAssertTrue(setup.waitForExistence(timeout: 5))
        setup.click()
        XCTAssertTrue(app.staticTexts["Your usual week"].waitForExistence(timeout: 3))
        let addRoutine = app.buttons["Add usual-week item"]
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
        XCTAssertTrue(app.staticTexts["Habits in practice"].waitForExistence(timeout: 4))
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
        XCTAssertTrue(element(containing: "Focused", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Completed", in: app).exists)

        let export = element(containing: "Export", in: app)
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
        miniTimer.buttons["Nothing — just a break"].click()
        miniTimer.buttons["End"].click()
        XCTAssertTrue(miniTimer.staticTexts["Set your anchor"].waitForExistence(timeout: 3))
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
        app.buttons["Schedule these habits"].click()
        XCTAssertTrue(app.staticTexts["Give each habit a real place."].waitForExistence(timeout: 4))

        let monday = app.buttons["Monday"]
        XCTAssertTrue(monday.waitForExistence(timeout: 2))
        XCTAssertEqual(monday.value as? String, "Selected")
        monday.click()
        XCTAssertEqual(monday.value as? String, "Not selected")

        app.buttons["Save week and continue"].click()

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
