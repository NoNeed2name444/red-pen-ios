import XCTest

/// Turning the phone loses nothing (T0138): portrait, on its left side, on
/// its right side and back, and on a foldable through each posture the
/// screenshot launch can draw. After every turn the quiz is still on
/// question 3 with its answer chosen, the library on the same row, the
/// name sheet open with what was typed, New set's draft still typed, and
/// the mock paper on its part and question.
///
/// Run by iphone-duo.yml (jobs duo and iphones) and ios-preview.yml's
/// orientation pass; the result bundle goes into their artifacts.
final class RotationStateUITests: XCTestCase {
    private let turns: [UIDeviceOrientation] = [.portrait, .landscapeLeft, .landscapeRight, .portrait]

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
            XCTContext.runActivity(named: "\(what) after turning to \(turn.rawValue)") { _ in still() }
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
            let shown = names.filter { name in
                let row = app.staticTexts.matching(NSPredicate(format: "label == %@", name)).firstMatch
                return row.exists && row.isHittable
            }
            XCTAssertFalse(shown.isEmpty, "no set row on screen after scrolling")
            guard let row = shown.last else { continue }
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
            let field = app.textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 30), "the name sheet did not open")
            field.tap()
            field.typeText("Renal block")
            everyTurn("name sheet (\(posture ?? "phone"))", app) {
                let now = app.textFields.firstMatch
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

    // MARK: the mock paper on its part and question

    func testMockSittingKeepsItsPlace() {
        for posture in postures {
            let app = launch("mock-sitting", posture: posture)
            let part = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Part '")).firstMatch
            XCTAssertTrue(part.waitForExistence(timeout: 30), "the mock paper shows no Part")
            let partLabel = part.label
            let choice = answers(app).element(boundBy: 1)
            reach(choice, in: app)
            choice.tap()
            let chosen = choice.label
            everyTurn("mock sitting (\(posture ?? "phone"))", app) {
                XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", partLabel)).firstMatch.exists,
                              "left \(partLabel)")
                let same = answers(app).matching(NSPredicate(format: "label == %@", chosen)).firstMatch
                XCTAssertTrue(same.exists && same.isSelected, "the paper lost its answer: \(chosen)")
            }
            app.terminate()
        }
    }
}
