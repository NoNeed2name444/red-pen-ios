import XCTest

/// A picture tour of the redesigned app, for the owner to look through before
/// installing it: the library on each of the dock's categories, a category
/// scrolled down to its tiles, New set, a quiz and a card, Ideas in each of
/// its views with the floating switcher open and folded, the account and
/// settings menu, Settings and Progress; Mission Control, the mock paper,
/// the exam plan, symptom blocks and Settings' Look and feel - and on an iPad
/// the library and Ideas turned on their side as well.
///
/// Run by the "Design preview" workflow on an iPhone and on an iPad; the
/// pictures land on the design-preview branch, named after the step.
///
/// Every step is forgiving. A control that cannot be found is recorded as a
/// "missing-<what>" picture and the tour carries on, so one moved button
/// costs one picture rather than all of them. What is asserted is that the
/// app is still running after each step; if it is not, the failure is noted
/// and the app is opened again for the rest of the tour.
///
/// Everything is found by the accessibility identifiers in the app's sources:
/// localSignIn, acceptRecordingTerms, dockCategory-<category>,
/// dockCategory-ideas, feature-mixed, feature-mock, feature-examPlan,
/// feature-symptomBlocks, morePractise, more-analytics, newSetButton,
/// newSetNext, setRow-mcq, setRow-anki, ideasMode-list/board/space,
/// ideasSwitcherToggle, graph3D, examplesBanner, example-ideas,
/// missionPlan, mockStart, learnDone, alwaysNightToggle, soundsToggle and
/// libraryMenu.
///
/// Some of the app's buttons stand in interactive glass that is raised and
/// tilted (the pop-out): XCUITest can find them yet call them not hittable.
/// `press` taps those at their centre instead of giving up on them.
final class DesignTourUITests: XCTestCase {
    private var app: XCUIApplication!

    /// The dock's five categories, in the dock's order.
    private let categories: [String] = ["questions", "cards", "cases", "osce", "audio"]

    func testDesignTour() {
        continueAfterFailure = true
        // a system alert (notifications, the microphone) answered rather than
        // left standing over every picture after it
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
        app.launchArguments += ["-personalBuild"]
        app.launch()
        signIn()
        let dock = element("dockCategory-questions")
        XCTAssertTrue(dock.waitForExistence(timeout: 20), "the library didn't open")
        check("sign-in")

        libraryOnEachCategory()
        check("library")
        categoryTiles()
        check("category tiles")
        newSet()
        check("new set")
        mcqQuiz()
        check("quiz")
        ankiCard()
        check("cards")
        ideas()
        check("ideas")
        examplesHub()
        check("examples")
        menuAndSettings()
        check("menu and settings")
        progress()
        check("progress")
        missionControl()
        check("mission control")
        mockPaper()
        check("mock paper")
        examPlan()
        check("exam plan")
        symptomBlocks()
        check("symptom blocks")
        lookAndFeel()
        check("look and feel")
        if isWide {
            landscape()
            check("landscape")
        }
    }

    // MARK: - The steps

    /// 01-05: the library on each of the five categories.
    private func libraryOnEachCategory() {
        goHome()
        for (index, category) in categories.enumerated() {
            let number: String = String(format: "%02d", index + 1)
            if choose(category) {
                snap("\(number)-library-\(category)")
            }
        }
    }

    /// 06-07: Questions, scrolled down to its tiles, then on to the tools.
    private func categoryTiles() {
        goHome()
        guard chooseFresh("questions") else { return }
        if reveal(element("feature-mixed")) {
            snap("06-category-questions-tiles")
        } else {
            missing("feature-mixed")
        }
        if reveal(element("more-analytics")) {
            snap("07-category-questions-tools")
        } else {
            missing("more-analytics")
        }
    }

    /// 08-09: New set, and its second step when Next can be pressed.
    private func newSet() {
        goHome()
        guard chooseFresh("questions") else { return }
        guard let button = newSetControl() else {
            missing("newSetButton")
            return
        }
        press(button)
        let bar = app.navigationBars["New set"]
        let next = element("newSetNext")
        let opened: Bool = bar.waitForExistence(timeout: 8) || next.exists
        guard opened else {
            missing("new-set-sheet")
            goHome()
            return
        }
        sleep(1)
        snap("08-new-set")
        if next.exists && next.isEnabled && next.isHittable {
            next.tap()
            sleep(2)
            snap("09-new-set-next")
        }
        closeSheet(bar)
        goHome()
    }

