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
        logReach(crashReports)
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
    ///
    /// Hittable is not enough: the walk back up brings a row in from the
    /// top, and XCTest can call a row hittable while it is still under the
    /// navigation bar: the masthead (WardMasthead) over it takes no touches
    /// and is hidden from accessibility, but the bar itself takes the tap
    /// (likeliest reading of App build 42001724201 on 9316cf73: crashReports
    /// hittable after the eighth step up, tapped at t 118.05 with the app
    /// idle, and no Diagnostics page; SETTINGS-REACH logs the frames).
    /// So the row must also lie wholly between the bar and the window's
    /// foot; one step (a third of the screen) is shorter than that band, so
    /// a step always lands it there.
    private func reach(_ element: XCUIElement) {
        var steps = 0
        while !inReach(element) && steps < 30 { scroll(down: true); steps += 1 }
        steps = 0
        while !inReach(element) && steps < 30 { scroll(down: false); steps += 1 }
    }

    /// The element exists, can be hit, and lies wholly below the navigation
    /// bar and above the home indicator's strip.
    private func inReach(_ element: XCUIElement) -> Bool {
        guard element.exists && element.isHittable else { return false }
        let frame: CGRect = element.frame
        let window: CGRect = app.windows.firstMatch.frame
        let bar = app.navigationBars.firstMatch
        let top: CGFloat = bar.exists ? bar.frame.maxY : window.minY
        return frame.minY >= top && frame.maxY <= window.maxY - Self.footClearance
    }

    /// For the next run's log: where the row and the bar were at the tap.
    private func logReach(_ element: XCUIElement) {
        let bar = app.navigationBars.firstMatch
        let barFrame: CGRect = bar.exists ? bar.frame : .null
        print("SETTINGS-REACH row=\(element.frame) bar=\(barFrame) window=\(app.windows.firstMatch.frame) hittable=\(element.isHittable)")
    }

    /// The home indicator's strip at the window's foot (34 points on a
    /// Face ID iPhone), kept clear so a tap is never read as its swipe.
    private static let footClearance: CGFloat = 34

    /// Moves the page about a third of the screen: `down` shows what is
    /// below. The drag runs in the page's leading margin, left of the
    /// groups' cards, so no row is under the finger. On the rows' words it
    /// stopped once the library switch was reached: every drag then began on
    /// a switch row, whose face (WardToggleFace) holds a long press across
    /// the whole row, and the page never moved again (run 41848103900).
    private func scroll(down: Bool) {
        let window: CGRect = app.windows.firstMatch.frame
        let x: CGFloat = marginX(in: window)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let low = origin.withOffset(CGVector(dx: x, dy: window.minY + window.height * 0.7))
        let high = origin.withOffset(CGVector(dx: x, dy: window.minY + window.height * 0.35))
        let (from, to) = down ? (low, high) : (high, low)
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .default, thenHoldForDuration: 0.3)
    }

    /// The middle of the page's leading margin, from the element tree: half
    /// way between the paper's gutter and the nearest card's edge (a Form
    /// cell, or a switch row's own edge), a few points in at least.
    ///
    /// Not from the window's edge: the first 16 points (WardPaper.sideInset)
    /// are the paper's gutter, where WardEdgeReach hands a touch to the
    /// navigation stack for its swipe back, never to the page's scroll view.
    /// Half way from the window's edge to the cards (at x 32) was x 16, the
    /// gutter's last point (WardEdgeReachRule.inside, x <= minX + inset), so
    /// none of the drags moved the page (run 41876986518, "Press ... ->
    /// (16.0, ...)" on all 300 drags, and every row "is not a row").
    private func marginX(in window: CGRect) -> CGFloat {
        let gutter: CGFloat = window.minX + Self.paperGutter + 1
        var edge: CGFloat = window.maxX
        for item in [app.cells.firstMatch, app.switches.firstMatch] where item.exists {
            edge = min(edge, item.frame.minX)
        }
        if edge >= window.maxX { edge = gutter + 16 }
        return gutter + max((edge - gutter) / 2, 4)
    }

    /// WardPaper.sideInset in the app: its leading gutter.
    private static let paperGutter: CGFloat = 16
}
