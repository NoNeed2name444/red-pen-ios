import XCTest

/// Settings (the owner, 22 Oct): there is no AI models page and no writer to
/// choose. The cloud's status, Verify, the accuracy engine and the crash
/// reports are plain rows in Settings itself, each reached by scrolling, and
/// the crash reports row opens its page.
final class SettingsRowsUITests: XCTestCase {
    private let app = XCUIApplication()

    func testTheWritingRowsAreInSettingsWithNoModelsPage() {
        app.keepTraceOffConsole()
        app.launchArguments += ["-personalBuild", "-stillSky", "-uiPreviewScreen", "settings"]
        app.launch()

        // in the page's order (SupportCenter.body: the cloud group, then the
        // accuracy engine's), so each is reached scrolling one way
        let rows: [XCUIElement] = [
            app.descendants(matching: .any)["cloudStatus"],
            app.switches["verifyToggle"],
            app.buttons["crashReports"],
            app.switches["Check my whole library in the background"],
        ]
        for row in rows {
            reach(row)
            XCTAssertTrue(row.exists, "\(row) is not a row in Settings")
        }
        XCTAssertFalse(app.buttons["AI models"].exists, "Settings still offers an AI models page")
        XCTAssertFalse(app.staticTexts["AI models"].exists, "Settings still names an AI models page")

        // the page was scrolled down to the library switch: bring the row back
        // (it is above, so the first pass runs to the page's foot and the
        // second walks back up to it)
        let crashReports = app.buttons["crashReports"]
        reach(crashReports)
        crashReports.tap()
        XCTAssertTrue(app.navigationBars["Diagnostics"].waitForExistence(timeout: 10),
                      "the crash reports row did not open its page")
    }

    /// Scrolls the page up (up to 30 steps) and then down (up to 30 steps)
    /// until the element exists and can be hit.
    ///
    /// Each step is a drag held still before it lets go, so the page stops
    /// where the finger does. A swipe is a flick: one swipe down from the
    /// page's foot coasted all the way to its top (App build on d4567ed0,
    /// the 2.5 s settle after the first swipe down, then no movement), past
    /// the crash reports row, which is below the first screen, and every
    /// later swipe down did nothing.
    private func reach(_ element: XCUIElement) {
        var steps = 0
        while !(element.exists && element.isHittable) && steps < 30 { scroll(down: true); steps += 1 }
        steps = 0
        while !(element.exists && element.isHittable) && steps < 30 { scroll(down: false); steps += 1 }
    }

    /// Moves the page about a third of the screen: `down` shows what is
    /// below. The drag runs near the leading edge, on the rows' words, clear
    /// of the switches and the slider's thumb.
    private func scroll(down: Bool) {
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.7))
        let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.35))
        let (from, to) = down ? (low, high) : (high, low)
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .default, thenHoldForDuration: 0.3)
    }
}