    /// New set: the floating button over the dock, or - with nothing in the
    /// library, when that one stays away - the big one in the empty state
    /// card. Found by its identifier, else by its title.
    private func newSetControl() -> XCUIElement? {
        let byId = element("newSetButton")
        if byId.waitForExistence(timeout: 5) { return byId }
        let byTitle = app.buttons.matching(NSPredicate(format: "label == %@", "New set")).firstMatch
        if byTitle.waitForExistence(timeout: 3) { return byTitle }
        if reveal(byId, swipes: 4) { return byId }
        return nil
    }

    /// Cancel on a sheet, or a pull down from its top when there is none.
    /// Done here rather than left to goHome: on an iPad the library can
    /// still be found behind a form sheet.
    private func closeSheet(_ bar: XCUIElement) {
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists && cancel.isHittable {
            cancel.tap()
        } else if bar.exists {
            let top = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
            let below = top.withOffset(CGVector(dx: 0, dy: 500))
            top.press(forDuration: 0.1, thenDragTo: below)
        }
        sleep(2)
        if bar.exists {
            missing("new-set-close")
        }
    }

    /// 10-11: the example MCQ set, then with an answer chosen.
    private func mcqQuiz() {
        goHome()
        guard chooseFresh("questions") else { return }
        guard openSet("mcq") else { return }
        snap("10-mcq-quiz")
        let first = NSPredicate(format: "label BEGINSWITH %@", "Answer A")
        let answer = app.buttons.matching(first).firstMatch
        if answer.exists && answer.isHittable {
            answer.tap()
            sleep(2)
            snap("11-mcq-answered")
        } else {
            missing("mcq-answer")
        }
        goHome()
    }

    /// 12-13: the example deck's card, then revealed.
    private func ankiCard() {
        goHome()
        guard chooseFresh("cards") else { return }
        guard openSet("anki") else { return }
        snap("12-anki-card")
        let reveal = app.buttons["Reveal"].firstMatch
        if reveal.waitForExistence(timeout: 4) && reveal.isHittable {
            reveal.tap()
            sleep(2)
            snap("13-anki-revealed")
        } else {
            missing("anki-reveal")
        }
        goHome()
    }

    /// 14-19: Ideas as a list, a board and a space with the switcher open;
    /// folded on the space, folded on the list, and opened again.
    private func ideas() {
        goHome()
        guard choose("ideas") else { return }
        openSwitcher()
        showIdeas("list", as: "14-ideas-list")
        showIdeas("board", as: "15-ideas-board")
        showIdeas("space", as: "16-ideas-space")
        if foldSwitcher() {
            snap("17-ideas-space-switcher-collapsed")
        }
        // back to the list (as it was), folded there too, then open again
        if openSwitcher() {
            showIdeas("list", as: nil)
        }
        if foldSwitcher() {
            snap("18-ideas-list-switcher-collapsed")
        }
        if openSwitcher() {
            snap("19-ideas-list-switcher-expanded")
        }
        choose("questions")
    }

    /// 20: the personal build's "Try every feature" page.
    private func examplesHub() {
        goHome()
        guard chooseFresh("questions") else { return }
        let banner = element("examplesBanner")
        guard reveal(banner, swipes: 16) else {
            missing("examplesBanner")
            return
        }
        banner.tap()
        let row = element("example-ideas")
        if row.waitForExistence(timeout: 8) {
            sleep(1)
            snap("20-examples-hub")
        } else {
            missing("examplesHub")
        }
        goHome()
    }

    /// 21-23: the account and settings menu open, then Settings.
    private func menuAndSettings() {
        goHome()
        guard openMenu() else { return }
        snap("21-menu")
        let settings = menuItem("Settings")
        guard settings.exists, settings.isHittable else {
            missing("menu-settings")
            dismissMenu()
            return
        }
        settings.tap()
        sleep(2)
        if atLibrary() {
            missing("settings-page")
            return
        }
        snap("22-settings")
        app.swipeUp(velocity: .slow)
        sleep(1)
        snap("23-settings-more")
        goHome()
    }

