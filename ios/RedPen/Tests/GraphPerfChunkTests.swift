// The million map's chunks, on Linux: the octree (C1, C2), 16-bit positions
// (C3), the links' adjacency and the notes' hierarchy (C4), bundles (C5),
// frustum culling (C6), level of detail by size with continuous morphing
// and no pops (C7), the guard band (C8), the depth band (C9, plan 4f),
// streaming within a frame's budget, soonest first (C10), a leaf that is
// not ready showing its summary and morphing open once it is (C11),
// bundles giving way to links (C12), bundle light shared where bundles meet
// (C14), planning a frame ahead on its own thread (C15), the selection
// (C16), the depth shells: detail by depth with hysteresis, ramped, nothing
// past the band (C17), a half turn swapping front and back detail within a
// quarter second of settling, and no body's brightness moving more than a
// sixth of its range in a frame (C18; the owner's D3), a faded body picked
// and the chosen note's neighbourhood at full detail (C19; D4), and the
// million itself: built, and a frame planned in a small share of a 120 Hz
// frame (C13).
//
// CI compiles this with -O (tools/swift_suites.py --release); a debug build
// (-Onone, tools/preflight.sh) uses a smaller map and wider time bounds.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func seconds(_ body: () -> Void) -> Double {
    let t0 = DispatchTime.now().uptimeNanoseconds
    body()
    return Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9
}

func ms(_ t: Double) -> String { String(format: "%.2f ms", t * 1000) }

let optimized: Bool = {
    var debug = false
    assert({ debug = true; return true }())
    return !debug
}()
let widen: Double = optimized ? 1 : 25
print("     build: " + (optimized ? "optimised (-O)" : "debug (-Onone): a smaller map, time bounds x25"))

// MARK: - C1 Morton codes

check("C1 each axis takes every third bit, x lowest",
      GraphPerfOctree.morton(1, 0, 0) == 1 && GraphPerfOctree.morton(0, 1, 0) == 2 && GraphPerfOctree.morton(0, 0, 1) == 4
      && GraphPerfOctree.morton(2, 0, 0) == 8 && GraphPerfOctree.morton(3, 3, 3) == 63)
let topCode = GraphPerfOctree.morton(0x1F_FFFF, 0x1F_FFFF, 0x1F_FFFF)
check("C1 21 bits an axis fill 63 bits", topCode == (UInt64(1) << 63) - 1, String(topCode, radix: 16))

// MARK: - the map under test

let notes = optimized ? 100_000 : 20_000
let scene = GraphPerfScene.build(GraphPerfSynthetic.make(.init(notes: notes)))!
var map: GraphPerfMillionMap?
let buildTime = seconds { map = GraphPerfMillionMap.build(scene) }
let m = map!
let tree = m.octree
print("     \(notes) notes: \(tree.cells.count) cells, \(tree.leafCount) leaves, \(m.adjacency.count) adjacency entries, "
      + "\(m.bundles.count) bundles over \(m.bundles.cells.count) cut cells, built in \(ms(buildTime))")

// MARK: - C2 the octree

var seen = [Int](repeating: 0, count: tree.bodyCount)
for s in 0..<tree.bodyCount { seen[Int(tree.order[s])] += 1 }
check("C2 every body has exactly one slot, and slotOf inverts order",
      seen.allSatisfy { $0 == 1 } && (0..<tree.bodyCount).allSatisfy { tree.order[Int(tree.slotOf[$0])] == Int32($0) })
var leafCover = [Int](repeating: 0, count: tree.bodyCount)
var leavesOK = true, boxesOK = true, partsOK = true, rangesOK = true
for (k, c) in tree.leafCell.enumerated() {
    let cell = tree.cells[Int(c)]
    if cell.leaf != Int32(k) || cell.count > Int32(tree.leafSize) { leavesOK = false }
    for s in Int(cell.first) ..< Int(cell.first + cell.count) {
        leafCover[s] += 1
        if tree.leaf(ofSlot: s) != k { leavesOK = false }
    }
}
for (c, cell) in tree.cells.enumerated() {
    for s in Int(cell.first) ..< Int(cell.first + cell.count) {
        let p = scene.layout.positions[Int(tree.order[s])]
        if p.x < cell.lo.x - 1e-3 || p.y < cell.lo.y - 1e-3 || p.z < cell.lo.z - 1e-3
            || p.x > cell.hi.x + 1e-3 || p.y > cell.hi.y + 1e-3 || p.z > cell.hi.z + 1e-3 { boxesOK = false }
    }
    if !cell.isLeaf {
        let kids = tree.children(c)
        var at = cell.first
        for k in kids {
            let kid = tree.cells[Int(k)]
            if kid.first != at || kid.parent != Int32(c) || kid.depth <= cell.depth { partsOK = false }
            at += kid.count
            if Int(k) <= c || Int(k) + Int(kid.subtree) > c + Int(cell.subtree) { rangesOK = false }
        }
        if at != cell.first + cell.count || kids.count < 2 { partsOK = false }
    }
    let leavesUnder = (c ..< c + Int(cell.subtree)).filter { tree.cells[$0].isLeaf }.map { Int(tree.cells[$0].leaf) }
    if leavesUnder != Array(Int(cell.leafStart) ..< Int(cell.leafEnd)) { rangesOK = false }
}
check("C2 every slot is in exactly one leaf, none over the leaf size", leavesOK && leafCover.allSatisfy { $0 == 1 })
check("C2 every cell's box holds its bodies", boxesOK)
check("C2 children split their parent's run in order, at least two of them", partsOK)
check("C2 a subtree and its leaves are contiguous (depth first)", rangesOK)
check("C2 leaves fit in 16 bits", tree.leafCount <= GraphPerfOctree.maxLeaves)
var meanOK = true
for c in stride(from: 0, to: tree.cells.count, by: max(tree.cells.count / 50, 1)) {
    let cell = tree.cells[c]
    var sum = SIMD3<Double>.zero
    for s in Int(cell.first) ..< Int(cell.first + cell.count) {
        let p = scene.layout.positions[Int(tree.order[s])]
        sum += SIMD3(Double(p.x), Double(p.y), Double(p.z))
    }
    let mean = sum / Double(cell.count)
    let d = SIMD3<Float>(Float(mean.x), Float(mean.y), Float(mean.z)) - cell.centroid
    if (d * d).sum().squareRoot() > 1e-2 { meanOK = false }
}
check("C2 a summary's centroid is its bodies' mean", meanOK)
check("C2 the root holds everything", tree.root.count == Int32(tree.bodyCount) && tree.root.leafEnd == Int32(tree.leafCount))

// MARK: - C3 16-bit positions

