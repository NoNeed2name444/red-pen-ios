import XCTest

/// Settings (the owner, 22 Oct): there is no AI models page and no writer to
/// choose. The cloud's status, Verify, the accuracy engine and the crash
/// reports are plain rows in Settings itself, each reached by scrolling, and
/// the crash reports row opens its page.
final class SettingsRowsUITests: XCTestCase {
    func testTheWritingRowsAreInSettingsWithNoModelsPage() {
        let app = XCUIApplication()
        app.keepTraceOffConsole()
        app.launchArguments += ["-personalBuild", "-stillSky", "-uiPreviewScreen", "settings"]
        app.launch()

        let rows: [XCUIElement] = [
            app.descendants(matching: .any)["cloudStatus"],
            app.switches["verifyToggle"],
            app.switches["Check my whole library in the background"],
            app.buttons["crashReports"],
        ]
        for row in rows {
            var scrolls = 0
            while !(row.exists && row.isHittable) && scrolls < 20 { app.swipeUp(); scrolls += 1 }
            XCTAssertTrue(row.exists, "\(row) is not a row in Settings")
        }
        XCTAssertFalse(app.buttons["AI models"].exists, "Settings still offers an AI models page")
        XCTAssertFalse(app.staticTexts["AI models"].exists, "Settings still names an AI models page")

        app.buttons["crashReports"].tap()
        XCTAssertTrue(app.navigationBars["Diagnostics"].waitForExistence(timeout: 10),
                      "the crash reports row did not open its page")
    }
}
