import XCTest

@MainActor
final class AnchorIOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFocusInterruptionAndReturnJourneyPersists() {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_STORE_PATH"] = "/tmp/anchor-ui-\(UUID().uuidString).store"
        app.launch()

        let intention = app.textFields["Ship the auth flow"]
        XCTAssertTrue(intention.waitForExistence(timeout: 5))
        intention.tap()
        intention.typeText("Finish the release")
        app.buttons["Done"].tap()
        let start = app.buttons["Start focusing"]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        start.tap()
        XCTAssertTrue(app.staticTexts["Finish the release"].waitForExistence(timeout: 4))

        let capture = app.buttons["Lock a distraction"]
        XCTAssertTrue(capture.waitForExistence(timeout: 3))
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
        app.buttons["Resume"].tap()
        let decline = app.buttons["Nothing — just a break"]
        XCTAssertTrue(decline.waitForExistence(timeout: 3))
        decline.tap()

        app.buttons["End session"].tap()
        app.tabBars.buttons["Parked"].tap()
        XCTAssertTrue(app.staticTexts["Check the build status"].waitForExistence(timeout: 3))
    }
}
