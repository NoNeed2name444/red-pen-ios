// Stethoscore · the launch opening: the heartbeat's timing, the ECG drawn
// in step with the sound, home arriving in one wave behind the ECG, and the
// art, paper and sound files the opening is built on.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func near(_ a: Double, _ b: Double, _ tol: Double = 1e-6) -> Bool { abs(a - b) <= tol }

let withSound = LaunchOpening()
let still = LaunchOpening(reduced: true)

// MARK: the first frame is the launch screen

for (name, o) in [("full", withSound), ("reduced", still)] {
    check("\(name): the mark starts at its launch-screen size", o.beat(at: 0) == 1 && o.markScale(at: 0) == 1)
    check("\(name): no ECG on the first frame", o.ecgDrawn(at: 0) == nil)
    check("\(name): nothing of home is drawn before the hand-off",
          o.entrance(from: o.openingArrives, at: o.handoff - 0.001).scale <= 0.0001
          && o.entrance(from: o.arrival(y: 100, from: 600, to: 250), at: o.handoff - 0.001).scale <= 0.0001)
    check("\(name): the title's letters wait at nothing", (0..<11).allSatisfy { o.letter($0, at: 0).scale == 0 })
    let samples = o.times()
    check("\(name): key times run from 0 to the end", samples.first == 0 && near(samples.last!, o.duration))
    check("\(name): the mark has shrunk to nothing when the splash goes", o.markScale(at: o.duration) <= 0.001)
    let scales = samples.map { o.markScale(at: $0) }
    check("\(name): and only ever shrinks", zip(scales, scales.dropFirst()).allSatisfy { $0 >= $1 })
}

// MARK: length

// the last part to arrive is the one above the title the farthest the wave
// can reach; a part is done moving to the eye once it stays within half a
// point of its place (its 10 pt rise, and a 200 pt part's scale)
let lastArrival = withSound.landed + LaunchOpening.topLead
let moving = stride(from: 0.0, through: 1, by: 0.001).first { t in
    stride(from: t, through: t + 0.5, by: 0.005).allSatisfy { u in
        let s = LaunchOpening.spring(u)
        return LaunchOpening.rise * abs(1 - s) < 0.5 && 200 * (1 - LaunchOpening.contentScale) * abs(1 - s) < 0.5 } }!
check("the hand-off moves for 0.6 to 0.8 s after the ECG", (0.6...0.8).contains(lastArrival + moving - withSound.handoff),
      "\(lastArrival + moving - withSound.handoff)")
check("and all is still within a second of it", withSound.settled - withSound.handoff <= 1.0,
      "\(withSound.settled - withSound.handoff)")
check("the opening, hand-off and all, is still within 1.7 s", withSound.settled <= 1.7, "\(withSound.settled)")
check("Reduce Motion is done within 0.2 s", still.settled <= 0.2 && still.duration <= 0.2, "\(still.settled)")

// MARK: the heartbeat, in step with the sound

func peak(_ o: LaunchOpening, _ from: Double, _ to: Double) -> (t: Double, v: Double) {
    var best = (t: from, v: 0.0)
    var t = from
    while t <= to { let v = o.beat(at: t); if v > best.v { best = (t, v) }; t += 0.001 }
    return best
}
let lub = peak(withSound, withSound.r - 0.05, withSound.r + 0.15)
let dub = peak(withSound, withSound.s2 - 0.05, withSound.s2 + 0.15)
check("the lub swells to 1.06", near(lub.v, 1.06, 0.001), "\(lub)")
check("the dub to 1.04", near(dub.v, 1.04, 0.001), "\(dub)")
check("the lub peaks just after S1 is heard", lub.t > withSound.r && lub.t < withSound.r + 0.09, "\(lub.t)")
check("the dub peaks just after S2", dub.t > withSound.s2 && dub.t < withSound.s2 + 0.09, "\(dub.t)")
check("back to 1 between the two", near(withSound.beat(at: (withSound.r + 0.16 + withSound.s2 - 0.02) / 2), 1, 0.003))
check("back to 1 before the hand-off", near(withSound.beat(at: withSound.handoff), 1, 0.001))
check("no beat under Reduce Motion", still.times().allSatisfy { still.beat(at: $0) == 1 })

// MARK: the sound file, measured

