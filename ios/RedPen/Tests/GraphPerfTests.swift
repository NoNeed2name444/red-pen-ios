// The Performance theme's Foundation core at 100,000 notes: the synthetic
// vault (P1), the graph build (P2), the seed layout (P3), screen-bin picks
// against brute force (P4), the world grid (P5), level of detail and labels
// (P6), frame stats (P7), and that every stage stays linear (P8).
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

func ms(_ t: Double) -> String { String(format: "%.1f ms", t * 1000) }

func edgeHash(_ input: GraphPerfInput) -> UInt64 {
    var h: UInt64 = 0xCBF2_9CE4_8422_2325
    for e in input.edges { GraphPerfGraph.fnv(&h, UInt64(e)) }
    return h
}

func length(_ v: SIMD3<Float>) -> Float { (v * v).sum().squareRoot() }

// MARK: - P1 the synthetic vault

let spec = GraphPerfSynthetic.Spec()
let input = GraphPerfSynthetic.make(spec)
let n = input.noteIDs.count
check("P1 100,000 notes, a kind and a folder each", n == 100_000 && input.isPage.count == n && input.folderOfNote.count == n)
let tops = input.folderParent.filter { $0 < 0 }.count
check("P1 24 top folders among \(input.folderIDs.count)", tops == 24 && input.folderIDs.count > 500)
var depthOK = true, acyclic = true
for f in input.folderParent.indices {
    var d = 0, cur = Int(input.folderParent[f])
    while cur >= 0 { d += 1; if cur >= f { acyclic = false; break }; cur = Int(input.folderParent[cur]) }
    if d > 3 { depthOK = false }
}
check("P1 folders at most 3 deep, every parent made before its child (acyclic)", depthOK && acyclic)
let pages = Double(input.isPage.filter { $0 }.count) / Double(n)
let loose = Double(input.folderOfNote.filter { $0 < 0 }.count) / Double(n)
check("P1 about 15% pages and 2% loose", abs(pages - 0.15) < 0.01 && abs(loose - 0.02) < 0.005,
      "\(pages) \(loose)")
let linkCount = input.edges.count / 2
check("P1 about 2.3 links a note", (2.0...2.5).contains(Double(linkCount) / Double(n)), "\(linkCount)")
var pairSet = Set<UInt64>(), selfOrDup = 0
for k in 0..<linkCount {
    let a = UInt64(input.edges[2 * k]), b = UInt64(input.edges[2 * k + 1])
    if a == b || !pairSet.insert(min(a, b) << 32 | max(a, b)).inserted { selfOrDup += 1 }
}
check("P1 no self links and no duplicate links", selfOrDup == 0, "\(selfOrDup)")
check("P1 unique ids", Set(input.noteIDs).count == n && Set(input.folderIDs).count == input.folderIDs.count)
let again = GraphPerfSynthetic.make(spec)
check("P1 the same seed gives the same vault", edgeHash(again) == edgeHash(input) && again.noteIDs == input.noteIDs
      && again.folderOfNote == input.folderOfNote)
var other = spec; other.seed += 1
check("P1 another seed another vault", edgeHash(GraphPerfSynthetic.make(other)) != edgeHash(input))
check("P1 titles on demand", GraphPerfSynthetic.title(4821).hasSuffix(" 04821"))

// MARK: - P2 the graph

let graph = GraphPerfGraph(input)
let hubDegree = (0..<n).map { graph.degree($0) }.max() ?? 0
print("     graph: \(graph.noteCount) notes, \(graph.folderCount) folders, \(graph.linkCount) links, " +
      "\(graph.looseGroupCount) loose groups, highest degree \(hubDegree)")
check("P2 every generated link kept once", graph.linkCount == linkCount)
check("P2 hubs grow (preferential attachment)", hubDegree > 100, "\(hubDegree)")
var symmetric = true
for i in 0..<n {
    let row = graph.adjacency[Int(graph.adjStart[i])..<Int(graph.adjStart[i + 1])]
    if zip(row, row.dropFirst()).contains(where: { $0 >= $1 }) || row.contains(Int32(i)) { symmetric = false; break }
    for j in row {
        let back = graph.adjacency[Int(graph.adjStart[Int(j)])..<Int(graph.adjStart[Int(j) + 1])]
        if !back.contains(Int32(i)) { symmetric = false; break }
    }
}
check("P2 CSR symmetric, rows ascending, no self", symmetric && graph.adjacency.count == 2 * graph.linkCount)
check("P2 notes in UUID byte order", zip(graph.noteIDs, graph.noteIDs.dropFirst()).allSatisfy {
    GraphPerfGraph.words($0) < GraphPerfGraph.words($1)
})

