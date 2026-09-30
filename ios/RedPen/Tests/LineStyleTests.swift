// Lines: Curved / Straight (GraphLineStyle.swift): the stored choice, the
// 3D map's straight segment - collinear, evenly spaced, exact at both ends,
// its length coordinate continuous as the link grows - and the 2D board's
// connectors - the bow symmetric and leaning one way, parallel links and
// fanned lanes never on top of one another, the arrowhead's direction and
// the hit test following the shape chosen.
//
// Compiled with GraphLineStyle.swift alone (Foundation only).
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "PASS " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func near(_ a: Float, _ b: Float, _ tolerance: Float = 0.0001) -> Bool {
    abs(a - b) <= tolerance
}

func nearD(_ a: Double, _ b: Double, _ tolerance: Double = 0.0001) -> Bool {
    abs(a - b) <= tolerance
}

func size3(_ v: SIMD3<Float>) -> Float {
    GraphStraightLine.size(v)
}

func gap(_ a: CGPoint, _ b: CGPoint) -> Double {
    let dx: Double = Double(a.x - b.x)
    let dy: Double = Double(a.y - b.y)
    return (dx * dx + dy * dy).squareRoot()
}

// MARK: L1 the stored choice

check("L1 nothing stored: Curved, today's look", GraphLineStyle.stored(nil) == .curved && GraphLineStyle.standard == .curved)
check("L1 true is Straight, false Curved", GraphLineStyle.stored(true) == .straight && GraphLineStyle.stored(false) == .curved)
check("L1 the key", GraphLineStyle.key == "vignette.ideas.straightLines")
check("L1 the words", GraphLineStyle.allCases.map(\.title) == ["Curved", "Straight"])
check("L1 -ideasLines straight forces it for a run", GraphLineStyle.parse(arguments: ["app", "-ideasLines", "straight"]) == .straight
      && GraphLineStyle.parse(arguments: ["app", "-ideasLines", "curved"]) == .curved)
check("L1 no flag, or a bad one: the stored choice", GraphLineStyle.parse(arguments: ["app"]) == nil
      && GraphLineStyle.parse(arguments: ["app", "-ideasLines"]) == nil
      && GraphLineStyle.parse(arguments: ["app", "-ideasLines", "wiggly"]) == nil)
check("L1 in force: the stored Bool without the flag", GraphLineStyle.inForce(true) == .straight
      && GraphLineStyle.inForce(false) == .curved)

// MARK: L2 the 3D map's straight segment

let start = SIMD3<Float>(1, -2, 0.5)
let end = SIMD3<Float>(7, 3, -4)
var points: [SIMD3<Float>] = []
var lengths: [Float] = []
let n: Int = 40
let total: Float = GraphStraightLine.sample(from: start, to: end, grow: 1, count: n, points: &points, lengths: &lengths)
let whole: Float = size3(end - start)
check("L2 as many points as the curve's sampling", points.count == n + 1 && lengths.count == n + 1)
check("L2 the ends match exactly", points[0] == start && points[n] == end, "\(points[0]) \(points[n])")
check("L2 the length is the segment's", near(total, whole, 0.0005) && near(lengths[n], total, 0.0))

var worstOff: Float = 0
let axis: SIMD3<Float> = (end - start) / whole
for p in points {
    let rel: SIMD3<Float> = p - start
    let along: Float = rel.x * axis.x + rel.y * axis.y + rel.z * axis.z
    let off: Float = size3(rel - axis * along)
    worstOff = max(worstOff, off)
}
check("L2 every sample on the one line (collinear)", worstOff < 0.0005, "\(worstOff)")

var worstSpacing: Float = 0
let step: Float = whole / Float(n)
for k in 1...n {
    let piece: Float = size3(points[k] - points[k - 1])
    worstSpacing = max(worstSpacing, abs(piece - step))
}
check("L2 evenly spaced", worstSpacing < 0.0005, "\(worstSpacing)")

var coordinateOK: Bool = lengths[0] == 0
for k in 1...n {
    let measured: Float = size3(points[k] - points[0])
    if !near(lengths[k], measured, 0.0005) || lengths[k] < lengths[k - 1] { coordinateOK = false }
}
check("L2 the length coordinate is the true distance along, rising from 0", coordinateOK)

