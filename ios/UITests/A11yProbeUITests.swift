import XCTest

/// Diagnostic, not a check (T0177): it never fails on what the audit finds.
///
/// It opens the "a11y-probe" preview at the largest accessibility text size
/// (as AccessibilityUITests sets it), once per way of setting the font
/// (`-a11yProbeVariant a` to `f`, PreviewExtras' A11yProbe), runs only the
/// Dynamic Type audit, and prints one PROBE-FLAG line for each text it
/// flags, then PROBE-DONE. It runs in the accessibility step beside the real audit (app-build.yml).
final class A11yProbeUITests: XCTestCase {
    func testDynamicTypeProbeDiagnostic() throws {
        for variant in ["a", "b", "c", "d", "e", "f"] {
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
                try app.performAccessibilityAudit(for: .dynamicType) { issue in
                    print("PROBE-FLAG", issue.element?.identifier ?? "?", issue.compactDescription)
                    return true
                }
                probe.swipeUp()
            }
            app.terminate()
        }
        print("PROBE-DONE")
    }
}