func caf(_ path: String) -> (samples: [Double], rate: Double)? {
    guard let d = FileManager.default.contents(atPath: path), d.count > 8,
          String(decoding: d.prefix(4), as: UTF8.self) == "caff" else { return nil }
    let b = [UInt8](d)
    func be(_ at: Int, _ n: Int) -> UInt64 { (0..<n).reduce(0) { $0 << 8 | UInt64(b[at + $1]) } }
    var i = 8, rate = 0.0
    var samples: [Double] = []
    while i + 12 <= b.count {
        let kind = String(decoding: b[i..<i + 4], as: UTF8.self)
        let size = Int(be(i + 4, 8))
        let body = i + 12
        if kind == "desc" { rate = Double(bitPattern: be(body, 8)) }
        if kind == "data" {
            var j = body + 4
            while j + 1 < body + size {
                samples.append(Double(Int16(bitPattern: UInt16(be(j, 2)))) / 32768)
                j += 2
            }
        }
        i = body + size
    }
    return (samples, rate)
}

/// As tools/make_heartbeat.py --measure: where the 5 ms RMS first passes a
/// tenth of its peak, for the first sound and the next after 60 ms of quiet.
func onsets(_ x: [Double], _ rate: Double) -> (Double, Double) {
    let win = Int(0.005 * rate)
    var rms = [Double](repeating: 0, count: x.count)
    var sum = 0.0
    for i in 0..<x.count {
        sum += x[i] * x[i]
        if i >= win { sum -= x[i - win] * x[i - win] }
        rms[i] = (max(sum, 0) / Double(win)).squareRoot()
    }
    let level = 0.1 * (rms.max() ?? 0)
    let first = rms.firstIndex { $0 > level } ?? 0
    var quiet = 0, i = first
    while i < x.count {
        quiet = rms[i] > level ? 0 : quiet + 1
        if Double(quiet) > 0.06 * rate { break }
        i += 1
    }
    let second = rms[i...].firstIndex { $0 > level } ?? i
    return (Double(first) / rate, Double(second) / rate)
}

if let sound = caf("ios/RedPen/Assets.xcassets/Heartbeat.dataset/heartbeat.caf") {
    let (s1, s2) = onsets(sound.samples, sound.rate)
    check("the file's S1 is where HeartbeatSound says", near(s1, HeartbeatSound.s1, 0.001), "\(s1)")
    check("the file's S2 is where HeartbeatSound says", near(s2, HeartbeatSound.s2, 0.001), "\(s2)")
    check("the file is as long as it says", near(Double(sound.samples.count) / sound.rate, HeartbeatSound.length, 0.001))
    check("S1 to S2 is a resting systole (0.25-0.35 s)", (0.25...0.35).contains(s2 - s1), "\(s2 - s1)")
} else {
    check("the heartbeat .caf reads", false, "not found or not a CAF")
}

// MARK: the ECG, drawn as the sound is heard

let o = withSound
check("the sound starts so that S1 lands on the R peak", near(o.audioAt + HeartbeatSound.s1, o.r))
check("and S2 on the end of the T wave", near(o.audioAt + HeartbeatSound.s2, o.s2))
var tallest = (t: 0.0, v: -1.0)
var t = 0.0
while t < o.traceEnd { let v = o.ecgHeight(at: t); if v > tallest.v { tallest = (t, v) }; t += 0.0005 }
check("the R peak is the tallest point, on S1", near(tallest.t, o.r, 0.001) && near(tallest.v, 1, 0.01), "\(tallest)")
check("P comes before QRS", o.ecgHeight(at: o.r - 0.15) > 0.1 && o.ecgHeight(at: o.r - 0.07) < 0.02)
let tWave = o.ecgHeight(at: o.s2 - 0.09)
check("the T wave rises between S1 and S2", tWave > 0.2, "\(tWave)")
check("the T wave has ended by S2", abs(o.ecgHeight(at: o.s2)) < 0.01 && abs(o.ecgHeight(at: o.s2 + 0.03)) < 0.002,
      "\(o.ecgHeight(at: o.s2))")
check("Q and S dip below the line", o.ecgHeight(at: o.r - 0.022) < 0 && o.ecgHeight(at: o.r + 0.022) < 0)
check("the baseline is flat where it starts", abs(o.ecgHeight(at: 0.05)) < 0.001)

// the drawing head is at the trace time of the moment, once the baseline is out
if let at = o.ecgDrawn(at: o.r) { check("the head is on the R peak when S1 is heard", near(at.to, o.r)) }
else { check("the head is on the R peak when S1 is heard", false) }
if let at = o.ecgDrawn(at: o.s2) { check("the head is at the T wave's end when S2 is heard", near(at.to, o.s2)) }
else { check("the head is at the T wave's end when S2 is heard", false) }

let early = o.ecgDrawn(at: 0.04)!
check("it appears as a baseline growing out from its centre",
      near((early.from + early.to) / 2, LaunchOpening.baselineGrow / 2) && early.to - early.from < 0.05, "\(early)")