// a growing link: drawn from its start, the coordinate continuous with the
// whole link's (the shader's flow and impulses do not jump as it grows)
var grownPoints: [SIMD3<Float>] = []
var grownLengths: [Float] = []
let half: Float = GraphStraightLine.sample(from: start, to: end, grow: 0.5, count: n, points: &grownPoints, lengths: &grownLengths)
check("L2 half grown: half the length", near(half, whole * 0.5, 0.0005))
let middle: SIMD3<Float> = start + (end - start) * 0.5
check("L2 half grown: runs from the start to the middle", grownPoints[0] == start && size3(grownPoints[n] - middle) < 0.0005)
var sameLine: Bool = true
for k in 0...n {
    // the half-grown link's point at distance d is the whole link's point at d
    let d: Float = grownLengths[k]
    let onWhole: SIMD3<Float> = start + axis * d
    if size3(grownPoints[k] - onWhole) > 0.0005 { sameLine = false }
}
check("L2 growing keeps every point where the grown link will have it", sameLine)

var continuous: Bool = true
var previousTotal: Float = 0
for g in 1...20 {
    var pts: [SIMD3<Float>] = []
    var lens: [Float] = []
    let grow: Float = Float(g) / 20
    let t: Float = GraphStraightLine.sample(from: start, to: end, grow: grow, count: n, points: &pts, lengths: &lens)
    if t < previousTotal || abs(t - previousTotal) > whole / 20 + 0.001 { continuous = false }
    previousTotal = t
}
check("L2 the length grows smoothly with the link", continuous && near(previousTotal, whole, 0.0005))

var reused: [SIMD3<Float>] = [SIMD3<Float>](repeating: SIMD3<Float>(9, 9, 9), count: 64)
var reusedLengths: [Float] = [Float](repeating: 9, count: 64)
_ = GraphStraightLine.sample(from: start, to: end, grow: 1, count: 20, points: &reused, lengths: &reusedLengths)
check("L2 buffers are reused, never shrunk", reused.count == 64 && reused[20] == end && reusedLengths[0] == 0)

var zeroPts: [SIMD3<Float>] = []
var zeroLens: [Float] = []
let none: Float = GraphStraightLine.sample(from: start, to: start, grow: 1, count: 8, points: &zeroPts, lengths: &zeroLens)
check("L2 a zero-length link is a point, no NaN", none == 0 && zeroPts.allSatisfy { $0 == start })
let clamped: Float = GraphStraightLine.sample(from: start, to: end, grow: 3, count: 8, points: &zeroPts, lengths: &zeroLens)
check("L2 grow is clamped to the whole link", near(clamped, whole, 0.0005) && zeroPts[8] == end)

// MARK: L3 the board's curve

let p = CGPoint(x: 100, y: 200)
let q = CGPoint(x: 400, y: 260)
let pq: Double = gap(p, q)
let curved: [CGPoint] = IdeaLinkShape.samples(.curved, from: p, to: q, count: 40)
check("L3 the curve's ends are the card centres", gap(curved[0], p) < 1e-9 && gap(curved[40], q) < 1e-9)

var symmetric: Bool = true
let mx: Double = Double(p.x + q.x) / 2
let my: Double = Double(p.y + q.y) / 2
let ux: Double = Double(q.x - p.x) / pq
let uy: Double = Double(q.y - p.y) / pq
for k in 0...40 {
    // mirror across the perpendicular bisector: along -> -along
    let a: CGPoint = curved[k]
    let b: CGPoint = curved[40 - k]
    let alongA: Double = (Double(a.x) - mx) * ux + (Double(a.y) - my) * uy
    let alongB: Double = (Double(b.x) - mx) * ux + (Double(b.y) - my) * uy
    let acrossA: Double = -(Double(a.x) - mx) * uy + (Double(a.y) - my) * ux
    let acrossB: Double = -(Double(b.x) - mx) * uy + (Double(b.y) - my) * ux
    if !nearD(alongA, -alongB, 1e-6) || !nearD(acrossA, acrossB, 1e-6) { symmetric = false }
}
check("L3 the bow is symmetric end to end", symmetric)

let top: CGPoint = IdeaLinkShape.point(.curved, from: p, to: q, t: 0.5)
let across: Double = -(Double(top.x) - mx) * uy + (Double(top.y) - my) * ux
check("L3 a gentle bow: its middle a ninth of the length off the line (today's)",
      nearD(across, pq * IdeaLinkShape.bow / 2, 1e-6), "\(across)")
check("L3 it leans to the left of p-to-q, always", across > 0)

// the same bow however long, and never back across the line
let far = CGPoint(x: 100, y: 900)
let bent: CGPoint = IdeaLinkShape.point(.curved, from: p, to: far, t: 0.5)
// travelling down the screen, the same side of travel is towards smaller x
check("L3 a vertical link leans the same way, relative to its travel", Double(bent.x) < Double(p.x))

// MARK: L4 parallel links don't overlap