// the same vault handed over in another order, links reversed and repeated
var rng = GraphPerfSynthetic.Random(seed: 7)
func shuffled(_ count: Int) -> [Int] {
    var p = Array(0..<count)
    for i in stride(from: count - 1, to: 0, by: -1) { p.swapAt(i, rng.below(i + 1)) }
    return p
}
let small = GraphPerfSynthetic.make(.init(notes: 4_000, topFolders: 6, seed: 11))
let np = shuffled(small.noteIDs.count), fp = shuffled(small.folderIDs.count)
var newNote = [Int](repeating: 0, count: np.count), newFolder = [Int](repeating: 0, count: fp.count)
for (k, i) in np.enumerated() { newNote[i] = k }
for (k, f) in fp.enumerated() { newFolder[f] = k }
var mixed = GraphPerfInput(noteIDs: np.map { small.noteIDs[$0] }, isPage: np.map { small.isPage[$0] },
                           folderOfNote: np.map { small.folderOfNote[$0] < 0 ? -1 : Int32(newFolder[Int(small.folderOfNote[$0])]) },
                           folderIDs: fp.map { small.folderIDs[$0] },
                           folderParent: fp.map { small.folderParent[$0] < 0 ? -1 : Int32(newFolder[Int(small.folderParent[$0])]) },
                           edges: [], linkScale: 1)
for k in stride(from: small.edges.count - 2, through: 0, by: -2) {
    let a = UInt32(newNote[Int(small.edges[k])]), b = UInt32(newNote[Int(small.edges[k + 1])])
    mixed.edges += k % 4 == 0 ? [b, a, a, b] : [a, b]
}
mixed.edges += [UInt32(np.count), 0, 3, 3, 1, UInt32.max] // unknown ends and a self link
let g1 = GraphPerfGraph(small), g2 = GraphPerfGraph(mixed)
check("P2 input order, link direction, duplicates and unknown ends do not matter",
      g1.signature == g2.signature && g1.noteIDs == g2.noteIDs && g1.edgeA == g2.edgeA && g1.edgeB == g2.edgeB
      && g1.folder == g2.folder && g1.systemOfNote == g2.systemOfNote)
let l1 = GraphPerfLayout.seed(g1)!, l2 = GraphPerfLayout.seed(g2)!
check("P2 and so the layout is the same", l1.positions == l2.positions)
var scaled = small; scaled.linkScale = 1.5
var fewer = small; fewer.edges.removeLast(2)
check("P2 the signature changes with the link scale and the links",
      GraphPerfGraph(scaled).signature != g1.signature && GraphPerfGraph(fewer).signature != g1.signature)

// folder cycles: 0 -> 1 -> 2 -> 0, 3 its own parent, 4 under a missing folder, 5 under 2
let fid = (0..<6).map { _ in rng.uuid() }
let cyc = GraphPerfGraph(GraphPerfInput(noteIDs: [rng.uuid()], isPage: [false], folderOfNote: [5],
                                        folderIDs: fid, folderParent: [1, 2, 0, 3, 99, 2], edges: []))
let slot = { (f: Int) in Int(cyc.inputOfFolder.firstIndex(of: Int32(f))!) }
let cycle = [0, 1, 2].map(slot)
let cutAt = cycle.min()!
check("P2 a folder cycle is cut at its lowest slot, once",
      cyc.folderParent[cutAt] == -1 && cycle.filter { cyc.folderParent[$0] == -1 }.count == 1)
check("P2 a folder its own parent, or under a missing one, is top level",
      cyc.folderParent[slot(3)] == -1 && cyc.folderParent[slot(4)] == -1)
check("P2 depth, region and subtree counts follow the cut tree",
      cyc.folderRegion[slot(5)] == Int32(cutAt) && cyc.folderDepth[slot(5)] == cyc.folderDepth[slot(2)] + 1
      && cyc.folderSubtreeCount[cutAt] == 1)

