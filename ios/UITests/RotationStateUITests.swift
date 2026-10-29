import XCTest

/// Turning the phone loses nothing (T0138): portrait, on its left side, on
/// its right side and back, and on a foldable through each posture the
/// screenshot launch can draw. After every turn the quiz is still on
/// question 3 with its answer chosen, the library on the same row, the
/// name sheet open with what was typed, New set's draft still typed, and
/// the mock paper on its part and question.
///
/// Run by iphone-duo.yml (jobs duo and iphones) and ios-preview.yml's
/// orientation pass; the result bundle goes into their artifacts. On an iPad
/// (design-preview.yml's `ipad` part, `ROTATION_IPAD=1`, T0140) the turns
/// are all four ways up, upside down too, every target on screen is checked
/// for 44 points after each, and the window's width changes under the quiz
/// and the library (the rail becoming a bottom bar and back).
final class RotationStateUITests: XCTestCase {
    /// The iPad pass (`ROTATION_IPAD=1`).
    private var onIpad: Bool { ProcessInfo.processInfo.environment["ROTATION_IPAD"] == "1" }

    private var turns: [UIDeviceOrientation] {
        onIpad ? [.portrait, .landscapeLeft, .portraitUpsideDown, .landscapeRight, .portrait]
            : [.portrait, .landscapeLeft, .landscapeRight, .portrait]
    }