let p2 = CGPoint(x: 100, y: 230)
let q2 = CGPoint(x: 400, y: 290)
let neighbour: [CGPoint] = IdeaLinkShape.samples(.curved, from: p2, to: q2, count: 40)
var closest: Double = Double.greatestFiniteMagnitude
for a in curved {
    closest = min(closest, IdeaLinkShape.distance(from: a, to: .curved, from: p2, to: q2))
}
_ = neighbour
let offset: Double = 30 * ux // how far apart the two lines are, square to them
check("L4 two parallel links 30 apart stay apart all along", closest > offset * 0.66, "\(closest) vs \(offset)")

let keys: [String] = ["ab", "cd", "ab", "ab"]
let lanes: [(lane: Int, lanes: Int)] = IdeaLinkShape.lanes(for: keys)
check("L4 lanes per pair", lanes[0] == (0, 3) && lanes[1] == (0, 1) && lanes[2] == (1, 3) && lanes[3] == (2, 3))
check("L4 one link: today's bow", nearD(IdeaLinkShape.bowFactor(lane: 0, of: 1), IdeaLinkShape.bow))

var fanApart: Bool = true
var midpoints: [CGPoint] = []
for lane in 0..<3 {
    midpoints.append(IdeaLinkShape.point(.curved, from: p, to: q, lane: lane, lanes: 3, t: 0.5))
}
for a in 0..<3 {
    for b in (a + 1)..<3 where gap(midpoints[a], midpoints[b]) < 12 { fanApart = false }
}
check("L4 three links between one pair fan out, their middles well apart", fanApart,
      midpoints.map { "\($0)" }.joined(separator: " "))

var fanTouch: Bool = false
for lane in 0..<2 {
    let mine: [CGPoint] = IdeaLinkShape.samples(.curved, from: p, to: q, lane: lane, lanes: 2, count: 40)
    for k in 4...36 {
        let d: Double = IdeaLinkShape.distance(from: mine[k], to: .curved, from: p, to: q, lane: 1 - lane, lanes: 2)
        if d < 2 { fanTouch = true }
    }
}
check("L4 fanned curves meet only at the cards", !fanTouch)

let s0: (CGPoint, CGPoint) = IdeaLinkShape.straightEnds(from: p, to: q, lane: 0, lanes: 2)
let s1: (CGPoint, CGPoint) = IdeaLinkShape.straightEnds(from: p, to: q, lane: 1, lanes: 2)
let apart: Double = IdeaLinkShape.segmentDistance(s0.0, s1.0, s1.1)
check("L4 straight lanes side by side, a lane's gap apart", nearD(apart, IdeaLinkShape.laneGap, 1e-6), "\(apart)")
let single: (CGPoint, CGPoint) = IdeaLinkShape.straightEnds(from: p, to: q)
check("L4 one straight link: exactly centre to centre", gap(single.0, p) < 1e-9 && gap(single.1, q) < 1e-9)

// MARK: L5 straight on the board, and what follows the shape

let straight: [CGPoint] = IdeaLinkShape.samples(.straight, from: p, to: q, count: 10)
var straightOK: Bool = true
for k in 0...10 {
    let want: CGPoint = IdeaLinkShape.lerp(p, q, Double(k) / 10)
    if gap(straight[k], want) > 1e-9 { straightOK = false }
}
check("L5 straight: evenly along the segment", straightOK)

let straightIn: CGPoint = IdeaLinkShape.endDirection(.straight, from: p, to: q)
check("L5 an arrowhead on a straight link points along it",
      nearD(Double(straightIn.x), ux, 1e-6) && nearD(Double(straightIn.y), uy, 1e-6))
let curvedIn: CGPoint = IdeaLinkShape.endDirection(.curved, from: p, to: q)
let control: CGPoint = IdeaLinkShape.control(from: p, to: q)
let tangent: CGPoint = IdeaLinkShape.unit(CGPoint(x: q.x - control.x, y: q.y - control.y))
check("L5 an arrowhead on a curved link follows the curve in",
      gap(curvedIn, tangent) < 0.02 && gap(curvedIn, straightIn) > 0.1, "\(curvedIn) \(tangent)")

let onCurve: CGPoint = IdeaLinkShape.point(.curved, from: p, to: q, t: 0.5)
let onLine: CGPoint = IdeaLinkShape.lerp(p, q, 0.5)
check("L5 a hit test finds the curve where it is drawn",
      IdeaLinkShape.distance(from: onCurve, to: .curved, from: p, to: q) < 0.5
      && IdeaLinkShape.distance(from: onLine, to: .curved, from: p, to: q) > 10)
check("L5 and the straight line where it is drawn",
      IdeaLinkShape.distance(from: onLine, to: .straight, from: p, to: q) < 1e-9
      && IdeaLinkShape.distance(from: onCurve, to: .straight, from: p, to: q) > 10)

print(failures.isEmpty ? "all passed" : "\(failures.count) failed")
exit(failures.isEmpty ? 0 : 1)
