import XCTest

/// The library's dock as the UI tests reach it, in whichever form it is drawn.
///
/// CategoryDock is a row of `dockCategory-<place>` buttons where they fit,
/// and otherwise one `dockList` button ("Sections, now Questions") that
/// opens a sheet listing every place, its rows carrying the same
/// `dockCategory-<place>` identifiers. Which form a phone gets depends on its
/// width and text size: an iPhone 17 Pro at the default size gets the list
/// button, so a test that waits for `dockCategory-questions` alone never
/// finds the library there.
struct LibraryDock {
    let app: XCUIApplication

    /// The dock in either form: Questions' button or the list button.
    var anyForm: XCUIElement {
        let either = NSPredicate(format: "identifier == %@ OR identifier == %@", "dockCategory-questions", "dockList")
        return app.descendants(matching: .any).matching(either).firstMatch
    }

    /// Whether the library is open: its dock, in either form, is there.
    func waitForLibrary(timeout: TimeInterval) -> Bool {
        anyForm.waitForExistence(timeout: timeout)
    }

    /// Goes to a place (a category or "ideas"): taps its dock button where
    /// the dock shows one, or else opens the list and taps its row there.
    /// `press` does the tapping, so a test can keep its own way of pressing
    /// raised glass. False when neither form is found or the row is not in
    /// the list (which is then closed again).
    func choose(_ place: String, timeout: TimeInterval = 5,
                press: (XCUIElement) -> Bool = LibraryDock.tap) -> Bool {
        let item = element("dockCategory-\(place)")
        let list = element("dockList")
        guard waitForLibrary(timeout: timeout) else { return false }
        if item.exists { return press(item) }
        guard list.exists, press(list) else { return false }
        // the sheet's row for the place
        guard item.waitForExistence(timeout: 5) else {
            closeList()
            return false
        }
        for _ in 0..<4 where !item.isHittable {
            app.swipeUp()
        }
        guard press(item) else {
            closeList()
            return false
        }
        // the sheet goes once a row is chosen
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: item)
        _ = XCTWaiter.wait(for: [gone], timeout: 5)
        return true
    }

    /// A plain tap, when the element is there.
    static func tap(_ target: XCUIElement) -> Bool {
        guard target.exists else { return false }
        target.tap()
        return true
    }

    private func closeList() {
        let done = app.buttons["Done"].firstMatch
        if done.exists && done.isHittable { done.tap() }
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
}