let drawn = o.times(rate: 240).compactMap { o.ecgDrawn(at: $0) }
check("its head never goes back", zip(drawn, drawn.dropFirst()).allSatisfy { $0.to <= $1.to + 1e-9 })
if let whole = o.ecgDrawn(at: o.handoff) {
    check("the trace is drawn whole when the hand-off starts", whole.from == 0 && near(whole.to, o.traceEnd))
} else { check("the trace is drawn whole when the hand-off starts", false) }
check("no ECG under Reduce Motion", still.times().allSatisfy { still.ecgDrawn(at: $0) == nil })

let trace = o.trace(width: 160, height: 30)
check("the trace runs the full width", near(trace.points.first!.x, 0) && near(trace.points.last!.x, 160))
check("its R peak is 30 pt high (drawn upward)", abs((trace.points.map { $0.y }.min() ?? 0) + 30) < 0.5)
let fractions = stride(from: 0.0, through: o.traceEnd, by: 0.002).map { LaunchOpening.fraction($0, of: trace, end: o.traceEnd) }
check("trim fractions only grow along the trace", zip(fractions, fractions.dropFirst()).allSatisfy { $0 <= $1 })
check("trim fractions run 0 to 1",
      LaunchOpening.fraction(0, of: trace, end: o.traceEnd) == 0 && near(LaunchOpening.fraction(o.traceEnd, of: trace, end: o.traceEnd), 1))

// MARK: the hand-off

check("the hand-off starts once the trace is whole", near(o.handoff, o.traceEnd))
check("the ECG starts its journey at the hand-off and lands when the splash goes",
      o.travel(at: o.handoff) == 0 && near(o.travel(at: o.landed), 1) && o.landed <= o.duration)
let journey = o.times().map { o.travel(at: $0) }
check("and never goes back", zip(journey, journey.dropFirst()).allSatisfy { $0 <= $1 + 1e-12 })
check("the mark is still whole when the hand-off starts", o.markScale(at: o.handoff) == 1)
// the wave: an ECG starting at y 600 and landing on a squiggle at y 250
let (y0, y1) = (600.0, 250.0)
check("the page's opening, with all in it, arrives first, just into the hand-off",
      o.openingArrives > o.handoff && o.openingArrives < o.handoff + 0.1
      && o.arrival(y: 800, from: y0, to: y1) == o.openingArrives && o.arrival(y: y0, from: y0, to: y1) == o.openingArrives)
let ys = stride(from: 900.0, through: 0, by: -10).map { $0 }
let arrivals = ys.map { o.arrival(y: $0, from: y0, to: y1) }
check("the wave goes up the screen: the higher a part, the later it arrives, never earlier",
      zip(arrivals, arrivals.dropFirst()).allSatisfy { $0 <= $1 + 1e-12 })
check("a part between the ECG's start and the title arrives as the ECG's middle passes it",
      [300.0, 400.0, 500.0].allSatisfy { y in
          let t = o.arrival(y: y, from: y0, to: y1)
          return t <= o.openingArrives + 1e-9 || near(y0 + (y1 - y0) * o.travel(at: t), y, 0.01) })
check("what is above the title arrives after the ECG has landed, at most topLead after",
      [240.0, 150.0, 0.0].allSatisfy { y in
          let t = o.arrival(y: y, from: y0, to: y1)
          return t > o.landed && t <= o.landed + LaunchOpening.topLead + 1e-9 })
check("easeInOut's inverse undoes it",
      stride(from: 0.0, through: 1, by: 0.05).allSatisfy { near(LaunchOpening.easeInOut(LaunchOpening.easeInOutInverse($0)), $0, 1e-9) })
let starts = [o.openingArrives, o.arrival(y: 400, from: y0, to: y1), o.arrival(y: 100, from: y0, to: y1)]
check("every part arrives whole and nearly full size, never as a small copy",
      starts.allSatisfy { s in
          stride(from: s + 0.001, through: o.settled, by: 0.005).allSatisfy { o.entrance(from: s, at: $0).scale >= 0.94 } })
check("each part is nothing until it arrives, and exactly in place at rest",
      starts.allSatisfy { o.entrance(from: $0, at: $0).scale <= 0.0001 && o.entrance(from: $0, at: .infinity) == (1, 0) })
check("after the run-on the springs are within a tenth of a point of a 400 pt card",
      starts.allSatisfy { s in
          let e = o.entrance(from: s, at: o.settled + LaunchOpening.runOn)
          return abs(e.scale - 1) * 400 < 0.1 && abs(e.drop) < 0.1 })