var worst: Float = 0, worstAllowed: Float = 0, leafCodesOK = true
for s in 0..<tree.bodyCount {
    let leaf = tree.leaf(ofSlot: s)
    let cell = tree.cells[Int(tree.leafCell[leaf])]
    let q = SIMD3(m.packed[4 * s], m.packed[4 * s + 1], m.packed[4 * s + 2])
    if Int(m.packed[4 * s + 3]) != leaf { leafCodesOK = false }
    let back = GraphPerfQuantize.unpack(q, lo: cell.lo, hi: cell.hi)
    let diff = back - scene.layout.positions[Int(tree.order[s])]
    let err = SIMD3(abs(diff.x), abs(diff.y), abs(diff.z))
    let allowed = GraphPerfQuantize.error(lo: cell.lo, hi: cell.hi) + SIMD3(repeating: 1e-4)
    if (err - allowed).max() > worst - worstAllowed { worst = err.max(); worstAllowed = allowed.max() }
    if err.x > allowed.x || err.y > allowed.y || err.z > allowed.z { leafCodesOK = false }
}
check("C3 every body unpacks within half a 16-bit step of its leaf's box, its leaf alongside", leafCodesOK,
      "worst \(worst) vs \(worstAllowed)")
let unit = GraphPerfQuantize.pack(SIMD3(0.5, 0, 1), lo: .zero, hi: SIMD3(repeating: 1))
check("C3 the ends and the middle", unit == SIMD3(32_768, 0, 65_535), "\(unit)")
let outside = GraphPerfQuantize.pack(SIMD3(-5, 9, 0.25), lo: .zero, hi: SIMD3(repeating: 1))
check("C3 outside the box is clamped to it", outside.x == 0 && outside.y == 65_535)
check("C3 eight bytes a body", m.packed.count == 4 * tree.bodyCount)

// MARK: - C4 the links' adjacency and the notes' hierarchy

let lineCount = scene.lineCount
var lineEnds = 0
for k in 0..<lineCount {
    let a = Int(scene.lineEnds[2 * k]), b = Int(scene.lineEnds[2 * k + 1])
    if a != b && a >= 0 && b >= 0 && a < tree.bodyCount && b < tree.bodyCount { lineEnds += 2 }
}
check("C4 every line is in both its ends' adjacency",
      m.adjacency.count == lineEnds && Int(m.adjacencyStart[tree.bodyCount]) == lineEnds, "\(m.adjacency.count) vs \(lineEnds)")
var symmetric = true
for s in stride(from: 0, to: tree.bodyCount, by: 97) {
    for n in m.neighbours(ofSlot: s) where !m.neighbours(ofSlot: Int(n)).contains(UInt32(s)) { symmetric = false }
}
check("C4 the adjacency runs both ways", symmetric)
check("C4 importance grows with the log of the links: none 0, 63 and more full",
      GraphPerfMillionMap.importance(degree: 0) == 0 && GraphPerfMillionMap.importance(degree: 63) == 1
      && GraphPerfMillionMap.importance(degree: 5_000) == 1
      && GraphPerfMillionMap.importance(degree: 3) < GraphPerfMillionMap.importance(degree: 7))
check("C4 a leaf note is drawn at 0.8 of its size and 0.78 of its brightness, a hub at 1.5 and in full",
      GraphPerfMillionMap.sizeFactor(0) == 0.8 && GraphPerfMillionMap.sizeFactor(1) == 1.5
      && GraphPerfMillionMap.brightnessFactor(0) == 0.78 && GraphPerfMillionMap.brightnessFactor(1) == 1)
let noteCount = scene.graph.noteCount
var looksOK = true
for s in stride(from: 0, to: tree.bodyCount, by: 13) {
    let body = Int(tree.order[s])
    var r = scene.layout.radius[body]
    if body < noteCount {
        let degree = Int(scene.graph.adjStart[body + 1]) - Int(scene.graph.adjStart[body])
        r *= GraphPerfMillionMap.sizeFactor(GraphPerfMillionMap.importance(degree: degree))
    }
    let code = UInt32(min(max((r * 100).rounded(), 1), 255))
    if m.looks[s] >> 24 != code || abs(m.radius(ofSlot: s) - Float(code) / 100) > 1e-6 { looksOK = false }
}
check("C4 each note's size follows its importance, and the pick reads it as the GPU draws it", looksOK)
var topsOK = true
for leaf in 0..<tree.leafCount {
    let cell = tree.cells[Int(tree.leafCell[leaf])]
    let range = Int(cell.first) ..< Int(cell.first + cell.count)
    let first = Int(m.leafTops[2 * leaf]), second = Int(m.leafTops[2 * leaf + 1])
    let degrees = range.filter { Int(tree.order[$0]) < noteCount }.map { m.degree(ofSlot: $0) }.sorted(by: >)
    let wantFirst = (degrees.first ?? 0) >= GraphPerfMillionMap.topDegree
    let wantSecond = degrees.count > 1 && degrees[1] >= GraphPerfMillionMap.topDegree
    if wantFirst != (first >= 0) || wantSecond != (second >= 0) { topsOK = false }
    if first >= 0 && (!range.contains(first) || m.degree(ofSlot: first) != degrees[0]) { topsOK = false }
    if second >= 0 && (!range.contains(second) || second == first || m.degree(ofSlot: second) != degrees[1]) {
        topsOK = false
    }
}
check("C4 each leaf's name candidates are its two most linked notes (\(GraphPerfMillionMap.topDegree) links or more)", topsOK)

// MARK: - C5 bundles

let cut = m.bundles.cells
var cutCover = [Int](repeating: 0, count: tree.leafCount)
for c in cut {
    let cell = tree.cells[Int(c)]
    for l in Int(cell.leafStart) ..< Int(cell.leafEnd) { cutCover[l] += 1 }
}
check("C5 the cut covers every leaf exactly once, in at most 384 cells",
      cutCover.allSatisfy { $0 == 1 } && cut.count <= 384 && cut.count > 1, "\(cut.count) cells")
var cutOfLeaf = [Int](repeating: -1, count: tree.leafCount)
for (k, c) in cut.enumerated() {
    let cell = tree.cells[Int(c)]
    for l in Int(cell.leafStart) ..< Int(cell.leafEnd) { cutOfLeaf[l] = k }
}
var between = 0
for k in 0..<lineCount {
    let a = Int(scene.lineEnds[2 * k]), b = Int(scene.lineEnds[2 * k + 1])
    if cutOfLeaf[tree.leaf(ofSlot: Int(tree.slotOf[a]))] != cutOfLeaf[tree.leaf(ofSlot: Int(tree.slotOf[b]))] { between += 1 }
}
let carried = Int(m.bundles.weight.reduce(0, +))
check("C5 the bundles carry every link between two cut cells, each pair once",
      carried == between && zip(m.bundles.a, m.bundles.b).allSatisfy { $0 < $1 }, "\(carried) vs \(between)")
check("C5 far fewer bundles than links", m.bundles.count * 4 < lineCount, "\(m.bundles.count) of \(lineCount)")
check("C5 the root spans the whole cut", m.bundles.cutStart[0] == 0 && Int(m.bundles.cutEnd[0]) == cut.count)

// MARK: - views

let width: Float = 1024, height: Float = 768
var whole = GraphPerfCamera()
whole.yaw = 0.55
whole.pitch = 0.32
whole = whole.framing(centre: scene.centre, radius: scene.radius, width: width, height: height)

func view(_ cam: GraphPerfCamera, motion: SIMD2<Float> = .zero, band: GraphPerfGuardBand = GraphPerfGuardBand())
    -> GraphPerfChunkView {
    let r = cam.depthRange(centre: scene.centre, radius: scene.radius)
    return GraphPerfChunkView(camera: cam, width: width, height: height, near: r.near, far: r.far,
                              guardBand: band, motion: motion)
}

