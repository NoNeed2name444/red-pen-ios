// The owner's "Link length" (GraphLinkLength, UniverseInput.linkScale): the
// links in the Ideas map longer or shorter, in the Universe and the
// Neurons, planned inside the pure planners so it is checked here.
//
// At the shortest (0.6), the standard (1) and the longest (1.8) every
// planner keeps its guarantees - no overlaps, the size ladder, containers
// holding their contents, determinism, the envelope holding everything -
// linked bodies stand further apart as the setting grows, and no body
// changes size.
//
// Compiled with GraphUniverse.swift, GraphThemePlan.swift, GraphNeurons.swift,
// GraphAnatomy.swift and GraphicsQuality.swift (Foundation only).
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "PASS " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func fixedID(_ n: Int) -> UUID {
    let hex: String = String(format: "%012X", n)
    return UUID(uuidString: "00000000-0000-4000-8000-" + hex) ?? UUID()
}

struct Dice {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z: UInt64 = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func below(_ n: Int) -> Int {
        guard n > 0 else { return 0 }
        return Int(next() % UInt64(n))
    }
    mutating func unit() -> Double {
        Double(next() >> 11) / 9_007_199_254_740_992.0
    }
}

/// A random vault, as the hierarchy tests make them.
func randomVault(_ seed: UInt64, maxNotes: Int, maxFolders: Int) -> UniverseInput {
    var dice = Dice(state: seed)
    let folderCount: Int = dice.below(maxFolders + 1)
    var folders: [UniverseFolder] = []
    var depthOf: [Int] = []
    for k in 0..<folderCount {
        var parent: UUID?
        var d: Int = 0
        if k > 0 && dice.unit() < 0.6 {
            let p: Int = dice.below(k)
            if depthOf[p] < 6 {
                parent = folders[p].id
                d = depthOf[p] + 1
            }
        }
        folders.append(UniverseFolder(id: fixedID(10_000 + k), name: "Folder \(k)", parent: parent))
        depthOf.append(d)
    }
    let noteCount: Int = dice.below(maxNotes + 1)
    var notes: [UniverseNote] = []
    for k in 0..<noteCount {
        var folder: UUID?
        if !folders.isEmpty && dice.unit() < 0.88 { folder = folders[dice.below(folders.count)].id }
        let words: Int = Int(pow(2.0, dice.unit() * 11))
        notes.append(UniverseNote(id: fixedID(k + 1), title: "Note \(k)", isPage: dice.unit() < 0.3,
                                  folder: folder, words: words, created: Double(k)))
    }
    var edges: [UniverseEdge] = []
    let linkCount: Int = noteCount * 13 / 10
    for _ in 0..<linkCount where noteCount > 1 {
        let a: Int = dice.below(noteCount)
        let b: Int = dice.below(noteCount)
        edges.append(UniverseEdge(a: fixedID(a + 1), b: fixedID(b + 1)))
    }
    return UniverseInput(notes: notes, folders: folders, edges: edges, seedByName: false)
}

/// A small fixed vault like the design preview's: two top folders, one
/// with a sub-folder and a sub-sub-folder, pages, ideas, a moon, a bridge
/// and two loose notes.
func fixedVault() -> UniverseInput {
    let a: UUID = fixedID(900)
    let b: UUID = fixedID(901)
    let c: UUID = fixedID(902)
    let d: UUID = fixedID(903)
    let folders: [UniverseFolder] = [
        UniverseFolder(id: a, name: "Examples", parent: nil), UniverseFolder(id: b, name: "Inguinal", parent: a),
        UniverseFolder(id: c, name: "Cardiology", parent: nil), UniverseFolder(id: d, name: "Anatomy", parent: b)
    ]
    let homes: [UUID?] = [a, a, b, b, b, d, d, c, c, c, c, c, c, a, nil, nil]
    var notes: [UniverseNote] = []
    for (k, home) in homes.enumerated() {
        let words: Int = [300, 40, 120, 20, 70, 10, 45, 280, 20, 35, 60, 15, 90, 25, 30, 12][k]
        notes.append(UniverseNote(id: fixedID(k + 1), title: "N\(k)", isPage: k % 3 == 0, folder: home,
                                  words: words, created: Double(k)))
    }
    let pairs: [(Int, Int)] = [(0, 1), (0, 2), (2, 3), (2, 4), (4, 5), (5, 6), (7, 8), (7, 9), (9, 10), (10, 11),
                               (12, 7), (13, 2), (13, 7), (13, 9), (14, 12), (6, 3), (1, 13), (0, 15)]
    let edges: [UniverseEdge] = pairs.map { UniverseEdge(a: fixedID($0.0 + 1), b: fixedID($0.1 + 1)) }
    return UniverseInput(notes: notes, folders: folders, edges: edges, seedByName: true)
}

