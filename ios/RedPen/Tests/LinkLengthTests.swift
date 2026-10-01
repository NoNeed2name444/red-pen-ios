// The owner's "Link length" (GraphLinkLength, UniverseInput.linkScale): the
// links in the Ideas map longer or shorter, in all three themes, planned
// inside the pure planners so it is checked here.
//
// At the shortest (0.6), the standard (1) and the longest (1.8) every
// planner keeps its guarantees - no overlaps, the size ladder, containers
// holding their contents, determinism, the envelope holding everything,
// the Circuit's closed loops and footprints - linked bodies stand further
// apart as the setting grows, and no body changes size.
//
// Compiled with GraphUniverse.swift, GraphThemePlan.swift, GraphNeurons.swift,
// GraphCircuit.swift and GraphicsQuality.swift (Foundation only).
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
    NeuronRole(rawValue: body.role) ?? .interneuron
}

func nFamily(_ plan: ThemePlan, _ i: Int, _ j: Int) -> Bool {
    let a: ThemeBody = plan.bodies[i]
    let b: ThemeBody = plan.bodies[j]
    let ga: Bool = nRole(a) == .glia
    let gb: Bool = nRole(b) == .glia
    if ga && a.parent == j { return true }
    if gb && b.parent == i { return true }
    return ga && gb && a.parent == b.parent
}