/// A planner with every leaf prepared and ready.
func readyPlanner() -> GraphPerfChunkPlanner {
    var p = GraphPerfChunkPlanner(octree: tree, bundles: m.bundles)
    for l in 0..<tree.leafCount { p.setPrepared(l, true) }
    p.settleReady()
    return p
}

let settings = GraphPerfChunkSettings()

let sortedWeights = m.bundleWeights
var pairsKept = Set<UInt64>()
for k in 0..<m.bundles.count { pairsKept.insert(UInt64(m.bundles.a[k]) << 32 | UInt64(m.bundles.b[k])) }
var pairsSent = Set<UInt64>()
for k in 0..<m.bundles.count { pairsSent.insert(UInt64(m.bundleEnds[2 * k]) << 32 | UInt64(m.bundleEnds[2 * k + 1])) }
check("C5 the GPU gets the bundles heaviest first (a frame short of time draws a prefix), every one of them",
      zip(sortedWeights, sortedWeights.dropFirst()).allSatisfy { $0 >= $1 } && pairsSent == pairsKept
      && abs(sortedWeights.reduce(0, +) - m.bundles.weight.reduce(0, +)) <= 1e-4 * max(m.bundles.weight.reduce(0, +), 1))

// MARK: - C6 frustum culling

var planner = readyPlanner()
var far = whole
far.distance *= 40
let farFrame = planner.plan(view(far), settings: settings)
check("C6 far away: no body drawn one by one, a few summary points stand for the map",
      farFrame.drawnBodies == 0 && farFrame.summaryCount >= 1 && farFrame.summaryCount < 64,
      "\(farFrame.drawnBodies) bodies, \(farFrame.summaryCount) summaries")

// close in on the busiest leaf, looking at it
let busiest = (0..<tree.leafCount).max { tree.cells[Int(tree.leafCell[$0])].count < tree.cells[Int(tree.leafCell[$1])].count }!
let target = tree.cells[Int(tree.leafCell[busiest])].centroid
var near = whole
near.target = target
near.distance = scene.layout.spacing * 30
let nearView = view(near)
let nearFrame = planner.plan(nearView, settings: settings)
var drawnVisible = true
var k = 0
while k < nearFrame.drawLeaves.count {
    let cell = tree.cells[Int(tree.leafCell[Int(nearFrame.drawLeaves[k])])]
    if !nearView.frustum.touches(centre: cell.ballCentre, radius: cell.ballRadius) { drawnVisible = false }
    k += 2
}
check("C6 close in: bodies drawn, and only from leaves the view touches",
      nearFrame.drawnBodies > 0 && drawnVisible, "\(nearFrame.drawnBodies) bodies")
// the debug map has a fifth of the leaves, so each one is a bigger share of it
check("C6 close in, most of the map is culled", nearFrame.drawnBodies < tree.bodyCount / (optimized ? 4 : 2),
      "\(nearFrame.drawnBodies) of \(tree.bodyCount)")
// the same eye, looking the other way
var behind = near
behind.yaw += Float.pi
behind.pitch = -near.pitch
behind.target = near.eye + near.back * near.distance
let behindFrame = planner.plan(view(behind), settings: settings)
var leafStillDrawn = false
k = 0
while k < behindFrame.drawLeaves.count {
    if Int(behindFrame.drawLeaves[k]) == busiest { leafStillDrawn = true }
    k += 2
}
check("C6 turned round, the leaf now behind the eye is not drawn", !leafStillDrawn)
var instancesOK = true
var expect: UInt32 = 0
k = 0
while k < nearFrame.drawLeaves.count {
    if nearFrame.drawLeaves[k + 1] != expect { instancesOK = false }
    expect += UInt32(tree.cells[Int(tree.leafCell[Int(nearFrame.drawLeaves[k])])].count)
    k += 2
}
check("C6 each drawn leaf starts where the one before ended", instancesOK && Int(expect) == nearFrame.drawnBodies)

// MARK: - C7 level of detail by size, morphing with no pops

var opens: [Float] = []
var cam = whole
cam.target = target
for step in 0..<12 {
    cam.distance = scene.radius * 6 / pow(2, Float(step))
    let w = planner.plan(view(cam), settings: settings).standIn[busiest].w
    opens.append(w >= 2 ? w - 2 : w)
}
check("C7 a leaf opens as the camera comes in: shut far away, open near, never closing on the way",
      opens.first! == 0 && opens.last! == 1 && zip(opens, opens.dropFirst()).allSatisfy { $0 <= $1 }, "\(opens)")
/// Where each leaf is shown (its bodies' centre as drawn), and each summary's drawn radius.
func shown(_ f: GraphPerfChunkFrame) -> [SIMD3<Float>] {
    (0..<tree.leafCount).map { l in
        let s = f.standIn[l]
        let open = s.w >= 2 ? s.w - 2 : s.w
        let from = SIMD3(s.x, s.y, s.z)
        return from + (tree.cells[Int(tree.leafCell[l])].centroid - from) * open
    }
}
var jump: Float = 0
cam.distance = scene.radius * 2
var before = shown(planner.plan(view(cam), settings: settings))
var openings = 0
while cam.distance > scene.layout.spacing * 6 {
    cam.distance *= 0.995
    let f = planner.plan(view(cam), settings: settings)
    let now = shown(f)
    for l in 0..<tree.leafCount {
        let d = now[l] - before[l]
        jump = max(jump, (d * d).sum().squareRoot())
    }
    openings = max(openings, f.openLeaves)
    before = now
}
check("C7 zooming in by half a percent a frame, no leaf jumps (morphing, not popping)",
      jump < scene.layout.spacing * 2 && openings > 0, "largest move \(jump) spacings")
check("C7 split sooner: a coarser budget draws fewer bodies at the same place",
      planner.plan(nearView, settings: GraphPerfChunkSettings(split: 80)).drawnBodies < nearFrame.drawnBodies)
let half = planner.plan(nearView, settings: settings)
let partial = (0..<half.summaryCount).map { half.summaries[2 * $0 + 1].z }.filter { $0 > 0 && $0 < 1 }
check("C7 summaries carry a scale that shrinks as they open (no opacity anywhere in the frame)",
      (0..<half.summaryCount).allSatisfy { half.summaries[2 * $0 + 1].z > 0 && half.summaries[2 * $0 + 1].z <= 1 },
      "\(partial.count) partly open")
let first = tree.cells[Int(tree.children(0).first!)]
check("C7 brightness follows how many a summary stands for",
      GraphPerfChunkPlanner.brightness(tree.root.count) > GraphPerfChunkPlanner.brightness(first.count / 8 + 1))

// MARK: - C8 the guard band

let band = GraphPerfGuardBand()
let still = band.margins(motion: .zero)
let right = band.margins(motion: SIMD2(1, 0))
check("C8 still: the same margin on every side", still == SIMD4(repeating: band.base))
check("C8 moving right: the right side reaches further, the left does not",
      right.x > still.x && right.y == still.y, "\(right)")
