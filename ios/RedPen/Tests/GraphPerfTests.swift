// The Performance theme's Foundation core at 100,000 notes and 300,000: the
// synthetic vault (P1), the graph build and the filter (P2), the seed layout
// (P3), screen-bin picks against brute force (P4), the world grid (P5),
// level of detail rules and labels (P6), frame stats and the readout (P7),
// that every stage stays linear (P8), the incremental force layout within a
// frame's budget (P9), the camera (P10), cluster level of detail - fewer
// bodies and lines as the camera goes back, full detail near (P11), the
// scene the GPU is handed (P12), the shaders' names and frame layout (P13),
// and tapping a node through the camera at 100,000 (P14).
//
// CI compiles this with -O (tools/swift_suites.py --release): the time
// bounds below are for that, and generous. tools/preflight.sh compiles with
// -Onone, about 25 times slower: there the bounds are 25 times wider and the
// brute-force comparisons run on fewer taps and a smaller vault.
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
func ms2(_ t: Double) -> String { String(format: "%.2f ms", t * 1000) }

func edgeHash(_ input: GraphPerfInput) -> UInt64 {
    var h: UInt64 = 0xCBF2_9CE4_8422_2325
    for e in input.edges { GraphPerfGraph.fnv(&h, UInt64(e)) }
    return h
}

func length(_ v: SIMD3<Float>) -> Float { (v * v).sum().squareRoot() }

func median(_ v: [Double]) -> Double {
    let s = v.sorted()
    return s.isEmpty ? 0 : s[s.count / 2]
}

/// An optimised build skips asserts; a debug one runs them.
let optimized: Bool = {
    var debug = false
    assert({ debug = true; return true }())
    return !debug
}()
let widen: Double = optimized ? 1 : 25
print("     build: " + (optimized ? "optimised (-O)" : "debug (-Onone): smaller samples, time bounds x25"))

// MARK: - P1 the synthetic vault

let spec = GraphPerfSynthetic.Spec()
var input: GraphPerfInput!
let genTime = seconds { input = GraphPerfSynthetic.make(spec) }
let n = input.noteIDs.count
check("P1 100,000 notes, a kind and a folder each (\(ms(genTime)))",
      n == 100_000 && input.isPage.count == n && input.folderOfNote.count == n)
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

var graph: GraphPerfGraph!
let graphTime = seconds { graph = GraphPerfGraph(input) }
let hubDegree = (0..<n).map { graph.degree($0) }.max() ?? 0
print("     graph: \(graph.noteCount) notes, \(graph.folderCount) folders, \(graph.linkCount) links, " +
      "\(graph.looseGroupCount) loose groups, highest degree \(hubDegree), built in \(ms(graphTime))")
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
    if !optimized && i >= 20_000 { break }
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

// the input as an app's store holds it: ids, folder and parent ids, id links
let byIDs = GraphPerfInput.make(noteIDs: small.noteIDs, isPage: small.isPage,
                                noteFolders: small.folderOfNote.map { $0 < 0 ? nil : small.folderIDs[Int($0)] },
                                folderIDs: small.folderIDs,
                                folderParents: small.folderParent.map { $0 < 0 ? nil : small.folderIDs[Int($0)] },
                                links: stride(from: 0, to: small.edges.count, by: 2).map {
                                    (small.noteIDs[Int(small.edges[$0])], small.noteIDs[Int(small.edges[$0 + 1])])
                                } + [(UUID(), small.noteIDs[0])],
                                noteTitles: small.noteIDs.indices.map { "Note \($0)" })
check("P2 an input made from ids is the same graph (an unknown id dropped)",
      GraphPerfGraph(byIDs).signature == g1.signature && byIDs.edges.count == small.edges.count)
let missingFolder = GraphPerfInput.make(noteIDs: [UUID()], isPage: [true], noteFolders: [UUID()], folderIDs: [],
                                        folderParents: [], links: [])
check("P2 a note in a folder that is not there is loose", missingFolder.folderOfNote == [-1])

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
// 1,000 loose pairs: the 256 largest groups stay, the rest join the pool
let pairIDs = (0..<2_000).map { _ in rng.uuid() }
let pairs = GraphPerfGraph(GraphPerfInput(noteIDs: pairIDs, isPage: Array(repeating: false, count: 2_000),
                                          folderOfNote: Array(repeating: -1, count: 2_000), folderIDs: [],
                                          folderParent: [], edges: (0..<2_000).map { UInt32($0) }))
let pairLayout = GraphPerfLayout.seed(pairs)!
check("P2 at most \(GraphPerfGraph.maxLooseGroups) loose groups of their own, then one pool",
      pairs.systemCount == GraphPerfGraph.maxLooseGroups + 1
      && pairs.systemNoteStart[pairs.systemCount] - pairs.systemNoteStart[pairs.systemCount - 1] == 2_000 - 512
      && pairLayout.positions.count == 2_000, "\(pairs.systemCount)")
let empty = GraphPerfGraph(GraphPerfInput(noteIDs: [], isPage: [], folderOfNote: [], folderIDs: [], folderParent: [], edges: []))
check("P2 an empty vault builds", empty.noteCount == 0 && empty.systemCount == 0 && GraphPerfLayout.seed(empty)!.positions.isEmpty)

// the filter, as bodies (notes, then hubs)
let pageMask = g1.mask(.pages)!, ideaMask = g1.mask(.ideas)!, linkedMask = g1.mask(.linked)!
let topSlot = (0..<g1.folderCount).first { g1.folderParent[$0] < 0 && g1.folderSubtreeCount[$0] > 50 }!
let folderMask = g1.mask(.folder(g1.folderIDs[topSlot]))!
check("P2 the filter: everything is no mask; pages, ideas and linked notes as they are",
      g1.mask(.all) == nil && (0..<g1.noteCount).allSatisfy { pageMask[$0] == g1.isPage[$0] && ideaMask[$0] != g1.isPage[$0]
          && linkedMask[$0] == (g1.degree($0) > 0) })
