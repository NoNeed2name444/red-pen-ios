import XCTest

/// A diagnostic probe (T0186), not a check: Xcode's accessibility audit on
/// the quiz screen at AX5, once for each of the mode wash's probe switches
/// (WardProbe), so the variant that drops the four element-less issues
/// (2x Dynamic Type, 2x Text clipped) names the part of the wash behind
/// them. It never fails on an audit issue: each one is printed as a QPROBE
/// line and let through. Launch, sign-in and the way to the quiz are
/// AccessibilityUITests' own, copied.
final class A11yQuizProbeUITests: XCTestCase {
    private var app: XCUIApplication!

    /// UIKit's own override for the text size, read at launch.
    private static let largestText: [String] = ["-UIPreferredContentSizeCategoryName",
                                                "UICTContentSizeCategoryAccessibilityXXXL"]

    /// As AccessibilityUITests: everything but colour contrast.
    private static let audited: XCUIAccessibilityAuditType = XCUIAccessibilityAuditType.all.subtracting([.contrast])

    private static let allSwitches = ["-probeNoWash", "-probeOldBar", "-probeOpaqueFaces", "-probeOldCharts"]

    override func setUp() {
        continueAfterFailure = true
    }

    override func tearDown() {
        app?.terminate()
    }

    // numbered so XCTest runs them in this order
    func test1None() throws { try probe("none", []) }
    func test2NoWash() throws { try probe("noWash", ["-probeNoWash"]) }
    func test3OldBar() throws { try probe("oldBar", ["-probeOldBar"]) }
    func test4OpaqueFaces() throws { try probe("opaqueFaces", ["-probeOpaqueFaces"]) }
    func test5OldCharts() throws { try probe("oldCharts", ["-probeOldCharts"]) }
    func test6All() throws { try probe("all", Self.allSwitches) }

    /// The quiz screen's audit under `switches`, every issue printed.
    private func probe(_ variant: String, _ switches: [String]) throws {
        launch(switches)
        guard element("dockList").waitForExistence(timeout: 20) else {
            print("QPROBE-DONE \(variant) count=-1 (the library did not open)")
            XCTFail("the library did not open")
            return
        }
        guard choose("questions"), openSet("mcq") else {
            print("QPROBE-DONE \(variant) count=-1 (the quiz was not reached)")
            XCTFail("the quiz was not reached")
            return
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "qprobe-" + variant
        shot.lifetime = .keepAlways
        add(shot)
        var count = 0
        try app.performAccessibilityAudit(for: Self.audited) { issue in
            count += 1
            let line = "QPROBE \(variant) \(issue.compactDescription) | \(issue.detailedDescription) | element=\(issue.element?.debugDescription ?? "nil")"
            print(line.replacingOccurrences(of: "\n", with: " / "))
            return true
        }
        print("QPROBE-DONE \(variant) count=\(count)")
    }

    // MARK: - Getting around (AccessibilityUITests')

    private func launch(_ switches: [String]) {
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
        app.keepTraceOffConsole()
        // the example sets to open, and a still sky so a busy simulator does
        // not drop taps
        app.launchArguments += ["-personalBuild", "-stillSky"] + Self.largestText + switches
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
        // the sheet opens at its top, so only down it
        guard scrollToFind(row, down: 6) else { return false }
        row.tap()
        // the sheet goes once a row is chosen
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: row)
        let closed: Bool = XCTWaiter.wait(for: [gone], timeout: 5) == .completed
        sleep(1)
        return closed
    }

    private func openSet(_ kind: String) -> Bool {
        let row = element("setRow-\(kind)")
        // down the page, then back up: the same section chosen again keeps
        // the page where it was, perhaps below the sets
        guard scrollToFind(row, down: 16, up: 24) else {
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
    ///
    /// With `clearOfSearch`, pressable also means wholly below the library's
    /// search field, which stays pinned at the top: the page scrolls under
    /// it, and XCTest calls a button half under it hittable though a tap at
    /// its middle lands on the field. That is how "Open plan" was "tapped"
    /// and opened nothing (run 41848103900). A target under the field is
    /// drawn back down past it, by a drag held still so the page does not
    /// coast. As RotationStateUITests' reach waits to clear the study deck.
    @discardableResult
    private func reveal(_ target: XCUIElement, swipes: Int = 12, clearOfSearch: Bool = false) -> Bool {
        for _ in 0..<swipes {
            let overlap: CGFloat = clearOfSearch && target.exists ? searchOverlap(target) : 0
            if overlap > 0 {
                // under the field, or scrolled past it: back down, a part
                // of the window at a time
                drawDown(by: min(overlap + 24, app.windows.firstMatch.frame.height * 0.4))
            } else if target.exists && target.isHittable {
                return true
            } else {
                app.swipeUp(velocity: .slow)
            }
            usleep(500_000)
        }
        let pressable: Bool = target.exists && target.isHittable
        return pressable && (!clearOfSearch || searchOverlap(target) <= 0)
    }

    /// Scrolls back up the page, a slow swipe at a time, until `target` can
    /// be pressed, at most `swipes` times. Stops at once if it already can.
    private func revealAbove(_ target: XCUIElement, swipes: Int = 8) {
        for _ in 0..<swipes {
            if target.exists && target.isHittable { return }
            app.swipeDown(velocity: .slow)
            usleep(500_000)
        }
    }

    /// How far `target`'s top stands above the bottom of the pinned search
    /// field, in points; zero or less when it is wholly below it, or when no
    /// search field is on screen.
    private func searchOverlap(_ target: XCUIElement) -> CGFloat {
        let search = element("librarySearch")
        guard search.exists else { return 0 }
        return search.frame.maxY - target.frame.minY + 1
    }

    /// Moves the page down by about `points`, showing what is above.
    private func drawDown(by points: CGFloat) {
        let window = app.windows.firstMatch
        let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = from.withOffset(CGVector(dx: 0, dy: points))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// Scrolls until `target` can be pressed: down the page up to `down`
    /// swipes, then back up up to `up`, then waits for it to be pressable.
    /// At AX sizes the header fills the screen and a list makes a row only
    /// once it is scrolled to, so the row is looked for while scrolling
    /// rather than waited for first. True once it can be pressed.
    private func scrollToFind(_ target: XCUIElement, down: Int, up: Int = 0) -> Bool {
        // the page, or the sheet, a moment to arrive
        _ = target.waitForExistence(timeout: 3)
        if !reveal(target, swipes: down) {
            for _ in 0..<up {
                if target.exists && target.isHittable { break }
                app.swipeDown(velocity: .slow)
                usleep(500_000)
            }
        }
        guard target.exists else { return false }
        let pressable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: target)
        return XCTWaiter.wait(for: [pressable], timeout: 5) == .completed
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

}