func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    let d: SIMD3<Float> = a - b
    return (d * d).sum().squareRoot()
}

let scales: [Double] = [0.6, 0.8, 1.0, 1.4, 1.8]
let vaults: [UniverseInput] = [fixedVault()] + (0..<24).map { randomVault(UInt64($0) &+ 4100, maxNotes: 90, maxFolders: 14) }

// MARK: L1 the setting

check("L1 default 1, range 0.6 to 1.8", GraphLinkLength.standard == 1 && GraphLinkLength.shortest == 0.6
      && GraphLinkLength.longest == 1.8)
check("L1 stored under vignette.space.linkLength", GraphLinkLength.key == "vignette.space.linkLength")
check("L1 missing or broken values read as standard", GraphLinkLength.stored(nil) == 1
      && GraphLinkLength.clamped(Double.nan) == 1 && GraphLinkLength.clamped(-3) == 1)
check("L1 clamped and snapped", GraphLinkLength.clamped(0.2) == 0.6 && GraphLinkLength.clamped(9) == 1.8
      && GraphLinkLength.clamped(1.26) == 1.3, "\(GraphLinkLength.clamped(1.26))")
check("L1 words", GraphLinkLength.word(0.6) == "Shorter" && GraphLinkLength.word(1) == "Standard"
      && GraphLinkLength.word(1.8) == "Longer")
check("L1 the footer is live", GraphLinkLength.footer(1.4).contains("40% longer")
      && GraphLinkLength.footer(0.8).contains("20% shorter") && GraphLinkLength.footer(1).contains("Standard"))
check("L1 the signature changes with it", GraphLinkLength.tag(1) != GraphLinkLength.tag(1.1)
      && GraphLinkLength.tag(1.04) == GraphLinkLength.tag(1))
let planned = UniverseInput(notes: [], folders: [], edges: [], seedByName: false)
check("L1 the input defaults to 1", planned.linkScale == 1 && planned.spacing == 1)
check("L1 the planners clamp too", planned.scaled(5).spacing == 1.8 && planned.scaled(0.1).spacing == 0.6
      && planned.scaled(Double.infinity).spacing == 1)
check("L1 at 1 the plan is exactly as before", GraphUniverse.plan(fixedVault()).bodies
      == GraphUniverse.plan(fixedVault().scaled(1)).bodies)

// MARK: helpers

/// Sizes by id: a body's size must not change with the link length.
func sizes(_ bodies: [(UUID, Float)]) -> [UUID: Float] {
    var out: [UUID: Float] = [:]
    for (id, s) in bodies { out[id] = s }
    return out
}

/// Mean distance at rest between the two ends of the links drawn.
func meanLink(_ homes: [SIMD3<Float>], _ pairs: [(Int, Int)]) -> Double {
    guard !pairs.isEmpty else { return 0 }
    var sum: Double = 0
    for (a, b) in pairs { sum += Double(distance(homes[a], homes[b])) }
    return sum / Double(pairs.count)
}

/// Whether a list grows (never falls by more than `slack`), and grows
/// overall from first to last.
func grows(_ list: [Double], slack: Double = 1e-6) -> Bool {
    guard let first = list.first, let last = list.last else { return true }
    for (x, y) in zip(list, list.dropFirst()) where y < x - slack { return false }
    return last > first * 1.3
}

// MARK: U the Universe

