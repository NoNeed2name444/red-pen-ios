import XCTest

/// The Sciences, photographed for the owner: the hub, a subject, a body
/// system, a topic, nine tools and the 3D atlas, each opened straight from
/// launch (`-uiPreviewScreen science-<name>`, SciencePreviewScreen), the
/// tools also scrolled once to their results. Run by design-preview.yml
/// (preview/<name>, its "only" input matching testSciencesTour).
final class SciencesUITests: XCTestCase {
    /// Each screen and what shows once it is open.
    private let screens: [(name: String, ready: String, scroll: Bool)] = [
        ("science-hub", "sciencesHub", false),
        ("science-subject", "scienceSubjectPage", false),
        ("science-system", "scienceSystemPage", false),
        ("science-topic", "scienceTopicPage", true),
        ("science-cardiac", "scienceToolPage-cardiacCycle", true),
        ("science-action", "scienceToolPage-actionPotential", true),
        ("science-oxygen", "scienceToolPage-oxygenCurve", true),
        ("science-acidbase", "scienceToolPage-acidBase", true),
        ("science-enzyme", "scienceToolPage-enzymeKinetics", true),
        ("science-punnett", "scienceToolPage-punnett", true),
        ("science-microbes", "scienceToolPage-microbes", false),
        ("science-shock", "scienceToolPage-shock", true),
        ("science-tests", "scienceToolPage-diagnosticTests", true),
        // the layers' chips show once the meshes are in
        ("science-atlas", "atlasLayer-skeletal", false),
        ("science-atlas-heart", "atlasChosen", false),
    ]

    func testSciencesTour() {
        for screen in screens {
            let app = XCUIApplication()
            app.launchArguments += ["-uiPreviewScreen", screen.name, "-stillSky"]
            app.launch()
            let ready = app.descendants(matching: .any)[screen.ready]
            if !ready.waitForExistence(timeout: 40) {
                XCTFail("\(screen.name): \(screen.ready) did not show")
            }
            // a moment for the charts' and the scene's first frames
            Thread.sleep(forTimeInterval: screen.name.hasPrefix("science-atlas") ? 4 : 1.5)
            snap(app, screen.name)
            if screen.scroll {
                app.swipeUp()
                Thread.sleep(forTimeInterval: 1)
                snap(app, screen.name + "-more")
            }
            app.terminate()
        }
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