check("C8 the margin is capped", band.margins(motion: SIMD2(100, -100)).max() == band.widest)
var probe = GraphPerfCamera()
probe.target = .zero
probe.distance = 20
let tx = tan(probe.fovY / 2) * width / height
// a ball just off the right edge, at the target's depth
let offRight = probe.target + probe.right * (20 * tx * 1.6)
let movingRight = band.frustum(probe, width: width, height: height, near: 0.1, far: 100, motion: SIMD2(1, 0))
let movingLeft = band.frustum(probe, width: width, height: height, near: 0.1, far: 100, motion: SIMD2(-1, 0))
let plain = probe.frustum(width: width, height: height, near: 0.1, far: 100)
check("C8 a chunk past the right edge: off screen, but prepared when moving right, not left",
      !plain.touches(centre: offRight, radius: 0.1) && movingRight.touches(centre: offRight, radius: 0.1)
      && !movingLeft.touches(centre: offRight, radius: 0.1))
var slid = probe
slid.pan(dx: -50, dy: 0, viewHeight: height)
let motion = GraphPerfGuardBand.motion(from: probe, to: slid, seconds: 1.0 / 120, aspect: width / height)
check("C8 sliding the view right reads as motion to the right", motion.x > 0 && abs(motion.y) < 1e-3, "\(motion)")
var turned = probe
turned.orbit(yaw: 0.01, pitch: 0)
let turning = GraphPerfGuardBand.motion(from: probe, to: turned, seconds: 1.0 / 120, aspect: width / height)
check("C8 a turn reads as motion across the screen", abs(turning.x) > 0, "\(turning)")
// the planner wants leaves beyond the edge it moves towards
var edge = near
edge.distance = scene.layout.spacing * 60
let stillWanted = Set(planner.plan(view(edge), settings: settings).wanted.map { $0.leaf })
let rushWanted = Set(planner.plan(view(edge, motion: SIMD2(3, 0)), settings: settings).wanted.map { $0.leaf })
// on the debug map (188 leaves) the still band already holds every leaf big
// enough to want, so there it can only keep them; the -O map shows the gain
check("C8 moving fast, more leaves are prepared ahead",
      (optimized ? rushWanted.count > stillWanted.count : true) && stillWanted.isSubset(of: rushWanted),
      "\(stillWanted.count) still, \(rushWanted.count) moving")

// MARK: - C9 the depth band (plan 4f): one curve, following the focus

let highBand = GraphPerfDepthBand.of(.high)
let d10 = highBand.depths(focus: 10)
check("C9 the band follows the focus: High fades from 1 to 1.4 times the camera's distance to it",
      abs(d10.x - 10) < 1e-5 && abs(d10.y - 14) < 1e-5
      && abs(highBand.depths(focus: 20).y - 2 * d10.y) < 1e-4, "\(d10)")
let curve = (0...40).map { highBand.fade(8 + Float($0) * 0.2, depths: d10) }
check("C9 one curve: nothing before the start, rising steadily, full at the end and past it",
      curve[0] == 0 && curve[10] == 0 && zip(curve, curve.dropFirst()).allSatisfy { $0 <= $1 }
      && abs(curve[30] - 1) < 1e-5 && curve[40] == 1
      && abs(highBand.fade(12, depths: d10) - Float(pow(0.5, Double(highBand.k)))) < 1e-5, "\(curve)")
check("C9 a lower Graphics level pulls the end in (less drawn); the start stays at the focus",
      GraphPerfDepthBand.of(.saver).end < GraphPerfDepthBand.of(.smooth).end
      && GraphPerfDepthBand.of(.smooth).end < GraphPerfDepthBand.of(.high).end
      && GraphPerfTier.allCases.allSatisfy { GraphPerfDepthBand.of($0).start == 1 && GraphPerfDepthBand.of($0).culls })
let contrastBand = GraphPerfDepthBand.of(.high, contrast: true)
let dc = contrastBand.depths(focus: 10)
check("C9 Increase Contrast: the fade starts later and stops short of the ground, so nothing is culled for it",
      dc.x > d10.x && dc.y > d10.y && contrastBand.fade(100, depths: dc) == GraphPerfDepthBand.contrastMost
      && !contrastBand.culls)
let pulledIn = highBand.depths(focus: 10, pull: 0.5)
check("C9 the frame budget pulls the end in, never past 0.7 of the band",
      abs(pulledIn.x - 10) < 1e-5 && abs(pulledIn.y - (10 + 4 * GraphPerfDepthBand.tightest)) < 1e-4
      && highBand.depths(focus: 10, pull: 0.9).y < d10.y, "\(pulledIn)")
let fadedView = GraphPerfChunkView(camera: whole, width: width, height: height, near: 0.1, far: 1e6, band: highBand)
let contrastView = GraphPerfChunkView(camera: whole, width: width, height: height, near: 0.1, far: 1e6,
                                      band: contrastBand)
let wholeDepths = highBand.depths(focus: whole.distance)
check("C9 what lies past the band's end is culled (the view's far plane); with Increase Contrast, nothing",
      abs(fadedView.far - wholeDepths.y) < 1e-3 && contrastView.far == 1e6
      && abs(fadedView.fade.x - wholeDepths.x) < 1e-3 && abs(fadedView.fade.y - wholeDepths.y) < 1e-3
      && fadedView.fade.z == highBand.k && fadedView.fade.w == 1)
let plainView = GraphPerfChunkView(camera: whole, width: width, height: height, near: 0.1, far: 1e6)
check("C9 with the fade off, nothing fades and nothing is culled for it", plainView.fade.w == 0 && plainView.far == 1e6)
let ground = GraphPerfScene.background
let ember = SIMD3<Float>(0.8, 0.3, 0.1)
let gone = GraphPerfDepthLook.centre(colour: ember, lit: 1, fade: 1, ground: ground)
let apart = GraphPerfDepthLook.centre(colour: ember, lit: 1, fade: GraphPerfDepthBand.contrastMost, ground: ground)
check("C9 a body fades into the ground, its light to nothing; with Increase Contrast it stays apart from the ground",
      ((gone - ground) * (gone - ground)).sum() < 1e-10
      && GraphPerfDepthLook.glow(fade: 0) == 1 && GraphPerfDepthLook.glow(fade: 1) == 0
      && GraphPerfDepthLook.luminance(apart) > GraphPerfDepthLook.luminance(ground) + 0.05)

// MARK: - C10 streaming within a budget, soonest first

var streamer = GraphPerfStreamer()
streamer.bodyBudget = 1_000
let wanted = planner.plan(nearView, settings: settings).wanted
let leafBodies: (Int) -> Int = { Int(tree.cells[Int(tree.leafCell[$0])].count) }
var preparedSoFar = Set<Int>()
let plan1 = streamer.plan(wanted: wanted, isPrepared: { preparedSoFar.contains($0) }, bodies: leafBodies)
let firstBodies = plan1.map(leafBodies).reduce(0, +)
check("C10 the wanted leaves come soonest first, and the soonest is prepared first",
      wanted.count > 1 && zip(wanted, wanted.dropFirst()).allSatisfy { $0.priority <= $1.priority }
      && plan1.first == Int(wanted[0].leaf), "\(wanted.count) wanted")
