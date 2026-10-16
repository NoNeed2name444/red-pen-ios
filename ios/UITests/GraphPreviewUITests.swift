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
            app.launchArguments += ["-graphPreview", "-graphPreviewStyle", style]
            app.launch()
            XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
            sleep(3)
            snap(app, "7-style-\(k + 1)-\(style)")
            app.terminate()
        }
    }

    /// Double-tapped Inguinal, as the app does it itself: the camera flown
    /// in to its system - Inguinal, its planets and the orange Anatomy
    /// companion - with its name pill held.
    func testUniverseFlyIn() {
        let app = XCUIApplication()
        app.launchArguments += ["-graphPreview", "-graphPreviewFly", "Inguinal"]
        app.launch()
        XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
        sleep(3)
        snap(app, "8-fly-inguinal")
    }

    /// "How your universe is built", opened by the app a second after the space.
    func testUniverseLegend() {
        let app = XCUIApplication()
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
        let dock = find("dockCategory-questions")
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

    // MARK: the depth fade (plan 4f)

    /// The depth fade in each SceneKit theme, on and off (`-graphDepthOff`),
    /// as pose-matched pairs: the map frozen (`-graphFreeze`, so the camera
    /// is the same in both), the whole map and flown in close (Neurons:
    /// Examples opened; Space: Inguinal's system) on High, the whole map on
    /// Smooth. What is far dissolves into the theme's background and nothing
    /// past the band's end is drawn. Stills are named
    /// `70-<theme>-<tier>-<view>-<on|off>`; with them goes `75-body-frames`
    /// (JSON, in points) for tools/depth_crops.py: for each still the window's
    /// size, the meter's frame and line, and a 44-point square round each
    /// body drawn on the screen.
    func testDepthBeforeAfter() {
        var stills: [String: Any] = [:]
        defer { attachFrames(stills) }
        for pair in Self.depthThemes {
            for level in ["High", "Smooth"] {
                for near in [false, true] where level == "High" || !near {
                    for off in [false, true] {
                        let name = "70-\(pair.0)-\(level.lowercased())-\(near ? "near" : "whole")-\(off ? "off" : "on")"
                        let app = depthApp(pair.0, fly: near ? pair.1 : nil, off: off,
                                           more: ["-stillSky", "-graphFreeze", "-graphDepthMeter", "-graphics" + level])
                        sleep(6)
                        snap(app, name)
                        stills[name] = stillRecord(app)
                        app.terminate()
                    }
                }
            }
        }
    }

    /// The map as the owner sees it, moving on its own (no `-graphFreeze`,
    /// and no `-stillSky`, as the file's other lively pictures), in each
    /// theme, whole.
    func testDepthLively() {
        for pair in Self.depthThemes {
            let app = depthApp(pair.0, fly: nil, off: false, more: ["-graphicsHigh"])
            sleep(6)
            snap(app, "71-\(pair.0)-whole")
            app.terminate()
        }
    }

    /// Slow turns flown in close, for the recording: what comes forward
    /// sharpens, what goes back dissolves, with no popping.
    func testDepthTurnNeurons() {
        let app = depthApp("neurons", fly: "Examples", off: false)
        sleep(6)
        snap(app, "61-1-neurons-turn-start")
        slowTurn(app, times: 3)
        sleep(1)
        snap(app, "61-2-neurons-turn-end")
    }

    func testDepthTurnSpace() {
        let app = depthApp("space", fly: "Inguinal", off: false)
        sleep(6)
        snap(app, "62-1-space-turn-start")
        slowTurn(app, times: 3)
        sleep(1)
        snap(app, "62-2-space-turn-end")
    }

    /// The numbers: frame times (the meter, `-graphDepthMeter`) in each
    /// theme at each Graphics level, whole and flown in close, on and off,
    /// each take after one slow turn from the default (tilted) view. Space
    /// has three takes of each, alternating on and off, Neurons one; then
    /// the ablation, Space on High, whole, with the per-pixel shader on its
    /// bodies (`-graphDepthPerPixel`), three takes. The meter's line says
    /// whether the fade was on, off, or off because its shader failed the
    /// device's check ("fallback"), the frame times, how many bodies were
    /// drawn, the tilt and whether the fade broke its protocol (bad).
    func testDepthMeasure() {
        var lines: [String] = []
        defer { attachText(lines.joined(separator: "\n"), named: "74-depth-numbers") }
        func cells(_ pair: (String, String), takes: Int) {
            for level in ["High", "Smooth"] {
                for near in [false, true] {
                    for k in 1...takes {
                        for mode in ["on", "off"] {
                            lines.append(measureTake(pair, level, near: near, mode: mode, take: k))
                        }
                    }
                }
            }
        }
        cells(Self.depthThemes[1], takes: 3)
        cells(Self.depthThemes[0], takes: 1)
        for k in 1...3 {
            lines.append(measureTake(Self.depthThemes[1], "High", near: false, mode: "pixel", take: k))
        }
    }

    /// Turning and tilting by hand in each theme, whole, with the meter read
    /// after each gesture: three turns one way, 300 points down, 600 points
    /// up, then a double tap on empty map, which frames the default view
    /// again. Soft checks: the tilt stays within 10...75, nothing bad, and
    /// the double tap brings the tilt back to the theme's own (35 in
    /// Neurons, 45 in Space) within 3 degrees.
    func testDepthSpin() {
        for pair in Self.depthThemes {
            let theme: String = pair.0
            let home: Int = theme == "space" ? 45 : 35
            var reads: [String] = []
            let app = depthApp(theme, fly: nil, off: false,
                               more: ["-stillSky", "-graphFreeze", "-graphDepthMeter", "-graphicsHigh"])
            _ = waitForMeter(app, frames: 0, seconds: 20)
            /// A read after a gesture, checked softly.
            @discardableResult
            func read(_ label: String, settle: Bool = true) -> DepthRead? {
                if settle { usleep(700_000) }
                let line: String = meterLine(app)
                reads.append("\(label): \(line)")
                guard let seen = DepthRead(line) else {
                    XCTFail("\(theme) \(label): no readable meter line: \(line)")
                    return nil
                }
                XCTAssertTrue((10...75).contains(seen.tilt), "\(theme) \(label): tilt \(seen.tilt) is outside 10...75")
                XCTAssertEqual(seen.bad, 0, "\(theme) \(label): bad \(seen.bad), not 0")
                return seen
            }
            for k in 1...3 {
                drag(app, from: CGVector(dx: 0.2, dy: 0.3), by: CGVector(dx: 0.6 * app.frame.width, dy: 0), velocity: 120)
                read("spin-\(k)")
                snap(app, "72-\(theme)-spin-\(k)")
            }
            drag(app, from: CGVector(dx: 0.9, dy: 0.25), by: CGVector(dx: 0, dy: 300), velocity: 200)
            read("down")
            snap(app, "73-\(theme)-down")
            // from low on the screen, so that all of it fits
            let low: CGFloat = min(app.frame.height - 60, 690) / app.frame.height
            drag(app, from: CGVector(dx: 0.9, dy: low), by: CGVector(dx: 0, dy: -min(600, low * app.frame.height - 60)),
                 velocity: 300)
            read("up")
            snap(app, "73-\(theme)-up")
            app.coordinate(withNormalizedOffset: emptySpot(app)).doubleTap()
            // the framing flies back: up to eight seconds for it
            for _ in 0..<16 {
                usleep(500_000)
                if let seen = DepthRead(meterLine(app)), abs(seen.tilt - home) <= 3 { break }
            }
            if let seen = read("double-tap", settle: false) {
                XCTAssertTrue(abs(seen.tilt - home) <= 3, "\(theme): tilt \(seen.tilt) after the double tap, not \(home)")
            }
            attachText(reads.joined(separator: "\n"), named: "72-\(theme)-reads")
            app.terminate()
        }
    }

    /// A link chip's glide to a body past the band's end: flown in to
    /// Inguinal's system, Groin hernia chosen, and its chip for Atrial
    /// fibrillation - a planet far off in Cardiology, not drawn - tapped.
    /// The camera glides it to the middle above the card, into the crisp
    /// zone, where VoiceOver finds it too.
    func testDepthGlide() {
        let app = depthApp("space", fly: "Inguinal", off: false, more: ["-graphPreviewSelect", "Groin hernia"])
        let card = app.otherElements["graphPeekCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 20), "no peek card")
        sleep(2)
        var chip: XCUIElement = card.buttons["Atrial fibrillation"]
        if !chip.waitForExistence(timeout: 5) {
            // the card's chip, not the body of the same name: low on the screen
            let named = app.buttons.matching(NSPredicate(format: "label == %@", "Atrial fibrillation"))
            for element in named.allElementsBoundByIndex where element.frame.minY > app.frame.height * 0.5 {
                chip = element
            }
        }
        XCTAssertTrue(chip.exists, "no Atrial fibrillation chip")
        let before: CGRect? = bodyFrame(app, "Atrial fibrillation")
        snap(app, "64-1-space-glide-before")
        XCTAssertNil(before, "Atrial fibrillation must start past the band's end (not drawn), but it is drawn at \(String(describing: before))")
        chip.tap()
        sleep(1)
        snap(app, "64-2-space-glide-after")
        let after: CGRect? = bodyFrame(app, "Atrial fibrillation")
        let note = XCTAttachment(string: "before \(String(describing: before))\nafter \(String(describing: after))")
        note.name = "64-3-space-glide-frames"
        note.lifetime = .keepAlways
        add(note)
        let screen: CGRect = app.frame
        guard let after else {
            XCTFail("Atrial fibrillation is not drawn after its chip's glide")
            return
        }
        XCTAssertEqual(after.midX, screen.width / 2, accuracy: screen.width * 0.2, "not glided to the middle")
        XCTAssertEqual(after.midY, screen.height * 0.34, accuracy: screen.height * 0.2, "not glided above the card")
    }

    /// The probe's node-opacity check: the meter reports whether node opacity
    /// fades light on this device (on or on/glowpx), never failing silently.
    func testDepthProbeOpacity() {
        let app = depthApp("space", fly: nil, off: false, more: ["-stillSky", "-graphFreeze", "-graphDepthMeter"])
        let line = waitForMeter(app, frames: 0, seconds: 15)
        guard let seen = DepthRead(line) else {
            XCTFail("no readable meter line: \(line)")
            return
        }
        XCTAssertTrue(["on", "on/glowpx"].contains(seen.state), "unexpected probe state: \(seen.state)")
        app.terminate()
    }

    private static let depthThemes: [(String, String)] = [("neurons", "Examples"), ("space", "Inguinal")]

    private func depthApp(_ theme: String, fly: String?, off: Bool, more: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-graphPreview", "-graphPreviewTheme", theme]
        if let fly { app.launchArguments += ["-graphPreviewFly", fly] }
        if off { app.launchArguments += ["-graphDepthOff"] }
        app.launchArguments += more
        app.launch()
        XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
        return app
    }

    /// Turns the map slowly, about two seconds each way, along the upper
    /// part of the screen (a quick press, so no body is held).
    private func slowTurn(_ app: XCUIApplication, times: Int) {
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.3))
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.3))
        for n in 0..<times {
            let from = n % 2 == 0 ? left : right
            let to = n % 2 == 0 ? right : left
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: 120, thenHoldForDuration: 0.2)
        }
    }

    /// Where a body is drawn, as VoiceOver has it (a 44-point square round
    /// it; none when it is not drawn), told apart from a chip of the same
    /// name by its size.
    private func bodyFrame(_ app: XCUIApplication, _ name: String) -> CGRect? {
        let named = app.buttons.matching(NSPredicate(format: "label == %@", name))
        for element in named.allElementsBoundByIndex {
            let frame: CGRect = element.frame
            if abs(frame.width - 44) < 1, abs(frame.height - 44) < 1 { return frame }
        }
        return nil
    }

    /// A one-finger drag from a place on the screen (a fraction of its size)
    /// by so many points, after a quick press, so no body is held.
    private func drag(_ app: XCUIApplication, from start: CGVector, by move: CGVector, velocity: XCUIGestureVelocity) {
        let from = app.coordinate(withNormalizedOffset: start)
        let to = from.withOffset(move)
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: velocity, thenHoldForDuration: 0.2)
    }

    /// The depth meter's line (`-graphDepthMeter`, on the window), or "no meter".
    private func meterLine(_ app: XCUIApplication) -> String {
        let meter = app.staticTexts["graphDepthMeter"]
        return meter.waitForExistence(timeout: 5) ? meter.label : "no meter"
    }

    /// The meter's line once it has numbers and at least `frames` frame gaps
    /// (it ignores them for a few seconds after the first frame and after
    /// each framing), waiting up to about `seconds`; whatever it says by
    /// then if not.
    private func waitForMeter(_ app: XCUIApplication, frames: Int, seconds: Int) -> String {
        var line: String = meterLine(app)
        for _ in 0..<(seconds * 2) {
            if let seen = DepthRead(line), seen.n >= frames { break }
            usleep(500_000)
            line = meterLine(app)
        }
        return line
    }

    /// One take of the numbers (`testDepthMeasure`): launched, given up to
    /// twenty seconds to have a frame time, turned slowly once, read.
    private func measureTake(_ pair: (String, String), _ level: String, near: Bool, mode: String, take: Int) -> String {
        var more: [String] = ["-graphDepthMeter", "-graphics" + level]
        if mode == "pixel" { more += ["-graphDepthPerPixel"] }
        let app = depthApp(pair.0, fly: near ? pair.1 : nil, off: mode == "off", more: more)
        _ = waitForMeter(app, frames: 1, seconds: 20)
        slowTurn(app, times: 1)
        usleep(700_000)
        let line: String = meterLine(app)
        app.terminate()
        return "\(pair.0) \(level.lowercased()) \(near ? "near" : "whole") \(mode) take \(take): \(line)"
    }

    /// The centre of each body drawn on the screen, as VoiceOver has it: the
    /// map's accessibility elements are its bodies, each a button with a
    /// 44-point frame and a value saying what it is (the interface's own
    /// 44-point buttons, Back, have none). A body not drawn has no frame,
    /// and one whose centre is off the screen is left out.
    private func bodyCentres(_ app: XCUIApplication, within screen: CGRect) -> [CGPoint] {
        var centres: [CGPoint] = []
        for element in app.buttons.allElementsBoundByIndex {
            let frame: CGRect = element.frame
            guard abs(frame.width - 44) < 1, abs(frame.height - 44) < 1 else { continue }
            let centre = CGPoint(x: frame.midX, y: frame.midY)
            guard screen.contains(centre) else { continue }
            let value: String = (element.value as? String) ?? ""
            if !value.isEmpty { centres.append(centre) }
        }
        return centres
    }

    /// A place on the map with no body near it, as a fraction of the screen,
    /// for a tap that must land on empty map: of a grid between the top bar
    /// and the bottom tools, the one farthest from every body.
    private func emptySpot(_ app: XCUIApplication) -> CGVector {
        let screen: CGRect = app.frame
        let centres: [CGPoint] = bodyCentres(app, within: screen)
        var best = CGPoint(x: screen.width * 0.5, y: screen.height * 0.5)
        var room: CGFloat = -1
        for y in stride(from: screen.height * 0.22, through: screen.height * 0.72, by: screen.height * 0.05) {
            for x in stride(from: screen.width * 0.1, through: screen.width * 0.9, by: screen.width * 0.1) {
                var nearest: CGFloat = .greatestFiniteMagnitude
                for centre in centres {
                    let across: CGFloat = centre.x - x
                    let down: CGFloat = centre.y - y
                    nearest = min(nearest, (across * across + down * down).squareRoot())
                }
                if nearest > room {
                    room = nearest
                    best = CGPoint(x: x, y: y)
                }
            }
        }
        return CGVector(dx: best.x / screen.width, dy: best.y / screen.height)
    }

    /// What tools/depth_crops.py needs of one still, all in points: the
    /// window's size, the meter's frame and line, and a 44-point square
    /// round each body drawn on the screen.
    private func stillRecord(_ app: XCUIApplication) -> [String: Any] {
        let window: XCUIElement = app.windows.firstMatch
        let screen: CGRect = (window.exists && window.frame.width > 0) ? window.frame : app.frame
        let meter: XCUIElement = app.staticTexts["graphDepthMeter"]
        let found: Bool = meter.waitForExistence(timeout: 5)
        let strip: CGRect = found ? meter.frame : .zero
        var squares: [[Double]] = []
        for centre in bodyCentres(app, within: screen) {
            squares.append([Double(centre.x - 22), Double(centre.y - 22), 44, 44])
        }
        return [
            "size": [Double(screen.width), Double(screen.height)],
            "meter": [Double(strip.minX), Double(strip.minY), Double(strip.width), Double(strip.height)],
            "line": found ? meter.label : "no meter",
            "bodies": squares,
        ]
    }

    /// `75-body-frames`: {"stills": {<still's name>: <stillRecord>, ...}} as
    /// JSON text.
    private func attachFrames(_ stills: [String: Any]) {
        let root: [String: Any] = ["stills": stills]
        guard JSONSerialization.isValidJSONObject(root),
              let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .withoutEscapingSlashes])
        else {
            XCTFail("the body frames could not be written as JSON")
            return
        }
        attachText(String(decoding: data, as: UTF8.self), named: "75-body-frames")
    }

    /// A text attachment, kept.
    private func attachText(_ text: String, named name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = uprightShot()
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}

