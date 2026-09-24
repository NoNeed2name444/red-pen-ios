import XCTest

/// The personal build's "Try every feature" page: every row opens its worked
/// example without crashing, with a screenshot of each for a person to look at.
final class ExamplesUITests: XCTestCase {
    private let rows = ["ideas", "reasoning", "progress", "analytics", "rules", "coverage",
                        "commute", "explain", "explain-live", "osce-bbn", "osce-history", "draw"]

    func testEveryExampleOpens() {
        let app = XCUIApplication()
        app.launchArguments += ["-personalBuild"]
        app.launch()

        let door = app.buttons["localSignIn"]
        if door.waitForExistence(timeout: 20) { door.tap() }
        let accept = app.buttons["acceptRecordingTerms"]
        if accept.waitForExistence(timeout: 15) {
            expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: accept)
            waitForExpectations(timeout: 12)
            accept.tap()
        }

        // at the bottom of the library page
        let banner = app.buttons["examplesBanner"]
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 20), "the library didn't open")
        var scrolls = 0
        while !(banner.exists && banner.isHittable) && scrolls < 8 { app.swipeUp(); scrolls += 1 }
        XCTAssertTrue(banner.exists, "the 'Try every feature' link isn't at the bottom of the library")
        banner.tap()
        snap(app, "hub")

        for id in rows {
            let row = app.buttons["example-\(id)"]
            // lower rows may need a scroll to come on screen
            var tries = 0
            while !row.isHittable && tries < 6 { app.swipeUp(); tries += 1 }
            XCTAssertTrue(row.exists, "no row for \(id)")
            row.tap()
            sleep(3)
            XCTAssertEqual(app.state, .runningForeground, "the app stopped opening \(id)")
            snap(app, id)
            let back = app.navigationBars.buttons.firstMatch
            if back.exists { back.tap() }
            sleep(1)
            while app.buttons["example-ideas"].exists && !app.buttons["example-ideas"].isHittable { app.swipeDown() }
        }
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
