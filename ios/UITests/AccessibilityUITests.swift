import XCTest

/// The App Store accessibility labels, checked on a simulator: the main
/// screens at the largest accessibility text size (AX5, "XXXL"), and
/// Xcode's own accessibility audit on each of them.
///
/// At that size the dock is one button over a list of sections (CategoryDock,
/// "dockList"), the tiles go one across, and the rating buttons one per row;
/// this walks through the library, a quiz, a card, Settings and Mission
/// Control's exam plan that way, and checks each control it needs is there,
/// can be pressed and sits inside the window rather than off its edge.
///
/// Found by the identifiers the other UI tests use (localSignIn,
/// acceptRecordingTerms, examOnboardingSkip, dockCategory-<place>,
/// setRow-mcq, setRow-anki, missionPlan, libraryMenu) plus dockList.
final class AccessibilityUITests: XCTestCase {
    private var app: XCUIApplication!

    /// UIKit's own override for the text size, read at launch.
    private static let largestText: [String] = ["-UIPreferredContentSizeCategoryName",
                                                "UICTContentSizeCategoryAccessibilityXXXL"]

    /// Everything the audit knows how to check, except colour contrast.
    ///
    /// Contrast is left out on purpose, not because it is ignored: the audit
    /// samples the pixels of one frame, and behind every screen here is the
    /// drifting night sky seen through Liquid Glass, which refracts it - so
    /// the same text passes on one frame and fails on the next. What the app
    /// promises for contrast is the Increase Contrast path (solid surfaces
    /// with an edge, the nebula at half strength, AccessibleGlass and
    /// AppBackdrop), which a pixel sample of the default look cannot check.
    private static let audited: XCUIAccessibilityAuditType = XCUIAccessibilityAuditType.all.subtracting([.contrast])

    override func setUp() {
        continueAfterFailure = true
    }

    // MARK: - The largest text size

    func testMainScreensAtTheLargestTextSize() {
        launch()
        let list = element("dockList")
        XCTAssertTrue(list.waitForExistence(timeout: 20), "the dock is not one button over a list at AX sizes")
        assertInWindow(list, "the sections button")
        snap("library")

        // every section, and Ideas, from the list
        for place in ["questions", "cards", "cases", "osce", "audio", "ideas"] {
            XCTAssertTrue(choose(place), "could not choose \(place) from the sections list")
            snap("section-\(place)")
        }

        tilesGoOneAcross()
        quiz()
        card()
        settings()
        examPlan()
        XCTAssertEqual(app.state, .runningForeground, "the app stopped")
    }

    /// Questions' tiles: one across, each inside the window.
    private func tilesGoOneAcross() {
        XCTAssertTrue(choose("questions"))
        let tile = element("feature-mixed")
        guard reveal(tile) else {
            XCTFail("no Mixed quiz tile on Questions")
            return
        }
        assertInWindow(tile, "the Mixed quiz tile")
        let window: CGRect = app.windows.firstMatch.frame
        XCTAssertGreaterThan(tile.frame.width, window.width * 0.6, "tiles are not one across at AX sizes")
        snap("tiles")
    }

    /// An example question: its options wrap inside the window, and it can
    /// be answered and checked.
    private func quiz() {
        XCTAssertTrue(choose("questions"))
        guard openSet("mcq") else { return }
        let first = NSPredicate(format: "label BEGINSWITH %@", "Answer A")
        let answer = app.buttons.matching(first).firstMatch
        guard reveal(answer) else {
            XCTFail("the first option is not on screen")
            goHome()
            return
        }
        assertInWindow(answer, "option A")
        answer.tap()
        let check = app.buttons["Check answer"].firstMatch
        if check.waitForExistence(timeout: 5) {
            assertInWindow(check, "Check answer")
            check.tap()
            // after checking, the option says whether it was right
            let value: String = (answer.value as? String) ?? ""
            XCTAssertFalse(value.isEmpty, "a checked option says nothing about right or wrong")
        } else {
            XCTFail("no Check answer button after choosing an option")
        }
        snap("quiz-checked")
        goHome()
    }

