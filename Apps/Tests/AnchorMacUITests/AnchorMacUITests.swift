import XCTest

final class AnchorMacUITests: XCTestCase {
    @MainActor
    func testInterruptionFirstOnboardingUsesMacGuidance() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_DEMO"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] =
            FileManager.default.temporaryDirectory
                .appendingPathComponent("anchor-mac-onboarding-\(UUID().uuidString).store")
                .path
        app.launch()

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
    func testSettingsKeepsLocalMCPSetupOnMac() throws {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launchEnvironment["ANCHOR_STORE_PATH"] =
            FileManager.default.temporaryDirectory
                .appendingPathComponent("anchor-mac-settings-\(UUID().uuidString).store")
                .path
        app.launch()

        app.buttons["Settings"].click()

        XCTAssertTrue(app.staticTexts["Significant Hobbies Hub"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Talk to your data"].exists)
        XCTAssertTrue(app.staticTexts["Database"].exists)
    }
}
