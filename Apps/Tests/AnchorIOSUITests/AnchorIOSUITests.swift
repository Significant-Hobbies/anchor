import XCTest

@MainActor
final class AnchorIOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDayCanBeCopiedWithoutReplacingTheOriginal() {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_STORE_PATH"] = "/tmp/anchor-copy-day-\(UUID().uuidString).store"
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launch()
        app.tabBars.buttons.ci("Today").tap()
        let add = app.buttons.ci("Add the first entry")
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let title = app.textFields.ci("What will you do?")
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        // The editor can exist while its presentation is still settling.
        let titleReady = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in title.isHittable }, object: nil
        )
        guard XCTWaiter.wait(for: [titleReady], timeout: 5) == .completed else {
            XCTFail("The entry title must become hittable before typing")
            return
        }
        title.tap()
        guard app.keyboards.firstMatch.waitForExistence(timeout: 5) else {
            XCTFail("Tapping the entry title must open the keyboard before typing")
            return
        }
        title.typeText("Read the next chapter")
        let enteredTitle = app.textFields.matching(
            NSPredicate(format: "value == %@", "Read the next chapter")
        ).firstMatch
        XCTAssertTrue(enteredTitle.waitForExistence(timeout: 3),
                      "The entry title must contain the intended text before saving")
        app.buttons.ci("Save").tap()
        XCTAssertTrue(app.staticTexts.ci("Read the next chapter").waitForExistence(timeout: 4))
        app.buttons.ci("anchor.today.copy-day").tap()
        XCTAssertTrue(app.buttons.ci("Copy entries").waitForExistence(timeout: 3))
        app.buttons.ci("Copy entries").tap()
        XCTAssertTrue(app.buttons.ci("Copy entries").waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.ci("Read the next chapter").exists)
        app.buttons.ci("Go to today").tap()
        XCTAssertTrue(app.staticTexts.ci("Read the next chapter").exists)
        app.terminate()
        app.launch()
        app.tabBars.buttons.ci("Today").tap()
        XCTAssertTrue(app.staticTexts.ci("Read the next chapter").waitForExistence(timeout: 4))
        keepScreenshot(app, named: "anchor-simple-day-copy")
    }

    func testFocusInterruptionAndReturnJourneyPersists() {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_STORE_PATH"] = "~/tmp/anchor-ui-\(UUID().uuidString).store"
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launch()

        app.tabBars.buttons.ci("Focus").tap()
        let adHoc = app.buttons.ci("anchor.focus.start-unplanned")
        XCTAssertTrue(adHoc.waitForExistence(timeout: 5))
        adHoc.tap()
        let intention = app.textFields.ci("Ship the auth flow")
        XCTAssertTrue(intention.waitForExistence(timeout: 5))
        intention.tap()
        intention.typeText("Finish the release")
        app.buttons.ci("Done").tap()
        let start = app.buttons.ci("Start focusing")
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists)
        XCTAssertTrue(start.isHittable)
        XCTAssertLessThanOrEqual(start.frame.maxY, tabBar.frame.minY - 8)
        start.tap()
        XCTAssertTrue(app.staticTexts.ci("Finish the release").waitForExistence(timeout: 4))

        let capture = app.buttons.ci("Lock a distraction")
        XCTAssertTrue(capture.waitForExistence(timeout: 3))
        XCTAssertTrue(capture.isHittable)
        XCTAssertLessThanOrEqual(capture.frame.maxY, tabBar.frame.minY - 8)
        capture.tap()

        let note = app.textFields.ci("Slack from Ravi about the invoice")
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.tap()
        note.typeText("Check the build status")
        app.buttons.ci("Done").tap()
        app.buttons.ci("anchor.capture.pause").tap()
        let resume = app.buttons.ci("Resume")
        XCTAssertTrue(resume.waitForExistence(timeout: 3))
        resume.tap()
        let decline = app.buttons.ci("Nothing — just a break")
        XCTAssertTrue(decline.waitForExistence(timeout: 3))
        decline.tap()

        app.buttons.ci("End session").tap()
        app.tabBars.buttons.ci("History").tap()
        app.buttons.ci("Interruptions").tap()
        XCTAssertTrue(app.staticTexts.ci("Check the build status").waitForExistence(timeout: 3))
    }

    func testInterruptionFirstOnboardingStartsARealSession() {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_STORE_PATH"] = "/tmp/anchor-onboarding-ui-\(UUID().uuidString).store"
        app.launchEnvironment["ANCHOR_ONBOARDING_DEMO"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts.ci("Plan the day. Learn what moved it.").waitForExistence(timeout: 5))
        app.buttons.ci("Choose what to protect").tap()
        XCTAssertTrue(app.staticTexts.ci("What tends to take more time than you want?").waitForExistence(timeout: 4))
        app.buttons.matching(NSPredicate(format: "label ==[c] %@", "Short videos")).firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Continue with")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts.ci("What do you want that time to make room for?").waitForExistence(timeout: 4))
        app.buttons.matching(NSPredicate(format: "label ==[c] %@", "More creativity")).firstMatch.tap()
        app.buttons.ci("Show me how Anchor protects it").tap()

        XCTAssertTrue(app.staticTexts.ci("Turn that time into something concrete.").waitForExistence(timeout: 4))
        let shape = app.buttons.ci("Shape these habits")
        shape.tap()
        // A tap that lands while the step transition is still settling can miss
        // the button entirely — retry rather than failing on a swallowed tap.
        let scheduleTitle = app.staticTexts.ci("Choose when each habit is available.")
        if !scheduleTitle.waitForExistence(timeout: 4) {
            let retry = app.buttons.matching(NSPredicate(
                format: "label ==[c] %@ OR label ==[c] %@", "Shape these habits", "Continue without habits"
            )).firstMatch
            retry.tap()
        }
        XCTAssertTrue(scheduleTitle.waitForExistence(timeout: 4))
        app.buttons.ci("Save habits and continue").tap()

        XCTAssertTrue(app.staticTexts.ci("One account for your Significant Hobbies.").waitForExistence(timeout: 5))
        #if ANCHOR_LOCAL_ONLY
        XCTAssertFalse(app.buttons.ci("anchor.hub.sign-in-apple").exists)
        XCTAssertFalse(app.buttons.ci("anchor.hub.sign-in-google").exists)
        XCTAssertTrue(app.descendants(matching: .any)["anchor.hub.unavailable"].exists)
        #else
        XCTAssertTrue(app.buttons.ci("anchor.hub.sign-in-apple").exists)
        XCTAssertTrue(app.buttons.ci("anchor.hub.sign-in-google").exists)
        #endif
        app.buttons.ci("anchor.onboarding.hub-continue-locally").tap()

        XCTAssertTrue(app.staticTexts.ci("Protect one thing.").waitForExistence(timeout: 5))
        let goal = app.textFields.ci("Finish the release")
        goal.tap()
        goal.typeText("Draft the launch note")
        app.buttons.ci("Done").tap()
        app.buttons.ci("Try the park-and-return loop").tap()

        XCTAssertTrue(app.staticTexts.ci("Draft the launch note").waitForExistence(timeout: 4))
        app.buttons.ci("Something pulled me").tap()
        let thought = app.textFields.ci("Check the build status")
        thought.tap()
        thought.typeText("Read the incoming message")
        app.buttons.ci("Done").tap()
        app.buttons.ci("Park it — return to focus").tap()

        XCTAssertTrue(app.staticTexts.ci("Thought parked.").waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts.ci("The practice interruption was discarded. Your real captures stay local and appear in History.").exists)
        let openFocus = app.buttons.ci("Open my Focus")
        XCTAssertTrue(openFocus.waitForExistence(timeout: 4))
        app.swipeUp()
        XCTAssertTrue(openFocus.isHittable)
        openFocus.tap()
        let focusTab = app.tabBars.buttons.ci("Focus")
        XCTAssertTrue(focusTab.waitForExistence(timeout: 5))
        let startScheduled = app.buttons.ci("Start this block")
        if startScheduled.waitForExistence(timeout: 2) {
            startScheduled.tap()
        } else {
            let startUnplanned = app.buttons.ci("anchor.focus.start-unplanned")
            XCTAssertTrue(startUnplanned.waitForExistence(timeout: 4))
            startUnplanned.tap()
            let realGoal = app.textFields.ci("Ship the auth flow")
            XCTAssertTrue(realGoal.waitForExistence(timeout: 3))
            realGoal.tap()
            realGoal.typeText("Draft the launch note")
            XCTAssertTrue(app.keyboards.firstMatch.exists)
            let start = app.buttons.ci("Start focusing")
            XCTAssertTrue(start.isHittable, "Starting must remain reachable while the keyboard is open")
            start.tap()
        }
        XCTAssertTrue(app.buttons.ci("Lock a distraction").waitForExistence(timeout: 4))
        app.buttons.ci("End session").tap()
    }

    func testDayPlanCreatesABlockAndOffersRecurringSchedule() {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_STORE_PATH"] = "/tmp/anchor-plan-ui-\(UUID().uuidString).store"
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launch()

        app.tabBars.buttons.ci("Today").tap()
        XCTAssertTrue(app.staticTexts.ci("Give the day one anchor").waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.datePickers.count, 0, "The schedule must allow choosing a day.")
        app.buttons.ci("Add the first entry").tap()
        let title = app.textFields.ci("What will you do?")
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.tap()
        title.typeText("Morning walk")
        XCTAssertTrue(app.switches.ci("Repeat weekly").exists)
        app.buttons.ci("Save").tap()

        XCTAssertTrue(app.staticTexts.ci("Morning walk").waitForExistence(timeout: 4))
    }

    func testTodayCompactControlsRemainReadableAndReachableOnPhone() {
        verifyTodayCompactControls()
    }

    func testTodayCompactControlsRemainReadableAndReachableOnPhone390() {
        verifyTodayCompactControls(expectedWidth: 390)
    }

    func testTodayLongLabelsEmptyDayOnPhone390() throws {
        let app = makeTodayVariantApp()
        defer { app.terminate() }
        launchTodayVariant(app, doublesLabels: true)
        let controls = verifyTodayLongLabelControls(app, copyEnabled: false)
        try keepTodayVariantEvidence(app, controls: controls, scenario: "empty-day",
                                    testCase: "testTodayLongLabelsEmptyDayOnPhone390",
                                    copyEnabled: false)

        controls[1].tap()
        let logTitle = app.descendants(matching: .any)["anchor.log.title"]
        XCTAssertTrue(logTitle.waitForExistence(timeout: 5),
                      "The enabled Log time control must open its real editor")
        let cancel = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Cancel")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.tap()
        XCTAssertTrue(logTitle.waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.buttons.ci("anchor.today.copy-day").isEnabled,
                       "Cancelling an empty log must leave Copy day disabled")
    }

    func testTodayLongLabelsEnabledDayOnPhone390() throws {
        let app = makeTodayVariantApp()
        defer { app.terminate() }
        // Seed through the existing editor, then stress the same stored entry
        // under pseudolocalization. No production fixture or UI hook is needed.
        launchTodayVariant(app, doublesLabels: false)
        let add = app.buttons.ci("Add the first entry")
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let title = app.textFields.ci("What will you do?")
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        let titleReady = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in title.isHittable }, object: nil
        )
        guard XCTWaiter.wait(for: [titleReady], timeout: 5) == .completed else {
            XCTFail("The synthetic entry editor must become hittable before typing")
            return
        }
        title.tap()
        guard app.keyboards.firstMatch.waitForExistence(timeout: 5) else {
            XCTFail("The synthetic entry title must have keyboard focus before typing")
            return
        }
        let entryTitle = "Read the next chapter"
        title.typeText(entryTitle)
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", entryTitle))
            .firstMatch.waitForExistence(timeout: 3))
        app.buttons.ci("Save").tap()
        XCTAssertTrue(app.staticTexts.ci(entryTitle).waitForExistence(timeout: 4))

        app.terminate()
        launchTodayVariant(app, doublesLabels: true)
        let controls = verifyTodayLongLabelControls(app, copyEnabled: true)
        try keepTodayVariantEvidence(app, controls: controls, scenario: "enabled-day",
                                    testCase: "testTodayLongLabelsEnabledDayOnPhone390",
                                    copyEnabled: true)
        controls[0].tap()
        let sheet = app.navigationBars.ci("Copy day Copy day")
        let copyEntries = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Copy entries")).firstMatch
        let cancel = sheet.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Cancel")).firstMatch
        let more = sheet.buttons.ci("OverflowBarButtonItem")
        func nativeOverflowIsReady() -> Bool {
            guard more.waitForExistence(timeout: 3), more.isEnabled, more.isHittable else {
                XCTFail("The native Copy day overflow must be visible and tappable")
                return false
            }
            guard more.label.lowercased() == "more more" else {
                XCTFail("The native overflow must show the actual doubled More label: \(more.label)")
                return false
            }
            return true
        }
        guard sheet.waitForExistence(timeout: 3), cancel.waitForExistence(timeout: 3),
              cancel.isEnabled, cancel.isHittable else {
            XCTFail("Copy day must open its real sheet with a reachable Cancel action")
            return
        }
        let visibleAction: XCUIElement
        if copyEntries.exists {
            guard copyEntries.isEnabled, copyEntries.isHittable else {
                XCTFail("The direct Copy entries action must be enabled and tappable")
                return
            }
            visibleAction = copyEntries
        } else {
            guard nativeOverflowIsReady() else { return }
            visibleAction = more
        }
        // Keep the actual visible toolbar before opening a menu, so cancellation
        // exercises the sheet rather than a Cancel action covered by that menu.
        try keepTodayVariantEvidence(app, controls: [cancel, visibleAction], scenario: "copy-sheet",
                                    testCase: "testTodayLongLabelsEnabledDayOnPhone390",
                                    copyEnabled: true)
        cancel.tap()
        guard sheet.waitForNonExistence(timeout: 3) else {
            XCTFail("Cancel must dismiss the Copy day sheet")
            return
        }
        XCTAssertTrue(app.staticTexts.ci(entryTitle).exists,
                      "Cancelling Copy day must preserve the original entry")

        let reopenedControls = verifyTodayLongLabelControls(app, copyEnabled: true)
        reopenedControls[0].tap()
        guard sheet.waitForExistence(timeout: 3), cancel.waitForExistence(timeout: 3),
              cancel.isEnabled, cancel.isHittable else {
            XCTFail("Copy day must reopen its real sheet with a reachable Cancel action")
            return
        }
        if !copyEntries.exists {
            guard nativeOverflowIsReady() else { return }
            more.tap()
        }
        guard copyEntries.waitForExistence(timeout: 3),
              copyEntries.label.lowercased().components(separatedBy: "copy entries").count - 1 == 2,
              copyEntries.isEnabled, copyEntries.isHittable else {
            XCTFail("The actual doubled Copy entries action must be enabled and tappable")
            return
        }
        copyEntries.tap()
        guard sheet.waitForNonExistence(timeout: 3) else {
            XCTFail("Copy entries must complete and dismiss its sheet")
            return
        }
        XCTAssertTrue(app.staticTexts.ci(entryTitle).waitForExistence(timeout: 4),
                      "The destination day must contain the copied entry")
        let goToToday = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Go to today")).firstMatch
        XCTAssertTrue(goToToday.waitForExistence(timeout: 3))
        goToToday.tap()
        XCTAssertTrue(app.staticTexts.ci(entryTitle).waitForExistence(timeout: 4),
                      "Copying must also preserve the original day")
    }

    private func makeTodayVariantApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_STORE_PATH"] = "/tmp/anchor-today-variant-\(UUID().uuidString).store"
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        return app
    }

    private func launchTodayVariant(_ app: XCUIApplication, doublesLabels: Bool) {
        app.launchArguments = ["-NSDoubleLocalizedStrings", doublesLabels ? "YES" : "NO"]
        app.launch()
        XCTAssertEqual(app.frame.width, 390, accuracy: 0.5,
                       "Variant qualification must use an actual 390-point app")
        let today = app.tabBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Today")).firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        today.tap()
    }

    private func verifyTodayLongLabelControls(_ app: XCUIApplication, copyEnabled: Bool) -> [XCUIElement] {
        let controls = [app.buttons.ci("anchor.today.copy-day"),
                        app.buttons.ci("anchor.today.log-time"),
                        app.buttons.ci("anchor.today.customize")]
        for control in controls {
            XCTAssertTrue(control.waitForExistence(timeout: 5))
        }
        // Populated Today deliberately scrolls to the current timetable position.
        // Navigate back to its actions before qualifying their visible layout;
        // this does not assert that the default populated viewport shows them.
        for _ in 0..<8 {
            let viewport = app.frame
            let controlsAreVisible = controls.allSatisfy { control in
                control.frame.minX >= viewport.minX - 0.5 &&
                control.frame.maxX <= viewport.maxX + 0.5 &&
                control.frame.minY >= viewport.minY - 0.5 &&
                control.frame.maxY <= viewport.maxY + 0.5
            }
            let enabledControls = copyEnabled ? controls : Array(controls.dropFirst())
            if controlsAreVisible && enabledControls.allSatisfy({ $0.isHittable }) { break }
            app.swipeDown()
        }
        for (control, baseline) in zip(controls, ["Copy day", "Log time", "Customize"]) {
            XCTAssertEqual(control.label.lowercased().components(separatedBy: baseline.lowercased()).count - 1, 2,
                           "Pseudolocalization must actually double \(baseline); baseline English is not variant evidence")
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
            XCTAssertGreaterThanOrEqual(control.frame.minX, app.frame.minX - 0.5)
            XCTAssertLessThanOrEqual(control.frame.maxX, app.frame.maxX + 0.5)
            XCTAssertGreaterThanOrEqual(control.frame.minY, app.frame.minY - 0.5)
            XCTAssertLessThanOrEqual(control.frame.maxY, app.frame.maxY + 0.5)
        }
        XCTAssertEqual(controls[0].isEnabled, copyEnabled)
        for control in copyEnabled ? controls : Array(controls.dropFirst()) {
            XCTAssertTrue(control.isEnabled)
            XCTAssertTrue(control.isHittable)
        }
        XCTAssertLessThanOrEqual(controls[0].frame.maxX, controls[1].frame.minX + 0.5,
                                 "The first-row actions must not overlap")
        XCTAssertGreaterThanOrEqual(controls[2].frame.minY,
                                    max(controls[0].frame.maxY, controls[1].frame.maxY) - 0.5,
                                    "Customize must remain below both first-row actions")
        return controls
    }

    private func keepTodayVariantEvidence(_ app: XCUIApplication, controls: [XCUIElement],
                                         scenario: String, testCase: String, copyEnabled: Bool) throws {
        let screenshot = app.screenshot()
        let name = "anchor-r3-390-\(scenario)"
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        // Keep reviewable PNGs from these exact tested states alongside the
        // XCResult attachments, without a raw xcresult export command.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("anchor-r3-390-evidence", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try screenshot.pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"))
        let metadata: [String: Any] = [
            "testCase": testCase, "scenario": scenario, "logicalWidth": app.frame.width,
            "simulatorId": ProcessInfo.processInfo.environment["SIMULATOR_UDID"] ?? "",
            "copyEnabled": copyEnabled, "imageName": name + ".png",
            "controls": controls.map { control -> [String: Any] in
                ["identifier": control.identifier, "label": control.label,
                 "isEnabled": control.isEnabled, "isHittable": control.isHittable,
                 "frame": ["x": control.frame.minX, "y": control.frame.minY,
                           "width": control.frame.width, "height": control.frame.height]]
            },
        ]
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent(name + ".json"))
    }

    private func verifyTodayCompactControls(expectedWidth: CGFloat? = nil) {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_STORE_PATH"] = "/tmp/anchor-today-compact-\(UUID().uuidString).store"
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launch()

        if let expectedWidth {
            XCTAssertEqual(app.frame.width, expectedWidth, accuracy: 0.5,
                           "Qualification must use an actual 390-point app surface")
        }

        let todayTab = app.tabBars.buttons.ci("Today")
        XCTAssertTrue(todayTab.waitForExistence(timeout: 5))
        todayTab.tap()

        let controls = [
            app.buttons.ci("anchor.today.copy-day"),
            app.buttons.ci("anchor.today.log-time"),
            app.buttons.ci("anchor.today.customize"),
        ]
        let expectedLabels = ["Copy day", "Log time", "Customize"]
        for (control, expectedLabel) in zip(controls, expectedLabels) {
            XCTAssertTrue(control.waitForExistence(timeout: 5), "Expected Today control \(control.identifier) to be present")
            XCTAssertEqual(control.label.lowercased(), expectedLabel.lowercased(), "The control should retain its clear accessible label")
            XCTAssertTrue(control.isHittable, "Today control \(control.identifier) must be reachable")
            XCTAssertGreaterThanOrEqual(control.frame.width, 44, "Today control \(control.identifier) needs a 44pt hit width")
            XCTAssertGreaterThanOrEqual(control.frame.height, 44, "Today control \(control.identifier) needs a 44pt hit height")
        }

        let customize = controls[2]
        XCTAssertGreaterThanOrEqual(customize.frame.minY, controls[0].frame.maxY - 1,
                                    "Customize should occupy the second compact row")

        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = expectedWidth == nil
            ? "anchor-today-compact-phone-controls"
            : "anchor-today-compact-phone-controls-390"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    func testBehaviorProfileSavesImmediatelyAndPersists() {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_STORE_PATH"] = "/tmp/anchor-profile-ui-\(UUID().uuidString).store"
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launch()

        let habits = app.tabBars.buttons.ci("Habits")
        XCTAssertTrue(habits.waitForExistence(timeout: 5))
        habits.tap()
        let editor = app.buttons.ci("anchor.habits.behavior-profile")
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()

        let shortVideos = app.buttons.ci("Short videos")
        XCTAssertTrue(shortVideos.waitForExistence(timeout: 4))
        shortVideos.tap()
        XCTAssertTrue(app.staticTexts.ci("anchor.profile.saved").waitForExistence(timeout: 3))

        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "anchor-ios-patterns-saved"
        evidence.lifetime = .keepAlways
        add(evidence)

        app.buttons.ci("Done").tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.value as? String, "1 pattern · 0 directions")

        app.terminate()
        app.launch()
        let reloadedHabits = app.tabBars.buttons.ci("Habits")
        XCTAssertTrue(reloadedHabits.waitForExistence(timeout: 5))
        reloadedHabits.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 4))
        XCTAssertEqual(editor.value as? String, "1 pattern · 0 directions")
    }

    @MainActor
    func testHabitsCanBeAddedEditedAndRescheduled() {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_STORE_PATH"] = "/tmp/anchor-habit-management-\(UUID().uuidString).store"
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launch()

        let habits = app.tabBars.buttons.ci("Habits")
        XCTAssertTrue(habits.waitForExistence(timeout: 5))
        habits.tap()
        XCTAssertTrue(app.buttons.ci("anchor.habits.add").waitForExistence(timeout: 5))
        app.buttons.ci("anchor.habits.add").tap()
        // Pick the second day before typing — once the keyboard is up it can
        // cover the weekday chips and swallow the tap.
        let secondDay = app.buttons.matching(
            NSPredicate(format: "label ENDSWITH[c] %@", "not selected")
        ).firstMatch
        XCTAssertTrue(secondDay.waitForExistence(timeout: 3))
        let secondDayName = secondDay.label.replacingOccurrences(of: " not selected", with: "")
        secondDay.tap()
        XCTAssertTrue(app.buttons.ci("\(secondDayName) selected").waitForExistence(timeout: 3))
        let title = app.textFields.ci("What will you do?")
        title.tap()
        title.typeText("Two-day reset")
        app.buttons.ci("Save").tap()
        XCTAssertTrue(app.staticTexts.ci("Two-day reset").waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts.ci("0 of 2 this week").exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Any time")).firstMatch.exists)
        let checkOff = app.buttons.ci("anchor.habits.complete")
        XCTAssertTrue(checkOff.exists)
        checkOff.tap()
        XCTAssertTrue(app.buttons.ci("Undo check-off").waitForExistence(timeout: 3))
        app.terminate()
        app.launch()
        app.tabBars.buttons.ci("Habits").tap()
        XCTAssertTrue(app.buttons.ci("Undo check-off").waitForExistence(timeout: 4))
        app.buttons.ci("Undo check-off").tap()
        XCTAssertTrue(app.buttons.ci("anchor.habits.complete").exists)


        // Habits live on the Habits tab; Today only gains one when it's
        // scheduled at a time, which places it on the timetable.
        app.tabBars.buttons.ci("Today").tap()
        XCTAssertFalse(app.descendants(matching: .any)["anchor.today.habits"].exists)

        app.tabBars.buttons.ci("Habits").tap()
        app.buttons.ci("Schedule").tap()
        XCTAssertTrue(app.navigationBars.ci("Place habit").waitForExistence(timeout: 3))
        app.buttons.ci("Save").tap()

        app.tabBars.buttons.ci("Today").tap()
        XCTAssertTrue(app.staticTexts.ci("Two-day reset").waitForExistence(timeout: 4))

        keepScreenshot(app, named: "anchor-build19-ios-scheduled-habit-today")

    }

    @MainActor
    func testProjectsAndTagsCanBeManaged() {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_STORE_PATH"] = "/tmp/anchor-metadata-library-\(UUID().uuidString).store"
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launch()

        app.buttons.ci("anchor.toolbar.settings").tap()
        let manage = app.buttons.ci("anchor.settings.manage-metadata")
        for _ in 0..<8 {
            if manage.exists && manage.isHittable { break }
            app.swipeUp()
        }
        guard manage.exists && manage.isHittable else {
            XCTFail("Manage projects and tags must be visible and tappable")
            return
        }
        manage.tap()

        let project = app.textFields.ci("anchor.metadata.new-project")
        guard project.waitForExistence(timeout: 5) else {
            XCTFail("Manage projects and tags did not open its editor")
            return
        }
        let projectReady = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in project.isHittable }, object: nil
        )
        guard XCTWaiter.wait(for: [projectReady], timeout: 5) == .completed else {
            XCTFail("The new project field must become hittable before typing")
            return
        }
        project.tap()
        guard app.keyboards.firstMatch.waitForExistence(timeout: 5) else {
            XCTFail("The new project field must have keyboard focus before typing")
            return
        }
        project.typeText("Launch\n")
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "Launch")).firstMatch.waitForExistence(timeout: 3))
        let tag = app.textFields.ci("anchor.metadata.new-tag")
        guard tag.waitForExistence(timeout: 5) else {
            XCTFail("The new tag field must exist before typing")
            return
        }
        let tagReady = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in tag.isHittable }, object: nil
        )
        guard XCTWaiter.wait(for: [tagReady], timeout: 5) == .completed else {
            XCTFail("The new tag field must become hittable before typing")
            return
        }
        tag.tap()
        guard app.keyboards.firstMatch.waitForExistence(timeout: 5) else {
            XCTFail("The new tag field must have keyboard focus before typing")
            return
        }
        tag.typeText("Deep work\n")

        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "Launch")).firstMatch.exists)
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "Deep work")).firstMatch.waitForExistence(timeout: 3))

        keepScreenshot(app, named: "anchor-build19-ios-projects-tags")
    }

    func testSettingsKeepsMacOnlyDiagnosticsOffIPhone() {
        let app = XCUIApplication()
        app.launchEnvironment["ANCHOR_STORE_PATH"] = "/tmp/anchor-settings-ui-\(UUID().uuidString).store"
        app.launchEnvironment["ANCHOR_ONBOARDING_SKIP"] = "1"
        app.launch()

        for tab in ["Today", "Habits", "History", "Focus"] {
            app.tabBars.buttons.ci(tab).tap()
            let toolbarButton = app.buttons.ci("anchor.toolbar.settings")
            XCTAssertTrue(toolbarButton.waitForExistence(timeout: 3), "Settings toolbar action is missing on \(tab)")
            XCTAssertTrue(toolbarButton.isHittable, "Settings toolbar action is not reachable on \(tab)")
        }

        let settingsButton = app.buttons.ci("anchor.toolbar.settings")
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 4))
        XCTAssertTrue(settingsButton.isHittable)
        settingsButton.tap()

        XCTAssertTrue(app.staticTexts.ci("Significant Hobbies Hub").waitForExistence(timeout: 4))
        #if ANCHOR_LOCAL_ONLY
        XCTAssertTrue(app.descendants(matching: .any)["anchor.hub.unavailable"].exists)
        XCTAssertFalse(app.buttons.ci("anchor.hub.sign-in-apple").exists)
        XCTAssertFalse(app.buttons.ci("anchor.hub.sign-in-google").exists)
        #else
        XCTAssertTrue(app.staticTexts.ci("Bring Anchor into your Hub").exists)
        XCTAssertTrue(app.buttons.ci("anchor.hub.sign-in-apple").exists)
        #endif
        let appearance = app.segmentedControls["anchor.settings.appearance"]
        XCTAssertTrue(appearance.exists)
        appearance.buttons.ci("Dark").tap()
        XCTAssertTrue(
            app.staticTexts.ci("Uses the charcoal focus canvas on this device.")
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.staticTexts.ci("This build stores appearance on this device only").exists)
        XCTAssertFalse(app.staticTexts.ci("Talk to your data").exists)
        XCTAssertFalse(app.staticTexts.ci("Database").exists)
    }

    @MainActor
    private func keepScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
