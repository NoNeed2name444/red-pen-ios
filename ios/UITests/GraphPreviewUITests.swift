import XCTest

/// Pictures of the 3D idea map for the owner to look at before trying the
/// app: the Universe at rest (the whole map), a moment later (the orbits
/// moving on), in landscape, while a star is being dragged with its system,
/// flown in to one star system, the legend, and each single look on its
/// own; then the same for the Neurons theme (`-graphPreviewTheme neurons`);
/// and bodies dying
/// as they are deleted (`-graphPreviewRemove`), in each theme; touching
/// the map (a note's and a folder's peek card, Open, a body's options, a
/// hold-drag), name pills over bright bodies, and the Link length.
/// Run on its own by the "Design preview" workflow.
final class GraphPreviewUITests: XCTestCase {
    func testGraphAtRest() {
        let app = XCUIApplication()
        app.keepTraceOffConsole()
        app.launchArguments += ["-graphPreview"]
        app.launch()
        let space = app.otherElements["graph3D"]
        XCTAssertTrue(space.waitForExistence(timeout: 30), "the 3D map didn't open")
        sleep(3)
        // VoiceOver's value is the Universe's summary
        let summary: String = (space.value as? String) ?? ""
        XCTAssertTrue(summary.contains("galaxies"), "no Universe summary: \(summary)")
        snap(app, "1-at-rest")
        sleep(2)
        snap(app, "2-two-seconds-later")
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        snap(app, "3-landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    func testGraphWhileDragging() {
        let app = XCUIApplication()
        app.keepTraceOffConsole()
        app.launchArguments += ["-graphPreview", "-graphPreviewDrag"]
        app.launch()
        XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
        // the app drags the busiest star (Inguinal) itself after a second;
        // catch it mid-move, its planets and companion star following
        usleep(1_600_000)
        snap(app, "4-dragging")
        usleep(700_000)
        snap(app, "5-dragging-later")
        sleep(3)
        snap(app, "6-after-release")
    }

    /// Every note in one style at a time, for a picture of each (the
    /// preview's own graph mixes them all).
    func testEachStyle() {
        let styles: [String] = ["blackHole", "sun", "rocky", "gasGiant", "pulsar", "comet"]
        for (k, style) in styles.enumerated() {
            let app = XCUIApplication()
            app.keepTraceOffConsole()
            app.launchArguments += ["-graphPreview", "-graphPreviewStyle", style]
            app.launch()
            XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
            sleep(3)
            snap(app, "7-style-\(k + 1)-\(style)")
            app.terminate()
        }
    }

    /// Each style's body close up (`-graphPreviewCloseUp`), at rest and
    /// while it is carried up the screen with the camera following, so its
    /// detail - and how it moves - can be judged.
    func testBodyCloseUps() {
        let styles: [String] = ["blackHole", "sun", "rocky", "gasGiant", "pulsar", "comet"]
        for (k, style) in styles.enumerated() {
            for dragged in [false, true] {
                let app = XCUIApplication()
                app.keepTraceOffConsole()
                app.launchArguments += ["-graphPreview", "-graphPreviewStyle", style, "-graphPreviewCloseUp"]
                if dragged { app.launchArguments += ["-graphPreviewDrag"] }
                app.launch()
                XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30),
                              "the 3D map didn't open")
                // framed at one second; carried from one and a half; the
                // first launch of a style also compiles its shaders
                usleep(dragged ? 4_500_000 : 5_000_000)
                snap(app, "8-body-\(k + 1)-\(style)-\(dragged ? "dragged" : "rest")")
                app.terminate()
            }
        }
    }

    /// Double-tapped Inguinal, as the app does it itself: the camera flown
    /// in to its system - Inguinal, its planets and the orange Anatomy
    /// companion - with its name pill held.
    func testUniverseFlyIn() {
        let app = XCUIApplication()
        app.keepTraceOffConsole()
        app.launchArguments += ["-graphPreview", "-graphPreviewFly", "Inguinal"]
        app.launch()
        XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
        sleep(3)
        snap(app, "8-fly-inguinal")
    }

    /// "How your universe is built", opened by the app a second after the space.
    func testUniverseLegend() {
        let app = XCUIApplication()
        app.keepTraceOffConsole()
        app.launchArguments += ["-graphPreview", "-graphPreviewLegend"]
        app.launch()
        XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
        let title = app.staticTexts["How your universe is built"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "the legend didn't open")
        sleep(1)
        snap(app, "9-legend")
    }

    /// The Look menu offers the Universe and, while it is chosen, the
    /// legend.
    func testLookMenu() {
        let app = XCUIApplication()
        app.keepTraceOffConsole()
        app.launchArguments += ["-graphPreview"]
        app.launch()
        XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
        let look = app.buttons["Look"]
        XCTAssertTrue(look.waitForExistence(timeout: 10), "no Look tool")
        look.tap()
        XCTAssertTrue(app.buttons["Universe"].waitForExistence(timeout: 5), "no Universe in the Look menu")
        let legend = app.buttons["How your universe is built"]
        XCTAssertTrue(legend.waitForExistence(timeout: 5), "no legend in the Look menu")
        legend.tap()
        XCTAssertTrue(app.staticTexts["How your universe is built"].waitForExistence(timeout: 10), "the legend didn't open")
        sleep(1)
        snap(app, "10-look-menu-legend")
    }

    // MARK: the Neurons theme

    /// The whole map as cells, all closed: Cardiology and Examples as two
    /// big cells with their dendrites, an axon growing out of one to a
    /// synapse on the other where their notes link, and the two loose
    /// notes as free cells; impulses running along the axons at their own
    /// random times - so the second picture differs from the first - and
    /// in landscape.
    func testNeuronsAtRest() {
        let app = XCUIApplication()
        app.keepTraceOffConsole()
        app.launchArguments += ["-graphPreview", "-graphPreviewTheme", "neurons"]
        app.launch()
        let space = app.otherElements["graph3D"]
        XCTAssertTrue(space.waitForExistence(timeout: 30), "the 3D map didn't open")
        sleep(3)
        let summary: String = (space.value as? String) ?? ""
        XCTAssertTrue(summary.contains("cell"), "no Neurons summary: \(summary)")
        snap(app, "11-neurons-at-rest")
        sleep(2)
        snap(app, "12-neurons-two-seconds-later")
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        snap(app, "13-neurons-landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    /// Double-tapped Examples, as the app does it itself: flown in, the
    /// cell opens - its nucleus fading back - and what it holds grows out
    /// inside it: Inguinal and Femoral as parts, its notes as vesicles and
    /// granules.
    func testNeuronsFlyIn() {
        let app = XCUIApplication()
        app.keepTraceOffConsole()
        app.launchArguments += ["-graphPreview", "-graphPreviewTheme", "neurons", "-graphPreviewFly", "Examples"]
        app.launch()
        XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
        sleep(3)
        snap(app, "14-neurons-fly-examples")
        sleep(2)
        snap(app, "15-neurons-fly-examples-later")
    }

    /// Opening in turn, as a user flies in deeper: Examples opens, then
    /// Inguinal, a part inside it, opens in its place - Anatomy (a smaller
    /// part) and Inguinal's notes growing out inside it.
    func testNeuronsOpenInTurn() {
        let app = XCUIApplication()
        app.keepTraceOffConsole()
        app.launchArguments += ["-graphPreview", "-graphPreviewTheme", "neurons", "-graphPreviewFly", "Examples,Inguinal"]
        app.launch()
        XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
        sleep(3)
        snap(app, "20-neurons-open-examples")
        sleep(5)
        snap(app, "21-neurons-open-inguinal")
        sleep(2)
        snap(app, "22-neurons-open-inguinal-later")
    }

    /// The busiest relay (Inguinal) picked up and carried: its cells and
    /// Anatomy, the relay beyond it, follow.
    func testNeuronsWhileDragging() {
        let app = XCUIApplication()
        app.keepTraceOffConsole()
        app.launchArguments += ["-graphPreview", "-graphPreviewTheme", "neurons", "-graphPreviewDrag"]
        app.launch()
        XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
        usleep(1_600_000)
        snap(app, "16-neurons-dragging")
        sleep(3)
        snap(app, "17-neurons-after-release")
    }

    /// "How your network is built", opened by the app a second after the map.
    func testNeuronsLegend() {
        let app = XCUIApplication()
        app.keepTraceOffConsole()
        app.launchArguments += ["-graphPreview", "-graphPreviewTheme", "neurons", "-graphPreviewLegend"]
        app.launch()
        XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
        XCTAssertTrue(app.staticTexts["How your network is built"].waitForExistence(timeout: 10), "the legend didn't open")
        sleep(1)
        snap(app, "18-neurons-legend")
    }

    /// The Look menu offers the themes, and in Neurons its legend.
    func testNeuronsLookMenu() {
        let app = XCUIApplication()
        app.keepTraceOffConsole()
        app.launchArguments += ["-graphPreview", "-graphPreviewTheme", "neurons"]
        app.launch()
        XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
        let look = app.buttons["Look"]
        XCTAssertTrue(look.waitForExistence(timeout: 10), "no Look tool")
        look.tap()
        XCTAssertTrue(app.buttons["Space"].waitForExistence(timeout: 5), "no Space theme in the Look menu")
        XCTAssertTrue(app.buttons["Neurons"].exists, "no Neurons theme in the Look menu")
        let legend = app.buttons["How your network is built"]
        XCTAssertTrue(legend.waitForExistence(timeout: 5), "no Neurons legend in the Look menu")
        snap(app, "19-neurons-look-menu")
    }

    // MARK: bodies dying

    /// Deleted from the map (`-graphPreviewRemove`: the Femoral and Anatomy
    /// folders, and BNP, Murmurs, Troponin, the bridging idea and a loose
    /// note, three seconds in), in each theme: pictures early and midway
    /// through their deaths - in Space each by its own physics (tidal
    /// disruption, stripped atmosphere, planetary nebula, the pulsar
    /// spinning down, the comet breaking up), in Neurons apoptosis - and
    /// after, the map carrying on.
    func testRemovalInEachTheme() {
        let themes: [String] = ["space", "neurons"]
        for (k, theme) in themes.enumerated() {
            let app = XCUIApplication()
            app.keepTraceOffConsole()
            app.launchArguments += ["-graphPreview", "-graphPreviewTheme", theme, "-graphPreviewRemove"]
            app.launch()
            XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
            // deleted at 3 s; the new scene is up a moment later
            usleep(3_500_000)
            snap(app, "30-\(k + 1)-\(theme)-dying-early")
            usleep(600_000)
            snap(app, "30-\(k + 1)-\(theme)-dying-midway")
            usleep(700_000)
            snap(app, "30-\(k + 1)-\(theme)-dying-late")
            sleep(2)
            snap(app, "30-\(k + 1)-\(theme)-after")
            app.terminate()
        }
    }

    /// A black hole evaporating (Space) and a whole cell dying (Neurons):
    /// the Cardiology folder deleted.
    func testRemovingATopFolder() {
        for (k, theme) in ["space", "neurons"].enumerated() {
            let app = XCUIApplication()
            app.keepTraceOffConsole()
            app.launchArguments += ["-graphPreview", "-graphPreviewTheme", theme, "-graphPreviewRemove", "Cardiology"]
            app.launch()
            XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
            usleep(4_000_000)
            snap(app, "31-\(k + 1)-\(theme)-top-folder-dying")
            usleep(900_000)
            snap(app, "31-\(k + 1)-\(theme)-top-folder-dying-later")
            app.terminate()
        }
    }

    // MARK: touching the map

    /// Tap a note: its peek card slides up (title, what it is in the theme,
    /// its first lines, its links as chips); tap Open: the note grows out
    /// of the card. In each theme.
    func testTapNoteThenOpen() {
        let themes: [(String, String)] = [("space", "Heart failure"), ("neurons", "Heart failure")]
        for (k, pair) in themes.enumerated() {
            let app = XCUIApplication()
            app.keepTraceOffConsole()
            app.launchArguments += ["-graphPreview", "-graphPreviewTheme", pair.0, "-graphPreviewSelect", pair.1]
            app.launch()
            XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
            let card = app.otherElements["graphPeekCard"]
            XCTAssertTrue(card.waitForExistence(timeout: 15), "no peek card in \(pair.0)")
            XCTAssertTrue(app.staticTexts[pair.1].waitForExistence(timeout: 5), "the card doesn't name it")
            sleep(1)
            snap(app, "40-\(k + 1)-\(pair.0)-peek-note")
            let open = app.buttons["graphPeekOpen"]
            XCTAssertTrue(open.waitForExistence(timeout: 5), "no Open on the card")
            open.tap()
            sleep(2)
            snap(app, "41-\(k + 1)-\(pair.0)-opened-note")
            app.terminate()
        }
    }

    /// Tap a folder: its card - counts, latest notes, Open folder and Fly in.
    func testTapFolder() {
        for (k, theme) in ["space", "neurons"].enumerated() {
            let app = XCUIApplication()
            app.keepTraceOffConsole()
            app.launchArguments += ["-graphPreview", "-graphPreviewTheme", theme, "-graphPreviewSelect", "Inguinal"]
            app.launch()
            XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
            XCTAssertTrue(app.otherElements["graphPeekCard"].waitForExistence(timeout: 15), "no folder card")
            XCTAssertTrue(app.buttons["Fly in"].waitForExistence(timeout: 5), "no Fly in on a folder's card")
            sleep(1)
            snap(app, "42-\(k + 1)-\(theme)-peek-folder")
            app.terminate()
        }
    }

    /// Hold a body still: its options beside it. In Neurons a note is only
    /// on the map once its cell is open, so the camera flies in to
    /// Cardiology first.
    func testHoldForOptions() {
        for (k, theme) in ["space", "neurons"].enumerated() {
            let app = XCUIApplication()
            app.keepTraceOffConsole()
            app.launchArguments += ["-graphPreview", "-graphPreviewTheme", theme, "-graphPreviewHold", "Heart failure"]
            if theme == "neurons" { app.launchArguments += ["-graphPreviewFly", "Cardiology"] }
            app.launch()
            XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
            // the scene, then the app's own hold: a loaded runner takes its time
            XCTAssertTrue(app.otherElements["graphNodeMenu"].waitForExistence(timeout: 45), "no options in \(theme)")
            XCTAssertTrue(app.buttons["Link to\u{2026}"].exists && app.buttons["Delete"].exists,
                          "an option is missing in \(theme)")
            snap(app, "43-\(k + 1)-\(theme)-hold-options")
            app.terminate()
        }
    }

    /// Hold and drag a body: picked up after a quarter second, its links
    /// resting and its system following (the app drags it itself, as in
    /// testGraphWhileDragging).
    func testHoldDrag() {
        for (k, theme) in ["space", "neurons"].enumerated() {
            let app = XCUIApplication()
            app.keepTraceOffConsole()
            app.launchArguments += ["-graphPreview", "-graphPreviewTheme", theme, "-graphPreviewDrag"]
            app.launch()
            XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
            usleep(1_700_000)
            snap(app, "44-\(k + 1)-\(theme)-hold-drag")
            app.terminate()
        }
    }

    /// Name pills over bright bodies stay readable: flown in to a system
    /// with a body chosen whose name sits over its star or its region's
    /// glowing soma.
    func testLabelsOverBrightBodies() {
        let cases: [(String, String, String)] = [("space", "Inguinal", "Inguinal canal"),
                                                 ("neurons", "Cardiology", "Heart failure")]
        for (k, entry) in cases.enumerated() {
            let app = XCUIApplication()
            app.keepTraceOffConsole()
            app.launchArguments += ["-graphPreview", "-graphPreviewTheme", entry.0, "-graphPreviewFly", entry.1,
                                    "-graphPreviewSelect", entry.2]
            app.launch()
            XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
            XCTAssertTrue(app.otherElements["graphPeekCard"].waitForExistence(timeout: 20), "nothing chosen")
            sleep(1)
            snap(app, "45-\(k + 1)-\(entry.0)-label-over-bright")
            app.terminate()
        }
    }

    /// The Look menu's Link length bar, and the map planned longer.
    func testLinkLength() {
        for (k, theme) in ["space", "neurons"].enumerated() {
            let app = XCUIApplication()
            app.keepTraceOffConsole()
            app.launchArguments += ["-graphPreview", "-graphPreviewTheme", theme, "-graphPreviewLinkLength", "1.8"]
            app.launch()
            XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
            sleep(3)
            snap(app, "46-\(k + 1)-\(theme)-links-longer")
            let look = app.buttons["Look"]
            XCTAssertTrue(look.waitForExistence(timeout: 10), "no Look tool")
            look.tap()
            let item = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Link length")).firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5), "no Link length in the Look menu")
            item.tap()
            XCTAssertTrue(app.otherElements["linkLengthBar"].waitForExistence(timeout: 5), "no Link length bar")
            snap(app, "47-\(k + 1)-\(theme)-link-length-bar")
            app.terminate()
        }
    }

    /// Lines: Straight (`-ideasLines straight`, for this run only, so the
    /// owner's choice is untouched): every link a direct segment in each
    /// theme of the 3D map - no arches or black-hole curls, no meander, no
    /// routed traces - with the Look menu's Lines section;
    /// then the 2D board's straight connectors, reached through the
    /// personal build's Ideas example (13 linked notes).
    func testStraightLines() {
        for (k, theme) in ["space", "neurons"].enumerated() {
            let app = XCUIApplication()
            app.keepTraceOffConsole()
            app.launchArguments += ["-graphPreview", "-graphPreviewTheme", theme,
                                    "-ideasLines", "straight"]
            app.launch()
            XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
            sleep(3)
            snap(app, "48-\(k + 1)-\(theme)-straight-lines")
            if k == 0 {
                let look = app.buttons["Look"]
                XCTAssertTrue(look.waitForExistence(timeout: 10), "no Look tool")
                look.tap()
                XCTAssertTrue(app.buttons["Straight"].waitForExistence(timeout: 5), "no Lines in the Look menu")
                XCTAssertTrue(app.buttons["Curved"].exists, "no Curved in the Look menu")
                snap(app, "48-4-look-menu-lines")
            }
            app.terminate()
        }

        // the board: signed in locally, the Ideas example, Board
        let app = XCUIApplication()
        app.keepTraceOffConsole()
        app.launchArguments += ["-personalBuild", "-ideasLines", "straight"]
        app.launch()
        func find(_ id: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: id).firstMatch
        }
        func press(_ target: XCUIElement) -> Bool {
            guard target.exists else { return false }
            if target.isHittable {
                target.tap()
                return true
            }
            target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return true
        }
        // the dock as its full row
        let dock = LibraryDock(app: app).row
        for _ in 0..<80 where !dock.exists {
            let door = app.buttons["localSignIn"]
            let accept = app.buttons["acceptRecordingTerms"]
            let skipExam = app.buttons["examOnboardingSkip"]
            if door.exists && door.isHittable {
                door.tap()
            } else if accept.exists && accept.isEnabled && accept.isHittable {
                accept.tap()
            } else if skipExam.exists && skipExam.isHittable {
                skipExam.tap()
            }
            usleep(500_000)
        }
        XCTAssertTrue(dock.waitForExistence(timeout: 20), "the library didn't open")
        let banner = find("examplesBanner")
        for _ in 0..<16 where !(banner.exists && banner.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(press(banner), "no examples banner")
        let example = find("example-ideas")
        XCTAssertTrue(example.waitForExistence(timeout: 8) && press(example), "no Ideas example")
        let board = find("ideasMode-board")
        if !board.waitForExistence(timeout: 4) {
            _ = press(find("ideasSwitcherToggle"))
        }
        XCTAssertTrue(board.waitForExistence(timeout: 4) && press(board), "no Board in the switcher")
        sleep(2)
        snap(app, "49-1-board-straight-lines")
        let look = app.buttons["Look"]
        if look.waitForExistence(timeout: 5) && press(look) {
            sleep(1)
            snap(app, "49-2-board-look-menu")
        }
    }

    // MARK: the island's motions

    /// The quiz bottom deck: folded and unfolded twice, then the question
    /// scrolled up and back so the scroll edge's line appears and goes.
    func testIslandDeckFold() throws {
        let app = XCUIApplication()
        app.keepTraceOffConsole()
        app.launchArguments += ["-uiPreviewScreen", "quiz"]
        app.launch()

        let fold = app.buttons["studyBarFold"]
        guard fold.waitForExistence(timeout: 30) else {
            throw XCTSkip("no study bar fold button on quiz")
        }

        // 1. Start with the deck open, at rest.
        usleep(1_500_000)

        // 2. Fold it with its fold button, then unfold it.
        press(fold)
        usleep(1_500_000)
        press(fold)
        usleep(1_500_000)

        // 3. Fold and unfold it once more.
        press(fold)
        usleep(1_500_000)
        press(fold)
        usleep(1_500_000)

        // 4. Scroll the question up and back, so the scroll edge's line appears and goes.
        app.swipeUp(velocity: .slow)
        usleep(1_500_000)
        app.swipeDown(velocity: .slow)
        usleep(1_500_000)
    }

    /// On a page with an open deck, push another page; swipe back interactively;
    /// push again, swipe back halfway and let go (a cancelled back).
    func testIslandPushAndBack() throws {
        let app = XCUIApplication()
        app.keepTraceOffConsole()
        app.launchArguments += ["-uiPreviewScreen", "anki-quizable"]
        app.launch()

        let fold = app.buttons["studyBarFold"]
        guard fold.waitForExistence(timeout: 30) else {
            throw XCTSkip("no study bar on anki-quizable")
        }
        let more = app.buttons["studyMore"]
        guard more.waitForExistence(timeout: 10) else {
            throw XCTSkip("no studyMore button")
        }

        // Start with the deck open, at rest.
        usleep(1_500_000)

        // Push another page (MCQQuizView from More -> Quiz me)
        press(more)
        let quizMe = app.buttons["quizMe"]
        let quizTarget = quizMe.waitForExistence(timeout: 5) ? quizMe : app.menuItems["quizMe"]
        if quizTarget.waitForExistence(timeout: 3) {
            press(quizTarget)
        } else {
            let byLabel = app.buttons["Quiz me"].exists ? app.buttons["Quiz me"] : app.menuItems["Quiz me"]
            guard byLabel.waitForExistence(timeout: 5) else {
                throw XCTSkip("no Quiz me option in More menu")
            }
            press(byLabel)
        }

        let patientHeader = NSPredicate(format: "label MATCHES %@", "Patient [0-9]+ of [0-9]+.*")
        let quizHeader = app.descendants(matching: .any).matching(patientHeader).firstMatch
        XCTAssertTrue(quizHeader.waitForExistence(timeout: 10), "pushed quiz view didn't appear")
        usleep(1_500_000)

        // 1. Go back with an interactive swipe from the left edge, not the back button:
        // an XCUICoordinate press and drag from x 0.01 to x 0.8, slowly (about 0.6 s).
        let window = app.windows.firstMatch
        let leftEdge = window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let backTarget = window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        leftEdge.press(forDuration: 0.05, thenDragTo: backTarget, withVelocity: .slow, thenHoldForDuration: 0.1)
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: quizHeader)
        XCTAssertTrue(XCTWaiter.wait(for: [gone], timeout: 10) == .completed, "did not return to anki card review")
        usleep(1_500_000)

        // 2. Push again, swipe back, stop halfway and let go, so the push stays (a cancelled back).
        XCTAssertTrue(more.waitForExistence(timeout: 5), "no studyMore button after returning")
        press(more)
        let quizMeAgain = app.buttons["quizMe"]
        let quizTargetAgain = quizMeAgain.waitForExistence(timeout: 5) ? quizMeAgain : app.menuItems["quizMe"]
        if quizTargetAgain.waitForExistence(timeout: 3) {
            press(quizTargetAgain)
        } else {
            let byLabel = app.buttons["Quiz me"].exists ? app.buttons["Quiz me"] : app.menuItems["Quiz me"]
            guard byLabel.waitForExistence(timeout: 5) else {
                throw XCTSkip("no Quiz me option in More menu on second push")
            }
            press(byLabel)
        }
        XCTAssertTrue(quizHeader.waitForExistence(timeout: 10), "second pushed quiz view didn't appear")
        usleep(1_500_000)

        let halfTarget = window.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
        leftEdge.press(forDuration: 0.05, thenDragTo: halfTarget, withVelocity: .slow, thenHoldForDuration: 0.1)
        usleep(1_500_000)
        XCTAssertTrue(quizHeader.exists, "pushed quiz view should remain after cancelled back")
    }

    @discardableResult
    private func press(_ target: XCUIElement) -> Bool {
        guard target.exists else { return false }
        if target.isHittable {
            target.tap()
            return true
        }
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return true
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = uprightShot()
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
