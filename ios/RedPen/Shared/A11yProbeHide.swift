import SwiftUI

/// Diagnostic only (T0224): hides ONE named region of a screen, so a launch
/// can show which region holds an accessibility audit issue that names no
/// element. `-a11yProbeHide <region>` on the command line picks the region;
/// AccessibilityUITests' testProbeBisect* tests pass it, once per region, and
/// print the audit's issues for each. No other test and no production path
/// passes it.
///
/// Without the argument (every normal launch) `region` is nil, no name can
/// match it, and `a11yProbeHide` returns the view it was given, unchanged.
/// `-a11yProbeHide none` names no region either: it is the baseline launch
/// of the bisect, in the same launch mode as the others.
///
/// A hidden region is not drawn (opacity 0, its place in the layout kept, so
/// what is around it does not move) and is out of the accessibility tree
/// (accessibilityHidden). The two top bars are hidden with the navigation bar
/// itself (`navigationBar: true`), which takes the bar's height with it.
///
/// The regions, by the view each one hides (the names are the tests' too):
/// - library: `library-header` (the date, the name and the greeting),
///   `library-plan-card` (the exam countdown pill, or the button that sets it
///   up), `library-revision-card` (Today's revision), `library-search`,
///   `library-set-rows`, `library-tab-bar` (the dock), `library-tiles`
///   (Progress and Brain map);
/// - quiz: `quiz-stem` (the patient chips, vitals, story and question),
///   `quiz-lab-table`, `quiz-options`, `quiz-top-bar` (the navigation bar),
///   `quiz-progress` (Question 1 of 3), `quiz-bottom-bar` (How sure? and the
///   buttons under it);
/// - revealed card: `card-top-bar` (the navigation bar), `card-progress-row`
///   (cards left, done), `card-face`, `card-bottom-bar` (Accuracy and Save
///   to Ideas), `card-rating-row` (Again to Easy).
enum A11yProbeHide {
    /// The region named on the command line, or nil for a normal launch.
    /// Read once, as the other launch arguments are (PreviewLaunch).
    static let region: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-a11yProbeHide"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()
}

private struct A11yProbeHider: ViewModifier {
    let name: String
    let navigationBar: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if A11yProbeHide.region != name {
            content
        } else if navigationBar {
            content.toolbar(.hidden, for: .navigationBar)
        } else {
            content.opacity(0).accessibilityHidden(true)
        }
    }
}

extension View {
    /// Hides this view when the launch names `region` (`-a11yProbeHide`);
    /// returns it unchanged otherwise. With `navigationBar`, hides the
    /// enclosing navigation bar instead of this view.
    func a11yProbeHide(_ region: String, navigationBar: Bool = false) -> some View {
        modifier(A11yProbeHider(name: region, navigationBar: navigationBar))
    }
}