func uKeepOut(_ body: UniverseBody, grow: Float) -> Float {
    if body.role == .galaxy && !body.empty { return body.sphere * 2.5 }
    let isNote: Bool = body.count == 0 && body.role != .galaxy && body.role != .star && body.role != .home
    return isNote ? body.sphere * grow : body.sphere
}

func uOverlaps(_ plan: UniversePlan, grow: Float, step: Double) -> [String] {
    var bad: [String] = []
    let kept: [Int] = plan.bodies.indices.filter { plan.bodies[$0].role != .comet && plan.bodies[$0].role != .oort }
    var t: Double = 0
    while t <= 600 {
        let at: [SIMD3<Float>] = kept.map { GraphUniverse.position(of: $0, in: plan, time: t) }
        for x in kept.indices {
            for y in (x + 1)..<kept.count {
                let a: UniverseBody = plan.bodies[kept[x]]
                let b: UniverseBody = plan.bodies[kept[y]]
                let family: Bool = a.parent == kept[y] || b.parent == kept[x]
                if family && (a.ringed || b.ringed) { continue }
                let limit: Float = uKeepOut(a, grow: grow) + uKeepOut(b, grow: grow)
                if distance(at[x], at[y]) < limit - 1e-4 && bad.count < 3 {
                    bad.append("\(a.title)/\(b.title) t=\(t)")
                }
            }
        }
        t += step
    }
    return bad
}

func uLadder(_ plan: UniversePlan) -> [String] {
    var bad: [String] = []
    var lowest: [UniverseRole: Float] = [:]
    var highest: [UniverseRole: Float] = [:]
    for body in plan.bodies {
        var role: UniverseRole = body.role
        if role == .home { role = .star }
        if role == .oort || role == .comet { continue }
        lowest[role] = min(lowest[role] ?? 9, body.sphere)
        highest[role] = max(highest[role] ?? 0, body.sphere)
        guard body.parent >= 0 else { continue }
        if body.sphere >= plan.bodies[body.parent].sphere { bad.append("\(body.title) not smaller than its holder") }
    }
    let ladder: [UniverseRole] = [.galaxy, .star, .gasGiant, .rocky, .moon, .pulsar]
    for pair in zip(ladder, ladder.dropFirst()) {
        guard let small = lowest[pair.0], let big = highest[pair.1] else { continue }
        if small <= big { bad.append("\(pair.0) <= \(pair.1)") }
    }
    return bad
}

/// Every body inside the envelope's box at any time. `slack`, a share of
/// the box: the envelope samples each system's circles at 8 points, and a
/// planet on a tilted orbit can pass a few percent outside that octagon's
/// box (as at the standard length; CosmicHierarchyTests checks the preview
/// and one big vault exactly).
func uEnvelope(_ plan: UniversePlan, slack: Float = 0) -> [String] {
    guard let first = plan.envelope.first else { return [] }
    var lo: SIMD3<Float> = first
    var hi: SIMD3<Float> = first
    for p in plan.envelope {
        lo = pointwiseMin(lo, p)
        hi = pointwiseMax(hi, p)
    }
    let span: Float = (hi - lo).max() * slack
    var bad: [String] = []
    var t: Double = 0
    while t <= 600 {
        for (i, body) in plan.bodies.enumerated() {
            let p: SIMD3<Float> = GraphUniverse.position(of: i, in: plan, time: t)
            let r: Float = body.sphere + 0.001 + span
            if !(all(p .>= lo - r) && all(p .<= hi + r)) && bad.count < 3 { bad.append("\(body.title) t=\(t)") }
        }
        t += 20
    }
    return bad
}

/// Each folder's own orbits hold its planets; a moon stays on its planet.
func uContainment(_ plan: UniversePlan) -> [String] {
    var bad: [String] = []
    for (i, body) in plan.bodies.enumerated() where body.shell >= 0 {
        let shell: UniverseShell = plan.shells[body.shell]
        if shell.owner != body.parent { bad.append("\(body.title) off its star's orbit") }
        let p: SIMD3<Float> = GraphUniverse.position(of: i, in: plan, time: 77)
        let o: SIMD3<Float> = GraphUniverse.position(of: body.parent, in: plan, time: 77)
        if abs(distance(p, o) - shell.radius) > 1e-3 { bad.append("\(body.title) not on its ring") }
    }
    for body in plan.bodies where body.role == .moon {
        if plan.bodies[body.parent].count != 0 { bad.append("\(body.title) not round a planet") }
    }
    return bad
}

