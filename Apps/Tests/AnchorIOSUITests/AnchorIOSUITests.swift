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
        app.tabBars.buttons["Parked"].tap()
        XCTAssertTrue(app.staticTexts["Check the build status"].waitForExistence(timeout: 3))
    }

    func testInterruptionFirstOnboardingStartsARealSession() {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_STORE_PATH"] = "/tmp/anchor-onboarding-ui-\(UUID().uuidString).store"
        app.launchEnvironment["ANCHOR_ONBOARDING_DEMO"] = "1"
        app.launch()

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

        XCTAssertTrue(app.staticTexts["Attention recovered."].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["The practice interruption was discarded. Your real captures stay local and appear in Parked."].exists)
        app.buttons["Begin real focus"].tap()

        XCTAssertTrue(app.staticTexts["Draft the launch note"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Lock a distraction"].exists)
    }

    func testSettingsKeepsMacOnlyDiagnosticsOffIPhone() {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_STORE_PATH"] = "/tmp/anchor-settings-ui-\(UUID().uuidString).store"
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launch()

        app.tabBars.buttons["Settings"].tap()

        XCTAssertTrue(app.staticTexts["Significant Hobbies Hub"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.staticTexts["Talk to your data"].exists)
        XCTAssertFalse(app.staticTexts["Database"].exists)
    }
}