// loose notes: a triangle, a pair and three singletons
let lid = (0..<8).map { _ in rng.uuid() }
let lg = GraphPerfGraph(GraphPerfInput(noteIDs: lid, isPage: Array(repeating: false, count: 8),
                                       folderOfNote: [-1, -1, -1, -1, -1, -1, -1, 0], folderIDs: [rng.uuid()],
                                       folderParent: [-1], edges: [0, 1, 1, 2, 2, 0, 3, 4, 5, 7]))
let sizes = (lg.folderCount..<lg.systemCount).map { lg.systemNoteStart[$0 + 1] - lg.systemNoteStart[$0] }
check("P2 loose notes grouped by component, largest first, singletons pooled last", sizes == [3, 2, 2], "\(sizes)")
let s0 = lg.noteOfInput[0], s1 = lg.noteOfInput[1], s5 = lg.noteOfInput[5], s6 = lg.noteOfInput[6]
check("P2 a link to a foldered note does not join a loose group",
      lg.systemOfNote[Int(s0)] == lg.systemOfNote[Int(s1)] && lg.systemOfNote[Int(s5)] == lg.systemOfNote[Int(s6)])
let empty = GraphPerfGraph(GraphPerfInput(noteIDs: [], isPage: [], folderOfNote: [], folderIDs: [], folderParent: [], edges: []))
check("P2 an empty vault builds", empty.noteCount == 0 && empty.systemCount == 0 && GraphPerfLayout.seed(empty)!.positions.isEmpty)

// MARK: - P3 the seed layout