    /// The postures to go through: the foldable's three where the job says
    /// it is one (`ROTATION_POSTURES=folded,open,half`), else the phone's own.
    private var postures: [String?] {
        let named = ProcessInfo.processInfo.environment["ROTATION_POSTURES"] ?? ""
        let list = named.split(separator: ",").map { String($0) }
        return list.isEmpty ? [nil] : list
    }

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(_ screen: String, posture: String?) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiPreviewScreen", screen]
        if let posture { app.launchArguments += ["-uiPreviewPosture", posture] }
        app.launch()
        return app
    }

    /// Turns the device, waits for the layout to settle, and checks.
    private func everyTurn(_ what: String, _ app: XCUIApplication, _ still: () -> Void) {
        for turn in turns {
            XCUIDevice.shared.orientation = turn
            // the rotation's own animation, then a layout pass
            _ = app.wait(for: .runningForeground, timeout: 3)
            usleep(1_200_000)
            XCTContext.runActivity(named: "\(what) after turning to \(turn.rawValue)") { _ in
                still()
                if onIpad { targetsFit(app, "\(what), turn \(turn.rawValue)") }
            }
        }
    }

    /// Every button on screen that can be tapped is at least 44 points each
    /// way (half a point for rounding).
    private func targetsFit(_ app: XCUIApplication, _ what: String) {
        let buttons = app.buttons.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        for b in buttons {
            let f = b.frame
            XCTAssertGreaterThanOrEqual(min(f.width, f.height), 43.5,
                                        "\(what): '\(b.label)' (\(b.identifier)) is \(f.width) x \(f.height)")
        }
    }

    /// Scrolls until `element` can be tapped, a few swipes at most.
    private func reach(_ element: XCUIElement, in app: XCUIApplication) {
        var swipes = 0
        while !element.isHittable && swipes < 5 {
            app.swipeUp()
            swipes += 1
        }
    }

    private func answers(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Answer '"))
    }

    // MARK: the quiz on question 3, an answer chosen

    func testQuizKeepsItsPlace() {
        for posture in postures {
            let app = launch("quiz", posture: posture)
            for _ in 0..<2 {
                let first = answers(app).firstMatch
                XCTAssertTrue(first.waitForExistence(timeout: 20), "no answers on the quiz")
                reach(first, in: app)
                first.tap()
                let check = app.buttons["Check answer"]
                reach(check, in: app)
                check.tap()
                let next = app.buttons["Next question"]
                XCTAssertTrue(next.waitForExistence(timeout: 5), "no Next question after checking")
                reach(next, in: app)
                next.tap()
            }
            let third = app.staticTexts["Question 3 of 3"]
            XCTAssertTrue(third.waitForExistence(timeout: 5), "the quiz did not reach question 3")
            let choice = answers(app).element(boundBy: 1)
            reach(choice, in: app)
            choice.tap()
            let chosen = choice.label
            everyTurn("quiz (\(posture ?? "phone"))", app) {
                XCTAssertTrue(app.staticTexts["Question 3 of 3"].exists, "left question 3")
                let same = answers(app).matching(NSPredicate(format: "label == %@", chosen)).firstMatch
                XCTAssertTrue(same.exists, "the chosen answer is gone: \(chosen)")
                XCTAssertTrue(same.isSelected, "the answer is no longer chosen: \(chosen)")
            }
            app.terminate()
        }
    }

    // MARK: the library on the same row

    func testLibraryKeepsItsRow() {
        let names = ["Nephrology — glomerular disease", "Cardiology — heart failure", "Endocrinology — thyroid",
                     "Skills — venepuncture & catheterisation", "Lecture — acid–base physiology", "Example patients"]
        for posture in postures {
            let app = launch("library", posture: posture)
            let any = app.staticTexts.matching(NSPredicate(format: "label IN %@", names)).firstMatch
            XCTAssertTrue(any.waitForExistence(timeout: 30), "no sets on the library")
            app.swipeUp()
            usleep(800_000)
            // the top row on screen after the scroll: the one a turn must keep
            let shown: [(name: String, top: CGFloat)] = names.compactMap { name in
                let row = app.staticTexts.matching(NSPredicate(format: "label == %@", name)).firstMatch
                guard row.exists, row.isHittable else { return nil }
                return (name, row.frame.minY)
            }
            XCTAssertFalse(shown.isEmpty, "no set row on screen after scrolling")
            guard let row = shown.min(by: { $0.top < $1.top })?.name else { continue }
            everyTurn("library (\(posture ?? "phone"))", app) {
                let same = app.staticTexts.matching(NSPredicate(format: "label == %@", row)).firstMatch
                XCTAssertTrue(same.exists && same.isHittable, "the library lost its row: \(row)")
            }
            app.terminate()
        }
    }

    // MARK: an open sheet with its draft

    func testNameSheetKeepsItsDraft() {
        for posture in postures {
            let app = launch("name-sheet", posture: posture)
            // The sheet's own field by its name: the library under the sheet
            // keeps its search field in the tree, and that came first, so
            // the draft was typed at a field the sheet covered (App build
            // 39946874030: "Neither element nor any descendant has keyboard
            // focus" on librarySearch, with Folder name focused; T0151).
            let field = app.textFields["nameSheetField"]
            XCTAssertTrue(field.waitForExistence(timeout: 30), "the name sheet did not open")
            field.tap()
            field.typeText("Renal block")
            everyTurn("name sheet (\(posture ?? "phone"))", app) {
                let now = app.textFields["nameSheetField"]
                XCTAssertTrue(now.exists, "the name sheet closed")
                XCTAssertEqual(now.value as? String, "Renal block", "the typed name was lost")
            }
            app.terminate()
        }
    }

    // MARK: New set's draft

    func testNewSetKeepsItsDraft() {
        for posture in postures {
            let app = launch("new-material", posture: posture)
            let editor = app.textViews.firstMatch
            XCTAssertTrue(editor.waitForExistence(timeout: 30), "no text to type into on New set")
            reach(editor, in: app)
            editor.tap()
            let draft = "Which drug lowers potassium?"
            editor.typeText(draft)
            everyTurn("new set (\(posture ?? "phone"))", app) {
                let now = app.textViews.firstMatch
                XCTAssertTrue(now.exists, "New set's editor is gone")
                XCTAssertTrue(((now.value as? String) ?? "").contains(draft), "the draft was lost")
            }
            app.terminate()
        }
    }

    // MARK: the window decides, not the device

    /// Home at a 390-point window (`-uiPreviewWidth 390`) has the dock as a
    /// row along the bottom, never the rail, whether the simulator is an
    /// iPhone or an iPad: the jobs run this on both.
    func testPhoneWidthIsTheSameLayoutOnAnyDevice() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiPreviewScreen", "library", "-uiPreviewWidth", "390"]
        app.launch()
        let tabs = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'dockCategory-'"))
        XCTAssertTrue(tabs.firstMatch.waitForExistence(timeout: 30), "no dock at 390 points")
        let frames: [CGRect] = (0..<tabs.count).map { tabs.element(boundBy: $0).frame }
        XCTAssertGreaterThanOrEqual(frames.count, 2, "the dock has one tab")
        let rows: CGFloat = (frames.map(\.midY).max() ?? 0) - (frames.map(\.midY).min() ?? 0)
        let across: CGFloat = (frames.map(\.midX).max() ?? 0) - (frames.map(\.midX).min() ?? 0)
        XCTAssertLessThan(rows, 8, "the dock is not one row at 390 points")
        XCTAssertGreaterThan(across, rows, "the dock is a rail at 390 points")
        let model: String = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unknown"
        print("layout at 390 points on \(model): row of \(frames.count) tabs")
    }

    // MARK: a width change under the open screen (iPad)

    /// The window narrows from broad to a phone's width and back
    /// (`-uiPreviewWidth 1024 -uiPreviewWidthToggle 390`, the surround's
    /// previewWidthToggle): the dock goes from the rail to the bottom bar
    /// and back, and the library keeps its row.
    func testWidthChangeKeepsTheLibrary() throws {
        try XCTSkipUnless(onIpad, "the iPad pass only (ROTATION_IPAD=1): 1024 points is wider than a phone")
        let app = XCUIApplication()
        app.launchArguments += ["-uiPreviewScreen", "library", "-uiPreviewWidth", "1024", "-uiPreviewWidthToggle", "390"]
        app.launch()
        let tabs = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'dockCategory-'"))
        XCTAssertTrue(tabs.firstMatch.waitForExistence(timeout: 30), "no dock")
        func dockIsRow() -> Bool {
            let frames: [CGRect] = (0..<tabs.count).map { tabs.element(boundBy: $0).frame }
            let rows: CGFloat = (frames.map(\.midY).max() ?? 0) - (frames.map(\.midY).min() ?? 0)
            let across: CGFloat = (frames.map(\.midX).max() ?? 0) - (frames.map(\.midX).min() ?? 0)
            return rows < 8 && across > rows
        }
        XCTAssertFalse(dockIsRow(), "the dock is not the rail at 1024 points")
        let cards = app.buttons["dockCategory-cards"]
        XCTAssertTrue(cards.exists, "no Cards tab")
        cards.tap()
        let toggle = app.buttons["previewWidthToggle"]
        XCTAssertTrue(toggle.exists, "no width toggle on the surround")
        for (step, row) in [(1, true), (2, false)] {
            toggle.tap()
            usleep(1_200_000)
            XCTAssertEqual(dockIsRow(), row, "width change \(step): the dock is \(row ? "not the bottom bar" : "not the rail")")
            XCTAssertTrue(app.buttons["dockCategory-cards"].isSelected, "width change \(step): Cards is no longer chosen")
            targetsFit(app, "library, width change \(step)")
        }
    }

    /// The quiz on question 3 with its answer chosen, through the same
    /// width change.
    func testWidthChangeKeepsTheQuiz() throws {
        try XCTSkipUnless(onIpad, "the iPad pass only (ROTATION_IPAD=1): 1024 points is wider than a phone")
        let app = XCUIApplication()
        app.launchArguments += ["-uiPreviewScreen", "quiz", "-uiPreviewWidth", "1024", "-uiPreviewWidthToggle", "390"]
        app.launch()
        for _ in 0..<2 {
            let first = answers(app).firstMatch
            XCTAssertTrue(first.waitForExistence(timeout: 20), "no answers on the quiz")
            reach(first, in: app)
            first.tap()
            let check = app.buttons["Check answer"]
            reach(check, in: app)
            check.tap()
            let next = app.buttons["Next question"]
            XCTAssertTrue(next.waitForExistence(timeout: 5), "no Next question after checking")
            reach(next, in: app)
            next.tap()
        }
        XCTAssertTrue(app.staticTexts["Question 3 of 3"].waitForExistence(timeout: 5), "the quiz did not reach question 3")
        let choice = answers(app).element(boundBy: 1)
        reach(choice, in: app)
        choice.tap()
        let chosen = choice.label
        let toggle = app.buttons["previewWidthToggle"]
        XCTAssertTrue(toggle.exists, "no width toggle on the surround")
        for step in 1...2 {
            toggle.tap()
            usleep(1_200_000)
            XCTAssertTrue(app.staticTexts["Question 3 of 3"].exists, "width change \(step): left question 3")
            let same = answers(app).matching(NSPredicate(format: "label == %@", chosen)).firstMatch
            XCTAssertTrue(same.exists && same.isSelected, "width change \(step): the answer is no longer chosen")
            targetsFit(app, "quiz, width change \(step)")
        }
    }

    // MARK: the mock paper on its part and question

    func testMockSittingKeepsItsPlace() {
        for posture in postures {
            let app = launch("mock-sitting", posture: posture)
            // The paper's place: its part, its question, its answer. The
            // header is one element ("Question 1 of 8, 0 answered"), and
            // names the part ("Paper 1 of 2 · 0 answered") only when the
            // paper has more than one, never as "Part ": the mock-sitting
            // preview is PLAB 1, one part, named by its title in the bar
            // ("PLAB 1 paper"). This looked for "Part " and found none on a
            // paper that was there (App build 39946874030's recording,
            // T0151). The header's count of answers and its pace ("aim: Q2 by
            // now") change as the paper is sat, so the part and the question
            // are read out of it rather than the whole line compared.
            let title = app.navigationBars.staticTexts.firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 30), "the mock paper did not open")
            let paper: String = title.label
            let header = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH 'Question ' AND label CONTAINS ' of '")).firstMatch
            XCTAssertTrue(header.waitForExistence(timeout: 5), "the mock paper shows no question number")
            // the part's line, should the header's lines be elements of their own
            let partLine = app.staticTexts.matching(
                NSPredicate(format: "label MATCHES %@", "^.+ of [0-9]+ \u{00B7} .*")).firstMatch
            let place: () -> String = { [header, partLine].filter(\.exists).map(\.label).joined(separator: "\n") }
            let start: String = place()
            let questionLabel: String = Self.match(Self.questionNumber, in: start) ?? ""
            XCTAssertFalse(questionLabel.isEmpty, "the mock paper shows no question number: \(start)")
            // "Paper 1 of 2" where the paper has parts; else the paper is its one part
            let partLabel: String? = Self.match(Self.partName, in: start)
            let choice = answers(app).element(boundBy: 1)
            reach(choice, in: app)
            choice.tap()
            let chosen = choice.label
            everyTurn("mock sitting (\(posture ?? "phone"))", app) {
                let now: String = place()
                XCTAssertEqual(app.navigationBars.staticTexts.firstMatch.label, paper, "left \(paper)")
                if let partLabel {
                    XCTAssertEqual(Self.match(Self.partName, in: now), partLabel, "left \(partLabel): \(now)")
                }
                XCTAssertEqual(Self.match(Self.questionNumber, in: now), questionLabel, "left \(questionLabel): \(now)")
                let same = answers(app).matching(NSPredicate(format: "label == %@", chosen)).firstMatch
                XCTAssertTrue(same.exists && same.isSelected, "the paper lost its answer: \(chosen)")
            }
            app.terminate()
        }
    }

    /// The question number at the head of the mock's header.
    private static let questionNumber = "^Question [0-9]+ of [0-9]+"
    /// The part, where the paper has more than one: "Paper 1 of 2" before
    /// its " · ".
    private static let partName = "[^,\u{00B7}\\n]+ of [0-9]+(?= \u{00B7} )"

    /// The first match of `pattern` in `text`, trimmed; nil if none.
    private static func match(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let found = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(found.range, in: text) else { return nil }
        return text[range].trimmingCharacters(in: .whitespaces)
    }
}