check("the last part to arrive is still by `settled`",
      o.settled >= o.landed + LaunchOpening.topLead + LaunchOpening.settleTime - 1e-9)
// a part in the opening moves as one piece with it
let card = (x: 200.0, y: 420.0), openingMiddle = (x: 201.0, y: 560.0)
let shift = LaunchOpening.withOpening(scale: 0.94, drop: 10, opening: openingMiddle, own: card)
check("a part in the opening is scaled about the opening's middle, not its own",
      near(card.x + shift.dx, openingMiddle.x + 0.94 * (card.x - openingMiddle.x))
      && near(card.y + shift.dy, openingMiddle.y + 0.94 * (card.y - openingMiddle.y) + 10)
      && LaunchOpening.withOpening(scale: 1, drop: 0, opening: openingMiddle, own: card) == (0, 0))
check("after a held-up main thread home carries on from where it was",
      near(o.carryOn(from: o.handoff + 0.1, to: o.handoff + 0.9, frame: 1.0 / 60), o.handoff + 0.1 + 1.0 / 60)
      && near(o.carryOn(from: o.handoff - 0.5, to: o.handoff + 0.5, frame: 0.01), o.handoff + 0.01)
      && o.carryOn(from: o.handoff + 0.1, to: o.handoff + 0.15, frame: 0.01) == o.handoff + 0.15
      && o.carryOn(from: 0.1, to: 0.5, frame: 0.01) == 0.5)
check("the spring starts at 0 and settles at 1",
      LaunchOpening.spring(0) == 0 && abs(LaunchOpening.spring(LaunchOpening.settleTime) - 1) < 0.01
      && abs(LaunchOpening.spring(3) - 1) < 1e-6)
let peakSpring = stride(from: 0.0, through: 1.0, by: 0.002).map { LaunchOpening.spring($0) }.max()!
check("it rises past its place only a little (a few points of a 10 pt rise)", peakSpring > 1 && peakSpring < 1.06, "\(peakSpring)")
check("every letter is in place, at full size, once all is still",
      (0..<11).allSatisfy { let l = o.letter($0, at: o.settled); return near(l.scale, 1) && near(l.drop, 0) })
check("the letters grow from the middle out", o.letter(5, at: o.markArrives + 0.1).scale > o.letter(0, at: o.markArrives + 0.1).scale
      && near(o.letter(0, at: o.markArrives + 0.1).scale, o.letter(10, at: o.markArrives + 0.1).scale))
check("the stethoscope perches on the title at about its letters' height",
      near(o.markScale(at: o.markArrives), LaunchOpening.perch) && LaunchOpening.perch * LaunchArt.side > 25
      && LaunchOpening.perch * LaunchArt.side < 45)
check("and the middle letters start to grow under it before it has gone into them",
      o.letter(5, at: o.markGone).scale > 0.3 && o.markScale(at: o.markArrives + 0.02) > 0.1)
let brand = (try? String(contentsOfFile: "ios/RedPen/Shared/Brand.swift", encoding: .utf8)) ?? ""
let brandName = brand.components(separatedBy: "static let name = \"").dropFirst().first?
    .split(separator: "\"").first.map(String.init) ?? ""
check("the title has the letters the timing allows for", brandName.count == LaunchOpening.titleLetters, brandName)
check("under Reduce Motion home is simply there at the hand-off",
      still.letter(3, at: still.handoff).scale == 1
      && still.entrance(from: still.arrival(y: 100, from: 600, to: 250), at: still.handoff) == (1, 0)
      && still.entrance(from: still.openingArrives, at: still.handoff) == (1, 0))

// The paper is now the same layer throughout, so warm-up must exercise its
// open mask, then close it for the heartbeat, and leave it open at rest.
for reduced in [false, true] {
    let opening = LaunchOpening(reduced: reduced)
    let label = reduced ? "reduced paper" : "full paper"
    let warm = opening.paperPose(at: .infinity)
    check("\(label): warm-up and rest both draw the actual open mask",
          warm?.scale == 1 && warm?.drop == 0)
    check("\(label): the heartbeat has a whole sheet, with no opening",
          opening.paperPose(at: 0) == nil && opening.paperPose(at: opening.handoff - 0.001) == nil)
    let first = opening.openingArrives + (reduced ? 0 : 0.001)
    check("\(label): the first revealed frame arrives with the content",
          opening.paperPose(at: first).map { p in
              let content = opening.entrance(from: opening.openingArrives, at: first)
              return p.scale >= 0.94 && p.scale == content.scale && p.drop == content.drop
          } ?? false)
    check("\(label): every visible cut follows the same spring as its content",
          stride(from: first, through: opening.settled + LaunchOpening.runOn, by: 1.0 / 120).allSatisfy { t in
              guard let p = opening.paperPose(at: t) else { return false }
              let content = opening.entrance(from: opening.openingArrives, at: t)
              return p.scale == content.scale && p.drop == content.drop
          })
    check("\(label): warm-up renders all the glyphs at their final positions",
          (0..<LaunchOpening.titleLetters).allSatisfy { i in
              let warm = opening.letter(i, at: .infinity)
              let end = opening.letter(i, at: opening.settled + LaunchOpening.runOn)
              return warm.scale == 1 && warm.drop == 0 && near(end.scale, warm.scale) && near(end.drop, warm.drop)
          })
}

