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
        XCTAssertFalse(accept.isEnabled, "the terms could be accepted before the countdown ended")
        let countdown = XCTAttachment(screenshot: app.screenshot())
        countdown.name = "terms-countdown"
        countdown.lifetime = .keepAlways
        add(countdown)
        let ready = NSPredicate(format: "isEnabled == true")
        expectation(for: ready, evaluatedWith: accept)
        waitForExpectations(timeout: 10)
        accept.tap()
        expectation(for: gone, evaluatedWith: accept)
        waitForExpectations(timeout: 10)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
    }
}