func uDrawn(_ plan: UniversePlan) -> [(Int, Int)] {
    plan.links.filter { $0.kind != 3 }.map { ($0.a, $0.b) }
}

var uPairBad: Int = 0
var uPairs: Int = 0

/// From the standard length up, every drawn link grows by exactly the
/// setting (the plan scaled); below it, most shrink and none by much more
/// than the setting.
func exactAbove(_ ends: [[Double]]) -> Bool {
    guard ends.count == scales.count, let standard = scales.firstIndex(of: 1) else { return false }
    let at1: [Double] = ends[standard]
    for (k, s) in scales.enumerated() where s > 1 {
        for (x, y) in zip(at1, ends[k]) {
            uPairs += 1
            if abs(y - x * s) > 1e-3 * max(1, x) { uPairBad += 1 }
        }
    }
    return true
}


var uBad: [String] = []
var uGrowBad: [String] = []
var uSizeBad: [String] = []
for (v, vault) in vaults.enumerated() {
    var means: [Double] = []
    var base: [UUID: Float] = [:]
    var ends: [[Double]] = []
    for s in scales {
        let plan: UniversePlan = GraphUniverse.plan(vault.scaled(s))
        let again: UniversePlan = GraphUniverse.plan(vault.scaled(s))
        if again.bodies != plan.bodies || again.shells != plan.shells { uBad.append("vault \(v) at \(s): not deterministic") }
        let deep: Bool = v < 6 || s == 0.6 || s == 1.8
        let step: Double = v == 0 ? 10 : 40
        var problems: [String] = uLadder(plan) + uContainment(plan)
        if deep {
            problems += uOverlaps(plan, grow: 1, step: step) + uOverlaps(plan, grow: 1.5, step: step * 2)
            problems += uEnvelope(plan, slack: v == 0 ? 0 : 0.06)
        }
        if !problems.isEmpty && uBad.count < 4 { uBad.append("vault \(v) at \(s): \(problems.prefix(2))") }
        let own: [UUID: Float] = sizes(plan.bodies.map { ($0.id, $0.sphere) })
        if base.isEmpty { base = own } else if own != base && uSizeBad.count < 3 { uSizeBad.append("vault \(v) at \(s)") }
        let homes: [SIMD3<Float>] = plan.bodies.map(\.home)
        let pairs: [(Int, Int)] = uDrawn(plan)
        means.append(meanLink(homes, pairs))
        ends.append(pairs.map { Double(distance(homes[$0.0], homes[$0.1])) })
    }
    _ = exactAbove(ends)
    if !means.allSatisfy({ $0 == 0 }) && !grows(means) && uGrowBad.count < 3 {
        uGrowBad.append("vault \(v) mean: \(means.map { String(format: "%.2f", $0) })")
    }
}

check("U at 0.6, 0.8, 1, 1.4 and 1.8: ladder, containment, no overlaps (also x1.5), envelope, determinism",
      uBad.isEmpty, "\(uBad)")
check("U body sizes never change with the link length", uSizeBad.isEmpty, "\(uSizeBad)")
check("U linked bodies stand further apart as it grows", uGrowBad.isEmpty, "\(uGrowBad)")
check("U above 1 every drawn link is exactly the setting times as long", uPairBad == 0 && uPairs > 100,
      "\(uPairBad) of \(uPairs)")
let uShort: UniversePlan = GraphUniverse.plan(fixedVault().scaled(0.6))
let uStandard: UniversePlan = GraphUniverse.plan(fixedVault())
let uLong: UniversePlan = GraphUniverse.plan(fixedVault().scaled(1.8))
let orbitsShort: Float = uShort.shells.map(\.radius).reduce(0, +)
let orbitsStandard: Float = uStandard.shells.map(\.radius).reduce(0, +)
let orbitsLong: Float = uLong.shells.map(\.radius).reduce(0, +)
check("U orbits tighten and widen", orbitsShort < orbitsStandard && orbitsLong > orbitsStandard * 1.79,
      "\(orbitsShort) \(orbitsStandard) \(orbitsLong)")
