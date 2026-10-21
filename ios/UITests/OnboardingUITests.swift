import XCTest

/// The first-run pages (FirstRunView): shown after the recording terms only
/// because the launch asks for them (-showOnboarding - never otherwise in the
/// simulator), walked once answering every page and once skipping every
/// page, each ending in the library. A screenshot of every page for a person
/// to look at.
final class OnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testEveryPageAnswered() {
        let app = launch()

        // 1 - the exam: pick the first one listed, then Save
        let firstExam = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'examPick-'")).firstMatch
        XCTAssertTrue(firstExam.waitForExistence(timeout: 15), "the exam page didn't appear")
        snap(app, "1-exam")
        firstExam.tap()
        tap(app.buttons["examPickerSave"], "the exam page's Save")

        // 2 - the date: the calendar, then Save the date
        XCTAssertTrue(app.descendants(matching: .any)["firstRunDatePicker"].waitForExistence(timeout: 10),
                      "the date page has no calendar")
        snap(app, "2-date")
        tap(app.buttons["firstRun-date-next"], "the date page's Save")

        // 3 - the daily goal: a preset, then Set
        tap(app.buttons["firstRunGoal-100"], "the 100-a-day preset")
        let setGoal = app.buttons["firstRun-goal-next"]
        // the preset took: the main button now sets 100
        let hundred = NSPredicate(format: "label CONTAINS '100'")
        expectation(for: hundred, evaluatedWith: setGoal)
        waitForExpectations(timeout: 5)
        snap(app, "3-goal")
        tap(setGoal, "the goal page's Set")

        // 4 - reminders: left off (turning one on asks for notifications)
        let remindersNext = app.buttons["firstRun-reminders-next"]
        XCTAssertTrue(remindersNext.waitForExistence(timeout: 10), "the reminders page didn't appear")
        snap(app, "4-reminders")
        tap(remindersNext, "the reminders page's Next")

        // 5 - an example set
        let add = app.buttons["firstRunAddExamples"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "the examples page didn't appear")
        XCTAssertTrue(app.buttons["firstRunStartEmpty"].exists, "no Start empty beside the example set")
        snap(app, "5-examples")
        add.tap()

        assertLibrary(app, "after adding the example set")
    }

    func testEveryPageSkipped() {
        let app = launch()
        let skips: [String] = ["examOnboardingSkip", "firstRun-date-skip", "firstRun-goal-skip",
                               "firstRun-reminders-skip", "firstRun-examples-skip"]
        for id in skips {
            let skip = app.buttons[id]
            XCTAssertTrue(skip.waitForExistence(timeout: 15), "no Skip on the page (\(id))")
            snap(app, "skip-\(id)")
            tap(skip, id)
        }
        assertLibrary(app, "after skipping every page")
    }

    // MARK: - Steps

    /// Launched asking for the pages; signed in on this device and the terms
    /// agreed to, either of which may already be past on a simulator that
    /// has run the app before.
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // a still sky, so the simulator's main thread has time for the taps
        app.launchArguments += ["-showOnboarding", "-stillSky"]
        app.launch()
        let gone = NSPredicate(format: "exists == false")
        let door = app.buttons["localSignIn"]
        if door.waitForExistence(timeout: 20) {
            door.tap()
            expectation(for: gone, evaluatedWith: door)
            waitForExpectations(timeout: 15)
        }
        let accept = app.buttons["acceptRecordingTerms"]
        if accept.waitForExistence(timeout: 10) {
            expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: accept)
            waitForExpectations(timeout: 10)
            accept.tap()
            expectation(for: gone, evaluatedWith: accept)
            waitForExpectations(timeout: 10)
        }
        return app
    }

    /// Taps a button that has to be there and pressable.
    private func tap(_ button: XCUIElement, _ what: String) {
        XCTAssertTrue(button.waitForExistence(timeout: 10), "\(what) isn't on screen")
        XCTAssertTrue(button.isHittable, "\(what) is covered by something")
        button.tap()
    }

    /// The library, not another page: its dock is there.
    private func assertLibrary(_ app: XCUIApplication, _ when: String) {
        let dock = app.descendants(matching: .any)["dockCategory-questions"]
        XCTAssertTrue(dock.waitForExistence(timeout: 20), "the library didn't open \(when)")
        XCTAssertFalse(app.buttons["firstRun-examples-skip"].exists, "the first-run pages are still there \(when)")
        snap(app, "library")
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
