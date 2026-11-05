// A ring's words stay inside its groove (T0211 A5): the review found "67%"
// and "Readiness" crossing the arc of Vitals' rings. WardRingFit gives the
// words the largest square inside the groove's hole; this checks the square's
// corners stay in it at every ring size the app draws, that it is the largest
// such square, and that WardRing places its words with it.
import Foundation

var failures: [String] = []
var passed = 0

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    if ok { passed += 1; return }
    print("FAIL " + label + "  | " + detail)
    failures.append(label)
}

check("the clearance is min(2, a third of the line)",
      WardRingFit.clear(lineWidth: 8) == 2 && WardRingFit.clear(lineWidth: 3) == 1 && WardRingFit.clear(lineWidth: 6) == 2)
// the rings: Vitals' four (8 wide, up to 120 across), home's (6 wide, 56),
// the focus round's (6 wide, 180) and its mini ring (3 wide, 22)
for lineWidth in [3.0, 6.0, 8.0] {
    for diameter in stride(from: 20.0, through: 200.0, by: 0.5) {
        let hole = WardRingFit.holeRadius(diameter: diameter, lineWidth: lineWidth)
        let side = WardRingFit.labelSide(diameter: diameter, lineWidth: lineWidth)
        let corner = side / 2 * 2.0.squareRoot()
        let name = "\(diameter) across, \(lineWidth) wide"
        check("\(name): the hole is inside the groove",
              abs(hole - (diameter / 2 - lineWidth - 2 * WardRingFit.clear(lineWidth: lineWidth))) < 1e-9 || hole == 0)
        check("\(name): the words' corners are inside the hole", corner <= hole + 1e-9, "\(corner) > \(hole)")
        check("\(name): and touch its edge, so the square is the largest", hole == 0 || abs(corner - hole) < 1e-9)
        if side > 0 {
            check("\(name): the ring that a square of that side asks for is this ring",
                  abs(WardRingFit.diameter(labelSide: side, lineWidth: lineWidth) - diameter) < 1e-9)
        }
    }
}
// before: the words were inset by the line's width alone inside the arc's
// frame, a square whose corners reached past the hole on Vitals' rings
let vitals = 76.0, line = 8.0
let oldSide = vitals - line - 2 * WardRingFit.clear(lineWidth: line) - 2 * line
check("the old inset crossed the groove on a 76-point Vitals ring",
      oldSide / 2 * 2.0.squareRoot() > WardRingFit.holeRadius(diameter: vitals, lineWidth: line))
check("the new square is smaller than the old one there",
      WardRingFit.labelSide(diameter: vitals, lineWidth: line) < oldSide)

// WardRing places its words with it (the source, from the repository root)
var root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
while !FileManager.default.fileExists(atPath: root.appendingPathComponent("ios/RedPen").path), root.path != "/" {
    root.deleteLastPathComponent()
}
let ring = (try? String(contentsOf: root.appendingPathComponent("ios/RedPen/Shared/Ward/WardVitals.swift"), encoding: .utf8)) ?? ""
check("WardRing lays out its arc and words with RingWords", ring.contains("RingWords(lineWidth: lineWidth) {"))
check("RingWords gives the words WardRingFit's square",
      ring.contains("WardRingFit.labelSide(diameter: Double(min(bounds.width, bounds.height))")
      && ring.contains("proposal: ProposedViewSize(width: side, height: side)"))
check("the words shrink to fit it", ring.contains(".minimumScaleFactor(0.5)"))
check("the words are no longer inset by the line alone", !ring.contains(".padding(lineWidth)\n"))

print(failures.isEmpty ? "\nALL \(passed) WARD RING FIT CHECKS PASS" : "\n\(failures.count) FAILED of \(passed + failures.count)")
exit(failures.isEmpty ? 0 : 1)
