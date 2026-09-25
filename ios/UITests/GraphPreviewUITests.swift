import XCTest

/// Pictures of the 3D idea map for the owner to look at before trying the
/// app: the Universe at rest (the whole map), a moment later (the orbits
/// moving on), in landscape, while a star is being dragged with its system,
/// flown in to one star system, the legend, and each single look on its
/// own; then the same for the Neurons theme (`-graphPreviewTheme neurons`)
/// and the Circuit theme (`-graphPreviewTheme circuit`).
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

    /// "What the bodies mean", opened by the app a second after the space.
    func testUniverseLegend() {
        let app = XCUIApplication()
        app.launchArguments += ["-graphPreview", "-graphPreviewLegend"]
        app.launch()
        XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
        let title = app.staticTexts["What the bodies mean"]
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
        let legend = app.buttons["What the bodies mean"]
        XCTAssertTrue(legend.waitForExistence(timeout: 5), "no legend in the Look menu")
        legend.tap()
        XCTAssertTrue(app.staticTexts["What the bodies mean"].waitForExistence(timeout: 10), "the legend didn't open")
        sleep(1)
        snap(app, "10-look-menu-legend")
    }

    // MARK: the Neurons theme

    /// The whole map as a nervous system: Cardiology and Examples as two
    /// regions, Examples' pathway running out through Inguinal (Anatomy one
    /// relay further) and Femoral, impulses running along the axons at
    /// their own random times - so the second picture differs from the
    /// first - and in landscape.
    func testNeuronsAtRest() {
        let app = XCUIApplication()
        app.launchArguments += ["-graphPreview", "-graphPreviewTheme", "neurons"]
        app.launch()
        let space = app.otherElements["graph3D"]
        XCTAssertTrue(space.waitForExistence(timeout: 30), "the 3D map didn't open")
        sleep(3)
        let summary: String = (space.value as? String) ?? ""
        XCTAssertTrue(summary.contains("regions") && summary.contains("glia"), "no Neurons summary: \(summary)")
        snap(app, "11-neurons-at-rest")
        sleep(2)
        snap(app, "12-neurons-two-seconds-later")
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        snap(app, "13-neurons-landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    /// Double-tapped Examples, as the app does it itself: flown in to the
    /// region and its whole pathway, close enough to see the cells' gel,
    /// nuclei and dendrites and the impulses along the axons.
    func testNeuronsFlyIn() {
        let app = XCUIApplication()
        app.launchArguments += ["-graphPreview", "-graphPreviewTheme", "neurons", "-graphPreviewFly", "Examples"]
        app.launch()
        XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
        sleep(3)
        snap(app, "14-neurons-fly-examples")
        sleep(1)
        snap(app, "15-neurons-fly-examples-later")
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

    /// "What the cells mean", opened by the app a second after the map.
    func testNeuronsLegend() {
        let app = XCUIApplication()
        app.launchArguments += ["-graphPreview", "-graphPreviewTheme", "neurons", "-graphPreviewLegend"]
        app.launch()
        XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
        XCTAssertTrue(app.staticTexts["What the cells mean"].waitForExistence(timeout: 10), "the legend didn't open")
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
        let legend = app.buttons["What the cells mean"]
        XCTAssertTrue(legend.waitForExistence(timeout: 5), "no Neurons legend in the Look menu")
        snap(app, "19-neurons-look-menu")
    }

    // MARK: the Circuit theme

    /// The whole board: Cardiology and Examples as two processors in their
    /// zones, Examples' modules (Inguinal with Anatomy beside it, Femoral)
    /// on their sub-boards, the parts round each chip, copper traces routed
    /// square with rounded 45° corners, current running along them - so the
    /// second picture differs from the first - and in landscape.
    func testCircuitAtRest() {
        let app = XCUIApplication()
        app.launchArguments += ["-graphPreview", "-graphPreviewTheme", "circuit"]
        app.launch()
        let space = app.otherElements["graph3D"]
        XCTAssertTrue(space.waitForExistence(timeout: 30), "the 3D map didn't open")
        sleep(3)
        let summary: String = (space.value as? String) ?? ""
        XCTAssertTrue(summary.contains("processors") && summary.contains("capacitors"), "no Circuit summary: \(summary)")
        snap(app, "21-circuit-board")
        sleep(2)
        snap(app, "22-circuit-two-seconds-later")
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        snap(app, "23-circuit-landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    /// Double-tapped Examples, as the app does it itself: flown in to the
    /// processor's zone and its modules, close enough to read the names on
    /// the chips and see the cans, bands, LEDs and packets on the traces.
    func testCircuitFlyIn() {
        let app = XCUIApplication()
        app.launchArguments += ["-graphPreview", "-graphPreviewTheme", "circuit", "-graphPreviewFly", "Examples"]
        app.launch()
        XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
        sleep(3)
        snap(app, "24-circuit-fly-examples")
        sleep(1)
        snap(app, "25-circuit-fly-examples-later")
    }

    /// The busiest module (Inguinal) picked up and carried: its parts and
    /// sub-board come with it, Anatomy beside it follows, and every trace
    /// to them re-routes as it goes.
    func testCircuitWhileDragging() {
        let app = XCUIApplication()
        app.launchArguments += ["-graphPreview", "-graphPreviewTheme", "circuit", "-graphPreviewDrag"]
        app.launch()
        XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
        usleep(1_600_000)
        snap(app, "26-circuit-dragging")
        sleep(3)
        snap(app, "27-circuit-after-release")
    }

    /// "What the parts mean", opened by the app a second after the map.
    func testCircuitLegend() {
        let app = XCUIApplication()
        app.launchArguments += ["-graphPreview", "-graphPreviewTheme", "circuit", "-graphPreviewLegend"]
        app.launch()
        XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
        XCTAssertTrue(app.staticTexts["What the parts mean"].waitForExistence(timeout: 10), "the legend didn't open")
        sleep(1)
        snap(app, "28-circuit-legend")
    }

    /// The Look menu offers all three themes, and in Circuit its legend.
    func testCircuitLookMenu() {
        let app = XCUIApplication()
        app.launchArguments += ["-graphPreview", "-graphPreviewTheme", "circuit"]
        app.launch()
        XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 30), "the 3D map didn't open")
        let look = app.buttons["Look"]
        XCTAssertTrue(look.waitForExistence(timeout: 10), "no Look tool")
        look.tap()
        XCTAssertTrue(app.buttons["Circuit"].waitForExistence(timeout: 5), "no Circuit theme in the Look menu")
        XCTAssertTrue(app.buttons["Neurons"].exists && app.buttons["Space"].exists, "a theme is missing")
        let legend = app.buttons["What the parts mean"]
        XCTAssertTrue(legend.waitForExistence(timeout: 5), "no Circuit legend in the Look menu")
        snap(app, "29-circuit-look-menu")
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
