import XCTest

/// The million map's measured proof (plan 4f's depth fade, before and after):
/// the Performance theme's 1,000,000-note demo flies its proof tour by itself
/// (GraphPerfTour, under -graphPreviewPerfTour), and this test follows it in
/// the speed readout ("perfReadout", whose value ends "tour: <phase>" and then
/// the tour's summary, a line per phase). It takes the stills - front, back,
/// near, chosen and far, each once its phase has settled - with the readout's
/// words beside each, and keeps the summary as text (the workflow puts it in
/// the job's summary too).
///
/// The readout is read only for a still and at the end: reading it asks the
/// app for its accessibility on its main thread, which costs frames, so the
/// tour's measured stretches between (the opening turn and zooms, and every
/// comparison of the Graphics levels) go unread.
///
/// The same tour with the depth fade off for the whole run
/// (-graphPreviewPerfFade off) gives the "before" stills, at the same poses;
/// a third run is screen-recorded on the iPhone, apart from the measured
/// ones, so the recording's load stays out of their numbers.
///
/// The simulator is not the device: its numbers compare before with after on
/// one Mac. Run by the "Design preview" workflow's perf-proof parts.
final class GraphPerfProofUITests: XCTestCase {
    func testPerfProofTour() {
        fly(as: "proof")
    }

    func testPerfProofTourFadeOff() {
        fly(as: "proof-before", arguments: ["-graphPreviewPerfFade", "off"],
            note: "The depth fade was off for this whole run: each comparison's \"fade on\" was off too.")
    }

    func testPerfProofRecorded() {
        fly(as: "proof-recorded", stills: false)
    }

    /// GraphPerfTour's phases in order, with when each starts (seconds into
    /// the tour); "done" is the readout's once the tour is over.
    private static let phases: [(name: String, start: Double)] = [
        ("warm", 0), ("measure", 3), ("front", 14), ("turn", 22), ("back", 23.2), ("near", 31.2), ("chosen", 44.2),
        ("far", 52.2), ("compare high fade off", 60.2), ("compare high fade on", 64.2),
        ("compare smooth fade off", 68.2), ("compare smooth fade on", 72.2), ("compare saver fade off", 76.2),
        ("compare saver fade on", 80.2), ("done", 84.2)
    ]

    /// The stills: the phase, how far into it the picture is taken (near flies
    /// in for 3 s first; after the half turn the far side has its detail well
    /// within 2 s), and the picture's name. Each still phase lasts 8 s.
    private static let stills: [(phase: String, after: Double, name: String)] = [
        ("front", 2, "1-front"), ("back", 2, "2-back"), ("near", 5, "3-near"), ("chosen", 2, "4-chosen"),
        ("far", 2, "5-far")
    ]

