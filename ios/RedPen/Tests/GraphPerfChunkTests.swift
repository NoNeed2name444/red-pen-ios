// The million map's chunks, on Linux: the octree (C1, C2), 16-bit positions
// (C3), links per leaf (C4) and bundles (C5), frustum culling (C6), level of
// detail by size with continuous morphing and no pops (C7), the guard band
// (C8), the least-recently-used cache of prepared leaves (C9), streaming
// within a frame's budget, nearest first (C10), a leaf that is not ready
// showing its summary and morphing open once it is (C11), bundles giving way
// to links (C12), bundle light shared where bundles meet (C14), planning a
// frame ahead on its own thread (C15), single links only round the focus
// (C16), and the million itself: built, and a
// frame planned in a small share of a 120 Hz frame (C13).
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
print("     \(notes) notes: \(tree.cells.count) cells, \(tree.leafCount) leaves, \(m.links.entryCount) link entries, "
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

// MARK: - C4 links per leaf

var intra = 0, cross = 0, listedOK = true
let lineCount = scene.lineCount
for k in 0..<lineCount {
    let a = Int(scene.lineEnds[2 * k]), b = Int(scene.lineEnds[2 * k + 1])
    if a == b { continue }
    let la = tree.leaf(ofSlot: Int(tree.slotOf[a])), lb = tree.leaf(ofSlot: Int(tree.slotOf[b]))
    if la == lb { intra += 1 } else { cross += 1 }
}
for l in stride(from: 0, to: tree.leafCount, by: 7) {
    for e in Int(m.links.start[l]) ..< Int(m.links.start[l + 1]) {
        if tree.leaf(ofSlot: Int(m.links.pairs[2 * e])) != l { listedOK = false }
    }
}
check("C4 a link inside a leaf is listed once, between two leaves in both",
      m.links.entryCount == intra + 2 * cross, "\(m.links.entryCount) vs \(intra) + 2 x \(cross)")
check("C4 each entry starts at its own leaf", listedOK)

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

// MARK: - C9 the least-recently-used cache

var cache = GraphPerfChunkCache(leaves: 10, pageCount: 6, pageSize: 100)
check("C9 pages needed round up", cache.pagesNeeded(0) == 0 && cache.pagesNeeded(1) == 1 && cache.pagesNeeded(201) == 3)
_ = cache.admit(0, links: 200, frame: 0)   // 2 pages
_ = cache.admit(1, links: 100, frame: 1)   // 1
_ = cache.admit(2, links: 250, frame: 2)   // 3: full
check("C9 admitted until the pool is full", cache.freePages == 0 && cache.residentCount == 3)
cache.touch(0, frame: 10)
check("C9 touching moves a leaf to most recent", cache.orderOfUse == [1, 2, 0], "\(cache.orderOfUse)")
let got = cache.admit(3, links: 150, frame: 11)
check("C9 a newcomer lets the least recently used go, oldest first, until it fits",
      got?.evicted == [1, 2] && cache.resident[3] && !cache.resident[1] && cache.resident[0], "\(String(describing: got))")
var pagesUsed: [Int32] = []
for l in 0..<10 { pagesUsed += cache.pages[l] }
check("C9 no page belongs to two leaves", Set(pagesUsed).count == pagesUsed.count && pagesUsed.count + cache.freePages == 6)
check("C9 a leaf used in the last few frames is never let go (a frame on the GPU may draw it)",
      cache.admit(4, links: 600, frame: 12) == nil && cache.resident[0] && cache.resident[3])
check("C9 too big for the whole pool: refused, nothing changed", cache.admit(5, links: 10_000, frame: 50) == nil
      && cache.resident[0])
let later = cache.admit(4, links: 600, frame: 40)
check("C9 once they are old, they go", later != nil && !cache.resident[0] && cache.resident[4])
check("C9 a resident leaf is admitted for free", cache.admit(4, links: 600, frame: 41)?.evicted == [])

// MARK: - C10 streaming within a budget, nearest first

var streamCache = GraphPerfChunkCache(leaves: tree.leafCount, pageCount: 4_096, pageSize: 1_024)
var streamer = GraphPerfStreamer()
streamer.linkBudget = 20_000
streamer.bodyBudget = 1_000_000
let wanted = planner.plan(nearView, settings: settings).wanted
let plan1 = streamer.plan(wanted: wanted, cache: &streamCache, links: m.links,
                          bodies: { Int(tree.cells[Int(tree.leafCell[$0])].count) }, frame: 1)
let firstLinks = plan1.jobs.map { m.links.count($0.leaf) }.reduce(0, +)
let nearest = wanted.min { $0.priority < $1.priority }!.leaf
check("C10 the nearest wanted leaf is prepared first", plan1.jobs.first?.leaf == Int(nearest))
check("C10 a frame copies no more links than its budget (beyond its first leaf)",
      plan1.jobs.count == 1 || firstLinks <= streamer.linkBudget, "\(firstLinks) links in \(plan1.jobs.count) leaves")
let plan2 = streamer.plan(wanted: wanted, cache: &streamCache, links: m.links,
                          bodies: { Int(tree.cells[Int(tree.leafCell[$0])].count) }, frame: 2)
check("C10 the next frame carries on with others, not the same again",
      Set(plan2.jobs.map { $0.leaf }).isDisjoint(with: Set(plan1.jobs.map { $0.leaf })))
var tiny = GraphPerfStreamer()
tiny.linkBudget = 1
tiny.bodyBudget = 1
var tinyCache = GraphPerfChunkCache(leaves: tree.leafCount, pageCount: 4_096, pageSize: 1_024)
let starve = tiny.plan(wanted: wanted, cache: &tinyCache, links: m.links,
                       bodies: { Int(tree.cells[Int(tree.leafCell[$0])].count) }, frame: 1)
check("C10 a budget smaller than any leaf still prepares one a frame", starve.jobs.count == 1)

// MARK: - C11 not ready yet: the summary, then a morph

var fresh = GraphPerfChunkPlanner(octree: tree, bundles: m.bundles)
let cold = fresh.plan(nearView, settings: settings)
check("C11 nothing prepared: no body drawn, summaries stand in, nothing empty",
      cold.drawnBodies == 0 && cold.summaryCount > 0)
for job in plan1.jobs { fresh.setPrepared(job.leaf, true) }
fresh.advance(seconds: 0.1)
let warming = fresh.plan(nearView, settings: settings)
let openNow = plan1.jobs.map { j -> Float in
    let w = warming.standIn[j.leaf].w
    return w >= 2 ? w - 2 : w
}
check("C11 a tenth of a second after it is ready, a leaf is part open",
      openNow.contains { $0 > 0 && $0 < 1 }, "\(openNow)")
fresh.advance(seconds: 0.3)
let warm = fresh.plan(nearView, settings: settings)
check("C11 after a quarter second it is as open as its size says",
      warm.drawnBodies > warming.drawnBodies || warm.drawnBodies == warming.drawnBodies && warm.drawnBodies > 0)
fresh.setPrepared(plan1.jobs[0].leaf, false)
let goneW = fresh.plan(nearView, settings: settings).standIn[plan1.jobs[0].leaf].w
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

let aheadState = GraphPerfMillionState(planner: readyPlanner(),
                                       cache: GraphPerfChunkCache(leaves: tree.leafCount, pageCount: 16, pageSize: 1_024))
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
let otherState = GraphPerfMillionState(planner: readyPlanner(),
                                       cache: GraphPerfChunkCache(leaves: tree.leafCount, pageCount: 16, pageSize: 1_024))
ahead.start(aheadState, view: view(whole), settings: settings, step: 0)
check("C15 a plan made for a map since replaced is not used, and nothing waits once it is taken",
      ahead.finish(for: otherState) == nil && ahead.finish(for: aheadState) == nil)

// MARK: - C16 single links only round the focus

var focusCam = whole
focusCam.target = tree.cells[Int(tree.leafCell[tree.leafCount / 3])].centroid
focusCam.distance = whole.distance / 6
var focusPlanner = readyPlanner()
let focusFrame = focusPlanner.plan(view(focusCam), settings: settings)
var drawnSet = Set<Int>()
var fk = 0
while fk < focusFrame.drawLeaves.count { drawnSet.insert(Int(focusFrame.drawLeaves[fk])); fk += 2 }
let shownLeaves = GraphPerfLinkFocus.leaves(drawLeaves: focusFrame.drawLeaves, octree: tree, links: m.links,
                                            focus: focusCam.target, distance: focusCam.distance, chosenLeaf: nil)
let reachW = GraphPerfLinkFocus.reach * focusCam.distance
func focusD(_ l: Int) -> Float {
    let c = tree.cells[Int(tree.leafCell[l])].centroid - focusCam.target
    return (c * c).sum().squareRoot()
}
check("C16 links are drawn for some leaves round the focus, fewer than all drawn",
      !shownLeaves.isEmpty && shownLeaves.count < drawnSet.count, "\(shownLeaves.count) of \(drawnSet.count)")
check("C16 every leaf with links is drawn and within reach of the focus, nearest first",
      shownLeaves.allSatisfy { drawnSet.contains($0) && focusD($0) <= reachW }
      && zip(shownLeaves, shownLeaves.dropFirst()).allSatisfy { focusD($0) <= focusD($1) })
let capped = GraphPerfLinkFocus.leaves(drawLeaves: focusFrame.drawLeaves, octree: tree, links: m.links,
                                       focus: focusCam.target, distance: focusCam.distance, chosenLeaf: nil,
                                       reach: 100, cap: 3_000)
check("C16 the links drawn one by one stay under the cap",
      capped.count >= 1 && (capped.count == 1 || capped.reduce(0) { $0 + m.links.count($1) } <= 3_000),
      "\(capped.reduce(0) { $0 + m.links.count($1) })")
let farLeaf = drawnSet.max { focusD($0) < focusD($1) }!
let withChosen = GraphPerfLinkFocus.leaves(drawLeaves: focusFrame.drawLeaves, octree: tree, links: m.links,
                                           focus: focusCam.target, distance: focusCam.distance, chosenLeaf: farLeaf)
check("C16 the chosen note's leaf shows its links first, even far from the focus",
      withChosen.first == farLeaf && focusD(farLeaf) > reachW && Set(withChosen.dropFirst()) == Set(shownLeaves).subtracting([farLeaf]),
      "\(focusD(farLeaf)) vs \(reachW)")

// MARK: - C13 a million

if optimized {
    var bigScene: GraphPerfScene?
    let sceneTime = seconds { bigScene = GraphPerfScene.build(GraphPerfSynthetic.make(.init(notes: 1_000_000))) }
    var big: GraphPerfMillionMap?
    let chunkTime = seconds { big = GraphPerfMillionMap.build(bigScene!) }
    let b = big!
    print("     1,000,000 notes: scene \(ms(sceneTime)), chunks \(ms(chunkTime)); \(b.octree.leafCount) leaves, "
          + "\(b.links.entryCount) link entries, \(b.bundles.count) bundles")
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