check("C10 a frame lays out no more bodies than its budget (beyond its first leaf)",
      plan1.count == 1 || firstBodies <= streamer.bodyBudget, "\(firstBodies) bodies in \(plan1.count) leaves")
preparedSoFar.formUnion(plan1)
let plan2 = streamer.plan(wanted: wanted, isPrepared: { preparedSoFar.contains($0) }, bodies: leafBodies)
check("C10 the next frame carries on with others, not the same again",
      !plan2.isEmpty && Set(plan2).isDisjoint(with: Set(plan1)))
var tiny = GraphPerfStreamer()
tiny.bodyBudget = 1
let starve = tiny.plan(wanted: wanted, isPrepared: { _ in false }, bodies: leafBodies)
check("C10 a budget smaller than any leaf still prepares one a frame", starve.count == 1)

// MARK: - C11 not ready yet: the summary, then a morph

var fresh = GraphPerfChunkPlanner(octree: tree, bundles: m.bundles)
let cold = fresh.plan(nearView, settings: settings)
check("C11 nothing prepared: no body drawn, summaries stand in, nothing empty",
      cold.drawnBodies == 0 && cold.summaryCount > 0)
for leaf in plan1 { fresh.setPrepared(leaf, true) }
fresh.advance(seconds: 0.1)
let warming = fresh.plan(nearView, settings: settings)
let openNow = plan1.map { leaf -> Float in
    let w = warming.standIn[leaf].w
    return w >= 2 ? w - 2 : w
}
check("C11 a tenth of a second after it is ready, a leaf is part open",
      openNow.contains { $0 > 0 && $0 < 1 }, "\(openNow)")
fresh.advance(seconds: 0.3)
let warm = fresh.plan(nearView, settings: settings)
check("C11 after a quarter second it is as open as its size says",
      warm.drawnBodies > warming.drawnBodies || warm.drawnBodies == warming.drawnBodies && warm.drawnBodies > 0)
fresh.setPrepared(plan1[0], false)
let goneW = fresh.plan(nearView, settings: settings).standIn[plan1[0]].w
check("C11 a leaf let go closes", goneW == 0)

// MARK: - C12 bundles give way to links

let farBundles = planner.plan(view(far), settings: settings).bundleCells
check("C12 far away every bundle is at full width", farBundles.allSatisfy { $0.w == 1 })
let nearBundles = planner.plan(nearView, settings: settings).bundleCells
let target12 = tree.leafCell[busiest]
let holder = (0..<cut.count).first { k in
    let c = Int(cut[k])
    return Int(target12) >= c && Int(target12) < c + Int(tree.cells[c].subtree)
}!
check("C12 close in, the bundle cell round the camera narrows as its leaves open", nearBundles[holder].w < 1,
      "\(nearBundles[holder].w)")

// MARK: - C14 bundle light shares the crowd

let shares = GraphPerfMillionMap.overlapShares(ends: [0, 1, 0, 2, 0, 3, 0, 4, 5, 6], cells: 8)
check("C14 a cut cell where four bundles meet gives each half its light (1/sqrt 4)", shares[0] == 0.5, "\(shares)")
check("C14 a lone bundle end keeps full strength, and so does a cell with none",
      shares[1] == 1 && shares[5] == 1 && shares[7] == 1, "\(shares)")
check("C14 the million map has one share per cut cell, none above 1",
      m.bundleShares.count == m.bundles.cells.count && m.bundleShares.allSatisfy { $0 > 0 && $0 <= 1 })

// MARK: - C15 planning a frame ahead, on its own thread

let aheadState = GraphPerfMillionState(planner: readyPlanner())
var inline = readyPlanner()
let ahead = GraphPerfPlanAhead()
var aheadSame = true
var aheadTimed = true
for k in 0..<6 {
    var cam = whole
    cam.distance = whole.distance / Float(1 + 3 * k)
    cam.yaw += 0.2 * Float(k)
    let v = view(cam)
    ahead.start(aheadState, view: v, settings: settings, step: 1.0 / 60)
    inline.advance(seconds: 1.0 / 60)
    let expected = inline.plan(v, settings: settings)
    guard let got = ahead.finish(for: aheadState) else {
        aheadSame = false
        break
    }
    aheadTimed = aheadTimed && got.seconds > 0
    // summaries carry colour bits in a float, so compare bits, not values
    func bits(_ v: [SIMD4<Float>]) -> [UInt32] { v.flatMap { [$0.x.bitPattern, $0.y.bitPattern, $0.z.bitPattern, $0.w.bitPattern] } }
    aheadSame = aheadSame && got.frame.drawLeaves == expected.drawLeaves && bits(got.frame.summaries) == bits(expected.summaries)
        && got.frame.wanted.map { $0.leaf } == expected.wanted.map { $0.leaf } && got.frame.bundleCells == expected.bundleCells
}
check("C15 a plan made on the planning thread is the plan made inline, view after view",
      aheadSame && aheadTimed, "same \(aheadSame), timed \(aheadTimed)")
let otherState = GraphPerfMillionState(planner: readyPlanner())
ahead.start(aheadState, view: view(whole), settings: settings, step: 0)
check("C15 a plan made for a map since replaced is not used, and nothing waits once it is taken",
      ahead.finish(for: otherState) == nil && ahead.finish(for: aheadState) == nil)

// MARK: - C16 the selection: links hidden until a note is chosen, then its own grow out

let hubSlot = (0..<tree.bodyCount).max { m.degree(ofSlot: $0) < m.degree(ofSlot: $1) }!
let hubLeaf = tree.leaf(ofSlot: hubSlot)
let focusList = m.focusLeaves(ofSlot: hubSlot)
let around = Set(m.neighbours(ofSlot: hubSlot).map { tree.leaf(ofSlot: Int($0)) }).union([hubLeaf])
check("C16 a choice brings its own leaf and its neighbours' to full detail: its own first, each once, at most 64",
      focusList.first == hubLeaf && Set(focusList).count == focusList.count && Set(focusList).isSubset(of: around)
      && focusList.count == min(around.count, 64), "\(focusList.count) of \(around.count)")
var chooser = GraphPerfFocusMotion()
check("C16 nothing chosen: nothing moves", !chooser.isMoving(towards: nil) && chooser.shown == nil && chooser.dim == 0)
chooser.step(towards: 7, seconds: 1.0 / 60)
check("C16 a note chosen with none before: its links start at once", chooser.shown == 7 && chooser.isMoving(towards: 7))
var growFrames = 1
while chooser.isMoving(towards: 7) && growFrames < 600 {
    chooser.step(towards: 7, seconds: 1.0 / 60)
    growFrames += 1
}
check("C16 its links have grown and the rest has stepped back within half a second",
      chooser.grow == 1 && chooser.dim == GraphPerfFocusLook.dimmed && growFrames <= 30, "\(growFrames) frames")
chooser.step(towards: 9, seconds: 1.0 / 60)
let drawingBack = chooser.shown == 7 && chooser.progress < 1 && chooser.progress > 0
var switchFrames = 1
while chooser.shown != 9 && switchFrames < 600 {
    chooser.step(towards: 9, seconds: 1.0 / 60)
    switchFrames += 1
}
check("C16 another chosen: the old links draw back first (in under a sixth of a second), then the new grow",
      drawingBack && switchFrames <= 10 && chooser.progress == 0 && chooser.dim == GraphPerfFocusLook.dimmed,
      "\(switchFrames) frames")