check("P2 a folder filter shows its notes and hubs, all the way down, and nothing else",
      (0..<g1.noteCount).allSatisfy { folderMask[$0] == (g1.folder[$0] >= 0 && g1.folderRegion[Int(g1.folder[$0])] == Int32(topSlot)) }
      && (0..<g1.folderCount).allSatisfy { folderMask[g1.noteCount + $0] == (g1.folderRegion[$0] == Int32(topSlot)) })
check("P2 a hub shows while a note under it does",
      (0..<g1.folderCount).allSatisfy { f in
          let any = (0..<g1.noteCount).contains { i in
              pageMask[i] && g1.folder[i] >= 0 && {
                  var cur = g1.folder[i]
                  while cur >= 0 { if Int(cur) == f { return true }; cur = g1.folderParent[Int(cur)] }
                  return false
              }()
          }
          return pageMask[g1.noteCount + f] == any
      })
check("P2 an unknown folder filters everything out", g1.mask(.folder(UUID()))!.allSatisfy { !$0 })

// MARK: - P3 the seed layout

var layout: GraphPerfLayout!
let seedTime = seconds { layout = GraphPerfLayout.seed(graph) }
let pos = layout.positions
check("P3 notes then hubs, all finite (\(ms(seedTime)))",
      pos.count == n + graph.folderCount && pos.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
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
let sampleStride = optimized ? 1 : 20
var minSpacing = Float.infinity, touching = 0
for i in stride(from: 0, to: n, by: sampleStride) {
    if let j = noteGrid.nearest(1, to: pos[i], excluding: i).first { minSpacing = min(minSpacing, length(pos[i] - pos[j])) }
}
for i in stride(from: 0, to: pos.count, by: sampleStride) {
    for j in world.within(layout.radius[i] + 1.2, of: pos[i]) where j != i
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
// brute force reads every body: the whole 100,000 when optimised, a 20,000 vault in a debug build
let pickInput = optimized ? input! : GraphPerfSynthetic.make(.init(notes: 20_000, seed: 21))
let pickGraph = optimized ? graph! : GraphPerfGraph(pickInput)
let pickLayout = optimized ? layout! : GraphPerfLayout.seed(pickGraph)!
let pickPos = pickLayout.positions, pickNotes = pickGraph.noteCount
let pickExtent = pickPos.map(length).max() ?? 0
let tapsPerPose = optimized ? 250 : 40
var taps = 0, agree = 0, hits = 0, pickTime = 0.0, bruteTime = 0.0
let poses: [(SIMD3<Float>, SIMD3<Float>)] = (0..<8).map { k in
    let target = k < 4 ? SIMD3<Float>.zero : pickPos[rng.below(pickNotes)]
    let away: Float = k < 4 ? pickExtent * 2.2 : Float(8 + rng.below(40))
    let dir = SIMD3<Float>(Float(rng.unit()) - 0.5, Float(rng.unit()) - 0.5, Float(rng.unit()) - 0.5)
    return (target + dir / length(dir) * away, target)
}
var poseBins: [GraphPerfScreenBins] = []
for (eye, target) in poses {
    let seen = project(pickPos, pickLayout.radius, notes: pickNotes, eye: eye, target: target)
    let bins = GraphPerfScreenBins(seen, width: width, height: height)
    poseBins.append(bins)
    for t in 0..<tapsPerPose {
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
print("     picks over \(pickPos.count) bodies: \(agree)/\(taps) equal brute force, \(hits) hit; " +
      "\(String(format: "%.4f", pickTime / Double(2 * taps) * 1000)) ms a pick vs " +
      "\(String(format: "%.3f", bruteTime / Double(2 * taps) * 1000)) ms brute")
check("P4 \(taps) taps over 8 poses pick as brute force does", agree == taps && hits > taps / 4, "\(agree) \(hits)")

// ties everywhere: bodies on whole points with few sizes and depths, taps on whole points
var grid = GraphPerfScreenPoints()
for _ in 0..<3_000 {
    grid.x.append(Float(rng.below(420)) - 15); grid.y.append(Float(rng.below(880)) - 18)
    grid.radius.append([2, 4, 4, 8, 30, 120][rng.below(6)]); grid.depth.append(Float(1 + rng.below(3)))
    grid.isNote.append(rng.below(3) > 0)
}
let gridBins = GraphPerfScreenBins(grid, width: width, height: height)
var tieAgree = 0
let tieTaps = optimized ? 1_000 : 200
for _ in 0..<tieTaps {
    let x = Float(rng.below(390)), y = Float(rng.below(844))
    if gridBins.pick(x: x, y: y) == GraphPerfPick.bruteForce(grid, x: x, y: y)
        && gridBins.dragPick(x: x, y: y) == GraphPerfPick.bruteForceDrag(grid, x: x, y: y) { tieAgree += 1 }
}
check("P4 with exact ties and discs wider than a bin, still brute force's answer", tieAgree == tieTaps, "\(tieAgree)")

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

let pickWorld = GraphPerfWorldGrid(pickPos, cell: 2 * pickLayout.spacing)
var gridAgree = true
for _ in 0..<(optimized ? 200 : 30) {
    let p = pickPos[rng.below(pickPos.count)] + SIMD3(Float(rng.unit()), Float(rng.unit()), Float(rng.unit())) * 3
    let r = Float(rng.unit() * 4)
    let brute = pickPos.indices.filter { ((pickPos[$0] - p) * (pickPos[$0] - p)).sum() <= r * r }
    if pickWorld.within(r, of: p) != brute { gridAgree = false }
}
check("P5 sphere queries equal brute force", gridAgree)
var kAgree = true
for _ in 0..<(optimized ? 50 : 6) {
    let p = SIMD3(Float(rng.unit()) - 0.5, Float(rng.unit()) - 0.5, Float(rng.unit()) - 0.5) * pickExtent
    let brute = pickPos.indices.map { (((pickPos[$0] - p) * (pickPos[$0] - p)).sum(), $0) }
        .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }.prefix(5).map { $0.1 }
    if pickWorld.nearest(5, to: p) != brute { kAgree = false }
}
check("P5 k-nearest queries equal brute force (in empty space too)", kAgree)

// MARK: - P6 level of detail rules and labels

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

// MARK: - P7 frame stats and the readout

let target = 1.0 / 60
let calm = GraphPerfFrameStats(Array(repeating: target, count: 100), target: target)
check("P7 a steady stream: p50 = p95 = the frame, no hitches", calm.p50 == target && calm.p95 == target && calm.hitches == 0)
let rough = GraphPerfFrameStats((1...100).map { Double($0) / 1000 }, target: target)
check("P7 1 to 100 ms: p50 50, p95 95, 75 frames over 25 ms", rough.p50 == 0.05 && rough.p95 == 0.095 && rough.hitches == 75)
let spiky = GraphPerfFrameStats(Array(repeating: target, count: 97) + [0.04, 0.05, 0.1], target: target)
check("P7 three long frames are three hitches, p95 still the frame", spiky.hitches == 3 && spiky.p95 == target)
let none7 = GraphPerfFrameStats([], target: target)
check("P7 no frames, zeros", none7.count == 0 && none7.p50 == 0 && none7.p95 == 0 && none7.hitches == 0)
var readout = GraphPerfStats(notes: 100_000, links: 230_080, drawnBodies: 98_412, drawnGlows: 236, drawnLines: 231_940,
                             fps: 119.6, cpuP95: 0.004, settling: false)
check("P7 the readout: notes, links, frames a second; what was drawn",
      readout.line == "100,000 notes \u{00B7} 230,080 links \u{00B7} 120 fps"
      && readout.drawn == "98,412 drawn \u{00B7} 236 glows \u{00B7} 231,940 lines", readout.line + " / " + readout.drawn)
readout.notes = 1; readout.links = 1; readout.drawnGlows = 1
check("P7 one of each is singular, and small numbers have no commas",
      readout.line == "1 note \u{00B7} 1 link \u{00B7} 120 fps" && GraphPerfStats.grouped(999) == "999"
      && GraphPerfStats.grouped(1_000) == "1,000" && GraphPerfStats.grouped(-12_345) == "-12,345")

// MARK: - P8 linear time

func stages(_ notes: Int) -> [Double] {
    var best = [Double](repeating: .infinity, count: 4)
    for _ in 0..<(optimized ? 3 : 1) {
        var inp: GraphPerfInput!, gr: GraphPerfGraph!, lay: GraphPerfLayout!
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

// MARK: - P9 the force layout, a slice a frame

func ballCheck(_ f: GraphPerfForce, _ g: GraphPerfGraph, _ l: GraphPerfLayout) -> (outside: Int, inHub: Int) {
    var outside = 0, inHub = 0
    for i in 0..<g.noteCount {
        let s = Int(g.systemOfNote[i])
        let d = length(f.position(i) - l.systemCentre[s])
        if d + l.radius[i] > l.coreRadius[s] + 1e-3 { outside += 1 }
        if s < g.folderCount && d < l.radius[g.noteCount + s] + l.radius[i] - 1e-3 { inHub += 1 }
    }
    return (outside, inHub)
}

/// The mean length of links inside one system, and of all links.
func linkLengths(_ f: GraphPerfForce, _ g: GraphPerfGraph) -> (inside: Float, all: Float) {
    var inside: Double = 0, all: Double = 0, count = 0
    for k in 0..<g.linkCount {
        let a = Int(g.edgeA[k]), b = Int(g.edgeB[k])
        let d = Double(length(f.position(a) - f.position(b)))
        all += d
        if g.systemOfNote[a] == g.systemOfNote[b] { inside += d; count += 1 }
    }
    return (Float(inside / Double(max(count, 1))), Float(all / Double(max(g.linkCount, 1))))
}

var force = GraphPerfForce(graph: graph, layout: layout)
let seedLengths = linkLengths(force, graph)
// the renderer sizes its slice to about 3 ms a frame; 5,000 notes is about that on a phone
let budget = 5_000
var stepTimes: [Double] = [], visited = 0, steps = 0
while !force.isSettled && steps < 1_000 {
    var did = 0
    stepTimes.append(seconds { did = force.step(budget: budget) })
    visited += did
    steps += 1
}
let settledLengths = linkLengths(force, graph)
let p95Step = stepTimes.sorted()[min(stepTimes.count - 1, Int(Double(stepTimes.count) * 0.95))]
print("     force: \(steps) steps of \(budget) notes over \(force.sweep) sweeps; a step " +
      "\(ms2(median(stepTimes))) median, \(ms2(p95Step)) p95, \(ms2(stepTimes.max() ?? 0)) worst; " +
      "links inside a folder \(String(format: "%.2f", seedLengths.inside)) -> \(String(format: "%.2f", settledLengths.inside)) units")
check("P9 at 100,000 notes a step of \(budget) is within a frame: median under \(Int(8 * widen)) ms, worst under \(Int(25 * widen)) ms",
      median(stepTimes) < 0.008 * widen && (stepTimes.max() ?? 0) < 0.025 * widen,
      "\(ms2(median(stepTimes))) \(ms2(stepTimes.max() ?? 0))")
check("P9 it settles: every note visited once a sweep, then a step does nothing",
      force.isSettled && visited == force.sweep * n && force.step(budget: budget) == 0, "\(visited) \(force.sweep)")
let balls = ballCheck(force, graph, layout)
check("P9 every note still inside its folder's ball and clear of its hub", balls.outside == 0 && balls.inHub == 0,
      "\(balls)")
check("P9 links inside a folder draw together (at least 10% shorter)",
      settledLengths.inside < seedLengths.inside * 0.9, "\(seedLengths) \(settledLengths)")
check("P9 hubs never move", (0..<graph.folderCount).allSatisfy { force.position(n + $0) == layout.positions[n + $0] })
let settledPositions = (0..<n).map { force.position($0) }
let settledGrid = GraphPerfWorldGrid(settledPositions, cell: 2 * layout.spacing)
var settledMin = Float.infinity
for i in stride(from: 0, to: n, by: optimized ? 1 : 20) {
    if let j = settledGrid.nearest(1, to: settledPositions[i], excluding: i).first {
        settledMin = min(settledMin, length(settledPositions[i] - settledPositions[j]))
    }
}
check("P9 notes stay apart: none closer than 0.45 of a spacing", settledMin >= 0.45 * layout.spacing, "\(settledMin)")
check("P9 every position finite", settledPositions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
// the same sweeps, sliced differently, give the same map
var sliceA = GraphPerfForce(graph: g1, layout: l1), sliceB = GraphPerfForce(graph: g1, layout: l1)
while !sliceA.isSettled { sliceA.step(budget: 997) }
while !sliceB.isSettled { sliceB.step(budget: 3_331) }
var whole1 = GraphPerfForce(graph: g1, layout: l1)
whole1.settle()
check("P9 deterministic, and the same however the sweeps are sliced into steps",
      sliceA.xyzr == sliceB.xyzr && sliceA.xyzr == whole1.xyzr && sliceA.sweep == sliceB.sweep)
check("P9 a step stops at the end of a sweep",
      { var f = GraphPerfForce(graph: g1, layout: l1); let first = f.step(budget: 3_000); let second = f.step(budget: 3_000)
        return first == 3_000 && second == g1.noteCount - 3_000 && f.sweep == 1 && f.cursor == 0 }())
var emptyForce = GraphPerfForce(graph: empty, layout: GraphPerfLayout.seed(empty)!)
check("P9 an empty map is settled at once", emptyForce.isSettled && emptyForce.step(budget: 100) == 0)
check("P9 positions are what the GPU takes: x, y, z, radius per body",
      force.xyzr.count == 4 * graph.nodeCount && force.xyzr[3] == layout.radius[0]
      && force.xyzr[4 * n + 3] == layout.radius[n])

// MARK: - P10 the camera

var cam = GraphPerfCamera()
cam.target = SIMD3(3, -2, 5)
cam.distance = 40
cam.yaw = 0.7
cam.pitch = 0.4
func near3(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ eps: Float = 1e-3) -> Bool { length(a - b) <= eps }
let view = cam.viewMatrix()
let eyeInView = view.apply(SIMD4(cam.eye.x, cam.eye.y, cam.eye.z, 1))
let targetInView = view.apply(SIMD4(cam.target.x, cam.target.y, cam.target.z, 1))
check("P10 the view puts the eye at the origin and the target straight ahead",
      near3(SIMD3(eyeInView.x, eyeInView.y, eyeInView.z), .zero)
      && near3(SIMD3(targetInView.x, targetInView.y, targetInView.z), SIMD3(0, 0, -40), 1e-2))
check("P10 right, up and forward are a right-handed unit frame",
      abs(length(cam.right) - 1) < 1e-5 && abs(length(cam.up) - 1) < 1e-5
      && abs((cam.right * cam.up).sum()) < 1e-5 && abs((cam.right * cam.forward).sum()) < 1e-5
      && near3(GraphPerfCamera.cross(cam.right, cam.up), -cam.forward, 1e-5))
let projection = cam.projectionMatrix(aspect: width / height, near: 2, far: 200)
func clipDepth(_ d: Float) -> Float {
    let p = cam.eye + cam.forward * d
    let c = (projection * view).apply(SIMD4(p.x, p.y, p.z, 1))
    return c.z / c.w
}
check("P10 depth 0 at the near plane, 1 at the far one", abs(clipDepth(2)) < 1e-4 && abs(clipDepth(200) - 1) < 1e-4)
let centreOnScreen = cam.project(cam.target, width: width, height: height)
check("P10 the target is in the middle of the screen", abs(centreOnScreen.x - width / 2) < 1e-3
      && abs(centreOnScreen.y - height / 2) < 1e-3 && abs(centreOnScreen.depth - 40) < 1e-3)
var roundTrip = true
for _ in 0..<200 {
    let p = cam.target + SIMD3(Float(rng.unit()) - 0.5, Float(rng.unit()) - 0.5, Float(rng.unit()) - 0.5) * 30
    let s = cam.project(p, width: width, height: height)
    guard s.depth > 0.1 else { continue }
    // the projection matrix agrees with project()
    let c = (projection * view).apply(SIMD4(p.x, p.y, p.z, 1))
    let sx = (c.x / c.w + 1) / 2 * width, sy = (1 - c.y / c.w) / 2 * height
    let r = cam.ray(x: s.x, y: s.y, width: width, height: height)
    let along = ((p - r.origin) * r.direction).sum()
    let off = length(p - (r.origin + r.direction * along))
    if abs(sx - s.x) > 0.01 || abs(sy - s.y) > 0.01 || off > 1e-3 * s.depth { roundTrip = false }
}
check("P10 a point projects where the matrices put it, and the ray back through it passes through it", roundTrip)
var orbited = cam
orbited.orbit(yaw: 0.5, pitch: 10)
check("P10 turning keeps the distance and stops short of straight down",
      abs(length(orbited.eye - orbited.target) - 40) < 1e-3 && orbited.pitch == GraphPerfCamera.pitchLimit)
var zoomed = cam
zoomed.zoom(by: 2, limits: 5...100)
let closer = zoomed.distance
zoomed.zoom(by: 100, limits: 5...100)
check("P10 a pinch halves the distance, within its limits", closer == 20 && zoomed.distance == 5)
var panned = cam
let before = panned.project(SIMD3(10, 3, -4), width: width, height: height)
panned.pan(dx: 30, dy: -12, viewHeight: height)
let afterPan = panned.project(SIMD3(10, 3, -4), width: width, height: height)
check("P10 two fingers slide the target across the view, a point at its depth moving with them",
      abs(((panned.target - cam.target) * cam.forward).sum()) < 1e-4
      && abs(cam.project(panned.target, width: width, height: height).depth - 40) < 1e-3
      && abs((afterPan.x - before.x) - 30 * 40 / before.depth) < 0.05
      && abs((afterPan.y - before.y) + 12 * 40 / before.depth) < 0.05, "\(afterPan) \(before)")
let ballCentre = SIMD3<Float>(50, -20, 10)
let insets: (top: Float, left: Float, bottom: Float, right: Float) = (60, 0, 200, 0)
let framedCam = cam.framing(centre: ballCentre, radius: 25, width: width, height: height, insets: insets, fill: 0.9)
var inWindow = true, widest: Float = 0
for k in 0..<64 {
    let d = GraphPerfLayout.fibonacci(k, 64)
    let s = framedCam.project(ballCentre + d * 25, width: width, height: height)
    if s.x < insets.left || s.x > width - insets.right || s.y < insets.top || s.y > height - insets.bottom { inWindow = false }
    let c = framedCam.project(ballCentre, width: width, height: height)
    widest = max(widest, abs(s.x - c.x))
}
let windowCentre = framedCam.project(ballCentre, width: width, height: height)
check("P10 framing a ball fits it in the window above the card, centred there, about 90% across",
      inWindow && abs(windowCentre.x - width / 2) < 0.5
      && abs(windowCentre.y - (insets.top + (height - insets.top - insets.bottom) / 2)) < 0.5
      && widest > 0.8 * 0.9 * width / 2 && widest <= width / 2, "\(widest) \(windowCentre)")
var turned = cam
turned.yaw = -3.0
cam.yaw = 3.0
let halfway = GraphPerfCamera.glide(cam, turned, t: 0.5)
check("P10 a glide starts and ends on its poses, and turns the short way round",
      GraphPerfCamera.glide(cam, turned, t: 0) == cam && GraphPerfCamera.glide(cam, turned, t: 1).yaw == turned.yaw
      && abs(abs(halfway.yaw) - Float.pi) < 0.01)
let frustum = cam.frustum(width: width, height: height, near: 1, far: 100)
check("P10 the frustum holds the target, not what is behind the eye, beyond the far plane or off to the side",
      frustum.touches(centre: cam.target, radius: 0.1)
      && !frustum.touches(centre: cam.eye - cam.forward * 5, radius: 1)
      && !frustum.touches(centre: cam.eye + cam.forward * 150, radius: 1)
      && !frustum.touches(centre: cam.target + cam.right * 200, radius: 1)
      && frustum.touches(centre: cam.target + cam.right * 200, radius: 190))

// MARK: - P11 cluster level of detail

var scene: GraphPerfScene!
let sceneTime = seconds { scene = GraphPerfScene(graph: graph, layout: layout, input: input) }
let clusters = scene.clusters
let bundled = clusters.bundleLinks.count, insideLinks = clusters.internalLinks.count
check("P11 every link once: inside one cluster, or in the bundle of its two",
      bundled + insideLinks == graph.linkCount
      && Set(clusters.bundleLinks.map { Int($0) } + clusters.internalLinks.map { Int($0) }).count == graph.linkCount)
var bundlesRight = true
for b in 0..<clusters.bundleCount {
    let a = clusters.bundleA[b], c = clusters.bundleB[b]
    if a >= c || (b > 0 && (clusters.bundleA[b - 1], clusters.bundleB[b - 1]) >= (a, c)) { bundlesRight = false }
    for k in Int(clusters.bundleStart[b])..<Int(clusters.bundleStart[b + 1]) {
        let l = Int(clusters.bundleLinks[k])
        let sa = graph.systemOfNote[Int(graph.edgeA[l])], sb = graph.systemOfNote[Int(graph.edgeB[l])]
        if (min(sa, sb), max(sa, sb)) != (a, c) { bundlesRight = false }
    }
}
check("P11 bundles: one per cluster pair, in order, holding exactly that pair's links (\(clusters.bundleCount))", bundlesRight)

func plan(_ distance: Float, settings: GraphPerfLODSettings = .of(.high), mask: [Bool]? = nil,
          maskVersion: Int = 0) -> GraphPerfLODPlanner {
    var c = GraphPerfCamera()
    c.yaw = 0.55
    c.pitch = 0.32
    c = c.framing(centre: scene.centre, radius: scene.radius, width: width, height: height)
    c.distance *= distance
    let range = c.depthRange(centre: scene.centre, radius: scene.radius)
    var p = GraphPerfLODPlanner()
    p.plan(clusters, view: GraphPerfViewpoint(camera: c, width: width, height: height, near: range.near, far: range.far),
           settings: settings, mask: mask, maskVersion: maskVersion)
    return p
}
var counts: [(Float, Int, Int, Int)] = []
var planTimes: [Double] = []
for d: Float in [1, 2, 4, 8, 16, 64] {
    var p = GraphPerfLODPlanner()
    planTimes.append(seconds { p = plan(d) })
    counts.append((d, p.lists.nodes.count, p.lists.glows.count, p.lists.lineCount))
}
for (d, bodies, glows, lines) in counts {
    print("     lod x\(Int(d)) the framing distance: \(bodies) bodies, \(glows) glows, \(lines) lines")
}
let nodesShrink = zip(counts, counts.dropFirst()).allSatisfy { $0.1 >= $1.1 && $0.3 >= $1.3 }
check("P11 bodies and lines drawn shrink as the camera goes back (whole map in view)",
      nodesShrink && counts.last!.1 < counts.first!.1 && counts.last!.3 < counts.first!.3, "\(counts)")
check("P11 at the whole-map framing (a phone held upright) at least 95,000 of 100,000 notes are drawn one by one",
      counts[0].1 >= 95_000, "\(counts[0])")
let farthest = plan(64)
check("P11 far enough away every cluster is one glow, and only bundles and the folder tree are left",
      counts.last!.1 == 0 && counts.last!.2 == clusters.count
      && farthest.lists.links.count == clusters.treeChild.count
      && farthest.lists.lineCount == farthest.lists.bundles.count + clusters.treeChild.count)
check("P11 planning the whole map takes under \(Int(16 * widen)) ms (\(ms2(median(planTimes))) median)",
      median(planTimes) < 0.016 * widen)
// near: the camera framing one folder's own ball shows it in full
let bigFolder = (0..<graph.folderCount).max { clusters.memberCount($0) < clusters.memberCount($1) }!
var closeCam = GraphPerfCamera()
closeCam = closeCam.framing(centre: layout.systemCentre[bigFolder], radius: clusters.ball[bigFolder].w,
                            width: width, height: height)
let closeRange = closeCam.depthRange(centre: scene.centre, radius: scene.radius)
var closePlan = GraphPerfLODPlanner()
closePlan.plan(clusters, view: GraphPerfViewpoint(camera: closeCam, width: width, height: height, near: closeRange.near,
                                                 far: closeRange.far), settings: .of(.saver))
let closeMembers = Set(closePlan.lists.nodes)
check("P11 near, even on the saver tier, a folder is drawn in full: every note, its hub and its own links",
      closePlan.states[bigFolder] == .full
      && (Int(clusters.memberStart[bigFolder])..<Int(clusters.memberStart[bigFolder + 1])).allSatisfy {
          closeMembers.contains(UInt32(clusters.members[$0]))
      } && closeMembers.contains(UInt32(n + bigFolder))
      && Set(closePlan.lists.links).isSuperset(of: clusters.internalLinks[Int(clusters.internalStart[bigFolder])..<Int(clusters.internalStart[bigFolder + 1])].map { UInt32($0) }))
let culled = closePlan.states.filter { $0 == .culled }.count
check("P11 and what is out of view is not drawn at all (\(culled) of \(clusters.count) clusters culled)",
      culled > clusters.count / 4 && closePlan.lists.nodes.count < n / 2)
// over a budget: the smallest on screen give way, never past it
let tight = plan(1, settings: GraphPerfLODSettings(collapseBelow: 1.5, linksBelow: 2.5, nodeBudget: 20_000, linkBudget: 30_000))
check("P11 a tier's budget is never passed: the clusters smallest on screen collapse first",
      tight.lists.nodes.count <= 20_000 && tight.lists.nodes.count > 10_000
      && zip(tight.states, tight.screenRadius).allSatisfy { state, rho in
          state != .collapsed || tight.screenRadius.indices.allSatisfy { s in
              tight.states[s].rawValue < GraphPerfLODPlanner.State.notes.rawValue || tight.screenRadius[s] >= rho
          }
      }, "\(tight.lists.nodes.count)")
var unchanged = plan(1)
let firstVersion = unchanged.version
var sameCam = GraphPerfCamera()
sameCam.yaw = 0.55
sameCam.pitch = 0.32
sameCam = sameCam.framing(centre: scene.centre, radius: scene.radius, width: width, height: height)
let sameRange = sameCam.depthRange(centre: scene.centre, radius: scene.radius)
let replanned = unchanged.plan(clusters, view: GraphPerfViewpoint(camera: sameCam, width: width, height: height,
                                                                  near: sameRange.near, far: sameRange.far),
                               settings: .of(.high))
check("P11 the same view again changes nothing (no copy to the GPU)", !replanned && unchanged.version == firstVersion)
let pagesOnly = plan(1, mask: graph.mask(.pages), maskVersion: 1)
check("P11 the filter: only pages (and hubs over them) drawn, only links between two shown notes",
      pagesOnly.lists.nodes.allSatisfy { Int($0) >= n || graph.isPage[Int($0)] }
      && pagesOnly.lists.links.allSatisfy { k in
          Int(k) >= graph.linkCount || (graph.isPage[Int(graph.edgeA[Int(k)])] && graph.isPage[Int(graph.edgeB[Int(k)])])
      } && pagesOnly.lists.nodes.count < counts[0].1 / 3)

// MARK: - P12 the scene the GPU is handed

print("     scene at 100,000 from graph and layout: \(ms(sceneTime)) (clusters, colours, lines, ids)")
check("P12 a colour per body, opaque; a hub lighter than the notes of its region",
      scene.colours.count == graph.nodeCount && scene.colours.allSatisfy { $0 >> 24 == 255 }
      && (0..<graph.folderCount).allSatisfy { f in
          let hub = GraphPerfScene.unpack(scene.colours[n + f])
          let base = GraphPerfScene.palette[Int(graph.folderRegion[f]) % GraphPerfScene.palette.count]
          return hub.x + hub.y + hub.z > base.sum()
      })
check("P12 lines: every link's two notes, then each folder's hub to its parent's",
      scene.lineCount == graph.linkCount + clusters.treeChild.count
      && (0..<graph.linkCount).allSatisfy { scene.lineEnds[2 * $0] == UInt32(graph.edgeA[$0]) && scene.lineEnds[2 * $0 + 1] == UInt32(graph.edgeB[$0]) }
      && (0..<clusters.treeChild.count).allSatisfy { t in
          let child = Int(scene.lineEnds[2 * (graph.linkCount + t)]) - n
          let parent = Int(scene.lineEnds[2 * (graph.linkCount + t) + 1]) - n
          return child >= 0 && graph.folderParent[child] == Int32(parent)
      })
check("P12 each body's cluster: a note's system, a hub its own folder",
      (0..<n).allSatisfy { scene.clusterOfBody[$0] == UInt32(graph.systemOfNote[$0]) }
      && (0..<graph.folderCount).allSatisfy { scene.clusterOfBody[n + $0] == UInt32($0) }
      && scene.clusterBalls.count == 4 * clusters.count && scene.bundleEnds.count == 2 * clusters.bundleCount)
var idsRight = true
for _ in 0..<500 {
    let b = rng.below(scene.bodyCount)
    if let id = scene.id(b), scene.body(id) == b { continue }
    idsRight = false
}
check("P12 a body's id and back", idsRight && scene.id(-1) == nil && scene.id(scene.bodyCount) == nil
      && scene.body(UUID()) == nil)
check("P12 titles: made on demand for the demo vault, the input's own otherwise",
      scene.title(0) == GraphPerfSynthetic.title(Int(graph.inputOfNote[0])) && scene.title(n).hasPrefix("Folder ")
      && GraphPerfScene.build(byIDs)!.title(GraphPerfGraph(byIDs).noteOfInput.map { Int($0) }[7]) == "Note 7")
check("P12 the bounds hold every body",
      (0..<scene.bodyCount).allSatisfy { length(layout.positions[$0] - scene.centre) <= scene.radius + 1e-2 })
var built100: GraphPerfScene?
let build100 = seconds { built100 = GraphPerfScene.build(input) }
check("P12 the whole scene from 100,000 notes in under \(Int(1.5 * widen)) s (\(ms(build100)))",
      built100 != nil && build100 < 1.5 * widen)
if optimized {
    var input300: GraphPerfInput!, scene300: GraphPerfScene?
    let gen300 = seconds { input300 = GraphPerfSynthetic.make(.init(notes: 300_000)) }
    let build300 = seconds { scene300 = GraphPerfScene.build(input300) }
    let s300 = scene300!
    var p300 = GraphPerfLODPlanner()
    var c300 = GraphPerfCamera()
    c300 = c300.framing(centre: s300.centre, radius: s300.radius, width: width, height: height)
    let r300 = c300.depthRange(centre: s300.centre, radius: s300.radius)
    let plan300 = seconds {
        p300.plan(s300.clusters, view: GraphPerfViewpoint(camera: c300, width: width, height: height, near: r300.near, far: r300.far),
                  settings: .of(.smooth))
    }
    var f300 = GraphPerfForce(graph: s300.graph, layout: s300.layout)
    var steps300: [Double] = []
    for _ in 0..<30 { steps300.append(seconds { f300.step(budget: budget) }) }
    print("     300k: generated in \(ms(gen300)), scene in \(ms(build300)), \(s300.graph.linkCount) links; " +
          "smooth tier draws \(p300.lists.nodes.count) bodies, \(p300.lists.glows.count) glows, \(p300.lists.lineCount) lines " +
          "(planned in \(ms2(plan300))); a layout step \(ms2(median(steps300))) median")
    check("P12 300,000 notes: the scene in under 4 s, the smooth tier within its budget, a layout step within a frame",
          build300 < 4 && p300.lists.nodes.count <= GraphPerfLODSettings.of(.smooth).nodeBudget
          && median(steps300) < 0.008 && plan300 < 0.05, "\(build300) \(median(steps300))")
} else {
    print("     300k: skipped in a debug build (CI runs it optimised)")
}

// MARK: - P13 the shaders and the frame

for name in GraphPerfShaders.functions {
    check("P13 the shader source has \(name)", GraphPerfShaders.source.contains(" " + name + "("))
}
// each buffer the shaders read, by the name they give it, and the slot the renderer binds it to
let slotsUsed: [(String, Int)] = [
    ("Frame& f", GraphPerfShaders.Slot.frame), ("float4* xyzr", GraphPerfShaders.Slot.positions),
    ("uint* colour", GraphPerfShaders.Slot.colours), ("uint* list", GraphPerfShaders.Slot.list),
    ("uint2* ends", GraphPerfShaders.Slot.lineEnds), ("uint* clusterOf", GraphPerfShaders.Slot.clusterOfBody),
    ("float4* balls", GraphPerfShaders.Slot.clusterBalls), ("uint* collapsed", GraphPerfShaders.Slot.collapsed),
    ("uint* clusterColour", GraphPerfShaders.Slot.clusterColours), ("uint2* bundleEnds", GraphPerfShaders.Slot.bundleEnds),
    ("float* weights", GraphPerfShaders.Slot.bundleWeights)
]
var slotProblems: [String] = []
for (name, slot) in slotsUsed {
    let uses = GraphPerfShaders.source.components(separatedBy: name + " [[buffer(").dropFirst()
    if uses.isEmpty { slotProblems.append(name + " unused") }
    for use in uses where !use.hasPrefix("\(slot))]]") { slotProblems.append(name + " at " + String(use.prefix(3))) }
}
let bufferUses = GraphPerfShaders.source.components(separatedBy: "[[buffer(").count - 1
let namedUses = slotsUsed.reduce(0) { $0 + GraphPerfShaders.source.components(separatedBy: $1.0 + " [[buffer(").count - 1 }
check("P13 every buffer the shaders read sits at the slot the renderer binds it to",
      slotProblems.isEmpty && bufferUses == namedUses, slotProblems.joined(separator: "; ") + " \(bufferUses) \(namedUses)")
var frameCam = GraphPerfCamera()
frameCam = frameCam.framing(centre: scene.centre, radius: scene.radius, width: width, height: height)
let frameRange = frameCam.depthRange(centre: scene.centre, radius: scene.radius)
let viewpoint = GraphPerfViewpoint(camera: frameCam, width: width, height: height, near: frameRange.near, far: frameRange.far)
let frame = GraphPerfShaders.frame(viewpoint, scene: scene, tier: .smooth, bold: true, selected: 42, focus: nil,
                                   pixelsPerPoint: 3, time: 1.5)
let viewProj = frameCam.projectionMatrix(aspect: width / height, near: frameRange.near, far: frameRange.far) * frameCam.viewMatrix()
check("P13 the frame is ten float4s in Frame's order",
      frame.count * 4 == GraphPerfShaders.frameFloats && frame[0] == viewProj.c0 && frame[3] == viewProj.c3
      && frame[5] == SIMD4(width, height, frameCam.focal(viewHeight: height), 3)
      && abs(frame[7].x - 0.21) < 1e-6 && frame[8].x == 42 && frame[8].y == -1 && frame[8].z == Float(n)
      && frame[9].w == Float(graph.linkCount) && frame[4].w == 1.5)

// MARK: - P14 tapping a node through the camera, at 100,000

var tapCam = GraphPerfCamera()
tapCam.yaw = 1.1
tapCam.pitch = 0.2
tapCam = tapCam.framing(centre: layout.systemCentre[bigFolder], radius: clusters.ball[bigFolder].w * 0.6,
                        width: width, height: height)
let tapRange = tapCam.depthRange(centre: scene.centre, radius: scene.radius)
let tapView = GraphPerfViewpoint(camera: tapCam, width: width, height: height, near: tapRange.near, far: tapRange.far)
var tapPlan = GraphPerfLODPlanner()
tapPlan.plan(clusters, view: tapView, settings: .of(.high))
var drawn = GraphPerfDrawnPoints()
var bins: GraphPerfScreenBins!
let pickSetup = seconds {
    drawn = GraphPerfDrawnPoints.of(scene, lists: tapPlan.lists, xyzr: force.xyzr, view: tapView)
    bins = GraphPerfScreenBins(drawn.points, width: width, height: height)
}
var tried = 0, found = 0, same = 0, tapTime = 0.0
let tapPoints = drawn.points
for k in stride(from: 0, to: drawn.ids.count, by: 7) where tried < 400 {
    guard drawn.ids[k] >= 0, tapPoints.pickable(k), tapPoints.x[k] > 0, tapPoints.x[k] < width,
          tapPoints.y[k] > 0, tapPoints.y[k] < height else { continue }
    tried += 1
    var hit: Int?
    tapTime += seconds { hit = bins.pick(x: tapPoints.x[k], y: tapPoints.y[k]) }
    if hit == GraphPerfPick.bruteForce(tapPoints, x: tapPoints.x[k], y: tapPoints.y[k]) { same += 1 }
    if hit == k { found += 1 }
}
print("     tap at 100,000: \(drawn.ids.count) drawn bodies projected and binned in \(ms2(pickSetup)), " +
      "a tap \(String(format: "%.4f", tapTime / Double(max(tried, 1)) * 1000)) ms; \(found)/\(tried) landed on the node tapped " +
      "(the rest on a smaller or nearer disc over it)")
check("P14 a tap on a drawn node's centre picks as brute force over what is drawn",
      tried >= 100 && same == tried && found > 0, "\(same) \(found)/\(tried)")
check("P14 projecting and binning what is drawn at 100,000 takes under \(Int(20 * widen)) ms", pickSetup < 0.02 * widen)
let farPlan = plan(64)
var farCam = GraphPerfCamera()
farCam.yaw = 0.55
farCam.pitch = 0.32
farCam = farCam.framing(centre: scene.centre, radius: scene.radius, width: width, height: height)
farCam.distance *= 64
let farRange = farCam.depthRange(centre: scene.centre, radius: scene.radius)
let farView = GraphPerfViewpoint(camera: farCam, width: width, height: height, near: farRange.near, far: farRange.far)
let farDrawn = GraphPerfDrawnPoints.of(scene, lists: farPlan.lists, xyzr: force.xyzr, view: farView)
let glowIndex = farDrawn.ids.firstIndex { $0 < 0 }!
let farBins = GraphPerfScreenBins(farDrawn.points, width: width, height: height)
let glowHit = farBins.pick(x: farDrawn.points.x[glowIndex], y: farDrawn.points.y[glowIndex]).map { farDrawn.ids[$0] }
check("P14 far away a tap lands on a cluster's glow", glowHit.map { $0 < 0 } == true, "\(String(describing: glowHit))")

print(failures.isEmpty ? "ALL PASSED" : "\(failures.count) FAILED")
exit(failures.isEmpty ? 0 : 1)
