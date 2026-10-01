import XCTest

/// "Turn into…": an MCQ set turned into Cards has to arrive as a real deck,
/// opened straight away, from nothing more than a long press and two taps.
/// Checked with real touches, because a menu item that does nothing and a
/// sheet that closes without navigating both look fine in code.
final class TurnIntoUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testMCQTurnsIntoCardsAndOpens() {
        let app = XCUIApplication()
        // a still sky, so the simulator's main thread has time for the taps
        app.launchArguments += ["-personalBuild", "-stillSky"]
        app.launch()
        let gone = NSPredicate(format: "exists == false")

        // Signed out on a fresh simulator: this device only, then the terms.
        // Either may already be past on a simulator that has run before.
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
        // then, once, "Which exam are you preparing for?" - skipped here
        let skipExam = app.buttons["examOnboardingSkip"]
        if skipExam.waitForExistence(timeout: 8) { skipExam.tap() }
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 15), "the library didn't open")
        snap(app, "1-library")

        // The personal build seeds an example of every mode; the MCQ one is
        // "Example: Nephrology - glomerular disease".
        let row = app.descendants(matching: .any).matching(identifier: "setRow-mcq").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "no MCQ set in the library")
        var swipes = 0
        while !row.isHittable && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(row.isHittable, "the MCQ set is off screen")
        row.press(forDuration: 1.2)

        // The context menu's item, by identifier, or by its title where the
        // menu does not carry the identifier across.
        var turnInto = app.buttons["turnInto"]
        if !turnInto.waitForExistence(timeout: 5) {
            turnInto = app.buttons["Turn into\u{2026}"]
        }
        XCTAssertTrue(turnInto.waitForExistence(timeout: 5), "no Turn into\u{2026} in the menu")
        snap(app, "2-menu")
        turnInto.tap()

        let cards = app.descendants(matching: .any).matching(identifier: "turnInto-anki").firstMatch
        XCTAssertTrue(cards.waitForExistence(timeout: 10), "the picker didn't open")
        snap(app, "3-picker")
        cards.tap()
        expectation(for: gone, evaluatedWith: cards)
        waitForExpectations(timeout: 10)

        // Straight into the new deck: a Cards screen, the one with "Reveal"
        // under the card (and "Quiz me" in its toolbar, unless the toolbar
        // has folded it away), showing one of the quiz's stems as a front.
        let reveal = app.buttons["Reveal"]
        let quizMe = app.buttons["Quiz me"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 10) || quizMe.exists, "the new deck didn't open")
        let front = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@ OR label CONTAINS %@",
                                  "frothy urine", "hepatitis C", "Anti-PLA2R")).firstMatch
        XCTAssertTrue(front.exists, "the deck isn't showing the quiz's questions")
        snap(app, "4-new-deck")

        // and it is in the library, named after the quiz it came from
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let named = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "\u{2013} Cards")).firstMatch
        XCTAssertTrue(named.waitForExistence(timeout: 10), "no set named \u{2026} \u{2013} Cards in the library")
        snap(app, "5-library-after")
    }
}