let layout = GraphPerfLayout.seed(graph)!
let pos = layout.positions
check("P3 notes then hubs, all finite", pos.count == n + graph.folderCount && pos.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
var outside = 0, outsideRegion = 0
for i in 0..<n {
    let sys = Int(graph.systemOfNote[i])
    if length(pos[i] - layout.systemCentre[sys]) + layout.radius[i] > layout.coreRadius[sys] + 1e-3 { outside += 1 }
    let top = graph.folder[i] >= 0 ? Int(graph.folderRegion[Int(graph.folder[i])]) : sys
    if length(pos[i] - layout.systemCentre[top]) > layout.systemRadius[top] + 1e-2 { outsideRegion += 1 }
}
check("P3 every note inside its folder's ball", outside == 0, "\(outside)")
check("P3 and inside its region's system", outsideRegion == 0, "\(outsideRegion)")
var overlaps = 0
func apart(_ list: [Int], core: Float, around: SIMD3<Float>) {
    for (k, a) in list.enumerated() {
        let ca = layout.systemCentre[a], ra = layout.systemRadius[a]
        if core > 0 && length(ca - around) < core + ra - 1e-3 { overlaps += 1 }
        for b in list[(k + 1)...] where length(ca - layout.systemCentre[b]) < ra + layout.systemRadius[b] - 1e-3 { overlaps += 1 }
    }
}
for f in 0..<graph.folderCount {
    apart(graph.folderChildren[Int(graph.folderChildStart[f])..<Int(graph.folderChildStart[f + 1])].map { Int($0) },
          core: layout.coreRadius[f], around: layout.systemCentre[f])
}
apart((0..<graph.folderCount).filter { graph.folderParent[$0] < 0 } + Array(graph.folderCount..<graph.systemCount), core: 0, around: .zero)
check("P3 no sibling systems overlap, nor their parent's ball", overlaps == 0, "\(overlaps)")
let world = GraphPerfWorldGrid(pos, cell: 2 * layout.spacing)
let noteGrid = GraphPerfWorldGrid(Array(pos[0..<n]), cell: 2 * layout.spacing)
var minSpacing = Float.infinity, touching = 0
for i in 0..<n {
    if let j = noteGrid.nearest(1, to: pos[i], excluding: i).first { minSpacing = min(minSpacing, length(pos[i] - pos[j])) }
}
for i in 0..<pos.count {
    for j in world.within(layout.radius[i] + 1.2, of: pos[i]) where j > i
        && length(pos[i] - pos[j]) < layout.radius[i] + layout.radius[j] { touching += 1 }
}
let extent = pos.map(length).max() ?? 0
print(String(format: "     seed: minimum note spacing %.3f, extent %.0f units", minSpacing, extent))
check("P3 nearest neighbours at least 0.8 spacing apart", minSpacing >= 0.8, "\(minSpacing)")
check("P3 no two bodies' discs touch", touching == 0, "\(touching)")
check("P3 deterministic", GraphPerfLayout.seed(GraphPerfGraph(input))!.positions == pos)
var cancelAfter = 3
check("P3 a cancelled layout stops", GraphPerfLayout.seed(graph, isCancelled: { cancelAfter -= 1; return cancelAfter < 0 }) == nil)
var extents: [Float] = [], radii: [[Float]] = []
for scale: Float in [0.6, 1, 1.8] {
    var v = small; v.linkScale = scale
    let l = GraphPerfLayout.seed(GraphPerfGraph(v))!
    extents.append(l.positions.map(length).max() ?? 0)
    radii.append(l.radius)
}
check("P3 a longer link scale moves bodies apart, sizes stay",
      extents[0] < extents[1] && extents[1] < extents[2] && radii[0] == radii[1] && radii[1] == radii[2], "\(extents)")

// MARK: - P4 screen bins and picks

let width: Float = 390, height: Float = 844
func project(_ points: [SIMD3<Float>], _ radius: [Float], notes: Int, eye: SIMD3<Float>, target: SIMD3<Float>) -> GraphPerfScreenPoints {
    let forward = (target - eye) / length(target - eye)
    var right = SIMD3<Float>(forward.z, 0, -forward.x)
    right /= max(length(right), 1e-6)
    let up = SIMD3<Float>(right.y * forward.z - right.z * forward.y, right.z * forward.x - right.x * forward.z,
                          right.x * forward.y - right.y * forward.x)
    let focal = GraphPerfLOD.focal(projectionYY: 1 / tan(Float.pi / 6), viewHeight: height)
    var out = GraphPerfScreenPoints()
    for (i, p) in points.enumerated() {
        let v = p - eye, depth = (v * forward).sum()
        let w = max(depth, 1e-3)
        out.x.append(width / 2 + (v * right).sum() * focal / w)
        out.y.append(height / 2 - (v * up).sum() * focal / w)
        out.radius.append(GraphPerfLOD.pixelRadius(radius[i], depth: w, focal: focal))
        out.depth.append(depth > 0.05 ? depth : -1)
        out.isNote.append(i < notes)
    }
    return out
}
var taps = 0, agree = 0, hits = 0, pickTime = 0.0, bruteTime = 0.0
let poses: [(SIMD3<Float>, SIMD3<Float>)] = (0..<8).map { k in
    let target = k < 4 ? SIMD3<Float>.zero : pos[rng.below(n)]
    let away: Float = k < 4 ? extent * 2.2 : Float(8 + rng.below(40))
    let dir = SIMD3<Float>(Float(rng.unit()) - 0.5, Float(rng.unit()) - 0.5, Float(rng.unit()) - 0.5)
    return (target + dir / length(dir) * away, target)
}
var poseBins: [GraphPerfScreenBins] = []
for (eye, target) in poses {
    let seen = project(pos, layout.radius, notes: n, eye: eye, target: target)
    let bins = GraphPerfScreenBins(seen, width: width, height: height)
    poseBins.append(bins)
    for t in 0..<500 {
        var x = Float(rng.unit()) * width, y = Float(rng.unit()) * height
        let i = rng.below(seen.count)
        if t % 2 == 0, seen.pickable(i), (0..<width).contains(seen.x[i]), (0..<height).contains(seen.y[i]) {
            x = seen.x[i] + Float(rng.unit() * 20 - 10); y = seen.y[i] + Float(rng.unit() * 20 - 10)
        }
        var fast: [Int?] = [], slow: [Int?] = []
        pickTime += seconds { fast = [bins.pick(x: x, y: y), bins.dragPick(x: x, y: y)] }
        bruteTime += seconds { slow = [GraphPerfPick.bruteForce(seen, x: x, y: y), GraphPerfPick.bruteForceDrag(seen, x: x, y: y)] }
        if t % 5 == 0 {
            fast.append(bins.pick(x: x, y: y, reach: GraphPerfPick.pointerReach))
            slow.append(GraphPerfPick.bruteForce(seen, x: x, y: y, reach: GraphPerfPick.pointerReach))
        }
        taps += 1
        if fast == slow { agree += 1 }
        if fast[0] != nil { hits += 1 }
    }
}
print("     picks: \(agree)/\(taps) equal brute force, \(hits) hit; \(String(format: "%.4f", pickTime / Double(taps) * 1000)) ms " +
      "vs \(String(format: "%.3f", bruteTime / Double(taps) * 1000)) ms brute")
check("P4 4,000 taps over 8 poses pick as brute force does", taps == 4_000 && agree == taps && hits > 1_000, "\(agree) \(hits)")

// ties everywhere: bodies on whole points with few sizes and depths, taps on whole points
var grid = GraphPerfScreenPoints()
for _ in 0..<3_000 {
    grid.x.append(Float(rng.below(420)) - 15); grid.y.append(Float(rng.below(880)) - 18)
    grid.radius.append([2, 4, 4, 8, 30, 120][rng.below(6)]); grid.depth.append(Float(1 + rng.below(3)))
    grid.isNote.append(rng.below(3) > 0)
}
let gridBins = GraphPerfScreenBins(grid, width: width, height: height)
var tieAgree = 0
for _ in 0..<1_000 {
    let x = Float(rng.below(390)), y = Float(rng.below(844))
    if gridBins.pick(x: x, y: y) == GraphPerfPick.bruteForce(grid, x: x, y: y)
        && gridBins.dragPick(x: x, y: y) == GraphPerfPick.bruteForceDrag(grid, x: x, y: y) { tieAgree += 1 }
}
check("P4 with exact ties and discs wider than a bin, still brute force's answer", tieAgree == 1_000, "\(tieAgree)")

func screen(_ bodies: [(Float, Float, Float, Float, Bool)]) -> GraphPerfScreenBins {
    GraphPerfScreenBins(GraphPerfScreenPoints(x: bodies.map { $0.0 }, y: bodies.map { $0.1 }, radius: bodies.map { $0.2 },
                                              depth: bodies.map { $0.3 }, isNote: bodies.map { $0.4 }), width: width, height: height)
}
check("P4 (a) the smallest disc holding the finger",
      screen([(100, 100, 30, 5, true), (110, 100, 5, 5, true)]).pick(x: 108, y: 100) == 1)
check("P4 (a) unless a nearer disc covers its centre",
      screen([(100, 100, 30, 2, false), (110, 100, 5, 5, true)]).pick(x: 108, y: 100) == 0)
check("P4 (a) equal discs: the first",
      screen([(100, 100, 5, 5, true), (100, 100, 5, 5, true)]).pick(x: 100, y: 100) == 0)
check("P4 (b) a note within 6 points beats a nearer folder",
      screen([(100, 100, 1, 5, false), (100, 120, 1, 5, true)]).pick(x: 100, y: 108) == 1)
check("P4 (b) but not from further than 6",
      screen([(100, 100, 1, 5, false), (100, 123, 1, 5, true)]).pick(x: 100, y: 108) == 0)
check("P4 (b) then the smaller",
      screen([(100, 100, 1, 5, true), (100, 120, 0.5, 5, true)]).pick(x: 100, y: 108) == 1)
check("P4 (b) a finger reaches 28 points, the pointer 16",
      screen([(100, 100, 2, 5, true)]).pick(x: 120, y: 100) == 0
      && screen([(100, 100, 2, 5, true)]).pick(x: 120, y: 100, reach: GraphPerfPick.pointerReach) == nil)
let tiny = screen([(100, 100, 2, 5, true)])
check("P4 a drag picks up a 2-point disc 15 points away (12-point floor), never by rule (b)",
      tiny.dragPick(x: 115, y: 100) == 0 && tiny.dragPick(x: 120, y: 100) == nil)
check("P4 behind the camera is never picked", screen([(100, 100, 30, -1, true)]).pick(x: 100, y: 100) == nil)
let none = GraphPerfScreenBins(GraphPerfScreenPoints(), width: width, height: height)
check("P4 an empty map picks nothing", none.pick(x: 10, y: 10) == nil && none.dragPick(x: 10, y: 10) == nil
      && GraphPerfPick.bruteForce(GraphPerfScreenPoints(), x: 10, y: 10) == nil)

// MARK: - P5 the world grid

var gridAgree = true
for _ in 0..<200 {
    let p = pos[rng.below(pos.count)] + SIMD3(Float(rng.unit()), Float(rng.unit()), Float(rng.unit())) * 3
    let r = Float(rng.unit() * 4)
    let brute = pos.indices.filter { ((pos[$0] - p) * (pos[$0] - p)).sum() <= r * r }
    if world.within(r, of: p) != brute { gridAgree = false }
}
check("P5 sphere queries equal brute force", gridAgree)
var kAgree = true
for _ in 0..<50 {
    let p = SIMD3(Float(rng.unit()) - 0.5, Float(rng.unit()) - 0.5, Float(rng.unit()) - 0.5) * extent
    let brute = pos.indices.map { (((pos[$0] - p) * (pos[$0] - p)).sum(), $0) }
        .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }.prefix(5).map { $0.1 }
    if world.nearest(5, to: p) != brute { kAgree = false }
}
check("P5 k-nearest queries equal brute force (in empty space too)", kAgree)

