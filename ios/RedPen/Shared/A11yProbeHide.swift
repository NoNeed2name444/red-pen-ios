import SwiftUI

/// Diagnostic only (T0224, T0260): hides or omits ONE named region of a
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
/// `-rest-`), and `everything` is those and the rest regions (T0260, named
/// `<screen>-rest-<what>`, for what each screen draws outside the first
/// regions). A piece of a list that is several Sections cannot take a
/// modifier (it would stack them into one row, LaunchOpeningTests); there the
/// call site asks `A11yProbeHide.omits(_:)` in an `if` instead.
///
/// The regions, by the view each one hides (the names are the tests' too):
/// - library: `library-header` (the date, the name and the greeting),
///   `library-plan-card` (the exam countdown pill, or the button that sets it
///   up), `library-revision-card` (Today's revision), `library-search`,
///   `library-set-rows`, `library-tab-bar` (the dock), `library-tiles`
///   (Progress and Brain map); rest: `library-rest-account-menu`,
///   `library-rest-new-set`, `library-rest-sets-header` (Your sets, See all,
///   Select), `library-rest-build-session`, `library-rest-feature-tiles` (the
///   ways to practise and the tools), `library-rest-across-the-app`,
///   `library-rest-examples` (Try every feature, personal build only);
/// - quiz: `quiz-stem` (the patient chips, vitals, story and question),
///   `quiz-lab-table`, `quiz-options`, `quiz-top-bar` (the navigation bar),
///   `quiz-progress` (Question 1 of 3), `quiz-bottom-bar` (How sure? and the
///   buttons under it); rest: `quiz-rest-chart-title` (Single best answer,
///   Hint, Flag);
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