while chooser.isMoving(towards: 9) { chooser.step(towards: 9, seconds: 1.0 / 60) }
var clearFrames = 0
while chooser.isMoving(towards: nil) && clearFrames < 600 {
    chooser.step(towards: nil, seconds: 1.0 / 60)
    clearFrames += 1
}
check("C16 cleared: the links draw back and the map comes forward again within a third of a second",
      chooser.shown == nil && chooser.dim == 0 && clearFrames <= 20, "\(clearFrames) frames")
var instant = GraphPerfFocusMotion()
instant.step(towards: 3, seconds: 0, reduceMotion: true)
check("C16 Reduce Motion: all at once",
      instant.shown == 3 && instant.grow == 1 && instant.dim == GraphPerfFocusLook.dimmed && !instant.isMoving(towards: 3))
check("C16 every link grows at one speed, so the short arrive first; a neighbour grows in as its link reaches it",
      GraphPerfFocusLook.tip(grow: 0.5, reach: 10, length: 2) == 1
      && GraphPerfFocusLook.tip(grow: 0.5, reach: 10, length: 10) == 0.5
      && GraphPerfFocusLook.arrival(tip: 0.5) == 0 && GraphPerfFocusLook.arrival(tip: 1) == 1
      && GraphPerfFocusLook.arrival(tip: 0.92) > 0 && GraphPerfFocusLook.arrival(tip: 0.92) < 1)
check("C16 a far neighbour is still a target; none outgrows a hub's cap",
      GraphPerfFocusLook.pixels(radius: 0.1, focal: 600, depth: 1_000) == GraphPerfFocusLook.floor
      && GraphPerfFocusLook.pixels(radius: 50, focal: 600, depth: 1) == GraphPerfLOD.hubClamp.upperBound)

// MARK: - C17 depth shells: detail by depth, with hysteresis, ramped, nothing past the band

let shells = GraphPerfChunkSettings()
check("C17 front stays front until mostly faded, then middle, then back",
      shells.shell(depth: 0.65, was: 0) == 0 && shells.shell(depth: 0.75, was: 0) == 1 && shells.shell(depth: 0.9, was: 0) == 2)
check("C17 back stays back until well clear, then middle, then front",
      shells.shell(depth: 0.8, was: 2) == 2 && shells.shell(depth: 0.7, was: 2) == 1 && shells.shell(depth: 0.5, was: 2) == 0)
var lowestSwitch: Float = 1
for pass in 0..<2 {
    var was: UInt8 = pass == 0 ? 0 : 2
    for step in 0...400 {
        let f = pass == 0 ? Float(step) / 400 : 1 - Float(step) / 400
        let next = shells.shell(depth: f, was: was)
        if next != was { lowestSwitch = min(lowestSwitch, f) }
        was = next
    }
}
check("C17 as a cell's fade moves, its detail changes only where it is mostly faded (about 0.6 or more)",
      lowestSwitch >= 0.59, "lowest switch at \(lowestSwitch)")
var flips = 0
var jittered: UInt8 = 0
for step in 0..<400 {
    let f: Float = shells.frontOut + 0.045 * sin(Float(step) * 0.7)
    let next = shells.shell(depth: f, was: jittered)
    if next != jittered { flips += 1 }
    jittered = next
}
check("C17 a cell jittering on a border switches once, not every frame (hysteresis)", flips == 1, "\(flips) switches")
check("C17 a back cell opens later than a front one, a middle one between",
      abs(shells.splitFactor(detail: 1) - 1) < 1e-6 && abs(shells.splitFactor(detail: 0.5) - shells.middleSplit) < 1e-6
      && abs(shells.splitFactor(detail: 0) - shells.backSplit) < 1e-6)

func depthView(_ cam: GraphPerfCamera, tier: GraphPerfTier = .high, pull: Float = 1) -> GraphPerfChunkView {
    let r = cam.depthRange(centre: scene.centre, radius: scene.radius)
    return GraphPerfChunkView(camera: cam, width: width, height: height, near: r.near, far: r.far,
                              band: GraphPerfDepthBand.of(tier), pull: pull)
}
func cellDepth(_ c: Int, _ cam: GraphPerfCamera) -> Float { ((tree.cells[c].ballCentre - cam.eye) * cam.forward).sum() }
func walkedLeaves(_ p: GraphPerfChunkPlanner) -> Set<Int> {
    Set((0..<tree.leafCount).filter { p.wasWalked(Int(tree.leafCell[$0])) })
}

// the eye at the map's edge, looking through its middle: the near half crisp, the far half fading
var deep = whole
deep.target = scene.centre
deep.pitch = 0
deep.distance = scene.radius
let deepView = depthView(deep)
var shellPlanner = readyPlanner()
var settledFrame = GraphPerfChunkFrame()
for _ in 0..<20 {
    shellPlanner.advance(seconds: 1.0 / 60)
    settledFrame = shellPlanner.plan(deepView, settings: settings)
}
print("     shells: \(settledFrame.shellCounts.x) front, \(settledFrame.shellCounts.y) middle, "
      + "\(settledFrame.shellCounts.z) back cells; \(settledFrame.drawnBodies) bodies drawn")
check("C17 the depth band gives front and back cells, and still they settle",
      settledFrame.shellCounts.x > 0 && settledFrame.shellCounts.z > 0 && settledFrame.ramping == 0
      && settledFrame.fade == deepView.fade, "\(settledFrame.shellCounts)")
var pastEnd = 0
k = 0
while k < settledFrame.drawLeaves.count {
    let c = Int(tree.leafCell[Int(settledFrame.drawLeaves[k])])
    if cellDepth(c, deep) - tree.cells[c].ballRadius > deepView.fade.y { pastEnd += 1 }
    k += 2
}
check("C17 nothing wholly past the band's end is drawn", pastEnd == 0, "\(pastEnd) leaves")
var shellsAgree = true
for leaf in walkedLeaves(shellPlanner) {
    let c = Int(tree.leafCell[leaf])
    let sh = shellPlanner.cellShell(c)
    let f = highBand.fade(cellDepth(c, deep), depths: SIMD2(deepView.fade.x, deepView.fade.y))
    if settledFrame.leafDetail[leaf] != GraphPerfChunkSettings.detail(shell: sh) { shellsAgree = false }
    if (sh == 0 && f > shells.frontOut) || (sh == 2 && f < shells.backOut) { shellsAgree = false }
}
check("C17 settled, each leaf is at its shell's detail (front 1, middle 0.5, back 0), and its shell is its fade's",
      shellsAgree)
let sameDeep = depthView(deep)
var deepPlain = readyPlanner()
let plainDeep = deepPlain.plan(view(deep), settings: settings)
check("C17 fewer bodies drawn with the band than without (the back opens later, past the end is culled)",
      settledFrame.drawnBodies < plainDeep.drawnBodies && sameDeep.far < view(deep).far,
      "\(settledFrame.drawnBodies) vs \(plainDeep.drawnBodies)")