// the ECG becoming the squiggle beside the title
let pairs = o.morph(trace.points, width: 160)
check("every point of the trace is kept, in order",
      pairs.count >= trace.points.count
      && trace.points.allSatisfy { p in pairs.contains { near($0.from.x, p.x) && near($0.from.y, p.y) } })
check("every corner of the squiggle is a point of the journey",
      LaunchOpening.squiggle.allSatisfy { c in pairs.contains { near($0.to.u, c.u) && near($0.to.v, c.v) } })
check("and they run left to right at both ends", zip(pairs, pairs.dropFirst()).allSatisfy {
    $0.from.x <= $1.from.x + 1e-9 && $0.to.u <= $1.to.u + 1e-9 })
if let rPair = pairs.min(by: { $0.from.y < $1.from.y }) {
    check("the R peak lands on the squiggle's R", near(rPair.to.u, 0.54) && near(rPair.to.v, -0.5), "\(rPair)")
}
let box = (x: 300.0, y: 120.0, width: 34.0, height: 18.0)
let start = LaunchOpening.morphed(pairs, at: 0, origin: (10, 50), target: box)
let end = LaunchOpening.morphed(pairs, at: 1, origin: (10, 50), target: box)
check("it starts as the trace where it was drawn",
      zip(start, pairs).allSatisfy { near($0.x, 10 + $1.from.x) && near($0.y, 50 + $1.from.y) })
check("and ends as the squiggle, in its frame",
      end.allSatisfy { $0.x >= box.x - 1e-9 && $0.x <= box.x + box.width + 1e-9
                       && $0.y >= box.y - 1e-9 && $0.y <= box.y + box.height + 1e-9 }
      && near(end.min { $0.y < $1.y }!.y, box.y), "\(end.min { $0.y < $1.y }!)")

let vitals = (try? String(contentsOfFile: "ios/RedPen/Shared/Ward/WardVitals.swift", encoding: .utf8)) ?? ""
let squiggleText = LaunchOpening.squiggle.map { "(\(fmt($0.u)), \(fmt($0.v)))" }.joined(separator: ", ")
func fmt(_ x: Double) -> String { x == x.rounded() ? String(Int(x)) : String(format: "%.2f", x) }
let bare = vitals.filter { !$0.isWhitespace }
check("the squiggle is EcgSquiggle's own shape", bare.contains(squiggleText.filter { !$0.isWhitespace }), squiggleText)

let home = (try? String(contentsOfFile: "ios/RedPen/Features/Library/WardHome.swift", encoding: .utf8)) ?? ""
check("home's title and squiggle tell the opening where they are",
      home.contains(".launchTarget(.title)") && home.contains(".launchTarget(.squiggle)") && home.contains(".launchLetters()"))

// Source wiring checks, not a timing or pixel test: one persistent paper
// renderer, warmed with the mask attached, and no outer ink ring. Runtime
// timing and rasterization still have to be checked by the Mac recording.
let surfaces = (try? String(contentsOfFile: "ios/RedPen/Shared/Ward/WardSurfaces.swift", encoding: .utf8)) ?? ""
func section(_ text: String, from start: String, to end: String) -> String {
    guard let a = text.range(of: start), let b = text.range(of: end, range: a.upperBound..<text.endIndex) else { return "" }
    return String(text[a.lowerBound..<b.lowerBound])
}
let frame = section(surfaces, from: "struct WardPaperFrame: View {", to: "/// What the opening's hand-off asks")
let paperStage = section(surfaces, from: "private struct WardPaperCutStage: View {", to: "#if canImport(UIKit)\n/// Home's paper")
let sheet = section(surfaces, from: "final class WardPaperCutView: UIView {", to: "/// The sheet's picture, band and opening")
check("one paper renderer survives from warm-up through the final home frame",
      frame.contains("WardPaperCutStage()") && !surfaces.contains("WardPaperRest")
      && !frame.contains(".overlay"))