    /// 24-25: Progress, from the menu - or, failing that, from the
    /// category's "Across the app" row.
    private func progress() {
        goHome()
        var opened = false
        if openMenu() {
            let item = menuItem("Progress")
            if item.exists && item.isHittable {
                item.tap()
                sleep(2)
                opened = !atLibrary()
            } else {
                dismissMenu()
            }
        }
        if !opened {
            let row = element("more-analytics")
            if chooseFresh("questions") && reveal(row) {
                row.tap()
                sleep(2)
                opened = !atLibrary()
            }
        }
        guard opened else {
            missing("progress")
            return
        }
        snap("24-progress")
        app.swipeUp(velocity: .slow)
        sleep(1)
        snap("25-progress-more")
        goHome()
    }

    /// 28: Mission Control, the Today card at the top of Questions.
    private func missionControl() {
        goHome()
        guard chooseFresh("questions") else { return }
        let plan = element("missionPlan")
        if plan.waitForExistence(timeout: 5) {
            _ = reveal(plan, swipes: 3)
            sleep(1)
            snap("28-mission-control")
        } else {
            missing("missionPlan")
        }
    }

    /// 29-30: the mock paper's start page, from Questions' "More ways to
    /// practise"; then with the paper chosen and ready to start.
    private func mockPaper() {
        goHome()
        guard chooseFresh("questions") else { return }
        guard openTile("mock") else { return }
        let bar = app.navigationBars["Mock paper"]
        if bar.waitForExistence(timeout: 8) || element("mockStart").exists {
            sleep(1)
            snap("29-mock-paper-start")
            app.swipeUp(velocity: .slow)
            sleep(1)
            snap("30-mock-paper-more")
        } else {
            missing("mock-paper")
        }
        goHome()
    }

    /// 31: the exam plan - from Mission Control's Plan, or the Tools tile.
    private func examPlan() {
        goHome()
        guard chooseFresh("questions") else { return }
        let plan = element("missionPlan")
        if plan.waitForExistence(timeout: 4) && reveal(plan, swipes: 3) {
            press(plan)
        } else if !openTile("examPlan") {
            return
        }
        if app.navigationBars["Exam plan"].waitForExistence(timeout: 8) {
            sleep(2)
            snap("31-exam-plan")
            app.swipeUp(velocity: .slow)
            sleep(1)
            snap("32-exam-plan-more")
        } else {
            missing("exam-plan")
        }
        goHome()
    }

    /// 33: symptom blocks, from Questions' "More ways to practise".
    private func symptomBlocks() {
        goHome()
        guard chooseFresh("questions") else { return }
        guard openTile("symptomBlocks") else { return }
        if app.navigationBars["Symptom blocks"].waitForExistence(timeout: 8) {
            sleep(2)
            snap("33-symptom-blocks")
        } else {
            missing("symptom-blocks")
        }
        goHome()
    }

    /// 34-35: Settings' Look and feel, with Always night sky and Sounds;
    /// then with Always night sky on, turned back off afterwards.
    private func lookAndFeel() {
        goHome()
        guard openMenu() else { return }
        let settings = menuItem("Settings")
        guard settings.exists else {
            missing("menu-settings")
            dismissMenu()
            return
        }
        press(settings)
        sleep(2)
        let night = element("alwaysNightToggle")
        guard night.waitForExistence(timeout: 6), reveal(night, swipes: 4) else {
            missing("alwaysNightToggle")
            goHome()
            return
        }
        if !element("soundsToggle").exists { missing("soundsToggle") }
        snap("34-settings-look-and-feel")
        let wasOn: Bool = (night.value as? String) == "1"
        if !wasOn {
            // the switch itself, at the trailing end of the row
            night.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            sleep(2)
            snap("35-settings-always-night-sky")
            night.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            sleep(1)
        }
        goHome()
    }

    /// 26-27: an iPad on its side - the library with the rail, and Ideas.
    private func landscape() {
        goHome()
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        if chooseFresh("questions") {
            snap("26-ipad-landscape-questions")
        }
        if choose("ideas") {
            snap("27-ipad-landscape-ideas")
        }
        choose("questions")
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
    }

    // MARK: - Getting in

