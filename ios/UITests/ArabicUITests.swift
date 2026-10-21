import XCTest

/// The first Arabic screens, right to left: sign-in, the recording terms,
/// the library's dock and Settings - the slice the String Catalog already
/// translates (ios/RedPen/Resources/Localizable.xcstrings), photographed for
/// the owner to look through.
///
/// The app is launched as an Egyptian Arabic phone would run it, by launch
/// arguments alone (-AppleLanguages (ar) -AppleLocale ar_EG), so no other
/// test and no preview ever sees Arabic.
///
/// What is asserted is that the sign-in button (found by the same identifier
/// as LocalSignInUITests) really reads in Arabic, which is the one thing
/// this test is here to prove, and that the library opens. Everything else
/// is forgiving: a screen that cannot be reached is recorded as an
/// "ar-missing-" picture instead.
final class ArabicUITests: XCTestCase {
    private var app: XCUIApplication!

    /// "Start without an account", as the catalog has it.
    private let startArabic: String = "ابدأ دون حساب"
    /// "Settings", as the catalog has it.
    private let settingsArabic: String = "الإعدادات"

    func testArabicRightToLeft() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_EG"]
        app.launch()

        // (a simulator that kept an earlier test's account opens straight
        // on the library: then there is no sign-in to photograph)
        let door = app.buttons["localSignIn"]
        if door.waitForExistence(timeout: 20) {
            snap("ar-01-sign-in")
            XCTAssertTrue(readsArabic(door), "the sign-in button isn't in Arabic: \(door.label)")
            door.tap()
        } else {
            missing("sign-in")
        }

        let accept = app.buttons["acceptRecordingTerms"]
        if accept.waitForExistence(timeout: 15) {
            snap("ar-02-terms")
            app.swipeUp(velocity: .slow)
            sleep(1)
            snap("ar-03-terms-end")
            let ready = NSPredicate(format: "isEnabled == true")
            expectation(for: ready, evaluatedWith: accept)
            waitForExpectations(timeout: 10)
            snap("ar-04-terms-ready")
            accept.tap()
        } else {
            missing("terms")
        }

        // once, skippable: the exam question (not translated yet)
        let skipExam = app.buttons["examOnboardingSkip"]
        if skipExam.waitForExistence(timeout: 10) {
            snap("ar-05-exam-question")
            skipExam.tap()
        }

        let dock = element("dockCategory-questions")
        guard dock.waitForExistence(timeout: 20) else {
            missing("library")
            XCTFail("the library didn't open in Arabic")
            return
        }
        sleep(1)
        snap("ar-06-library-dock")
        settings()
    }

    // MARK: - Steps

    /// The account menu, then Settings from it (by its Arabic name, or the
    /// English one if the catalog was not found).
    private func settings() {
        let menu = element("libraryMenu")
        guard menu.waitForExistence(timeout: 5), menu.isHittable else {
            missing("libraryMenu")
            return
        }
        menu.tap()
        sleep(1)
        snap("ar-07-menu")
        var item = menuItem(settingsArabic)
        if !item.exists { item = menuItem("Settings") }
        guard item.exists, item.isHittable else {
            missing("menu-settings")
            return
        }
        item.tap()
        sleep(2)
        snap("ar-08-settings")
        app.swipeUp(velocity: .slow)
        sleep(1)
        snap("ar-09-settings-more")
    }

    // MARK: - Helpers

    /// Whether the button's words are the catalog's Arabic.
    private func readsArabic(_ button: XCUIElement) -> Bool {
        if button.label.contains(startArabic) { return true }
        let named = NSPredicate(format: "label CONTAINS %@", startArabic)
        return app.staticTexts.matching(named).firstMatch.exists
    }

    private func menuItem(_ title: String) -> XCUIElement {
        let named = NSPredicate(format: "label == %@", title)
        let button = app.buttons.matching(named).firstMatch
        if button.waitForExistence(timeout: 3) { return button }
        return app.menuItems.matching(named).firstMatch
    }

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
        snap("ar-missing-\(what)")
    }
}