// Graphics to Saver at once: the band's end comes in, and detail moves by ramps
var ramped = shellPlanner
var lastDetail = settledFrame.leafDetail
var lastWalked = walkedLeaves(ramped)
var worstStep: Float = 0
var rampFrames = 0
for frame in 0..<40 {
    ramped.advance(seconds: 1.0 / 60)
    let f = ramped.plan(depthView(deep, tier: .saver), settings: settings)
    let walkedNow = walkedLeaves(ramped)
    for leaf in walkedNow.intersection(lastWalked) {
        worstStep = max(worstStep, abs(f.leafDetail[leaf] - lastDetail[leaf]))
    }
    lastDetail = f.leafDetail
    lastWalked = walkedNow
    if f.ramping > 0 { rampFrames = frame + 1 }
}
check("C17 detail moves by ramps (a fifth of a second end to end), never at once",
      worstStep <= 1.0 / 12 + 1e-4 && rampFrames > 0 && rampFrames <= 13, "step \(worstStep), \(rampFrames) frames")

// MARK: - C18 a half turn: front and back swap detail, and no brightness jumps

var turnCam = deep
var turner = readyPlanner()
var turnFrame = GraphPerfChunkFrame()
for _ in 0..<20 {
    turner.advance(seconds: 1.0 / 60)
    turnFrame = turner.plan(depthView(turnCam), settings: settings)
}
func axial(_ leaf: Int, _ cam: GraphPerfCamera) -> Float {
    ((tree.cells[Int(tree.leafCell[leaf])].ballCentre - cam.target) * cam.forward).sum()
}
// a half turn about the focus mirrors depth there: what was far is near
let reachedBefore = walkedLeaves(turner)
let wasBack = reachedBefore.filter { turner.cellShell(Int(tree.leafCell[$0])) == 2 }
let wasFront = reachedBefore.filter {
    turner.cellShell(Int(tree.leafCell[$0])) == 0 && axial($0, turnCam) < -0.38 * turnCam.distance
}
// bodies to watch: every 5th of each drawn leaf, their brightness through the turn
let at: (Int) -> SIMD3<Float> = { scene.layout.positions[Int(tree.order[$0])] }
func brightness(_ f: GraphPerfChunkFrame, _ cam: GraphPerfCamera) -> [Int: Float] {
    var out: [Int: Float] = [:]
    let focal = cam.focal(viewHeight: height)
    let band = SIMD2(f.fade.x, f.fade.y)
    var k = 0
    while k < f.drawLeaves.count {
        let leaf = Int(f.drawLeaves[k])
        k += 2
        let cell = tree.cells[Int(tree.leafCell[leaf])]
        let stand = f.standIn[leaf]
        let open = stand.w >= 2 ? stand.w - 2 : stand.w
        let q = f.leafDetail[leaf]
        for s in stride(from: Int(cell.first), to: Int(cell.first + cell.count), by: 5) {
            let p = SIMD3(stand.x, stand.y, stand.z) + (at(s) - SIMD3(stand.x, stand.y, stand.z)) * open
            let depth = ((p - cam.eye) * cam.forward).sum()
            guard depth > 1e-3 else { continue }
            let fade = GraphPerfDepthBand.fade(depth, depths: band, k: f.fade.z, most: f.fade.w)
            let look = m.looks[s]
            let colour = SIMD3(Float(look & 0xFF), Float(look >> 8 & 0xFF), Float(look >> 16 & 0xFF)) / 255
            let px = GraphPerfDepthLook.pixels(radius: m.radius(ofSlot: s), focal: focal, depth: depth, open: open, detail: q)
            let lit = GraphPerfDepthLook.lit(pixels: px, detail: q)
            let full = GraphPerfDepthLook.luminance(GraphPerfDepthLook.centre(colour: colour, lit: lit, fade: 0, ground: ground))
            let now = GraphPerfDepthLook.luminance(GraphPerfDepthLook.centre(colour: colour, lit: lit, fade: fade, ground: ground))
            let range = full - GraphPerfDepthLook.luminance(ground)
            guard range > 1e-3 else { continue }
            // a share of its range: 1 crisp, 0 the ground
            out[s] = (now - GraphPerfDepthLook.luminance(ground)) / range
        }
    }
    return out
}
var lastLight = brightness(turnFrame, turnCam)
var worstJump: Float = 0
// 180 degrees in a second, at 60 frames a second
let turnFrames = 60
for _ in 0..<turnFrames {
    turnCam.orbit(yaw: Float.pi / Float(turnFrames), pitch: 0)
    turner.advance(seconds: 1.0 / 60)
    turnFrame = turner.plan(depthView(turnCam), settings: settings)
    let light = brightness(turnFrame, turnCam)
    for (s, v) in light { if let was = lastLight[s] { worstJump = max(worstJump, abs(v - was)) } }
    lastLight = light
}
var afterTurn = 0
while turnFrame.ramping > 0 && afterTurn < 120 {
    turner.advance(seconds: 1.0 / 60)
    turnFrame = turner.plan(depthView(turnCam), settings: settings)
    let light = brightness(turnFrame, turnCam)
    for (s, v) in light { if let was = lastLight[s] { worstJump = max(worstJump, abs(v - was)) } }
    lastLight = light
    afterTurn += 1
}
let reachedAfter = walkedLeaves(turner)
let backNowFront = wasBack.intersection(reachedAfter)
let frontNowBack = wasFront.intersection(reachedAfter)
print("     half turn: \(wasBack.count) back leaves (\(backNowFront.count) still reached), \(wasFront.count) front "
      + "(\(frontNowBack.count)); settled \(afterTurn) frames after; largest brightness step \(worstJump)")
check("C18 after a half turn in a second, the back comes to full detail and the front drops back",
      !backNowFront.isEmpty && backNowFront.allSatisfy { turnFrame.leafDetail[$0] == 1 }
      && frontNowBack.allSatisfy { turner.cellShell(Int(tree.leafCell[$0])) == 2 && turnFrame.leafDetail[$0] == 0 },
      "\(backNowFront.filter { turnFrame.leafDetail[$0] != 1 }.count) back leaves not full")
check("C18 within a quarter second of settling (15 frames at 60)", afterTurn <= 15, "\(afterTurn) frames")
check("C18 no body's brightness moves more than a sixth of its range in a frame",
      worstJump <= 1.0 / 6, "\(worstJump)")

// MARK: - C19 a faded body is picked, one past the band is not, and a choice comes to full detail

