import SwiftUI

/// Diagnostic only (T0224, T0260, T0261): hides or omits ONE named region of a
/// screen, so a launch can show which region holds an accessibility audit
/// issue that names no element. `-a11yProbeHide <region>` hides a region and
/// `-a11yProbeOmit <region>[,<region>...]` takes one or more out of the view
/// tree; AccessibilityUITests' testProbeBisect* tests pass them, one variant
/// per launch, and print the audit's issues for each. No other test and no
/// production path passes either.
///
/// Without the arguments (every normal launch) `region` is nil, `omitted` is
/// empty, no name can match, and `a11yProbeHide` returns the view it was
/// given, unchanged. `-a11yProbeHide none` names no region either: it is the
/// baseline launch of the bisect, in the same launch mode as the others.
///
/// A hidden region is not drawn (opacity 0, its place in the layout kept, so
/// what is around it does not move) and is out of the accessibility tree
/// (accessibilityHidden), but it is still built: its views, their text and
/// their frames are in the view hierarchy. An omitted region is not built at
/// all: the view is an EmptyView in its place, so nothing of it is in the
/// hierarchy and the layout closes over it. Omitting is the stronger
/// removal: an issue that stays with a region hidden and goes with it omitted
/// is measured on something a hide leaves behind. The two top bars are hidden
/// or omitted with the navigation bar itself (`navigationBar: true`), which
/// takes the bar's height with it; a bar cannot be built out of its screen,
/// so for them omit is the same as hide.
///
/// Each omit value is a region name, or one of two words: `all` is every
/// region the first bisect named (T0224, the names below that carry no
/// `-rest-`), and `everything` is those and the rest regions (T0260 and
/// T0261, named `<screen>-rest-<what>`, for what each screen draws outside
/// the first regions, and for the pieces inside the library's search row and
/// the quiz's bottom bar). A piece of a list that is several Sections cannot
/// take a modifier (it would stack them into one row, LaunchOpeningTests);
/// there the call site asks `A11yProbeHide.omits(_:)` in an `if` instead.
///
/// The regions, by the view each one hides (the names are the tests'
/// too). After each, whether a test still launches it alone ("in the test")
/// and what a run already answered. The run is 43401453464 (f3f2e5d6), whose
/// baselines each had one "Text clipped" with no element: the library's with
/// 152 nodes, the quiz's with 105.
/// - library: `library-header` (the date, the name and the greeting;
///   answered, 2 issues, the flag stays), `library-plan-card` (the exam
///   countdown pill, or the button that sets it up; answered, left the flag),
///   `library-revision-card` (Today's revision; answered, 2 issues, the flag
///   stays), `library-search` (the search row; in the test as a control;
///   answered, its omit took the flag to 0), `library-set-rows` (answered,
///   left the flag; not in the tree on this screen), `library-tab-bar` (the
///   dock; answered, left the flag), `library-tiles` (Progress and Brain map;
///   answered, left the flag);
/// - library, rest: `library-rest-account-menu` (in the test as a control;
///   answered, its omit took the flag to 0), `library-rest-new-set` (answered,
///   left the flag), `library-rest-sets-header` (Your sets, See all, Select),
///   `library-rest-build-session`, `library-rest-feature-tiles` (the ways to
///   practise and the tools), `library-rest-across-the-app`,
///   `library-rest-examples` (Try every feature, personal build only): the
///   last five were not in the tree (their omits left the node count at the
///   baseline's), and no test launches any of the six now;
/// - library, inside the search row (T0261, in the test; all three are in
///   `library-search`, which is in the test): `library-rest-search-glyph` (the
///   magnifier Image), `library-rest-search-prompt` (SearchPrompt: the prompt
///   drawn over the field, accessibility-hidden, one line), and
///   `library-rest-search-field` (the TextField, "librarySearch");
/// - quiz: `quiz-stem` (the patient chips, vitals, story and question),
///   `quiz-lab-table`, `quiz-options`, `quiz-top-bar` (the navigation bar),
///   `quiz-progress` (Question 1 of 3), all answered, left the flag, and not
///   launched by a test now; `quiz-bottom-bar` (How sure? and the buttons
///   under it; in the test as a control; answered, its omit took the flag to
///   0, its hide left it); `quiz-rest-chart-title` (Single best answer, Hint,
///   Flag; answered, left the flag);
/// - quiz, inside the bottom bar (T0261, in the test; all are in
///   `quiz-bottom-bar`): `quiz-rest-confidence` (the whole How sure? picker
///   where `footer` uses it), `quiz-rest-sure-label` (the Text "How sure?"),
///   `quiz-rest-sure-tag` (the "optional" chip in that picker only, not the
///   one on "Why did you miss it?"), `quiz-rest-sure-chips` (Sure, Maybe,
///   Guess; an `if`, so it can be omitted but not hidden),
///   `quiz-rest-back-button`, `quiz-rest-check-button` (the Check answer or
///   Next button), `quiz-rest-answer-buttons` (the whole row of Back, Explain
///   and the main button, set where `answerButtons` builds the row, so both
///   the deck's call and the accessibility-size page's own call are in it).
///   T0261's are for omit;
/// - quiz, inside the two buttons (T0265, in the test; the buttons are in
///   `quiz-bottom-bar`): these are not wrapper views but one
///   `A11yProbeHide.omits(_:)` test at one site each, so they can be omitted
///   and not hidden. `quiz-rest-back-title` (Back's label is the bare chevron:
///   the word is not built), `quiz-rest-check-title` (Check's label is the bare
///   symbol image), `quiz-rest-back-disabled` and `quiz-rest-check-disabled`
///   (the button is enabled where the audit's quiz state has it disabled: Back
///   on question 0, Check with nothing picked);
/// - revealed card: `card-top-bar` (the navigation bar), `card-progress-row`
///   (cards left, done), `card-face`, `card-bottom-bar` (Accuracy and Save
///   to Ideas), `card-rating-row` (Again to Easy).
enum A11yProbeHide {
    /// The region hidden on the command line, or nil for a normal launch.
    /// Read once, into a static let, as LaunchStage reads its launch arguments.
    static let region: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-a11yProbeHide"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    /// The names omitted on the command line (`-a11yProbeOmit a,b`), empty
    /// for a normal launch.
    static let omitted: [String] = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-a11yProbeOmit"), i + 1 < args.count else { return [] }
        return args[i + 1].split(separator: ",").map { String($0) }
    }()

    /// Whether the launch omits the region `name`: named in the list, or
    /// covered by `all` (every region but the rest ones) or `everything`.
    static func omits(_ name: String) -> Bool {
        guard !omitted.isEmpty else { return false }
        if omitted.contains(name) || omitted.contains("everything") { return true }
        return omitted.contains("all") && !name.contains("-rest-")
    }
}

private struct A11yProbeHider: ViewModifier {
    let name: String
    let navigationBar: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if A11yProbeHide.region != name && !A11yProbeHide.omits(name) {
            content
        } else if navigationBar {
            content.toolbar(.hidden, for: .navigationBar)
        } else if A11yProbeHide.omits(name) {
            EmptyView()
        } else {
            content.opacity(0).accessibilityHidden(true)
        }
    }
}

extension View {
    /// Hides this view when the launch names `region` (`-a11yProbeHide`), or
    /// builds nothing in its place when the launch omits it
    /// (`-a11yProbeOmit`); returns it unchanged otherwise. With
    /// `navigationBar`, hides the enclosing navigation bar instead of this
    /// view, for hide and omit alike.
    func a11yProbeHide(_ region: String, navigationBar: Bool = false) -> some View {
        modifier(A11yProbeHider(name: region, navigationBar: navigationBar))
    }
}
