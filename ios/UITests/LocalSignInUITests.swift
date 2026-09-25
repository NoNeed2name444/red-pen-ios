import XCTest

/// Personal build: tapping "Use on this device only" has to get you into the
/// library. Checked with a real tap, because "nothing happens" is a touch
/// problem as often as a logic one.
final class LocalSignInUITests: XCTestCase {
    func testThisDeviceOnlyOpensTheLibrary() {
        let app = XCUIApplication()
        app.launch()
        let door = app.buttons["localSignIn"]
        XCTAssertTrue(door.waitForExistence(timeout: 20), "the button isn't on screen")
        XCTAssertTrue(door.isHittable, "the button is covered by something")
        door.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: door)
        waitForExpectations(timeout: 15)

        // then the recording terms: not pressable for five seconds, then pressable
        let accept = app.buttons["acceptRecordingTerms"]
        XCTAssertTrue(accept.waitForExistence(timeout: 10), "the recording terms didn't appear")
        // (whether it is still counting down depends on how long the simulator
        // took to show it, so that is not asserted here)
        let countdown = XCTAttachment(screenshot: app.screenshot())
        countdown.name = "terms-countdown"
        countdown.lifetime = .keepAlways
        add(countdown)
        let ready = NSPredicate(format: "isEnabled == true")
        expectation(for: ready, evaluatedWith: accept)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(accept.isHittable, "the agree button is covered by something")
        accept.tap()
        expectation(for: gone, evaluatedWith: accept)
        waitForExpectations(timeout: 10)
        // then, once, "Which exam are you preparing for?" - skippable
        let skipExam = app.buttons["examOnboardingSkip"]
        XCTAssertTrue(skipExam.waitForExistence(timeout: 10), "the exam question didn't appear")
        let question = XCTAttachment(screenshot: app.screenshot())
        question.name = "exam-question"
        question.lifetime = .keepAlways
        add(question)
        skipExam.tap()
        // and the library is really there, not a blank screen
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 15), "the library didn't open after agreeing")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
    }
}