check("warm-up poses the real paper mask without hiding or discarding its layer",
      paperStage.contains("let pose = stage.openingPose()")
      && !paperStage.contains("isFinite") && !sheet.contains("isHidden")
      && !sheet.contains("sheet.contents = nil") && !sheet.contains("built = nil"))
check("the moving cut is posed by transforms, drawing nothing per frame",
      sheet.contains("hole.transform = CATransform3DMakeScale(scale, scale, 1)")
      && sheet.contains("cutHolder.mask = hole")
      && sheet.contains("if built.map(") && !sheet.contains("setNeedsDisplay")
      && !sheet.contains(".path = "))
let paper = section(surfaces, from: "struct WardPaperFrame: View {", to: "extension WardPaperInk {")
check("neither a resting nor an animated paper outline draws the outer ring",
      !paper.isEmpty && !paper.contains("stroke(") && !paper.contains("strokeColor")
      && !paper.contains("private let edge ="))
check("the sheet uses the same picture, from the window's top left at its own size",
      surfaces.contains("UIImage(named: \"LaunchPaper\", in: nil, compatibleWith: traits)")
      && surfaces.contains("sheet.frame = CGRect(origin: .zero, size: picture.size)"))

// The title's layer kept one size: drawn bare, it followed the letters as
// they spread (148 to 196 points wide) and was reallocated mid-hand-off
// (28 ms, run 38721011808's display census).
let stageSource = (try? String(contentsOfFile: "ios/RedPen/Shared/LaunchStage.swift", encoding: .utf8)) ?? ""
let settleDraw = section(stageSource, from: "func draw(layout: Text.Layout, in context: inout GraphicsContext) {",
                         to: "let n = layout.reduce(0)")
check("the title draws one invisible box around all its letters can reach, at every moment, at rest too",
      settleDraw.contains("context.fill(Path(box), with: .color(.black.opacity(Self.boxOpacity)))")
      && stageSource.contains("var displayPadding: EdgeInsets { Self.reach }")
      && stageSource.contains("EdgeInsets(top: 4, leading: 4, bottom: 10, trailing: 4)"))
check("the title warms and finishes with the same glyph renderer as the animation",
      stageSource.contains("c.draw(slice)") && !settleDraw.contains("context.draw(line)")
      && !settleDraw.contains("if time >= o.settled") && stageSource.contains("paperPose(at: poseTime)"))
check("the box is never seen: under half a level of 255 on any background",
      stageSource.contains("static let boxOpacity = 0.001") && 0.001 * 255 < 0.5)
let letterSamples = stride(from: 0.0, through: 3.0, by: 0.001).flatMap { t in
    (0..<LaunchOpening.titleLetters).map { LaunchOpening(reduced: false).letter($0, at: t) }
}
let overshoot = letterSamples.map(\.scale).max() ?? 0
let deepest = letterSamples.map(\.drop).max() ?? 0
check("the box reaches past a letter at its overshoot (up to a 100-point letter) and its rise",
      (overshoot - 1) / 2 * 100 <= 4 && deepest <= 10 - 4 && letterSamples.allSatisfy { $0.drop >= 0 },
      "overshoot \(overshoot), drop \(deepest)")

// MARK: the art the launch screen and the opening share

let yml = (try? String(contentsOfFile: "ios/project.yml", encoding: .utf8)) ?? ""
let board = (try? String(contentsOfFile: "ios/AppResources/LaunchScreen.storyboard", encoding: .utf8)) ?? ""
check("the Xcode launch screen is the storyboard",
      yml.contains("UILaunchStoryboardName: LaunchScreen\n") && yml.contains("path: AppResources/LaunchScreen.storyboard"))
check("it shows the launch art, at its own size, in the middle of the safe area",
      board.contains("image=\"\(LaunchArt.imageName)\"") && board.contains("contentMode=\"center\"")
      && board.contains("firstAttribute=\"centerX\" secondItem=\"Lch-sa-001\"")
      && board.contains("firstAttribute=\"centerY\" secondItem=\"Lch-sa-001\""))
check("on home's paper, pinned to the screen's top left at its own size",
      board.contains("contentMode=\"topLeft\"") && board.contains("image=\"LaunchPaper\"")
      && board.contains("firstItem=\"Lch-pp-001\" firstAttribute=\"top\" secondItem=\"Lch-vw-001\" secondAttribute=\"top\"")
      && board.contains("firstItem=\"Lch-pp-001\" firstAttribute=\"left\" secondItem=\"Lch-vw-001\" secondAttribute=\"left\""))