    /// "Use on this device only", then the recording terms once they can be
    /// agreed to; either may already be past on a simulator that has run the
    /// app before.
    private func signIn() {
        let door = app.buttons["localSignIn"]
        let accept = app.buttons["acceptRecordingTerms"]
        // then, once, "Which exam are you preparing for?" - skipped here
        let skipExam = app.buttons["examOnboardingSkip"]
        let dock = element("dockCategory-questions")
        for _ in 0..<80 {
            if dock.exists { return }
            if door.exists && door.isHittable {
                door.tap()
                sleep(1)
            } else if accept.exists && accept.isEnabled && accept.isHittable {
                accept.tap()
                sleep(1)
            } else if skipExam.exists && skipExam.isHittable {
                skipExam.tap()
                sleep(1)
            } else {
                usleep(500_000)
            }
        }
    }

    /// Asserts the app is still up after a step; if it is not, opens it again
    /// so the rest of the tour still has pictures.
    private func check(_ step: String) {
        let running: Bool = app.state == .runningForeground
        XCTAssertTrue(running, "the app stopped during the \(step) step")
        guard !running else { return }
        app.launch()
        signIn()
    }

    // MARK: - Moving about

    /// Taps a dock item - a category, or Ideas. False, with a "missing"
    /// picture, when it is not there.
    @discardableResult
    private func choose(_ place: String) -> Bool {
        let item = element("dockCategory-\(place)")
        guard item.waitForExistence(timeout: 5), press(item) else {
            missing("dockCategory-\(place)")
            return false
        }
        sleep(2)
        return true
    }

    /// A category from the top of its page: another one first, because each
    /// page is built afresh when the dock moves to it.
    private func chooseFresh(_ category: String) -> Bool {
        let other: String = category == "osce" ? "audio" : "osce"
        let away = element("dockCategory-\(other)")
        if away.exists && away.isHittable {
            away.tap()
            sleep(1)
        }
        return choose(category)
    }

    /// Opens a feature tile on the category on show, opening "More ways to
    /// practise" first when the tile is folded away under it.
    private func openTile(_ feature: String) -> Bool {
        let tile = element("feature-\(feature)")
        if !tile.waitForExistence(timeout: 3) {
            let more = element("morePractise")
            let titled = app.buttons.matching(NSPredicate(format: "label == %@", "More ways to practise")).firstMatch
            let fold: XCUIElement = more.exists ? more : titled
            // already open (it stays so), with its tiles only loaded once
            // scrolled near: open it only if the tile is still not there
            if reveal(fold, swipes: 12) && !tile.exists {
                press(fold)
                sleep(1)
            }
        }
        guard reveal(tile, swipes: 12) else {
            missing("feature-\(feature)")
            return false
        }
        press(tile)
        sleep(2)
        if atLibrary() && !app.buttons["learnDone"].exists {
            missing("\(feature)-screen")
            return false
        }
        return true
    }

    /// Opens the first set of a kind from the category on show.
    private func openSet(_ kind: String) -> Bool {
        let row = element("setRow-\(kind)")
        _ = row.waitForExistence(timeout: 8)
        guard reveal(row) else {
            missing("setRow-\(kind)")
            return false
        }
        row.tap()
        sleep(3)
        if atLibrary() {
            missing("\(kind)-screen")
            return false
        }
        return true
    }

    /// Back to the library: Cancel on a sheet, Back on a pushed page.
    private func goHome() {
        for _ in 0..<6 {
            if atLibrary() { return }
            let cancel = app.buttons["Cancel"].firstMatch
            let done = app.buttons["learnDone"].firstMatch
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if cancel.exists && cancel.isHittable {
                cancel.tap()
            } else if done.exists && done.isHittable {
                // the learning screens' sheet (exam plan, mock paper...)
                done.tap()
            } else if back.exists && back.isHittable {
                back.tap()
            } else {
                dismissMenu()
            }
            sleep(1)
        }
        if !atLibrary() {
            missing("way-back-to-library")
        }
    }

    /// Whether the library - with its dock or rail - is what is on screen.
    private func atLibrary() -> Bool {
        let dock = element("dockCategory-questions")
        if app.buttons["learnDone"].exists { return false }
        return dock.exists && dock.isHittable
    }

    // MARK: - Ideas' switcher

