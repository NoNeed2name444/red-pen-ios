import XCTest

/// Diagnostic, not a check (T0241): it never fails on what the audit finds.
///
/// At the default text size the audit of the chart quiz flags the lab table
/// however it is labelled: with the table as one `.ignore` element and a joined
/// label (T0223) it names "Hit area is too small" on that element and "Dynamic
/// Type font sizes are partially unsupported" on the four texts of the lab row
/// (run 43183776170); before T0223 it named the name cell. This test opens the
/// example quiz (the "quiz" preview, as the bisect of T0224 does) once per
/// accessibility shape of ChartLabsTable, with `-a11yProbeLabs <name>`
/// (Shared/A11yProbeLabs.swift, where each shape is described), runs one audit
/// pass with the real audit's types, and prints one line:
///
///     LABS-VARIANT <name> issues=<n> <issue>[<element>]=<count>; ... nodes=<n>
///
/// `<issue>` is the audit's own short text, `<element>` the element's
/// identifier, else label (40 characters), else nil where it names none, and
/// `nodes` the size of the screen's accessibility tree (a shape that changed
/// nothing, or a name the app does not know, has the baseline's). `V0-present`
/// is the table as shipped: the app takes no variant from the name, so it is the
/// baseline, launched the same way as the rest. The quiz has 6 issues in that
/// shape (the lab row's hit area 1, its Dynamic Type 4, one "Text clipped" with
/// no element that comes from another region); the shape that clears the lab
/// table's flags shows `issues=1`, with only that one left. `Text clipped[nil]=1`
/// in every line is the control.
///
/// The other lines: `LABS-VARIANT-ERROR <name> <why>` for a shape whose screen
/// did not open, whose audit threw, or that was not run because the time was
/// used up; `LABS-VARIANT-DONE launches=<k> seconds=<s>`, the time actually
/// spent. Read: `grep -E "LABS-VARIANT" a11y.log` (the ui-test artifact; the
/// accessibility step's live output keeps only lines with "PROBE-" in them).
///
/// Time: a launch and an audit cost about 20 s, and the whole test is held to
/// about 180 s. The baseline always runs, first. A later shape is started only if
/// what has been spent plus the dearest launch so far still fits, so the shapes
/// are listed in the order in which each is thought most likely to answer: the
/// ones left out, if time runs short, are the last. It never fails on what the
/// audit finds; a launch that cannot be made is the only way it fails.
final class A11yLabsProbeUITests: XCTestCase {
    /// The shapes' names, as A11yProbeLabs.Variant spells them, in the order they
    /// are run: V0 first, then the whole-table `.combine` (the system's own way
    /// of one element), the static text trait on V0 (aimed at the hit area), one
    /// Text per result (no child nodes), the shape before T0223, V0 with the
    /// font set without a weight (aimed at the Dynamic Type flags), `.combine` per
    /// result, and V0 with each of its two layouts alone.
    private static let variants: [String] = [
        "V0-present", "V2-combine-table", "V7-static-text-trait", "V6-single-text", "V1-name-cell",
        "V8-font-no-weight", "V3-combine-rows", "V4-grid-only", "V5-stack-only",
    ]

    /// Seconds for the whole test.
    private static let budget: TimeInterval = 180

    /// Everything the audit knows how to check, except colour contrast, as
    /// AccessibilityUITests audits.
    private static let audited: XCUIAccessibilityAuditType = XCUIAccessibilityAuditType.all.subtracting([.contrast])

    private var app: XCUIApplication!

    /// What the audit found in the shape being run: the issue's text and its
    /// element, and how many times.
    private var tally: [String: Int] = [:]

    override func setUp() {
        continueAfterFailure = true
    }

    func testLabsVariantsDiagnostic() {
        let started = Date()
        var cost: TimeInterval = 0
        var launches = 0
        for name in Self.variants {
            // the baseline always runs; a later shape only if it would still fit,
            // costed as the dearest launch so far
            if launches > 0, Date().timeIntervalSince(started) + cost > Self.budget {
                print("LABS-VARIANT-ERROR \(name) not run: the \(Int(Self.budget)) s for the shapes is used up")
                continue
            }
            let began = Date()
            runVariant(name)
            cost = max(cost, Date().timeIntervalSince(began))
            launches += 1
        }
        print("LABS-VARIANT-DONE launches=\(launches) seconds=\(Int(Date().timeIntervalSince(started)))")
    }

    /// One launch with one shape, one audit, one LABS-VARIANT line.
    private func runVariant(_ name: String) {
        app = XCUIApplication()
        app.keepTraceOffConsole()
        // as the bisect: the personal build and a still sky, the example quiz
        // opened straight away at the default text size, and the shape
        app.launchArguments += ["-personalBuild", "-stillSky", "-uiPreviewScreen", "quiz",
                                "-a11yProbeLabs", name]
        app.launch()
        let marks: [NSPredicate] = ["studyMore", "studyBarFold"].map { NSPredicate(format: "identifier == %@", $0) }
        let marker = app.descendants(matching: .any)
            .matching(NSCompoundPredicate(orPredicateWithSubpredicates: marks)).firstMatch
        guard marker.waitForExistence(timeout: 20) else {
            print("LABS-VARIANT-ERROR \(name) the screen did not open within 20 s")
            app.terminate()
            return
        }
        // the screen a moment to settle before it is read
        usleep(500_000)
        let nodes: Int = nodeCount()
        tally = [:]
        var threw = ""
        XCTContext.runActivity(named: "Labs shape: \(name)") { _ in
            do {
                try app.performAccessibilityAudit(for: Self.audited) { [unowned self] issue in
                    self.tallyIssue(issue)
                }
            } catch {
                threw = "\(error)"
            }
        }
        if threw.isEmpty {
            let total: Int = tally.values.reduce(0, +)
            let kinds: String = tally.keys.sorted().map { "\($0)=\(tally[$0] ?? 0)" }.joined(separator: "; ")
            print("LABS-VARIANT \(name) issues=\(total) \(kinds.isEmpty ? "no issue" : kinds) nodes=\(nodes)")
        } else {
            print("LABS-VARIANT-ERROR \(name) the audit threw \(threw.replacingOccurrences(of: "\n", with: " "))")
        }
        app.terminate()
    }

    /// One audit issue, counted and let through.
    private func tallyIssue(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        var who = "nil"
        if let found = issue.element {
            let named: String = (found.identifier.isEmpty ? found.label : found.identifier)
                .replacingOccurrences(of: "\n", with: " ")
            who = named.isEmpty ? "unnamed" : String(named.prefix(40))
        }
        tally["\(issue.compactDescription)[\(who)]", default: 0] += 1
        return true
    }

    /// How many nodes the screen's accessibility snapshot holds, or -1 when it
    /// cannot be read.
    private func nodeCount() -> Int {
        guard let tree = try? app.snapshot() else { return -1 }
        func size(_ node: any XCUIElementSnapshot) -> Int {
            node.children.reduce(1) { $0 + size($1) }
        }
        return size(tree)
    }
}
