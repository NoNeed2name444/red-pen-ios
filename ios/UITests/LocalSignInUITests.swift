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
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
    }
}