func nProblems(_ plan: ThemePlan, drift: Bool) -> [String] {
    var bad: [String] = []
    let n: Int = plan.bodies.count
    // dendrites clear at rest
    for x in 0..<n {
        for y in (x + 1)..<n where !nFamily(plan, x, y) {
            let a: ThemeBody = plan.bodies[x]
            let b: ThemeBody = plan.bodies[y]
            let limit: Float = a.sphere * Float(nRole(a).reach) + b.sphere * Float(nRole(b).reach)
            if distance(a.home, b.home) < limit - 1e-4 && bad.count < 3 { bad.append("reach \(a.title)/\(b.title)") }
        }
    }
    // solid cells never meet as they drift
    if drift {
        for t in stride(from: 0.0, through: 60.0, by: 6.0) {
            let at: [SIMD3<Float>] = (0..<n).map { plan.position(of: $0, time: t) }
            for x in 0..<n {
                for y in (x + 1)..<n where distance(at[x], at[y]) < plan.bodies[x].sphere + plan.bodies[y].sphere {
                    if bad.count < 3 { bad.append("meet \(plan.bodies[x].title)/\(plan.bodies[y].title)") }
                }
            }
        }
    }
    // the ladder, and relays smaller than what holds them
    let containers: [Float] = plan.bodies.filter { nRole($0).isContainer }.map(\.sphere)
    let notes: [Float] = plan.bodies.filter { !nRole($0).isContainer }.map(\.sphere)
    if let c = containers.min(), let m = notes.max(), c <= m { bad.append("container \(c) <= note \(m)") }
    for (i, b) in plan.bodies.enumerated() {
        if b.parent >= i { bad.append("\(b.title) before its parent") }
        if nRole(b) == .relay && b.sphere >= plan.bodies[b.parent].sphere { bad.append("relay \(b.title) too big") }
        if nRole(b) == .relay && (b.home - plan.bodies[b.parent].home).sum() == 0 { bad.append("relay on its parent") }
    }
    // the pathway runs outward
    for b in plan.bodies where nRole(b) == .relay {
        let up: ThemeBody = plan.bodies[b.parent]
        if ((b.home - up.home) * up.axis).sum() <= 0 { bad.append("\(b.title) inward") }
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
    // a container's fly-in holds its cells
    for (i, b) in plan.bodies.enumerated() where nRole(b).isContainer && plan.systems[i].isEmpty {
        bad.append("\(b.title) has no system")
    }
    return bad
}

func drawnPairs(_ plan: ThemePlan) -> [(Int, Int)] {
    plan.links.filter { $0.kind != 3 }.map { ($0.a, $0.b) }
}

var nBad: [String] = []
var nGrowBad: [String] = []
var nSizeBad: [String] = []
var nExact: Int = 0
var nExactBad: Int = 0
for (v, vault) in vaults.enumerated() {
    var means: [Double] = []
    var base: [UUID: Float] = [:]
    var at1: [Double] = []
    for s in scales {
        let plan: ThemePlan = GraphNeurons.plan(vault.scaled(s))
        let again: ThemePlan = GraphNeurons.plan(vault.scaled(s))
        if again.bodies != plan.bodies || again.links != plan.links { nBad.append("vault \(v) at \(s): not deterministic") }
        let problems: [String] = nProblems(plan, drift: v < 8 || s == 0.6 || s == 1.8)
        if !problems.isEmpty && nBad.count < 4 { nBad.append("vault \(v) at \(s): \(problems.prefix(2))") }
        let own: [UUID: Float] = sizes(plan.bodies.map { ($0.id, $0.sphere) })
        if base.isEmpty { base = own } else if own != base && nSizeBad.count < 3 { nSizeBad.append("vault \(v) at \(s)") }
        let homes: [SIMD3<Float>] = plan.bodies.map(\.home)
        let pairs: [(Int, Int)] = drawnPairs(plan)
        means.append(meanLink(homes, pairs))
        let ends: [Double] = pairs.map { Double(distance(homes[$0.0], homes[$0.1])) }
        if s == 1 { at1 = ends }
        if s > 1 {
            for (x, y) in zip(at1, ends) {
                nExact += 1
                if abs(y - x * s) > 1e-3 * max(1, x) { nExactBad += 1 }
            }
        }
    }
    let nonzero: Bool = !means.allSatisfy { $0 == 0 }
    if nonzero && !grows(means) && nGrowBad.count < 3 { nGrowBad.append("vault \(v): \(means)") }
}
check("N at 0.6 to 1.8: dendrites clear, cells never meet, ladder, pathways outward, envelope, determinism",
      nBad.isEmpty, "\(nBad)")
check("N cell sizes never change", nSizeBad.isEmpty, "\(nSizeBad)")
check("N linked cells stand further apart as it grows", nGrowBad.isEmpty, "\(nGrowBad)")
check("N above 1 every drawn axon is exactly the setting times as long", nExactBad == 0 && nExact > 100,
      "\(nExactBad) of \(nExact)")
let nShort: ThemePlan = GraphNeurons.plan(fixedVault().scaled(0.6))
let nStandard: ThemePlan = GraphNeurons.plan(fixedVault())
let nLong: ThemePlan = GraphNeurons.plan(fixedVault().scaled(1.8))
func pathway(_ plan: ThemePlan) -> Double {
    meanLink(plan.bodies.map(\.home), plan.links.filter { $0.kind == 4 }.map { ($0.a, $0.b) })
}
check("N pathways shorten and lengthen", pathway(nShort) <= pathway(nStandard)
      && pathway(nLong) > pathway(nStandard) * 1.79, "\(pathway(nShort)) \(pathway(nStandard)) \(pathway(nLong))")

// MARK: C the Circuit

func cRole(_ body: ThemeBody) -> CircuitRole {
    CircuitRole(rawValue: body.role) ?? .led
}

let bRight: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.right)
let bForward: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.forward)
let bNormal: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.normal)

func onBoard(_ p: SIMD3<Float>) -> SIMD2<Double> {
    SIMD2<Double>(Double((p * bRight).sum()), Double((p * bForward).sum()))
}

func footprint(_ body: ThemeBody) -> CircuitRect {
    CircuitRect(c: onBoard(body.home), h: cRole(body).foot * Double(body.sphere))
}

func boardOf(_ plan: ThemePlan, _ i: Int) -> CircuitRect {
    let p: SIMD4<Float> = plan.patches[i]
    let at: SIMD2<Double> = onBoard(plan.bodies[i].home)
    return CircuitRect(c: at + SIMD2<Double>(Double(p.x), Double(p.y)), h: SIMD2<Double>(Double(p.z), Double(p.w)))
}

func topOf(_ plan: ThemePlan, _ i: Int) -> Int {
    var at: Int = i
    var steps: Int = 0
    while plan.bodies[at].parent >= 0 && steps < plan.bodies.count {
        at = plan.bodies[at].parent
        steps += 1
    }
    return at
}