let pickCam = deep
let pickView = depthView(pickCam)
var picker = readyPlanner()
var pickFrame = GraphPerfChunkFrame()
for _ in 0..<20 {
    picker.advance(seconds: 1.0 / 60)
    pickFrame = picker.plan(pickView, settings: settings)
}
let pickBand = SIMD2(pickFrame.fade.x, pickFrame.fade.y)
let pickFocal = pickCam.focal(viewHeight: height)
func screen(_ p: SIMD3<Float>, _ cam: GraphPerfCamera) -> (x: Float, y: Float, depth: Float) {
    let v = p - cam.eye
    let depth = (v * cam.forward).sum()
    return (width / 2 + (v * cam.right).sum() * pickFocal / depth, height / 2 - (v * cam.up).sum() * pickFocal / depth, depth)
}
var faded: (slot: Int, leaf: Int)?
var dl = 0
search: while dl < pickFrame.drawLeaves.count {
    let leaf = Int(pickFrame.drawLeaves[dl])
    dl += 2
    guard pickFrame.standIn[leaf].w >= 2.999 else { continue }
    let cell = tree.cells[Int(tree.leafCell[leaf])]
    for s in Int(cell.first) ..< Int(cell.first + cell.count) {
        let f = highBand.fade(screen(at(s), pickCam).depth, depths: pickBand)
        if f > 0.5 && f < 0.85 {
            faded = (s, leaf)
            break search
        }
    }
}
if let faded {
    var only = pickFrame
    only.drawLeaves = [UInt32(faded.leaf), 0]
    only.summaries = []
    only.summaryCells = []
    let p = screen(at(faded.slot), pickCam)
    let hit = m.pick(x: p.x, y: p.y, reach: 0, frame: only, camera: pickCam, width: width, height: height, at: at)
    var hitSlot = -1
    if case .body(let b)? = hit { hitSlot = Int(tree.slotOf[b]) }
    let cell = tree.cells[Int(tree.leafCell[faded.leaf])]
    check("C19 a body half faded into the depth is picked like any other",
          hitSlot >= Int(cell.first) && hitSlot < Int(cell.first + cell.count)
          && highBand.fade(screen(at(hitSlot), pickCam).depth, depths: pickBand) < GraphPerfMillionMap.unseen,
          "\(String(describing: hit))")
    // choosing it: its leaf and its neighbours' come to the front's detail, however deep
    let focusLeaves = m.focusLeaves(ofSlot: faded.slot)
    picker.setFocus(leaves: focusLeaves)
    var focusFrames = 0
    repeat {
        picker.advance(seconds: 1.0 / 60)
        pickFrame = picker.plan(pickView, settings: settings)
        focusFrames += 1
    } while pickFrame.ramping > 0 && focusFrames < 120
    let focusReached = focusLeaves.filter { picker.wasWalked(Int(tree.leafCell[$0])) }
    check("C19 choosing it brings its neighbourhood's leaves to full detail within a quarter second",
          focusReached.contains(faded.leaf) && focusReached.allSatisfy { pickFrame.leafDetail[$0] == 1 } && focusFrames <= 15,
          "\(focusReached.filter { pickFrame.leafDetail[$0] != 1 }.count) of \(focusReached.count) short, \(focusFrames) frames")
    var cold = GraphPerfChunkPlanner(octree: tree, bundles: m.bundles)
    cold.setFocus(leaves: focusLeaves)
    let coldFrame = cold.plan(pickView, settings: settings)
    let firstWanted = coldFrame.wanted.prefix { $0.priority == 0 }.map { Int($0.leaf) }
    check("C19 not laid out yet, the neighbourhood is prepared first",
          firstWanted.contains(faded.leaf) && Set(firstWanted).isSubset(of: Set(focusLeaves)), "\(firstWanted.count)")
} else {
    check("C19 a drawn body half faded to pick", false, "none found")
}
// a leaf wholly past the band's end, as if it were drawn: none of its bodies can be picked
let beyond = (0..<tree.leafCount).first { leaf in
    let c = Int(tree.leafCell[leaf])
    return cellDepth(c, pickCam) - tree.cells[c].ballRadius > pickBand.y
}
if let beyond {
    var ghost = pickFrame
    let c = tree.cells[Int(tree.leafCell[beyond])]
    ghost.drawLeaves = [UInt32(beyond), 0]
    ghost.standIn[beyond] = SIMD4(c.centroid.x, c.centroid.y, c.centroid.z, 3)
    ghost.summaries = []
    ghost.summaryCells = []
    let p = screen(at(Int(c.first)), pickCam)
    check("C19 past the band's end, nothing is picked",
          m.pick(x: p.x, y: p.y, reach: 20, frame: ghost, camera: pickCam, width: width, height: height, at: at) == nil)
} else {
    check("C19 a leaf past the band's end", false, "none")
}

// MARK: - C13 a million

if optimized {
    var bigScene: GraphPerfScene?
    let sceneTime = seconds { bigScene = GraphPerfScene.build(GraphPerfSynthetic.make(.init(notes: 1_000_000))) }
    var big: GraphPerfMillionMap?
    let chunkTime = seconds { big = GraphPerfMillionMap.build(bigScene!) }
    let b = big!
    print("     1,000,000 notes: scene \(ms(sceneTime)), chunks \(ms(chunkTime)); \(b.octree.leafCount) leaves, "
          + "\(b.adjacency.count) adjacency entries, \(b.bundles.count) bundles")
    check("C13 a million bodies chunked in under 4 s (Linux, -O)", chunkTime < 4, ms(chunkTime))
    let perBody = (2 * b.packed.count * 2 + b.looks.count * 4 + b.adjacency.count * 4) / b.bodyCount
    check("C13 under 44 bytes a body on the GPU (positions and their seed, looks, the links' adjacency)",
          perBody < 44, "\(perBody)")
    var bp = GraphPerfChunkPlanner(octree: b.octree, bundles: b.bundles)
    for l in 0..<b.octree.leafCount { bp.setPrepared(l, true) }
    bp.settleReady()
    var bc = GraphPerfCamera()
    bc.yaw = 0.55
    bc.pitch = 0.32
    bc = bc.framing(centre: b.centre, radius: b.radius, width: width, height: height)
    let range = bc.depthRange(centre: b.centre, radius: b.radius)
    let bv = GraphPerfChunkView(camera: bc, width: width, height: height, near: range.near, far: range.far)
    // the median of 21 plans of each view: one plan's time on a shared CI
    // machine can be a pause of the machine, not of the plan
    func medianPlan(_ v: GraphPerfChunkView) -> (median: Double, worst: Double) {
        let t = (0..<21).map { _ in seconds { bp.plan(v, settings: settings) } }.sorted()
        return (t[10], t[20])
    }
    let wholePlan = medianPlan(bv)
    var inside = bc
    inside.distance = b.spacing * 40
    inside.target = b.octree.cells[Int(b.octree.leafCell[b.octree.leafCount / 2])].centroid
    let r2 = inside.depthRange(centre: b.centre, radius: b.radius)
    let iv = GraphPerfChunkView(camera: inside, width: width, height: height, near: r2.near, far: r2.far)
    let insidePlan = medianPlan(iv)
    let typicalPlan = max(wholePlan.median, insidePlan.median)
    let worstPlan = max(wholePlan.worst, insidePlan.worst)
    let wholeFrame = bp.plan(bv, settings: settings)
    print("     whole map: \(wholeFrame.drawnBodies) bodies, \(wholeFrame.summaryCount) summaries; plan \(ms(typicalPlan)) typical, \(ms(worstPlan)) slowest")
    check("C13 a frame's plan of the million takes under 1.5 ms (an eighth of a 120 Hz frame is 1 ms on a phone)",
          typicalPlan < 0.0015, ms(typicalPlan))
} else {
    print("     C13 skipped in a debug build (CI runs it with -O)")
}

print(failures.isEmpty ? "ALL PASSED" : "\(failures.count) FAILED")
exit(failures.isEmpty ? 0 : 1)
