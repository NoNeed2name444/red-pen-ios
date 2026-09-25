import XCTest

/// Pictures of the 3D idea map for the owner to look at before trying the
/// app: the Universe at rest (the whole map), a moment later (the orbits
/// moving on), in landscape, while a star is being dragged with its system,
/// flown in to one star system, the legend, and each single look on its
/// own. Run on its own by the "Design preview" workflow.
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

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