func reach(_ next: [[Int]], from starts: [Int]) -> Set<Int> {
    var seen = Set<Int>(starts)
    var queue: [Int] = starts
    var head: Int = 0
    while head < queue.count {
        let x: Int = queue[head]
        head += 1
        for y in next[x] where seen.insert(y).inserted { queue.append(y) }
    }
    return seen
}

func cProblems(_ plan: ThemePlan) -> [String] {
    var bad: [String] = []
    // closed loops: every part reached from a power tap and reaching ground
    var next = [[Int]](repeating: [], count: plan.bodies.count)
    for l in plan.links {
        if l.kind == 5 || l.kind == 6 {
            next[l.a].append(l.b)
        } else if l.kind == 0 {
            let ra: Int = plan.bodies[l.a].rank
            let rb: Int = plan.bodies[l.b].rank
            if ra > rb { next[l.a].append(l.b) } else if rb > ra { next[l.b].append(l.a) }
        }
    }
    var back = [[Int]](repeating: [], count: next.count)
    for (a, list) in next.enumerated() { for b in list { back[b].append(a) } }
    let vcc: [Int] = plan.bodies.indices.filter { cRole(plan.bodies[$0]) == .vcc }
    let gnd: [Int] = plan.bodies.indices.filter { cRole(plan.bodies[$0]) == .ground }
    let up: Set<Int> = reach(next, from: vcc)
    let down: Set<Int> = reach(back, from: gnd)
    for (i, b) in plan.bodies.enumerated() where b.kind != .fixture && !(up.contains(i) && down.contains(i)) {
        if bad.count < 3 { bad.append("\(b.title) open") }
    }
    // footprints never overlap
    let parts: [Int] = plan.bodies.indices.filter { plan.bodies[$0].kind != .fixture }
    let rects: [CircuitRect] = parts.map { footprint(plan.bodies[$0]) }
    for x in rects.indices {
        for y in (x + 1)..<rects.count where !rects[x].clears(rects[y], gap: 0.0001) {
            if bad.count < 5 { bad.append("overlap \(plan.bodies[parts[x]].title)/\(plan.bodies[parts[y]].title)") }
        }
    }
    // flat, still, each inside its own board; boards apart
    for (i, b) in plan.bodies.enumerated() {
        if abs((b.home * bNormal).sum()) > 1e-4 && bad.count < 5 { bad.append("\(b.title) lifted") }
        let board: CircuitRect = boardOf(plan, topOf(plan, i))
        let r: CircuitRect = footprint(b)
        let inside: Bool = r.low.x >= board.low.x - 1e-4 && r.low.y >= board.low.y - 1e-4
            && r.high.x <= board.high.x + 1e-4 && r.high.y <= board.high.y + 1e-4
        if !inside && bad.count < 5 { bad.append("\(b.title) off its board") }
    }
    let tops: [Int] = plan.regions
    for x in tops.indices {
        for y in (x + 1)..<tops.count where !boardOf(plan, tops[x]).clears(boardOf(plan, tops[y]), gap: 0.3) {
            if bad.count < 5 { bad.append("boards touch") }
        }
    }
    // sizes: chips over pages over ideas, a sub-chip under its chip
    for (i, b) in plan.bodies.enumerated() {
        if b.parent >= i { bad.append("\(b.title) before its parent") }
        if cRole(b) == .module && b.sphere >= plan.bodies[b.parent].sphere { bad.append("\(b.title) too big") }
    }
    let chips: [Float] = plan.bodies.filter { cRole($0).isContainer }.map(\.sphere)
    let pages: [Float] = plan.bodies.filter { cRole($0) == .capacitor }.map(\.sphere)
    let ideas: [Float] = plan.bodies.filter { cRole($0) == .led }.map(\.sphere)
    if let a = chips.min(), let b = pages.max(), a <= b { bad.append("chip <= page") }
    if let a = pages.min(), let b = ideas.max(), a <= b { bad.append("page <= idea") }
    // the envelope holds everything
    var low = SIMD3<Float>(repeating: 1e9)
    var high = SIMD3<Float>(repeating: -1e9)
    for p in plan.envelope {
        low = pointwiseMin(low, p)
        high = pointwiseMax(high, p)
    }
    for b in plan.bodies where !(all(b.home - b.sphere .>= low) && all(b.home + b.sphere .<= high)) {
        if bad.count < 6 { bad.append("\(b.title) outside the envelope") }
    }
    return bad
}