/// The depth meter's line (GraphDepthKeeper's readout) as numbers:
/// `<state> frame %.2f p95 %.2f worst %.2f n %d drawn X/Y dim K out K tilt NN
/// bad K`, where the state is on, on/pixel, on/glowpx, off or fallback; "waiting"
/// before the first numbers is no read.
private struct DepthRead {
    var state: String = ""
    var frame: Double = 0
    var p95: Double = 0
    var worst: Double = 0
    var n: Int = 0
    var drawn: Int = 0
    var total: Int = 0
    var dim: Int = 0
    var out: Int = 0
    var tilt: Int = 0
    var bad: Int = 0

    init?(_ line: String) {
        let words: [Substring] = line.split(whereSeparator: { $0 == " " || $0 == "\n" })
        guard words.count >= 3 else { return nil }
        state = String(words[0])
        var seen = 0
        var at = 1
        while at + 1 < words.count {
            let value: Substring = words[at + 1]
            switch words[at] {
            case "frame": if let v = Double(value) { frame = v; seen += 1 }
            case "p95": if let v = Double(value) { p95 = v; seen += 1 }
            case "worst": if let v = Double(value) { worst = v; seen += 1 }
            case "n": if let v = Int(value) { n = v; seen += 1 }
            case "dim": if let v = Int(value) { dim = v; seen += 1 }
            case "out": if let v = Int(value) { out = v; seen += 1 }
            case "tilt": if let v = Int(value) { tilt = v; seen += 1 }
            case "bad": if let v = Int(value) { bad = v; seen += 1 }
            case "drawn":
                let parts: [Substring] = value.split(separator: "/")
                if parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]) {
                    drawn = a
                    total = b
                    seen += 1
                }
            default: break
            }
            at += 2
        }
        // frame, p95, worst, n, drawn, dim, out, tilt and bad
        guard seen == 9 else { return nil }
    }
}
