import XCTest

/// Diagnostic, not a check (T0177): it never fails on what the audit finds.
///
/// It opens the "a11y-probe" preview at the largest accessibility text size
/// (as AccessibilityUITests sets it), once per way of setting the font
/// (`-a11yProbeVariant a` to `f`, PreviewExtras' A11yProbe), runs only the
/// Dynamic Type audit, and prints one PROBE-FLAG line for each text it
/// flags, then PROBE-DONE. It runs in the accessibility step beside the real audit (app-build.yml).
///
/// The probe of the default-size audit (T0218) is not here: it needs
/// AccessibilityUITests' private way around the app, so it is
/// AccessibilityUITests.testDefaultSizeAuditProbeDiagnostic, and the same step runs it.
///
/// Nor is the bisect of that probe's four issues with no element (T0224): it
/// launches the app once per region of a screen with `-a11yProbeHide <region>`
/// (Shared/A11yProbeHide.swift) and prints a PROBE-BISECT line for each, as
/// AccessibilityUITests.testProbeBisect{Library,Quiz,Card}Diagnostic.
///
/// An app that stops running during a pass (T0242) prints `PROBE-CRASH
/// a11y-probe-<variant> pass=<n>` (n from 1) and fails the test: a crash is a
/// red, not a skip. The next variant launches the app anew, which is the
/// relaunch; a test has two of them, and a third stop prints
/// `PROBE-CRASH-STOP` and ends the variants.
final class A11yProbeUITests: XCTestCase {
    /// The audit's error domain and its code for an app that is gone
    /// (`Code=-51 "Invalid XCUIApplication."`).
    private static let auditDomain = "com.apple.xcode.xctest.accessibilityAudit"
    private static let maxRelaunches = 2

    func testDynamicTypeProbeDiagnostic() throws {
        var crashes = 0
        for variant in ["a", "b", "c", "d", "e", "f"] {
            if crashes > Self.maxRelaunches {
                print("PROBE-CRASH-STOP a11y-probe-\(variant) the app stopped \(crashes) times; this test has used its \(Self.maxRelaunches) relaunches")
                break
            }
            let app = XCUIApplication()
            app.keepTraceOffConsole()
            app.launchArguments += ["-personalBuild", "-stillSky", "-uiPreviewScreen", "a11y-probe",
                                    "-a11yProbeVariant", variant,
                                    "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launch()
            let probe = app.descendants(matching: .any)["a11yProbe"]
            guard probe.waitForExistence(timeout: 20) else {
                print("PROBE-MISSING", variant)
                continue
            }
            // the top, then twice further down: the audit reads what is on screen
            for pass in 0..<3 {
                print("PROBE-PASS", variant, pass)
                var thrown: Error?
                do {
                    try app.performAccessibilityAudit(for: .dynamicType) { issue in
                        print("PROBE-FLAG", issue.element?.identifier ?? "?", issue.compactDescription)
                        return true
                    }
                } catch {
                    thrown = error
                }
                if appIsGone(app, thrown) {
                    crashes += 1
                    print("PROBE-CRASH a11y-probe-\(variant) pass=\(pass + 1)")
                    XCTFail("the app stopped running during the a11y-probe variant \(variant) audit (pass \(pass + 1))")
                    break
                }
                if let thrown { throw thrown }
                probe.swipeUp()
            }
            app.terminate()
        }
        print("PROBE-DONE")
    }

    /// The app is not running, or the audit says so (Code -51).
    private func appIsGone(_ app: XCUIApplication, _ error: Error?) -> Bool {
        if app.state == .notRunning { return true }
        guard let error else { return false }
        let failure = error as NSError
        return failure.domain == Self.auditDomain && failure.code == -51
    }
}