// MARK: - P6 level of detail and labels

check("P6 pixel radius is radius x focal / depth", GraphPerfLOD.pixelRadius(0.5, depth: 10, focal: 1000) == 50
      && GraphPerfLOD.focal(projectionYY: 2, viewHeight: 800) == 800)
check("P6 notes drawn 1.25 to 28 points, hubs 3 to 48",
      GraphPerfLOD.drawnRadius(0.01, isNote: true) == 1.25 && GraphPerfLOD.drawnRadius(90, isNote: true) == 28
      && GraphPerfLOD.drawnRadius(0.01, isNote: false) == 3 && GraphPerfLOD.drawnRadius(90, isNote: false) == 48
      && GraphPerfLOD.drawnRadius(10, isNote: true) == 10)
let fades = stride(from: Float(0), through: 2, by: 0.05).map(GraphPerfLOD.noteAlpha)
check("P6 a note fades from 0 under 0.35 points to whole over 1.25, never back",
      fades.first == 0 && fades.last == 1 && zip(fades, fades.dropFirst()).allSatisfy { $0 <= $1 }
      && GraphPerfLOD.noteAlpha(0.35) == 0 && GraphPerfLOD.noteAlpha(1.25) == 1)
let whole = GraphPerfLOD.linkAlpha(tier: .high, endA: 1, endB: 1, lengthOnScreen: 20)
check("P6 a long link between whole notes is the tier's base", whole == 0.22
      && GraphPerfLOD.linkAlpha(tier: .smooth, endA: 1, endB: 1, lengthOnScreen: 20) == 0.14)