func galaxySpread(_ plan: UniversePlan) -> Float {
    let cores: [SIMD3<Float>] = plan.bodies.filter { $0.role == .galaxy }.map(\.home)
    guard cores.count == 2 else { return 0 }
    return distance(cores[0], cores[1])
}
check("U galaxies stand closer and further apart", galaxySpread(uShort) < galaxySpread(uStandard)
      && galaxySpread(uLong) > galaxySpread(uStandard) * 1.79,
      "\(galaxySpread(uShort)) \(galaxySpread(uStandard)) \(galaxySpread(uLong))")
check("U the summary and the roles do not change", uShort.summary == uStandard.summary
      && uLong.summary == uStandard.summary && uLong.bodies.map(\.role) == uStandard.bodies.map(\.role))

// MARK: N the Neurons

func nRole(_ body: ThemeBody) -> NeuronRole {
    NeuronRole(rawValue: body.role) ?? .granule
}

/// Where a body floats round (from what holds it), before its wobble.
func nBase(_ body: ThemeBody) -> SIMD3<Float> {
    if case let .drift(base, _, _, _) = body.orbit { return base }
    return body.home
}

/// How far a body wobbles.
func nAmp(_ body: ThemeBody) -> Float {
    if case let .drift(_, amp, _, _) = body.orbit { return amp }
    return 0
}

/// How far an outer body reaches, wobble and all: a cell's or a
/// receptor's processes, a little round a drifting free cell.
func nReach(_ body: ThemeBody) -> Float {
    let share: Float = nRole(body) == .drifter ? 1.15 : Float(GraphNeurons.reach)
    return body.sphere * share + nAmp(body) * Float(GraphNeurons.wobbleBound)
}

/// Whether body x holds body y, at any depth.
func nHolds(_ plan: ThemePlan, _ x: Int, _ y: Int) -> Bool {
    var at: Int = plan.bodies[y].parent
    var steps: Int = 0
    while at >= 0 && steps <= plan.bodies.count {
        if at == x { return true }
        at = plan.bodies[at].parent
        steps += 1
    }
    return false
}