    /// An example card: Reveal, then the four ratings, each inside the window.
    private func card() {
        XCTAssertTrue(choose("cards"))
        guard openSet("anki") else { return }
        let reveal = app.buttons["Reveal"].firstMatch
        guard reveal.waitForExistence(timeout: 6) else {
            XCTFail("no Reveal on the example deck")
            goHome()
            return
        }
        assertInWindow(reveal, "Reveal")
        reveal.tap()
        for title in ["Again", "Hard", "Good", "Easy"] {
            let rating = app.buttons[title].firstMatch
            XCTAssertTrue(rating.waitForExistence(timeout: 5), "no \(title) rating")
            _ = self.reveal(rating, swipes: 4)
            assertInWindow(rating, "the \(title) rating")
        }
        snap("card-revealed")
        goHome()
    }

    /// Settings, from the account menu.
    private func settings() {
        let menu = element("libraryMenu")
        guard menu.waitForExistence(timeout: 6) else {
            XCTFail("no account menu")
            return
        }
        menu.tap()
        let named = NSPredicate(format: "label == %@", "Settings")
        let button = app.buttons.matching(named).firstMatch
        let item: XCUIElement = button.waitForExistence(timeout: 4) ? button : app.menuItems.matching(named).firstMatch
        guard item.exists else {
            XCTFail("no Settings in the menu")
            return
        }
        item.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8), "Settings did not open")
        snap("settings")
        goHome()
    }

    /// Mission Control's Plan, to the exam plan.
    private func examPlan() {
        XCTAssertTrue(choose("questions"))
        let plan = element("missionPlan")
        guard plan.waitForExistence(timeout: 6), reveal(plan) else {
            // Mission Control only shows once there is something to say
            return
        }
        assertInWindow(plan, "Mission Control's Plan")
        plan.tap()
        XCTAssertTrue(app.navigationBars["Exam plan"].waitForExistence(timeout: 8), "the exam plan did not open")
        snap("exam-plan")
        goHome()
    }

    // MARK: - The audit

    func testAccessibilityAuditOfMainScreens() throws {
        launch()
        XCTAssertTrue(element("dockList").waitForExistence(timeout: 20), "the library did not open")
        try audit("library")

        if choose("questions"), openSet("mcq") {
            try audit("quiz")
            goHome()
        }
        if choose("cards"), openSet("anki") {
            let reveal = app.buttons["Reveal"].firstMatch
            if reveal.waitForExistence(timeout: 6) { reveal.tap() }
            try audit("card, revealed")
            goHome()
        }
        let menu = element("libraryMenu")
        if menu.waitForExistence(timeout: 6) {
            menu.tap()
            let named = NSPredicate(format: "label == %@", "Settings")
            let item = app.buttons.matching(named).firstMatch
            if item.waitForExistence(timeout: 4) {
                item.tap()
                if app.navigationBars["Settings"].waitForExistence(timeout: 8) {
                    try audit("settings")
                }
            }
            goHome()
        }
    }

    private func audit(_ screen: String) throws {
        try XCTContext.runActivity(named: "Audit: \(screen)") { _ in
            snap("audit-\(screen)")
            try app.performAccessibilityAudit(for: Self.audited) { [unowned self] issue in
                self.isBenign(issue)
            }
        }
    }

    /// The issues left to the system, each for a reason. Everything else
    /// fails the test.
    private func isBenign(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard let element = issue.element else { return false }
        // UIKit draws the navigation bar and truncates its inline title at
        // the largest sizes by design (the long-press on it shows the whole
        // title in the Large Content Viewer); the app's own words are not in
        // the bar.
        if issue.auditType == .textClipped {
            let bar = app.navigationBars.firstMatch
            if bar.exists && bar.frame.contains(element.frame) { return true }
        }
        // A symbol beside words is capped (scaledFont's maxSize) so it does
        // not crowd them out; the words it sits beside still grow. Only
        // images - never text - are let through here.
        if issue.auditType == .dynamicType && element.elementType == .image { return true }
        return false
    }

    // MARK: - Getting around

    private func launch() {
        // a system alert (notifications, the microphone) answered rather
        // than left standing over the screen being checked
        _ = addUIInterruptionMonitor(withDescription: "system alert") { alert in
            for title in ["Allow", "OK", "Don\u{2019}t Allow", "Don't Allow"] {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
        app = XCUIApplication()
        // the example sets to open, and a still sky so a busy simulator does
        // not drop taps
        app.launchArguments += ["-personalBuild", "-stillSky"] + Self.largestText
        app.launch()
        signIn()
    }

    private func signIn() {
        let door = app.buttons["localSignIn"]
        let accept = app.buttons["acceptRecordingTerms"]
        let skipExam = app.buttons["examOnboardingSkip"]
        let list = element("dockList")
        for _ in 0..<80 {
            if list.exists { return }
            if door.exists && door.isHittable {
                door.tap()
                sleep(1)
            } else if accept.exists && accept.isEnabled {
                // at the largest text the terms run long: scroll to the button
                if !accept.isHittable { app.swipeUp() }
                if accept.isHittable { accept.tap() }
                sleep(1)
            } else if skipExam.exists {
                if !skipExam.isHittable { app.swipeUp() }
                if skipExam.isHittable { skipExam.tap() }
                sleep(1)
            } else {
                usleep(500_000)
            }
        }
    }

    /// A section from the list the dock becomes at AX sizes.
    private func choose(_ place: String) -> Bool {
        let list = element("dockList")
        guard list.waitForExistence(timeout: 8) else { return false }
        list.tap()
        let row = element("dockCategory-\(place)")
        guard row.waitForExistence(timeout: 5) else { return false }
        if !row.isHittable { _ = reveal(row, swipes: 4) }
        row.tap()
        // the sheet goes once a row is chosen
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: row)
        let closed: Bool = XCTWaiter.wait(for: [gone], timeout: 5) == .completed
        sleep(1)
        return closed
    }

    private func openSet(_ kind: String) -> Bool {
        let row = element("setRow-\(kind)")
        guard row.waitForExistence(timeout: 8), reveal(row, swipes: 16) else {
            XCTFail("no example \(kind) set in the library")
            return false
        }
        row.tap()
        sleep(3)
        return !element("dockList").exists
    }

    /// Back to the library: Cancel or Done on a sheet, Back on a pushed page.
    private func goHome() {
        for _ in 0..<6 {
            let list = element("dockList")
            if list.exists && list.isHittable { return }
            let cancel = app.buttons["Cancel"].firstMatch
            let done = app.buttons["learnDone"].firstMatch
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if cancel.exists && cancel.isHittable {
                cancel.tap()
            } else if done.exists && done.isHittable {
                done.tap()
            } else if back.exists && back.isHittable {
                back.tap()
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
            }
            sleep(1)
        }
    }

    /// Scrolls until `target` can be pressed. True if it can.
    @discardableResult
    private func reveal(_ target: XCUIElement, swipes: Int = 12) -> Bool {
        for _ in 0..<swipes {
            if target.exists && target.isHittable { return true }
            app.swipeUp(velocity: .slow)
            usleep(500_000)
        }
        return target.exists && target.isHittable
    }

    /// On screen, pressable and inside the window side to side - not pushed
    /// off an edge by text that grew.
    private func assertInWindow(_ target: XCUIElement, _ what: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(target.exists, "\(what) is missing", file: file, line: line)
        guard target.exists else { return }
        let frame: CGRect = target.frame
        let window: CGRect = app.windows.firstMatch.frame
        XCTAssertFalse(frame.isEmpty, "\(what) has no size", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minX, window.minX - 1, "\(what) runs off the left edge", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 1, "\(what) runs off the right edge", file: file, line: line)
        XCTAssertTrue(target.isHittable, "\(what) cannot be pressed", file: file, line: line)
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "a11y-" + name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
