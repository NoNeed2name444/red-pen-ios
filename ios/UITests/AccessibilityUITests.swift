import XCTest

/// The App Store accessibility labels, checked on a simulator: the main
/// screens at the largest accessibility text size (AX5, "XXXL"), and
/// Xcode's own accessibility audit on each of them, at the default text
/// size and at AX5.
///
/// At AX5 the dock is one button over a list of sections (CategoryDock,
/// "dockList"), the tiles go one across, and the rating buttons one per row;
/// this walks through the library, a quiz, a card, Settings and the ward
/// round's exam plan that way, and checks each control it needs is there,
/// can be pressed and sits inside the window rather than off its edge.
/// At the default size the dock is the row of tabs (LibraryDock).
///
/// Found by the identifiers the other UI tests use (localSignIn,
/// acceptRecordingTerms, examOnboardingSkip, dockCategory-<place>,
/// setRow-mcq, setRow-anki, missionPlan, libraryMenu) plus dockList.
final class AccessibilityUITests: XCTestCase {
    private var app: XCUIApplication!

    /// The text size a test launches at.
    private enum TextSize {
        /// The simulator's own size, with no override.
        case standard
        /// AX5, the largest accessibility size.
        case largest
    }

    /// The size the running test launched at: it decides which dock the
    /// library has.
    private var size: TextSize = .largest

    /// UIKit's own override for the text size, read at launch.
    private static let largestText: [String] = ["-UIPreferredContentSizeCategoryName",
                                                "UICTContentSizeCategoryAccessibilityXXXL"]

    /// Everything the audit knows how to check, except colour contrast.
    ///
    /// Contrast is left out on purpose, not because it is ignored: every
    /// Ward text colour is promised a contrast against the surface it sits
    /// on, and WardPaletteTests checks those pairs on Linux, in light and
    /// dark. A pixel sample here would also catch the ECG grid lines behind
    /// the text, which are decoration.
    private static let audited: XCUIAccessibilityAuditType = XCUIAccessibilityAuditType.all.subtracting([.contrast])

    override func setUp() {
        continueAfterFailure = true
    }

    // MARK: - The largest text size