let paperSet = "ios/RedPen/Assets.xcassets/LaunchPaper.imageset"
let paperFiles = (try? FileManager.default.contentsOfDirectory(atPath: paperSet)) ?? []
check("the paper: iPhone at 2x and 3x, iPad at 2x, day and night",
      ["paper-iphone@2x.png", "paper-iphone@3x.png", "paper-ipad@2x.png",
       "paper-iphone-dark@2x.png", "paper-iphone-dark@3x.png", "paper-ipad-dark@2x.png"]
        .allSatisfy(paperFiles.contains), "\(paperFiles)")
let set = "ios/RedPen/Assets.xcassets/\(LaunchArt.imageName).imageset"
let files = (try? FileManager.default.contentsOfDirectory(atPath: set)) ?? []
check("launch art: day and night at 1x, 2x, 3x", files.filter { $0.hasSuffix(".png") }.count == 6, "\(files)")
for dark in [false, true] {
    let c = LaunchArt.chest(dark: dark)
    check("chest piece inside the \(dark ? "night" : "day") image",
          c.x > 0.5 && c.x < 1 && c.y > 0 && c.y < 0.5 && c.r > 0.03 && c.r < 0.2)
}
check("the two modes' chest pieces are near the same place (no jump between modes)",
      abs(LaunchArt.chest(dark: true).x - LaunchArt.chest(dark: false).x) < 0.02
      && abs(LaunchArt.chest(dark: true).y - LaunchArt.chest(dark: false).y) < 0.02)

// MARK: the storyboard's moments

// The Launch recording holds the opening at each named moment and
// photographs it (`-uiPreviewSplashAt`): in order, from the launch screen
// (A1's first frame) to home at rest, each where the timeline puts it.
for reduced in [false, true] {
    let o = LaunchOpening(reduced: reduced)
    let m = o.moments
    let label = reduced ? "Reduce Motion" : "the opening"
    check("\(label): its moments start at the launch screen and end with home at rest",
          m.first?.name == "launch" && m.first?.t == 0 && m.last?.name == "still"
          && abs((m.last?.t ?? 0) - (o.settled + LaunchOpening.runOn)) < 1e-9)
    check("\(label): its moments are in order and each named once",
          zip(m, m.dropFirst()).allSatisfy { $0.t < $1.t } && Set(m.map(\.name)).count == m.count)
}
let full = LaunchOpening()
check("a moment is found by name, or given in seconds",
      full.moment("lub") == full.r && full.moment("handoff") == full.handoff && full.moment("0.5") == 0.5
      && full.moment("later") == nil && full.moment("-1") == nil)
let recording = (try? String(contentsOfFile: ".github/workflows/launch-recording.yml", encoding: .utf8)) ?? ""
check("the Launch recording photographs every moment, in the storyboard's order",
      recording.contains("for m in " + full.moments.map(\.name).joined(separator: " ") + "; do")
      && recording.contains("-uiPreviewSplashAt \"$m\""))

// MARK: the hand-off's diagnostics

// A recorded opening lists each gap over 50 ms with the main thread's CPU
// time across it, the link's interval, and the marks of home's loads
// (LaunchDiagnostics); the judge reads gap_ms and ignores the rest.
var diag = LaunchDiagnostics()
// host clock: the opening's clock is 100 s behind it, hand-off at 0.73
let toClock: (Double) -> Double = { $0 - 100 }
diag.moment("handoff", at: 100.73)
diag.moment("home", at: 100.75)
diag.load("plan", from: 100.80, to: 101.38)
diag.load("early", from: 90.0, to: 90.1)
diag.load("late", from: 103.0, to: 103.2)
diag.tick(end: 100.70, gap: nil, cpu: 1.000, interval: 1.0 / 60)
diag.tick(end: 100.80, gap: 0.016, cpu: 1.010, interval: 1.0 / 60)
diag.tick(end: 100.94, gap: 0.117, cpu: 1.108, interval: 1.0 / 60)
diag.tick(end: 101.00, gap: 0.050, cpu: 1.120, interval: 1.0 / 60)
diag.tick(end: 101.40, gap: 0.062, cpu: 1.128, interval: 1.0 / 60)
check("only gaps over 50 ms are listed, with the CPU time across each",
      diag.gaps.count == 2 && near(diag.gaps[0].length, 0.117) && near(diag.gaps[0].cpu, 0.098)
      && near(diag.gaps[1].length, 0.062) && near(diag.gaps[1].cpu, 0.008), "\(diag.gaps)")
