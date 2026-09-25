import Foundation

/// When the first-run pages (FirstRunView) are shown: once per account, to an
/// account new to this device - straight after its recording terms - and
/// never to somebody who was already studying here before they existed.
///
/// Foundation only, so the Linux suite (FirstRunTests) checks the rules
/// without SwiftUI.
enum FirstRun {
    /// In the keys, so changing the pages enough to ask again is one bump.
    static let version = 1

    /// Launch arguments: the UI test that walks the pages asks for them, and
    /// anyone can switch them off.
    static let showArgument = "-showOnboarding"
    static let hideArgument = "-disableOnboarding"

    static func doneKey(for accountId: String) -> String {
        "firstRun.v\(version).done.\(accountId)"
    }

    /// Set on the first page, so a flow left half way (the app stopped on
    /// page two) comes back rather than being lost.
    static func startedKey(for accountId: String) -> String {
        "firstRun.v\(version).started.\(accountId)"
    }

    /// Whether this launch may show the pages at all. Never for a screenshot
    /// or design-preview run, and never in the simulator - where the UI tests
    /// run, each expecting the library straight after the exam question -
    /// unless the launch asks for them. The owner's iPhone and iPad are
    /// never a simulator.
    static func allowed(arguments: [String], preview: Bool, simulator: Bool) -> Bool {
        if arguments.contains(showArgument) { return true }
        if preview || arguments.contains(hideArgument) { return false }
        return !simulator
    }

    /// Whether this account still has the pages to see.
    ///
    /// - justAgreed: it agreed to the recording terms during this run - a new
    ///   account, or new to this device.
    /// - examAsked: the device already answered the old one-page exam
    ///   question, so whoever is here is not new to the app.
    /// - forced: the launch asked for the pages (the UI test) - shown even
    ///   to an account that has finished them, since a simulator that has
    ///   run the test before keeps its account (FirstRunStore stops them
    ///   coming back within the run).
    static func isDue(accountId: String, justAgreed: Bool, examAsked: Bool, forced: Bool,
                      defaults: UserDefaults = .standard) -> Bool {
        if forced { return true }
        if defaults.bool(forKey: doneKey(for: accountId)) { return false }
        if justAgreed || !examAsked { return true }
        return defaults.bool(forKey: startedKey(for: accountId))
    }

    static func start(accountId: String, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: startedKey(for: accountId))
    }

    static func finish(accountId: String, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: doneKey(for: accountId))
        defaults.removeObject(forKey: startedKey(for: accountId))
    }
}

/// The five pages the TipKit tips (StudyTips) wait for. A tip is about a
/// screen, so it waits until that screen is familiar - opened twice already -
/// and is then shown once.
enum TipScreen: String, CaseIterable {
    /// Any study screen with the More menu: "Turn into…".
    case study
    /// The library's list of sets: hold a set for more.
    case library
    /// A card review: Undo after a rating.
    case review
    /// Study Lens: scanning a photo or PDF.
    case lens
    /// Ideas: the map's theme picker.
    case ideas
}

enum TipSightings {
    /// Openings before a tip may show: "seen twice", so the third.
    static let before = 2
    /// Counting stops here; nothing needs more.
    static let cap = 1000

    static let showArgument = "-showTips"
    static let hideArgument = "-disableTips"

    static func key(_ screen: TipScreen) -> String {
        "tips.seen.\(screen.rawValue)"
    }

    static func count(_ screen: TipScreen, defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: key(screen))
    }

    /// One more opening of the screen; the new count.
    @discardableResult
    static func record(_ screen: TipScreen, defaults: UserDefaults = .standard) -> Int {
        let now: Int = min(count(screen, defaults: defaults) + 1, cap)
        defaults.set(now, forKey: key(screen))
        return now
    }

    /// Whether the screen's tip may show now: it has been opened twice before
    /// this time.
    static func ready(_ screen: TipScreen, defaults: UserDefaults = .standard) -> Bool {
        count(screen, defaults: defaults) > before
    }

    /// Whether this launch shows tips at all - the same rule as the first-run
    /// pages: a popover over a button is exactly what a UI test's tap must
    /// not meet.
    static func allowed(arguments: [String], preview: Bool, simulator: Bool) -> Bool {
        if arguments.contains(showArgument) { return true }
        if preview || arguments.contains(hideArgument) { return false }
        return !simulator
    }
}