    func testMainScreensAtTheLargestTextSize() {
        launch(.largest)
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
        // at AX sizes the page is long: twelve swipes stopped on "Build a
        // session", the section above the Mixed tile (LibraryView's
        // sections; run 41848103900)
        guard reveal(tile, swipes: 24) else {
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
        // At the AX sizes the header and the deck stand in the card's page
        // (AnkiReviewView's decksInline), so Reveal can be under the fold:
        // it is scrolled to, as the ratings are (run 41949124483)
        _ = self.reveal(reveal)
        assertInWindow(reveal, "Reveal")
        reveal.tap()
        // Turned over, the question is still there to read: at AX5 the fixed
        // deck once covered the whole card (run 41876986518). Scrolled down
        // to Reveal, the page is drawn back to the question first. It can be
        // pressed where it is, and it stands above the ratings, not under
        // them.
        let front = element("ankiCardFront")
        XCTAssertTrue(front.waitForExistence(timeout: 5), "no card question after Reveal")
        revealAbove(front)
        assertInWindow(front, "the card's question")
        let again = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Again,")).firstMatch
        if front.exists && again.waitForExistence(timeout: 5) {
            XCTAssertLessThanOrEqual(front.frame.maxY, again.frame.minY,
                                     "the card's question is under the rating deck")
        }
        // each rating's label is its whole spoken line, "Again, back in 1
        // minute. I forgot it." (AnkiCardFace's spoken), so it is matched by
        // the name it starts with
        for title in ["Again", "Hard", "Good", "Easy"] {
            let named = NSPredicate(format: "label BEGINSWITH %@", "\(title),")
            let rating = app.buttons.matching(named).firstMatch
            XCTAssertTrue(rating.waitForExistence(timeout: 5), "no \(title) rating")
            // at AX5 the open back stands between the question and Again:
            // four slow swipes stopped one short of it (run 41949124483,
            // Hard pressable after a fifth); up to ten, stopping as soon as
            // it can be pressed
            _ = self.reveal(rating, swipes: 10)
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

    /// The ward round's Plan, to the exam plan.
    private func examPlan() {
        XCTAssertTrue(choose("questions"))
        let plan = element("missionPlan")
        guard plan.waitForExistence(timeout: 6), reveal(plan, clearOfSearch: true) else {
            // the Plan only shows once there is something to say
            return
        }
        assertInWindow(plan, "the ward round's Plan")
        plan.tap()
        XCTAssertTrue(app.navigationBars["Exam plan"].waitForExistence(timeout: 8), "the exam plan did not open")
        snap("exam-plan")
        goHome()
    }

    // MARK: - The audit

    /// The library, a quiz, a revealed card and Settings, at the default
    /// text size, audited for every type but contrast.
    ///
    /// The Dynamic Type check is run here, not at AX5: it looks for text
    /// that does not grow when the size goes up, so it needs a larger size
    /// to step to (see testAccessibilityAuditAtTheLargestTextSize).
    func testAccessibilityAuditOfMainScreens() throws {
        launch(.standard)
        XCTAssertTrue(LibraryDock(app: app).waitForLibrary(timeout: 20), "the library did not open")
        try auditMainScreens(Self.audited)
    }

    /// The same four screens at AX5, audited for every type but contrast
    /// and Dynamic Type.
    ///
    /// Dynamic Type is left out at this size only, and is checked at the
    /// default size (testAccessibilityAuditOfMainScreens) instead of being
    /// dropped. The evidence, probe run 42024778055 (T0203): the revealed
    /// card's front was flagged "Dynamic Type font sizes are partially
    /// unsupported" in 3 of 3 runs at AX5, and in 2 of 3 at AX5 with the
    /// card screens' inline decks held off, against 0 of 3 at the default
    /// size and 0 of 2 at AccessibilityM (and 1 of 3 at
    /// UICTContentSizeCategoryXXXL, the largest size short of the
    /// accessibility ones and not AX5, in the run that also flagged the
    /// back's lines). Its face is Font.custom relative
    /// to its text style, with no cap on it (T0198): at AX5 there is no
    /// larger size for the check to step to, so it cannot measure the text
    /// growing there. testMainScreensAtTheLargestTextSize still checks AX5's
    /// layout, control by control.
    func testAccessibilityAuditAtTheLargestTextSize() throws {
        launch(.largest)
        XCTAssertTrue(element("dockList").waitForExistence(timeout: 20), "the library did not open")
        try auditMainScreens(Self.audited.subtracting(.dynamicType))
    }

    /// The library, a quiz, the example card revealed and Settings, each
    /// audited for `types`. A screen it cannot reach is not audited, and
    /// says so in one AUDIT-SKIP line rather than failing the test.
    private func auditMainScreens(_ types: XCUIAccessibilityAuditType) throws {
        try audit("library", types)

        if !choose("questions") {
            skipped("quiz", "Questions could not be chosen from the dock")
        } else if !openSet("mcq") {
            skipped("quiz", "the example question set did not open")
        } else {
            try audit("quiz", types)
            backHome(after: "quiz")
        }
        if !choose("cards") {
            skipped("card", "Cards could not be chosen from the dock")
        } else if !openSet("anki") {
            skipped("card", "the example deck did not open")
        } else {
            let reveal = app.buttons["Reveal"].firstMatch
            if reveal.waitForExistence(timeout: 6) {
                reveal.tap()
            } else {
                skipped("card-back", "no Reveal button, so the card is audited unrevealed")
            }
            // the card's front flagged as partly Dynamic Type on some runs
            // and not others (T0198): audited only once the opened card
            // has stopped moving, its frame logged before and after
            let front = element("ankiCardFront")
            settle(front, "card front")
            try audit("card, revealed", types)
            print("CARD-SETTLE card front after audit frame=\(front.exists ? "\(front.frame)" : "gone")")
            backHome(after: "card")
        }
        let menu = element("libraryMenu")
        guard menu.waitForExistence(timeout: 6) else {
            skipped("settings", "no account menu (libraryMenu)")
            return
        }
        menu.tap()
        let named = NSPredicate(format: "label == %@", "Settings")
        let item = app.buttons.matching(named).firstMatch
        if !item.waitForExistence(timeout: 4) {
            skipped("settings", "no Settings item in the account menu")
        } else {
            item.tap()
            if app.navigationBars["Settings"].waitForExistence(timeout: 8) {
                try audit("settings", types)
            } else {
                skipped("settings", "the Settings bar did not show after its menu item")
            }
        }
        backHome(after: "settings")
    }

    /// One line in a11y.log for a screen the audit walk did not audit:
    /// `AUDIT-SKIP <size> <screen> <why>`. Not a failure.
    private func skipped(_ screen: String, _ why: String) {
        print("AUDIT-SKIP \(size == .largest ? "AX5" : "default") \(screen) \(why)")
    }

    /// Back to the library after `screen`, saying so when it could not get
    /// there, since the screens after it may then be skipped too.
    private func backHome(after screen: String) {
        if !goHome() {
            skipped(screen, "no way back to the library after it; the screens after it may be skipped")
        }
    }

    /// The screen being audited, for the AUDIT-NIL lines.
    private var auditing = ""
    /// That screen's tree, read once, at its first issue with no element.
    private var auditTree: (any XCUIElementSnapshot)?

    private func audit(_ screen: String, _ types: XCUIAccessibilityAuditType) throws {
        auditing = screen
        auditTree = nil
        try XCTContext.runActivity(named: "Audit: \(screen)") { _ in
            snap("audit-\(screen)")
            try app.performAccessibilityAudit(for: types) { [unowned self] issue in
                self.isBenign(issue)
            }
        }
    }

    /// An issue the audit could not tie to an element still fails (isBenign);
    /// this names its likely elements, at most 20 lines: for a small hit area,
    /// each control on the screen under 44 by 44 points; for clipped text,
    /// each text whose frame runs past its parent's; for any other type, both.
    /// `AUDIT-NIL <size> <screen> <what> id=<identifier> label=<label> frame=<frame>`.
    /// The two "Hit area is too small" and the "Text clipped" of run
    /// 42076348385 (library, revealed card) came with no element.
    private func nameNilElements(for issue: XCUIAccessibilityAuditIssue) {
        let size: String = self.size == .largest ? "AX5" : "default"
        let head = "AUDIT-NIL \(size) \(auditing)"
        if auditTree == nil { auditTree = try? app.snapshot() }
        guard let tree = auditTree else {
            print("\(head) no snapshot of the screen")
            return
        }
        let window: CGRect = app.windows.firstMatch.frame
        let wantsSmall: Bool = issue.auditType != .textClipped
        let wantsCut: Bool = issue.auditType != .hitRegion
        var lines: [String] = []
        func line(_ what: String, _ node: any XCUIElementSnapshot) -> String {
            let label: String = node.label.replacingOccurrences(of: "\n", with: " ")
            return "\(head) \(what) type=\(node.elementType.rawValue) id=\(node.identifier) label=\(label.prefix(80)) frame=\(node.frame)"
        }
        func walk(_ node: any XCUIElementSnapshot, parent: (any XCUIElementSnapshot)?) {
            guard lines.count < 20 else { return }
            let frame: CGRect = node.frame
            let shown: Bool = !frame.isEmpty && frame.intersects(window)
            if shown && wantsSmall && node.isEnabled && Self.pressable.contains(node.elementType)
                && (frame.width < 44 || frame.height < 44) {
                lines.append(line("small", node))
            }
            if shown && wantsCut && node.elementType == .staticText, let parent,
               !parent.frame.isEmpty, !parent.frame.insetBy(dx: -0.5, dy: -0.5).contains(frame) {
                lines.append(line("cut parent=\(parent.frame)", node))
            }
            for child in node.children { walk(child, parent: node) }
        }
        walk(tree, parent: nil)
        if lines.isEmpty { lines = ["\(head) nothing under 44 points or cut by its parent"] }
        for text in lines.prefix(20) { print(text) }
    }

    /// What a person presses, for AUDIT-NIL's sizes.
    private static let pressable: Set<XCUIElement.ElementType> = [
        .button, .link, .cell, .switch, .toggle, .slider, .stepper, .textField, .secureTextField,
        .searchField, .segmentedControl, .menuButton, .popUpButton, .tab, .disclosureTriangle,
        .incrementArrow, .decrementArrow,
    ]

    /// The issues left to the system, each for a reason. Everything else
    /// fails the test.
    private func isBenign(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        // every issue named with its element, before it is judged
        let line: String = "AUDIT-ISSUE compact=\(issue.compactDescription) detailed=\(issue.detailedDescription) type=\(issue.auditType) element=\(issue.element?.debugDescription ?? "nil")"
        print(line.replacingOccurrences(of: "\n", with: " | "))
        guard let element = issue.element else {
            // named in AUDIT-NIL lines, and still a failure
            nameNilElements(for: issue)
            return false
        }
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

    private func launch(_ size: TextSize) {
        self.size = size
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
        // the example sets to open, a still sky so a busy simulator does not
        // drop taps, and AX5's text size (none at the standard size: the
        // simulator's own)
        app.launchArguments += ["-personalBuild", "-stillSky"] + (size == .largest ? Self.largestText : [])
        app.launch()
        signIn()
    }

    /// The library's dock is there: the one list button at AX5, Questions'
    /// tab on the row at the standard size.
    private func dockShown() -> Bool {
        switch size {
        case .largest: return element("dockList").exists
        case .standard: return LibraryDock(app: app).row.exists
        }
    }

    /// The library is what is on screen, its dock there to be pressed. At
    /// the standard size as DesignTourUITests' atLibrary: the row's tab
    /// pressable and no learning sheet over it.
    private func atLibrary() -> Bool {
        switch size {
        case .largest:
            let list = element("dockList")
            return list.exists && list.isHittable
        case .standard:
            let row = LibraryDock(app: app).row
            return row.exists && row.isHittable && !app.buttons["learnDone"].exists
        }
    }

    private func signIn() {
        let door = app.buttons["localSignIn"]
        let accept = app.buttons["acceptRecordingTerms"]
        let skipExam = app.buttons["examOnboardingSkip"]
        for _ in 0..<80 {
            if dockShown() { return }
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

    /// A section: from the list the dock becomes at AX sizes, or by its tab
    /// on the row at the standard size.
    private func choose(_ place: String) -> Bool {
        guard size == .largest else {
            let chosen: Bool = LibraryDock(app: app).choose(place, timeout: 8, press: { self.press($0) })
            // the section a moment to come in
            if chosen { sleep(2) }
            return chosen
        }
        let list = element("dockList")
        guard list.exists || list.waitForExistence(timeout: 8) else { return false }
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
        switch size {
        case .largest: return !element("dockList").exists
        case .standard: return !atLibrary()
        }
    }

    /// Back to the library: Cancel or Done on a sheet, Back on a pushed page.
    /// True when the library is on screen at the end.
    @discardableResult
    private func goHome() -> Bool {
        for _ in 0..<6 {
            if atLibrary() { return true }
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
        return atLibrary()
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

    /// Waits until `target` is there and its frame reads the same twice,
    /// half a second apart, at most eight reads; logs what it found, so a
    /// run shows whether the screen was still moving.
    private func settle(_ target: XCUIElement, _ name: String) {
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
        print("CARD-SETTLE \(name) still=\(still) reads=\(reads) frame=\(last)")
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

    /// A tap on `target`, at its middle when XCTest does not call it
    /// hittable but that middle is in the window (the dock's raised glass;
    /// DesignTourUITests' press). False when it is not there to press.
    private func press(_ target: XCUIElement) -> Bool {
        guard target.exists else { return false }
        if target.isHittable {
            target.tap()
            return true
        }
        let frame: CGRect = target.frame
        let window: CGRect = app.windows.firstMatch.frame
        guard !frame.isEmpty, window.contains(CGPoint(x: frame.midX, y: frame.midY)) else { return false }
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return true
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