    /// Launches the million with the tour, follows it to the end, and keeps
    /// its stills and summary under `name` (the summary after `note`, if any).
    private func fly(as name: String, arguments: [String] = [], stills: Bool = true, note: String = "") {
        let app = XCUIApplication()
        app.launchArguments += ["-graphPreview", "-graphPreviewTheme", "performance", "-graphPreviewPerfDemo", "1000000",
                                "-graphPreviewPerfTour"] + arguments
        app.keepTraceOffConsole()
        app.launch()
        XCTAssertTrue(app.otherElements["graph3D"].waitForExistence(timeout: 120), "the map didn't open")
        let readout = app.descendants(matching: .any)["perfReadout"]
        XCTAssertTrue(readout.waitForExistence(timeout: 120), "no speed readout")
        // the Debug build makes the million on the simulator's few cores, which
        // has taken from about a minute to several on CI: 15 minutes at most
        guard watch(readout, until: { $0.contains("1,000,000 notes") }, within: 900, every: 1) != nil else {
            XCTFail("the million was not built within 15 minutes: " + String(Self.words(readout).suffix(300)))
            return
        }
        // the tour starts as the million is shown; its clock is the screen's,
        // so the phases come on time from when it was first seen
        var last = ""
        guard let first = watch(readout, until: { Self.phase(in: $0) != nil }, within: 120, every: 0.25),
              let begun = Self.phase(in: first) else {
            XCTFail("the tour did not start (no \"tour: \" in the readout): " + String(Self.words(readout).suffix(300)))
            return
        }
        last = first
        let start = Date().addingTimeInterval(-(Self.phases.first { $0.name == begun }?.start ?? 0))
        for still in stills ? Self.stills : [] {
            guard let at = Self.phases.first(where: { $0.name == still.phase })?.start else { continue }
            Self.wait(until: start.addingTimeInterval(at + still.after))
            guard let found = reach(still.phase, readout, within: 90, last: &last) else {
                XCTFail("the tour did not reach \(still.phase): " + String(last.suffix(300)))
                break
            }
            guard found == still.phase else {
                XCTFail("missed the \(still.phase) still: the readout was already at \(found)")
                continue
            }
            snap(name + "-" + still.name)
            keepText(last, as: name + "-" + still.name + "-readout")
        }
        // the end: the readout keeps the summary once the tour is done
        Self.wait(until: start.addingTimeInterval(Self.phases.last?.start ?? 0))
        let final = watch(readout, until: { Self.phase(in: $0) == "done" && Self.summary(in: $0).contains("\ndone: ") },
                          within: 120, every: 0.5)
        if final == nil {
            last = Self.words(readout)
            XCTFail("the tour did not end with its summary: " + String(last.suffix(300)))
        }
        let words = final ?? last
        let summary = Self.summary(in: words)
        let kept = note.isEmpty ? summary : note + "\n" + summary
        keepText(kept, as: name + "-summary")
        keepText(words, as: name + "-readout")
        print("== " + name + " summary\n" + kept + "\n== end of " + name + " summary")
        let lines = summary.split(separator: "\n")
        let missing = Self.phases.map(\.name).filter { phase in !lines.contains { $0.hasPrefix(phase + ": ") } }
        XCTAssertTrue(missing.isEmpty, "the summary has no line for " + missing.joined(separator: ", ") + ":\n" + summary)
        XCTAssertTrue(summary.contains("turn: swap "), "no swap time in the summary:\n" + summary)
        XCTAssertTrue(summary.contains("GPU memory peak"), "no GPU memory peak in the summary:\n" + summary)
    }

    // MARK: - Reading the readout

    /// The readout's words now ("" when it cannot be read).
    private static func words(_ readout: XCUIElement) -> String {
        ((try? readout.snapshot())?.value as? String) ?? ""
    }

    /// The tour's phase in the readout's words: what follows "tour: " to the line's end.
    private static func phase(in words: String) -> String? {
        guard let at = words.range(of: "tour: ") else { return nil }
        return String(words[at.upperBound...].prefix { $0 != "\n" })
    }

    /// The tour's summary in the readout's words: the lines after its phase.
    private static func summary(in words: String) -> String {
        guard let at = words.range(of: "tour: "), let line = words[at.upperBound...].firstIndex(of: "\n") else {
            return ""
        }
        return String(words[words.index(after: line)...])
    }

    /// Sleeps until `date` (at once if it has passed).
    private static func wait(until date: Date) {
        let left = date.timeIntervalSinceNow
        if left > 0 { usleep(UInt32(min(left, 600) * 1_000_000)) }
    }

    /// Reads the readout every `every` seconds until `ok` holds; its words then (nil if `within` ran out).
    private func watch(_ readout: XCUIElement, until ok: (String) -> Bool, within seconds: Double,
                       every: Double) -> String? {
        let end = Date().addingTimeInterval(seconds)
        repeat {
            let now = Self.words(readout)
            if ok(now) { return now }
            usleep(UInt32(every * 1_000_000))
        } while Date() < end
        return nil
    }

    /// Waits until the tour is at `wanted` or past it; the phase found, nil if
    /// `within` ran out. The words last read go in `last`.
    private func reach(_ wanted: String, _ readout: XCUIElement, within seconds: Double, last: inout String) -> String? {
        let order = Self.phases.map(\.name)
        guard let goal = order.firstIndex(of: wanted) else { return nil }
        let end = Date().addingTimeInterval(seconds)
        repeat {
            let now = Self.words(readout)
            if !now.isEmpty { last = now }
            if let phase = Self.phase(in: now), let at = order.firstIndex(of: phase), at >= goal { return phase }
            usleep(250_000)
        } while Date() < end
        return nil
    }

    // MARK: - Keeping what was seen

    private func keepText(_ text: String, as name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func snap(_ name: String) {
        let shot = uprightShot()
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
