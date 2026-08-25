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
        XCTAssertTrue(app.staticTexts["Talk to your data"].exists)
        XCTAssertTrue(app.staticTexts["Database"].exists)
    }
}