let line = diag.fields(clock: toClock, from: 0.73, to: 1.97)
check("the extra fields: gaps, interval and marks, led by a space",
      line == " gaps=+0.94:117ms/cpu98ms,+1.40:62ms/cpu8ms interval_ms=16.7"
        + " marks=handoff+0.73,home+0.75,plan+0.80..+1.38", line)
check("a load outside the hand-off-to-still window is left out",
      !line.contains("early") && !line.contains("late"), line)
check("the gap_ms the judge reads is not in the extra fields", !line.contains("gap_ms"), line)
let quiet = LaunchDiagnostics().fields(clock: toClock, from: 0.73, to: 1.97)
check("with nothing noted the fields say so", quiet == " gaps=none interval_ms=none marks=none", quiet)
var many = LaunchDiagnostics()
for i in 0..<100 { many.load("plan", from: 100.8 + Double(i) * 0.001, to: 100.81 + Double(i) * 0.001) }
check("the marks are capped",
      many.fields(clock: toClock, from: 0.73, to: 1.97).components(separatedBy: "plan").count - 1 == LaunchDiagnostics.mostMarks)

// MARK: the experiments are over; the soft lights are drawn once

// The control takes (home's data stood in for, the glows left out) answered
// what they were for: the per-frame blur of the buttons' relief held the
// hand-off up. They are gone; the judged takes, the fixed pause, the
// snapshots after each take and the 100 ms gate are what the recording keeps.
func source(_ path: String) -> String { (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }
let gone = ["-uiPreviewNoGlows", "-uiPreviewStubHomeData", "HomeStandIn", "homeDue", "noGlows", "stubHomeData"]
let touched = ["ios/RedPen/Shared/LaunchStage.swift", "ios/RedPen/Shared/Ward/WardSurfaces.swift",
               "ios/RedPen/Features/Library/WardHome.swift", "ios/RedPen/Features/Library/LibraryView.swift",
               ".github/workflows/launch-recording.yml"]
for path in touched {
    let text = source(path)
    check("\(path) reads", !text.isEmpty)
    check("\(path) has no control-take scaffolding", gone.allSatisfy { !text.contains($0) })
}
check("the recording keeps three judged takes, the fixed 30 s pause and a snapshot after each take",
      recording.contains("for take in 1 2 3; do") && recording.contains("sleep 30")
      && recording.contains("busy \"take $take before launch\"")
      && recording.contains("busy \"take $take after the take\"") && !recording.contains("control"))
check("the recording's gate is unchanged: every take has a readout, none holds over 100 ms",
      recording.contains("[ -z \"$gap\" ]") && recording.contains("[ \"$gap\" -gt 100 ]")
      && recording.contains("no hand-off readout"))
let stage = source("ios/RedPen/Shared/LaunchStage.swift")
check("the readout keeps its gaps, cpu and marks fields",
      stage.contains("gap_ms=") && stage.contains("refreshes=") && stage.contains("diag.fields("))

// No image is made inside the hand-off window: the cache looks at the window
// before it makes anything, and sends a miss to the live drawing.
let images = source("ios/RedPen/Shared/Ward/WardLightImages.swift")
check("WardLightImages reads", !images.isEmpty)
if let window = images.range(of: "LaunchStage.shared.handingOff"), let make = images.range(of: "let made = store(request)") {
    check("a style asked for in the hand-off is not made there", window.lowerBound < make.lowerBound)
} else { check("the cache checks the hand-off window before it makes an image", false) }
check("the styles asked for in the hand-off are made once it is over",
      stage.contains("WardLightImages.shared.catchUp()") && stage.contains("var handingOff: Bool { link != nil }"))
let wardSurfaces = source("ios/RedPen/Shared/Ward/WardSurfaces.swift")
check("a pressable face draws from its image only at rest",
      wardSurfaces.contains("if depth <= Self.rest, !unlit, let fillColor, let kind = WardFaceShape(shape)"))

// MARK: no fading, anywhere in the opening

let splash = (try? String(contentsOfFile: "ios/RedPen/Shared/LaunchSplash.swift", encoding: .utf8)) ?? ""
check("LaunchSplash.swift reads", !splash.isEmpty)
for banned in [".opacity", "opacity =", "\"opacity\"", ".transition(.opacity", "fadeIn", "fadeOut"] {
    check("the splash never uses \(banned)", !splash.contains(banned))
}

print(failures.isEmpty ? "\nALL LAUNCH OPENING TESTS PASS"
                       : "\n\(failures.count) LAUNCH OPENING TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
