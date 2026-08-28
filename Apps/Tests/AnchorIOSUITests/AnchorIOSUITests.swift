import XCTest

@MainActor
final class AnchorIOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFocusInterruptionAndReturnJourneyPersists() {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_STORE_PATH"] = "/tmp/anchor-ui-\(UUID().uuidString).store"
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launch()

        app.tabBars.buttons["Focus"].tap()
        let adHoc = app.buttons["anchor.focus.start-unplanned"]
        XCTAssertTrue(adHoc.waitForExistence(timeout: 5))
        adHoc.tap()
        let intention = app.textFields["Ship the auth flow"]
        XCTAssertTrue(intention.waitForExistence(timeout: 5))
        intention.tap()
        intention.typeText("Finish the release")
        app.buttons["Done"].tap()
        let start = app.buttons["Start focusing"]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists)
        XCTAssertTrue(start.isHittable)
        XCTAssertLessThanOrEqual(start.frame.maxY, tabBar.frame.minY - 8)
        start.tap()
        XCTAssertTrue(app.staticTexts["Finish the release"].waitForExistence(timeout: 4))

        let capture = app.buttons["Lock a distraction"]
        XCTAssertTrue(capture.waitForExistence(timeout: 3))
        XCTAssertTrue(capture.isHittable)
        XCTAssertLessThanOrEqual(capture.frame.maxY, tabBar.frame.minY - 8)
        capture.tap()

        let note = app.textFields["Slack from Ravi about the invoice"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.tap()
        note.typeText("Check the build status")
        app.buttons["Done"].tap()
        app.buttons["Park it — back to work"].tap()

        let backToWork = app.buttons["Back to work"]
        XCTAssertTrue(backToWork.waitForExistence(timeout: 3))
        backToWork.tap()
        XCTAssertTrue(app.staticTexts["Check the build status"].waitForExistence(timeout: 3))

        app.buttons["Pause"].tap()
        let resume = app.buttons["Resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 3))
        resume.tap()
        let decline = app.buttons["Nothing — just a break"]
        XCTAssertTrue(decline.waitForExistence(timeout: 3))
        decline.tap()

        app.buttons["End session"].tap()
        app.tabBars.buttons["History"].tap()
        app.buttons["Interruptions"].tap()
        XCTAssertTrue(app.staticTexts["Check the build status"].waitForExistence(timeout: 3))
    }

    func testInterruptionFirstOnboardingStartsARealSession() {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_STORE_PATH"] = "/tmp/anchor-onboarding-ui-\(UUID().uuidString).store"
        app.launchEnvironment["ANCHOR_ONBOARDING_DEMO"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["Plan the day. Learn what moved it."].waitForExistence(timeout: 5))
        app.buttons["Choose what to protect"].tap()
        XCTAssertTrue(app.staticTexts["What tends to take more time than you want?"].waitForExistence(timeout: 4))
        app.buttons.matching(NSPredicate(format: "label == %@", "Short videos")).firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Continue with")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["What do you want that time to make room for?"].waitForExistence(timeout: 4))
        app.buttons.matching(NSPredicate(format: "label == %@", "More creativity")).firstMatch.tap()
        app.buttons["Show me how Anchor protects it"].tap()

        XCTAssertTrue(app.staticTexts["Turn that time into something concrete."].waitForExistence(timeout: 4))
        app.buttons["Schedule these habits"].tap()
        XCTAssertTrue(app.staticTexts["Give each habit a real place."].waitForExistence(timeout: 4))
        app.buttons["Save week and continue"].tap()

        XCTAssertTrue(app.staticTexts["One account for your Significant Hobbies."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["anchor.hub.sign-in-apple"].exists)
        XCTAssertTrue(app.buttons["anchor.hub.sign-in-google"].exists)
        app.buttons["anchor.onboarding.hub-continue-locally"].tap()

        XCTAssertTrue(app.staticTexts["Protect one thing."].waitForExistence(timeout: 5))
        let goal = app.textFields["Finish the release"]
        goal.tap()
        goal.typeText("Draft the launch note")
        app.buttons["Done"].tap()
        app.buttons["Try the park-and-return loop"].tap()

        XCTAssertTrue(app.staticTexts["Draft the launch note"].waitForExistence(timeout: 4))
        app.buttons["Something pulled me"].tap()
        let thought = app.textFields["Check the build status"]
        thought.tap()
        thought.typeText("Read the incoming message")
        app.buttons["Done"].tap()
        app.buttons["Park it — return to focus"].tap()

        XCTAssertTrue(app.staticTexts["Thought parked."].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["The practice interruption was discarded. Your real captures stay local and appear in History."].exists)
        app.buttons["Open my Focus"].tap()

        XCTAssertTrue(app.staticTexts["Make something"].waitForExistence(timeout: 4))
        app.buttons["Start this block"].tap()
        XCTAssertTrue(app.buttons["Lock a distraction"].waitForExistence(timeout: 4))
        app.buttons["End session"].tap()
    }

    func testDayPlanCreatesABlockAndOffersRecurringSchedule() {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_STORE_PATH"] = "/tmp/anchor-plan-ui-\(UUID().uuidString).store"
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launch()

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["Give the day one anchor"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.datePickers.count, 0, "Today must not browse other dates; History owns that.")
        app.buttons["Add the first block"].tap()
        let title = app.textFields["What will you do?"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.tap()
        title.typeText("Morning walk")
        XCTAssertTrue(app.switches["Repeat weekly"].exists)
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["Morning walk"].waitForExistence(timeout: 4))
    }

    func testBehaviorProfileSavesImmediatelyAndPersists() {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_STORE_PATH"] = "/tmp/anchor-profile-ui-\(UUID().uuidString).store"
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launch()

        app.tabBars.buttons["Habits"].tap()
        let editor = app.buttons["anchor.habits.behavior-profile"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()

        let shortVideos = app.buttons["Short videos"]
        XCTAssertTrue(shortVideos.waitForExistence(timeout: 4))
        shortVideos.tap()
        XCTAssertTrue(app.staticTexts["anchor.profile.saved"].waitForExistence(timeout: 3))

        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "anchor-ios-patterns-saved"
        evidence.lifetime = .keepAlways
        add(evidence)

        app.buttons["Done"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.value as? String, "1 pattern · 0 directions")

        app.terminate()
        app.launch()
        app.tabBars.buttons["Habits"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 4))
        XCTAssertEqual(editor.value as? String, "1 pattern · 0 directions")
    }

    func testSettingsKeepsMacOnlyDiagnosticsOffIPhone() {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_STORE_PATH"] = "/tmp/anchor-settings-ui-\(UUID().uuidString).store"
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launch()

        for tab in ["Today", "Habits", "History", "Focus"] {
            app.tabBars.buttons[tab].tap()
            let toolbarButton = app.buttons["anchor.toolbar.settings"]
            XCTAssertTrue(toolbarButton.waitForExistence(timeout: 3), "Settings toolbar action is missing on \(tab)")
            XCTAssertTrue(toolbarButton.isHittable, "Settings toolbar action is not reachable on \(tab)")
        }

        let settingsButton = app.buttons["anchor.toolbar.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 4))
        XCTAssertTrue(settingsButton.isHittable)
        settingsButton.tap()

        XCTAssertTrue(app.staticTexts["Significant Hobbies Hub"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Bring Anchor into your Hub"].exists)
        XCTAssertTrue(app.buttons["anchor.hub.sign-in-apple"].exists)
        let appearance = app.segmentedControls["anchor.settings.appearance"]
        XCTAssertTrue(appearance.exists)
        appearance.buttons["Dark"].tap()
        XCTAssertTrue(
            app.staticTexts["Uses the charcoal focus canvas on this device."]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.staticTexts["This build stores appearance on this device only"].exists)
        XCTAssertFalse(app.staticTexts["Talk to your data"].exists)
        XCTAssertFalse(app.staticTexts["Database"].exists)
    }
}