    private func showIdeas(_ mode: String, as name: String?) {
        let segment = element("ideasMode-\(mode)")
        guard segment.waitForExistence(timeout: 4), press(segment) else {
            missing("ideasMode-\(mode)")
            return
        }
        if mode == "space" {
            if !element("graph3D").waitForExistence(timeout: 12) {
                missing("graph3D")
            }
            sleep(3)
        } else {
            sleep(2)
        }
        if let name {
            snap(name)
        }
    }

    /// The switcher's strip open. The chevron that folds it and the circle it
    /// folds into share one identifier; the strip is open when its segments
    /// are there.
    @discardableResult
    private func openSwitcher() -> Bool {
        let list = element("ideasMode-list")
        if list.exists { return true }
        let toggle = element("ideasSwitcherToggle")
        guard toggle.waitForExistence(timeout: 4), press(toggle) else {
            missing("ideasSwitcherToggle")
            return false
        }
        if list.waitForExistence(timeout: 4) {
            sleep(1)
            return true
        }
        missing("switcher-expanded")
        return false
    }

    /// The switcher folded into its circle.
    private func foldSwitcher() -> Bool {
        let list = element("ideasMode-list")
        if !list.exists { return true }
        let toggle = element("ideasSwitcherToggle")
        guard toggle.exists, press(toggle) else {
            missing("switcher-collapse-button")
            return false
        }
        sleep(1)
        if list.exists {
            missing("switcher-collapsed")
            return false
        }
        return true
    }

    // MARK: - The menu

    private func openMenu() -> Bool {
        let menu = element("libraryMenu")
        guard menu.waitForExistence(timeout: 5), menu.isHittable else {
            missing("libraryMenu")
            return false
        }
        menu.tap()
        sleep(1)
        return true
    }

    /// One of the menu's items, by its title.
    private func menuItem(_ title: String) -> XCUIElement {
        let named = NSPredicate(format: "label == %@", title)
        let button = app.buttons.matching(named).firstMatch
        if button.waitForExistence(timeout: 3) { return button }
        return app.menuItems.matching(named).firstMatch
    }

    /// A tap in the open space near the top, which closes an open menu.
    private func dismissMenu() {
        let spot = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        spot.tap()
        sleep(1)
    }

    // MARK: - Scrolling

    /// Scrolls until the element sits in the open part of the page, clear of
    /// the navigation bar at the top and of New set and the dock at the
    /// bottom. True if it is on screen and can be tapped.
    @discardableResult
    private func reveal(_ target: XCUIElement, swipes: Int = 10) -> Bool {
        for _ in 0..<swipes {
            if isInView(target) { return true }
            let above: Bool = target.exists && target.frame.maxY < windowHeight * 0.2
            if above {
                app.swipeDown(velocity: .slow)
            } else {
                app.swipeUp(velocity: .slow)
            }
            usleep(600_000)
        }
        if isInView(target) { return true }
        return target.exists && target.isHittable
    }

    private func isInView(_ target: XCUIElement) -> Bool {
        guard target.exists, target.isHittable else { return false }
        let frame: CGRect = target.frame
        let top: CGFloat = windowHeight * 0.18
        return frame.minY >= top && frame.maxY <= bottomLimit()
    }

    /// Where the floating things at the bottom begin: New set and the dock
    /// on a phone, New set alone beside the wide iPad's rail.
    private func bottomLimit() -> CGFloat {
        let height: CGFloat = windowHeight
        var limit: CGFloat = height - 16
        for id in ["newSetButton", "dockCategory-questions"] {
            let item = element(id)
            guard item.exists else { continue }
            let top: CGFloat = item.frame.minY
            // the rail's items stand on the leading edge, not at the bottom
            if top > height * 0.55 && top < limit {
                limit = top
            }
        }
        return limit - 8
    }

    private var windowHeight: CGFloat {
        app.windows.firstMatch.frame.height
    }

    /// An iPad-sized window, for the landscape pictures.
    private var isWide: Bool {
        app.windows.firstMatch.frame.width >= 700
    }

    // MARK: - Finding and pictures

    /// Taps an element: normally, or - when it is on screen but XCUITest
    /// calls it not hittable, as it can a button in raised interactive glass
    /// - at its centre. False when it is not on screen at all.
    @discardableResult
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

    /// The first element of any type with this accessibility identifier.
    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// A picture of the screen where something was looked for and not found.
    private func missing(_ what: String) {
        snap("missing-\(what)")
    }
}