func nProblems(_ plan: ThemePlan, scale: Double, drift: Bool) -> [String] {
    var bad: [String] = []
    let n: Int = plan.bodies.count
    guard plan.systems.count == n else { return ["\(plan.systems.count) fly-ins for \(n) bodies"] }
    // what reaches out from the outer bodies keeps clear at rest (two
    // cells' from 0.8 up: shorter still, neighbours' processes brush)
    let outer: [Int] = (0..<n).filter { plan.bodies[$0].parent < 0 }
    for (k, x) in outer.enumerated() {
        for y in outer[(k + 1)...] {
            let a: ThemeBody = plan.bodies[x]
            let b: ThemeBody = plan.bodies[y]
            if scale < 0.8 && nRole(a).isContainer && nRole(b).isContainer { continue }
            if distance(nBase(a), nBase(b)) < nReach(a) + nReach(b) - 1e-4 && bad.count < 3 {
                bad.append("reach \(a.title)/\(b.title)")
            }
        }
    }
    // each after what holds it, smaller than the room inside it, and
    // inside that room with its wobble
    for (i, b) in plan.bodies.enumerated() where b.parent >= 0 {
        guard b.parent < i else {
            bad.append("\(b.title) before its holder")
            continue
        }
        let up: ThemeBody = plan.bodies[b.parent]
        let room: Float = up.sphere * Float(GraphNeurons.inner)
        if !nRole(up).isContainer { bad.append("\(b.title) held by a note") }
        if b.sphere >= room && bad.count < 5 { bad.append("\(b.title) too big for \(up.title)") }
        let out: Float = distance(nBase(b), .zero) + b.sphere + nAmp(b) * Float(GraphNeurons.wobbleBound)
        if out > room + 1e-4 && bad.count < 5 { bad.append("\(b.title) outside \(up.title)") }
    }
    // solid bodies never meet as they drift, unless one holds the other
    if drift {
        var family = Set<Int>()
        for y in 0..<n {
            var at: Int = plan.bodies[y].parent
            var steps: Int = 0
            while at >= 0 && steps <= n {
                family.insert(at * n + y)
                at = plan.bodies[at].parent
                steps += 1
            }
        }
        for t in stride(from: 0.0, through: 60.0, by: 6.0) {
            let at: [SIMD3<Float>] = (0..<n).map { plan.position(of: $0, time: t) }
            for x in 0..<n {
                for y in (x + 1)..<n where !family.contains(x * n + y) {
                    if distance(at[x], at[y]) < plan.bodies[x].sphere + plan.bodies[y].sphere && bad.count < 3 {
                        bad.append("meet \(plan.bodies[x].title)/\(plan.bodies[y].title) at \(t)")
                    }
                }
            }
        }
    }
    // processes join two shown bodies, neither holding the other, near
    // when they share a cell, dyed and as thick as planned
    for link in plan.links {
        guard link.a >= 0, link.a < n, link.b >= 0, link.b < n, link.a != link.b else {
            bad.append("process \(link.a)>\(link.b) out of range")
            continue
        }
        let a: ThemeBody = plan.bodies[link.a]
        let b: ThemeBody = plan.bodies[link.b]
        let near: Bool = a.region >= 0 && a.region == b.region
        if link.kind != (near ? 5 : 6) && bad.count < 5 { bad.append("process \(a.title)>\(b.title) kind \(link.kind)") }
        if nHolds(plan, link.a, link.b) || nHolds(plan, link.b, link.a) {
            bad.append("process \(a.title)>\(b.title) into itself")
        }
        if !(0...2).contains(link.tag) || !(link.width >= 0.67 - 1e-4 && link.width <= 1.75 + 1e-4) {
            if bad.count < 5 { bad.append("process \(a.title)>\(b.title) dye \(link.tag) width \(link.width)") }
        }
    }
    // the envelope holds everything
    var low = SIMD3<Float>(repeating: 1e9)
    var high = SIMD3<Float>(repeating: -1e9)
    for p in plan.envelope {
        low = pointwiseMin(low, p)
        high = pointwiseMax(high, p)
    }
    for (i, b) in plan.bodies.enumerated() {
        let p: SIMD3<Float> = plan.position(of: i, time: 30)
        let r: Float = b.sphere
        if !(all(p - r .>= low) && all(p + r .<= high)) && bad.count < 5 { bad.append("\(b.title) outside") }
    }
    // a container's fly-in holds it
    for (i, b) in plan.bodies.enumerated() where nRole(b).isContainer && plan.systems[i].isEmpty {
        bad.append("\(b.title) has no fly-in")
    }
    return bad
}

/// The same vault with every folder opened.
func nOpen(_ input: UniverseInput) -> UniverseInput {
    var copy: UniverseInput = input
    copy.open = input.folders.map(\.id)
    return copy
}

/// The mean rest length of the processes between cells on the sheet.
func sheetLinks(_ plan: ThemePlan) -> Double {
    var sum: Double = 0
    var count: Int = 0
    for link in plan.links {
        let a: ThemeBody = plan.bodies[link.a]
        let b: ThemeBody = plan.bodies[link.b]
        guard a.parent < 0, b.parent < 0, nRole(a).isContainer, nRole(b).isContainer else { continue }
        sum += Double(distance(nBase(a), nBase(b)))
        count += 1
    }
    return count == 0 ? 0 : sum / Double(count)
}

/// How the sheet's pitch grows with the length: the gap between cells
/// (GraphNeurons.sheetGap of the biggest at 1) scales, the cells
/// themselves do not.
func pitchRatio(_ s: Double) -> Double {
    (2 + GraphNeurons.sheetGap * s) / (2 + GraphNeurons.sheetGap)
}