check("P6 bold x1.5, the fainter end, across folders x0.55, dimmed x0.15",
      abs(GraphPerfLOD.linkAlpha(tier: .high, bold: true, endA: 1, endB: 1, lengthOnScreen: 20) - 0.33) < 1e-6
      && abs(GraphPerfLOD.linkAlpha(tier: .high, endA: 0.5, endB: 1, lengthOnScreen: 20) - 0.11) < 1e-6
      && abs(GraphPerfLOD.linkAlpha(tier: .high, endA: 1, endB: 1, lengthOnScreen: 20, crossFolder: true) - 0.121) < 1e-6
      && abs(GraphPerfLOD.linkAlpha(tier: .high, endA: 1, endB: 1, lengthOnScreen: 20, focus: .elsewhere) - 0.033) < 1e-6
      && GraphPerfLOD.linkAlpha(tier: .high, endA: 1, endB: 1, lengthOnScreen: 20, focus: .touches) == whole)
check("P6 a link under 2 points is not drawn, and fades in by 12",
      GraphPerfLOD.linkAlpha(tier: .high, endA: 1, endB: 1, lengthOnScreen: 1.5) == 0
      && GraphPerfLOD.linkAlpha(tier: .high, endA: 1, endB: 1, lengthOnScreen: 7) < whole)
