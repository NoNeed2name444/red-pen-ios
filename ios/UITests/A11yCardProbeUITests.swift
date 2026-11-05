import XCTest

/// A diagnostic probe (T0203), not a check: why the main-screens audit
/// flags the revealed card's front ("Dynamic Type font sizes are partially
/// unsupported", ankiCardFront) on some runs and not others.
///
/// Each test is one fresh launch at one text size, the way
/// AccessibilityUITests' audit reaches the card: Cards, the example deck,
/// Reveal, the front left to stop moving, then the same audit (the same
/// types, no issue let through by kind, every issue only counted). Five
/// variants, three runs each, interleaved so a slow first launch does not
/// fall on one variant:
/// - V1 AX5, as the audit runs today;
/// - V2 the default size (no size argument);
/// - V3 AccessibilityM, the smallest accessibility size, just across the
///   decksInline boundary;
/// - V4 XXXL, the largest size short of the accessibility ones;
/// - V5 AX5 with -probeNoInlineDecks, which keeps the card screens'
///   decksInline false at every size (AnkiReviewView, DueTodayView).
///
/// Lines: CPROBE-ISSUE per issue, and per run
/// `CPROBE <variant> run=<n> count=<issues> front=<front's Dynamic Type issues> ...`
/// with the front's frame before and after the audit. It never fails on an
/// audit issue.
final class A11yCardProbeUITests: XCTestCase {
    private var app: XCUIApplication!

    /// As AccessibilityUITests: everything but colour contrast.
    private static let audited: XCUIAccessibilityAuditType = XCUIAccessibilityAuditType.all.subtracting([.contrast])

    private static func size(_ category: String) -> [String] {
        ["-UIPreferredContentSizeCategoryName", category]
    }

    private static let variants: [String: (label: String, arguments: [String])] = [
        "V1": ("AX5", size("UICTContentSizeCategoryAccessibilityXXXL")),
        "V2": ("default", []),
        "V3": ("AXM", size("UICTContentSizeCategoryAccessibilityM")),
        "V4": ("XXXL", size("UICTContentSizeCategoryXXXL")),
        "V5": ("AX5-noInline", size("UICTContentSizeCategoryAccessibilityXXXL") + ["-probeNoInlineDecks"]),
    ]

    override func setUp() {
        continueAfterFailure = true
    }

    override func tearDown() {
        app?.terminate()
    }

    // named so XCTest runs them run by run: R1 V1-V5, then R2, then R3
    func testR1V1() throws { try probe("V1", run: 1) }
    func testR1V2() throws { try probe("V2", run: 1) }
    func testR1V3() throws { try probe("V3", run: 1) }
    func testR1V4() throws { try probe("V4", run: 1) }
    func testR1V5() throws { try probe("V5", run: 1) }
    func testR2V1() throws { try probe("V1", run: 2) }
    func testR2V2() throws { try probe("V2", run: 2) }
    func testR2V3() throws { try probe("V3", run: 2) }
    func testR2V4() throws { try probe("V4", run: 2) }
    func testR2V5() throws { try probe("V5", run: 2) }
    func testR3V1() throws { try probe("V1", run: 3) }
    func testR3V2() throws { try probe("V2", run: 3) }
    func testR3V3() throws { try probe("V3", run: 3) }
    func testR3V4() throws { try probe("V4", run: 3) }
    func testR3V5() throws { try probe("V5", run: 3) }

