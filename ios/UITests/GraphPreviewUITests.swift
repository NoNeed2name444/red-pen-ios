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

    /// The depth fade in each SceneKit theme, after and before
    /// (`-graphDepthOff`): the whole map, and flown in close (Neurons:
    /// Examples opened; Space: Inguinal's system), where what is far
    /// dissolves into the theme's background and nothing past the band's
    /// end is drawn.
    func testDepthBeforeAfter() {
        for (k, pair) in Self.depthThemes.enumerated() {
            for near in [false, true] {
                for off in [false, true] {
                    let app = depthApp(pair.0, fly: near ? pair.1 : nil, off: off)
                    sleep(near ? 6 : 4)
                    snap(app, "60-\(k + 1)-\(pair.0)-\(near ? "near" : "whole")-\(off ? "before" : "after")")
                    app.terminate()
                }
            }
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

    /// The numbers: frame times (the meter, `-graphDepthMeter`) and
    /// SceneKit's statistics (draw calls, on each picture) in each theme at
    /// each Graphics level, whole and flown in close, after and before,
    /// each over two slow turns. The meter's line says whether the fade was
    /// on, off, or off because its shader failed the device's check
    /// ("fallback"), and how many bodies were drawn.
    func testDepthMeasure() {
        var lines: [String] = []
        for (k, pair) in Self.depthThemes.enumerated() {
            for level in ["High", "Smooth"] {
                for near in [false, true] {
                    for off in [false, true] {
                        let app = depthApp(pair.0, fly: near ? pair.1 : nil, off: off,
                                           more: ["-graphDepthMeter", "-graphics" + level])
                        sleep(near ? 6 : 4)
                        slowTurn(app, times: 2)
                        usleep(700_000)
                        let meter = app.staticTexts["graphDepthMeter"]
                        let read: String = meter.waitForExistence(timeout: 5) ? meter.label : "no meter"
                        let name = "63-\(k + 1)-\(pair.0)-\(level.lowercased())-\(near ? "near" : "whole")-"
                            + (off ? "before" : "after")
                        lines.append(name + ": " + read)
                        snap(app, name)
                        app.terminate()
                    }
                }
            }
        }
        let table = XCTAttachment(string: lines.joined(separator: "\n"))
        table.name = "63-depth-numbers"
        table.lifetime = .keepAlways
        add(table)
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

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = uprightShot()
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