check("P6 label budgets 12, 8 and 4", GraphPerfTier.allCases.map(\.labelBudget) == [4, 8, 12])
let near = poseBins[4].points
let candidates = (0..<near.count).filter { near.pickable($0) && near.x[$0] >= 0 && near.x[$0] < width
    && near.y[$0] >= 0 && near.y[$0] < height }.map { (index: $0, depth: near.depth[$0]) }
var labels = GraphPerfLabelChooser(budget: GraphPerfTier.high.labelBudget)
let far = candidates.max { $0.depth < $1.depth }!.index
var chosen: [Int] = []
let labelTime = seconds { chosen = labels.choose(candidates, selection: far) }
let nearestTwelve = candidates.filter { $0.index != far }.sorted { ($0.depth, $0.index) < ($1.depth, $1.index) }.prefix(11).map(\.index)
check("P6 the nearest labels, within budget, the selection always first (\(candidates.count) on screen, \(ms(labelTime)))",
      chosen.count == 12 && chosen.first == far && Array(chosen.dropFirst()) == nearestTwelve)
var steady = GraphPerfLabelChooser(budget: 2)
_ = steady.choose([(index: 0, depth: 10), (index: 1, depth: 11), (index: 2, depth: 11.05)])
let held = steady.choose([(index: 0, depth: 10), (index: 1, depth: 11.05), (index: 2, depth: 11)])
check("P6 a 1% depth swap does not swap the labels", held == [0, 1], "\(held)")
let moved = steady.choose([(index: 0, depth: 10), (index: 1, depth: 13), (index: 2, depth: 11)])
check("P6 a clear change does", moved == [0, 2], "\(moved)")
var small4 = GraphPerfLabelChooser(budget: 4)
check("P6 the selection even when far and the budget is full",
      small4.choose((0..<10).map { (index: $0, depth: Float($0)) }, selection: 9) == [9, 0, 1, 2])

// MARK: - P7 frame stats

let target = 1.0 / 60
let calm = GraphPerfFrameStats(Array(repeating: target, count: 100), target: target)
check("P7 a steady stream: p50 = p95 = the frame, no hitches", calm.p50 == target && calm.p95 == target && calm.hitches == 0)
let rough = GraphPerfFrameStats((1...100).map { Double($0) / 1000 }, target: target)
check("P7 1 to 100 ms: p50 50, p95 95, 75 frames over 25 ms", rough.p50 == 0.05 && rough.p95 == 0.095 && rough.hitches == 75)
let spiky = GraphPerfFrameStats(Array(repeating: target, count: 97) + [0.04, 0.05, 0.1], target: target)
check("P7 three long frames are three hitches, p95 still the frame", spiky.hitches == 3 && spiky.p95 == target)
let none7 = GraphPerfFrameStats([], target: target)
check("P7 no frames, zeros", none7.count == 0 && none7.p50 == 0 && none7.p95 == 0 && none7.hitches == 0)

// MARK: - P8 linear time

func stages(_ notes: Int) -> [Double] {
    var best = [Double](repeating: .infinity, count: 4)
    for _ in 0..<3 {
        var inp: GraphPerfInput! , gr: GraphPerfGraph!, lay: GraphPerfLayout!
        let t0 = seconds { inp = GraphPerfSynthetic.make(.init(notes: notes)) }
        let t1 = seconds { gr = GraphPerfGraph(inp) }
        let t2 = seconds { lay = GraphPerfLayout.seed(gr) }
        let seen = project(lay.positions, lay.radius, notes: notes, eye: SIMD3(0, 0, 900), target: .zero)
        let t3 = seconds { _ = GraphPerfScreenBins(seen, width: width, height: height) }
        best = zip(best, [t0, t1, t2, t3]).map { min($0, $1) }
    }
    return best
}
let at25 = stages(25_000), at100 = stages(100_000)
for (k, name) in ["generator", "graph", "seed layout", "screen bins"].enumerated() {
    let ratio = at100[k] / max(at25[k], 1e-6)
    check("P8 \(name) linear: \(ms(at25[k])) at 25k, \(ms(at100[k])) at 100k, x\(String(format: "%.1f", ratio))", ratio < 8)
}

print(failures.isEmpty ? "ALL PASSED" : "\(failures.count) FAILED")
exit(failures.isEmpty ? 0 : 1)