    /// One launch of `variant`, to the revealed card, and its audit.
    private func probe(_ variant: String, run: Int) throws {
        guard let spec = Self.variants[variant] else { return }
        let tag = "\(variant) run=\(run)"
        launch(spec.arguments)
        guard atLibrary(timeout: 20) else {
            print("CPROBE \(tag) count=-1 size=\(spec.label) (the library did not open)")
            XCTFail("the library did not open")
            return
        }
        let dock: String = element("dockList").exists ? "list" : "row"
        guard choose("cards"), openSet("anki") else {
            print("CPROBE \(tag) count=-1 size=\(spec.label) dock=\(dock) (the deck was not reached)")
            XCTFail("the example deck was not reached")
            return
        }
        // as the audit: Reveal tapped where it is (inline at the AX sizes,
        // in the bar below them)
        let reveal = app.buttons["Reveal"].firstMatch
        if reveal.waitForExistence(timeout: 6) { reveal.tap() }
        let front = element("ankiCardFront")
        let (still, reads, before) = settle(front)
        snap("cprobe-\(variant)-r\(run)-before")
        var count = 0
        var frontCount = 0
        var failure = ""
        do {
            try app.performAccessibilityAudit(for: Self.audited) { issue in
                count += 1
                let described: String = issue.element?.debugDescription ?? "nil"
                let onFront: Bool = issue.auditType == .dynamicType && described.contains("ankiCardFront")
                if onFront { frontCount += 1 }
                var line = "CPROBE-ISSUE \(variant) run=\(run) type=\(issue.auditType.rawValue) front=\(onFront) \(issue.compactDescription) | \(issue.detailedDescription) | element=\(described)"
                line = line.replacingOccurrences(of: "\n", with: " / ")
                print(String(line.prefix(500)))
                return true
            }
        } catch {
            failure = " error=\(String(describing: error).replacingOccurrences(of: "\n", with: " / "))"
        }
        let after: CGRect = front.exists ? front.frame : .null
        snap("cprobe-\(variant)-r\(run)-after")
        print("CPROBE \(tag) count=\(failure.isEmpty ? count : -1) front=\(frontCount) size=\(spec.label) dock=\(dock) still=\(still) reads=\(reads) before=\(text(before)) after=\(text(after))\(failure)")
    }

    // MARK: - Getting around (AccessibilityUITests' and LibraryDock's, copied)

    private func launch(_ arguments: [String]) {
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
        // not drop taps; the probe's switch, if any, last
        app.launchArguments += ["-personalBuild", "-stillSky"] + arguments
        app.launch()
        signIn()
    }

    /// The library is open: its dock as the one list button (the AX sizes)
    /// or as the row of tabs (below them).
    private func libraryShown() -> Bool {
        element("dockList").exists || element("dockCategory-questions").exists
    }

    private func atLibrary(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if libraryShown() { return true }
            usleep(500_000)
        }
        return libraryShown()
    }

    private func signIn() {
        let door = app.buttons["localSignIn"]
        let accept = app.buttons["acceptRecordingTerms"]
        let skipExam = app.buttons["examOnboardingSkip"]
        for _ in 0..<80 {
            if libraryShown() { return }
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

    /// A section: from the list the dock becomes at the AX sizes, or its tab
    /// on the row below them.
    private func choose(_ place: String) -> Bool {
        let list = element("dockList")
        guard list.exists else {
            let tab = element("dockCategory-\(place)")
            guard tab.exists || tab.waitForExistence(timeout: 5) else { return false }
            if tab.isHittable {
                tab.tap()
            } else {
                tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            sleep(2)
            return true
        }
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
        guard scrollToFind(row, down: 16, up: 24) else { return false }
        row.tap()
        sleep(3)
        return app.buttons["Reveal"].firstMatch.waitForExistence(timeout: 6)
    }

    /// Waits until `target` is there and its frame reads the same twice,
    /// half a second apart, at most eight reads (AccessibilityUITests'
    /// settle). Whether it stopped, the reads taken, and the last frame.
    private func settle(_ target: XCUIElement) -> (Bool, Int, CGRect) {
        _ = target.waitForExistence(timeout: 5)
        var last: CGRect = target.exists ? target.frame : .null
        var reads = 1
        var still = false
        while reads < 8 {
            usleep(500_000)
            let now: CGRect = target.exists ? target.frame : .null
            reads += 1
            if now == last && !now.isNull {
                still = true
                break
            }
            last = now
        }
        return (still, reads, last)
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

    /// Scrolls until `target` can be pressed: down the page up to `down`
    /// swipes, then back up up to `up`, then waits for it to be pressable.
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

    private func text(_ frame: CGRect) -> String {
        guard !frame.isNull else { return "gone" }
        return String(format: "{{%.1f,%.1f},{%.1f,%.1f}}", frame.minX, frame.minY, frame.width, frame.height)
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