func boardArea(_ plan: ThemePlan) -> Double {
    var sum: Double = 0
    for t in plan.regions {
        let r: CircuitRect = boardOf(plan, t)
        sum += r.h.x * r.h.y * 4
    }
    return sum
}

var cBad: [String] = []
var cGrowBad: [String] = []
var cSizeBad: [String] = []
var cAreaBad: [String] = []
for (v, vault) in vaults.enumerated() {
    var means: [Double] = []
    var areas: [Double] = []
    var base: [UUID: Float] = [:]
    for s in scales {
        let plan: ThemePlan = GraphCircuit.plan(vault.scaled(s))
        let again: ThemePlan = GraphCircuit.plan(vault.scaled(s))
        if again.bodies != plan.bodies || again.links != plan.links || again.bars != plan.bars {
            cBad.append("vault \(v) at \(s): not deterministic")
        }
        let problems: [String] = cProblems(plan)
        if !problems.isEmpty && cBad.count < 4 { cBad.append("vault \(v) at \(s): \(problems.prefix(2))") }
        let own: [UUID: Float] = sizes(plan.bodies.filter { $0.kind != .fixture }.map { ($0.id, $0.sphere) })
        if base.isEmpty { base = own } else if own != base && cSizeBad.count < 3 { cSizeBad.append("vault \(v) at \(s)") }
        // the notes' own links, between two parts
        let pairs: [(Int, Int)] = plan.links.filter { l in
            (l.kind == 0 || l.kind == 3) && plan.bodies[l.a].kind == .note && plan.bodies[l.b].kind == .note
        }.map { ($0.a, $0.b) }
        means.append(meanLink(plan.bodies.map(\.home), pairs))
        areas.append(boardArea(plan))
    }
    let nonzero: Bool = !means.allSatisfy { $0 == 0 }
    if nonzero && !grows(means, slack: 0.02) && cGrowBad.count < 3 { cGrowBad.append("vault \(v): \(means)") }
    let bigger: Bool = zip(areas, areas.dropFirst()).allSatisfy { $0.1 > $0.0 }
    if !areas.allSatisfy({ $0 == 0 }) && !bigger && cAreaBad.count < 3 { cAreaBad.append("vault \(v): \(areas)") }
}
check("C at 0.6 to 1.8: closed loops, footprints clear, flat on their boards, boards apart, ladder, envelope, determinism",
      cBad.isEmpty, "\(cBad)")
check("C part sizes never change", cSizeBad.isEmpty, "\(cSizeBad)")
check("C linked parts stand further apart as it grows", cGrowBad.isEmpty, "\(cGrowBad)")
check("C boards grow with the setting", cAreaBad.isEmpty, "\(cAreaBad)")
let cShort: ThemePlan = GraphCircuit.plan(fixedVault().scaled(0.6))
let cLong: ThemePlan = GraphCircuit.plan(fixedVault().scaled(1.8))
let cStandard: ThemePlan = GraphCircuit.plan(fixedVault())
/// The parts (notes and chips), and which part feeds which: the circuit
/// itself, whatever wiring taps a longer or shorter board needs.
func circuitOf(_ plan: ThemePlan) -> [String] {
    var out: [String] = []
    for (i, b) in plan.bodies.enumerated() where b.kind != .fixture {
        var f: Int = plan.feeds[i]
        while f >= 0 && plan.bodies[f].kind == .fixture { f = plan.feeds[f] }
        let from: String = f >= 0 ? plan.bodies[f].id.uuidString : "rail"
        out.append(b.id.uuidString + "<" + from + "|" + String(b.role))
    }
    return out.sorted()
}
check("C the same circuit at every length", circuitOf(cShort) == circuitOf(cStandard)
      && circuitOf(cLong) == circuitOf(cStandard))

print(failures.isEmpty ? "all passed" : "\(failures.count) failed")
exit(failures.isEmpty ? 0 : 1)
