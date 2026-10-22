import XCTest

/// The library's dock as the UI tests reach it: the full row.
///
/// At every text size short of the accessibility ones, CategoryDock is the
/// row of `dockCategory-<place>` buttons on every phone (or the rail on a
/// wide iPad), never the one `dockList` button (WardDock.showsList; owner
/// 22 Oct: the folded "Questions" button on a 17 Pro was wrong). These
/// suites run at the default size, so the dock must be the row: a dock
/// drawn as the list button fails them. AccessibilityUITests covers the
/// list button at the accessibility sizes.
struct LibraryDock {
    let app: XCUIApplication

    /// Questions' tab on the row.
    var row: XCUIElement { element("dockCategory-questions") }

    /// Whether the library is open with its dock as the row: Questions' tab
    /// is there and the one list button is not.
    func waitForLibrary(timeout: TimeInterval) -> Bool {
        row.waitForExistence(timeout: timeout) && !element("dockList").exists
    }

    /// Goes to a place (a category or "ideas") by its tab on the row.
    /// `press` does the tapping, so a test can keep its own way of pressing
    /// raised glass. False when the tab is not on the row, or the dock is
    /// the list button.
    func choose(_ place: String, timeout: TimeInterval = 5,
                press: (XCUIElement) -> Bool = LibraryDock.tap) -> Bool {
        let item = element("dockCategory-\(place)")
        guard item.waitForExistence(timeout: timeout), !element("dockList").exists else { return false }
        return press(item)
    }

    /// A plain tap, when the element is there.
    static func tap(_ target: XCUIElement) -> Bool {
        guard target.exists else { return false }
        target.tap()
        return true
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
}
