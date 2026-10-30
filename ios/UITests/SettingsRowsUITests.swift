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
        let crashReports = app.buttons["crashReports"]
        reach(crashReports)
        crashReports.tap()
        XCTAssertTrue(app.navigationBars["Diagnostics"].waitForExistence(timeout: 10),
                      "the crash reports row did not open its page")
    }

    /// Swipes up (up to 20 times) and then down (up to 20 times) until the
    /// element exists and can be hit.
    private func reach(_ element: XCUIElement) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < 20 { app.swipeUp(); swipes += 1 }
        swipes = 0
        while !(element.exists && element.isHittable) && swipes < 20 { app.swipeDown(); swipes += 1 }
    }
}