var nBad: [String] = []
var nSameBad: [String] = []
var nSizeBad: [String] = []
var nInsideBad: [String] = []
var nSheetBad: [String] = []
var nSheetSeen: Int = 0
var nGrowBad: [String] = []
var nGrowSeen: Int = 0
for (v, vault) in vaults.enumerated() {
    // where each cell on the sheet floats at the standard length
    var one: [UUID: SIMD3<Float>] = [:]
    for body in GraphNeurons.plan(vault).bodies where body.parent < 0 && nRole(body).isContainer {
        one[body.id] = nBase(body)
    }
    var means: [Double] = []
    for opened in [false, true] {
        let input: UniverseInput = opened ? nOpen(vault) : vault
        var first: ThemePlan? = nil
        for s in scales {
            let plan: ThemePlan = GraphNeurons.plan(input.scaled(s))
            let again: ThemePlan = GraphNeurons.plan(input.scaled(s))
            let way: String = "vault \(v) \(opened ? "opened" : "closed") at \(s)"
            if again.bodies != plan.bodies || again.links != plan.links || again.envelope != plan.envelope {
                nBad.append("\(way): not deterministic")
            }
            let problems: [String] = nProblems(plan, scale: s, drift: v < 8 || s == 0.6 || s == 1.8)
            if !problems.isEmpty && nBad.count < 4 { nBad.append("\(way): \(problems.prefix(2))") }
            if !opened { means.append(sheetLinks(plan)) }
            let ratio = Float(pitchRatio(s))
            for body in plan.bodies where body.parent < 0 {
                guard let was = one[body.id] else { continue }
                let want = SIMD3<Float>(was.x * ratio, was.y * ratio, was.z)
                nSheetSeen += 1
                if distance(nBase(body), want) > 1e-4 * max(1, distance(was, .zero)) && nSheetBad.count < 3 {
                    nSheetBad.append("\(way): \(body.title)")
                }
            }
            guard let ref = first else {
                first = plan
                continue
            }
            if plan.bodies.map(\.id) != ref.bodies.map(\.id) || plan.bodies.map(\.role) != ref.bodies.map(\.role)
                || plan.bodies.map(\.parent) != ref.bodies.map(\.parent) || plan.links != ref.links
                || plan.summary != ref.summary {
                if nSameBad.count < 3 { nSameBad.append(way) }
                continue
            }
            for (body, was) in zip(plan.bodies, ref.bodies) {
                if body.sphere != was.sphere && nSizeBad.count < 3 { nSizeBad.append("\(way): \(body.title)") }
                if body.parent >= 0 && body.orbit != was.orbit && nInsideBad.count < 3 {
                    nInsideBad.append("\(way): \(body.title)")
                }
            }
        }
    }
    guard !means.allSatisfy({ $0 == 0 }) else { continue }
    nGrowSeen += 1
    if !grows(means) && nGrowBad.count < 3 { nGrowBad.append("vault \(v): \(means)") }
}
check("N at 0.6 to 1.8, closed and opened: reach clear, nothing meets, the ladder, insides held, processes, "
      + "envelope, determinism", nBad.isEmpty, "\(nBad)")
check("N the same bodies, roles and processes at every length", nSameBad.isEmpty, "\(nSameBad)")
check("N no body changes size", nSizeBad.isEmpty, "\(nSizeBad)")
check("N inside a cell nothing moves with it", nInsideBad.isEmpty, "\(nInsideBad)")
check("N the sheet grows exactly with the gap between cells, its depth kept", nSheetBad.isEmpty && nSheetSeen > 100,
      "\(nSheetBad) of \(nSheetSeen)")
check("N linked cells stand further apart as it grows", nGrowBad.isEmpty && nGrowSeen >= 5,
      "\(nGrowBad) of \(nGrowSeen)")
let nShort: Double = sheetLinks(GraphNeurons.plan(fixedVault().scaled(0.6)))
let nStandard: Double = sheetLinks(GraphNeurons.plan(fixedVault()))
let nLong: Double = sheetLinks(GraphNeurons.plan(fixedVault().scaled(1.8)))
check("N processes between cells shorten and lengthen", nStandard > 0 && nShort < nStandard
      && nLong > nStandard * 1.2, "\(nShort) \(nStandard) \(nLong)")

print(failures.isEmpty ? "all passed" : "\(failures.count) failed")
exit(failures.isEmpty ? 0 : 1)
