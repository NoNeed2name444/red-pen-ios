import Foundation

// The Circuit theme: the ideas' own hierarchy drawn as a printed circuit
// board, laid out the way a real board is - flat, square to its edges, parts
// clustered round the chip they serve, joined by routed copper.
//
// - the whole vault is the motherboard;
// - a top-level folder is a processor: a big chip package under a metal lid,
//   its name silkscreened on it, at the heart of its own zone of the board;
// - a folder inside a folder is a module: a smaller chip (a controller, a
//   regulator) on its own sub-board, placed on its parent's side of the
//   board - to the east, south, west or north of it - and always a little
//   smaller than the chip it hangs from;
// - a page is a capacitor, bigger the longer it is; a page of 250 words or
//   more is an inductor coil;
// - an idea is a resistor; an idea with two or more links an LED (it
//   lights up as current arrives); an idea whose links all run out of its
//   folder into one other folder a diode (current one way out);
// - a short idea linked only to the note it sits with is a small surface
//   mount part soldered beside that note;
// - an idea linking notes in two or more other folders is a bus header, a
//   row of pins the traces between modules run through;
// - a note in no folder sits on the board's edge: an edge-connector finger
//   when it has links (current comes in there), an unconnected pad on the
//   far edge when it has none;
// - with no folders at all, one system chip holds every note.
//
// Links are copper traces, routed square to the board's edges with 45°
// corners (GraphLinkRoute draws them, rounded): inside a zone thin signal
// traces, between zones and down each folder's pathway wider bus traces.
// Current runs from the sending end (the higher rank: processors and
// modules drive, edge fingers feed in, LEDs only ever receive).
//
// The same four rules as the other themes: what a part is = what the item
// is; size = how much is in it (every chip bigger than every part, a module
// always smaller than the chip it sits under, pages bigger than ideas, the
// small surface-mount parts smallest); position = which folder holds it;
// the pathway runs outward from each chip.
//
// Pure and deterministic: Foundation only, the same notes always give the
// same board, and no two parts' footprints overlap (each is placed in the
// first clear spot, spiralling out from its chip). Tested on Linux
// (Tests/CircuitHierarchyTests).

nonisolated enum CircuitRole: Int, Sendable, CaseIterable {
    /// A top-level folder: a processor under a metal lid.
    case processor = 0
    /// A folder inside a folder: a module's chip on its own sub-board.
    case module = 1
    /// The one container of a vault with no folders: a system chip.
    case soc = 2
    /// A page: an electrolytic capacitor.
    case capacitor = 3
    /// A page of 250 words or more: an inductor coil.
    case inductor = 4
    /// An idea: a resistor.
    case resistor = 5
    /// An idea with two or more links: an LED.
    case led = 6
    /// An idea whose links all run into one other folder: a diode.
    case diode = 7
    /// A short idea linked only to the note it sits beside.
    case smd = 8
    /// An idea linking notes in two or more other folders: a bus header.
    case header = 9
    /// A loose note with links: an edge-connector finger.
    case edgePin = 10
    /// A loose note with no links: an unconnected pad.
    case pad = 11

    /// Which end of a trace sends: chips drive, edge fingers feed in,
    /// passives pass it on, LEDs only receive.
    var rank: Int {
        switch self {
        case .processor, .soc: return 7
        case .module, .edgePin: return 6
        case .capacitor, .inductor: return 5
        case .header: return 4
        case .resistor, .diode: return 3
        case .smd: return 2
        case .led: return 1
        case .pad: return 0
        }
    }

    var isContainer: Bool {
        self == .processor || self == .module || self == .soc
    }

    /// Parts drawn along an axis (turned to point at their chip).
    var isOriented: Bool {
        self == .resistor || self == .diode || self == .header || self == .smd
    }

    /// Half its footprint, in sizes, lying along x: what must stay clear.
    var foot: SIMD2<Double> {
        switch self {
        case .processor, .module, .soc: return SIMD2<Double>(1.25, 1.25)
        case .capacitor: return SIMD2<Double>(0.95, 0.95)
        case .inductor: return SIMD2<Double>(1.12, 1.12)
        case .resistor: return SIMD2<Double>(1.72, 0.55)
        case .diode: return SIMD2<Double>(1.6, 0.52)
        case .led: return SIMD2<Double>(0.85, 0.85)
        case .smd: return SIMD2<Double>(1.05, 0.55)
        case .header: return SIMD2<Double>(2.1, 0.58)
        case .edgePin: return SIMD2<Double>(0.6, 1.4)
        case .pad: return SIMD2<Double>(0.9, 0.9)
        }
    }
}

/// A rectangle on the board, square to its edges: its centre and half its
/// size.
nonisolated struct CircuitRect: Sendable, Equatable {
    var c: SIMD2<Double>
    var h: SIMD2<Double>

    func moved(_ d: SIMD2<Double>) -> CircuitRect {
        CircuitRect(c: c + d, h: h)
    }

    func grown(_ by: Double) -> CircuitRect {
        CircuitRect(c: c, h: h + SIMD2<Double>(by, by))
    }

    /// Whether the two are at least `gap` apart along x or along y.
    func clears(_ o: CircuitRect, gap: Double) -> Bool {
        let dx: Double = abs(c.x - o.c.x)
        let dy: Double = abs(c.y - o.c.y)
        if dx >= h.x + o.h.x + gap { return true }
        return dy >= h.y + o.h.y + gap
    }

    var low: SIMD2<Double> { c - h }
    var high: SIMD2<Double> { c + h }

    static func around(low: SIMD2<Double>, high: SIMD2<Double>) -> CircuitRect {
        let half: SIMD2<Double> = (high - low) * 0.5
        return CircuitRect(c: low + half, h: half)
    }

    /// The smallest rectangle holding all of `rects`.
    static func bounding(_ rects: [CircuitRect]) -> CircuitRect {
        guard let first = rects.first else {
            return CircuitRect(c: SIMD2<Double>(0, 0), h: SIMD2<Double>(0, 0))
        }
        var lo: SIMD2<Double> = first.low
        var hi: SIMD2<Double> = first.high
        for r in rects {
            lo = SIMD2<Double>(min(lo.x, r.low.x), min(lo.y, r.low.y))
            hi = SIMD2<Double>(max(hi.x, r.high.x), max(hi.y, r.high.y))
        }
        return around(low: lo, high: hi)
    }
}

nonisolated enum GraphCircuit {
    /// Room left between two parts' footprints.
    static let gap: Double = 0.03
    /// How far a surface-mount part sits off its note.
    static let hug: Double = 0.012
    /// Room round a zone's parts, to its sub-board's edge.
    static let zoneMargin: Double = 0.07
    /// The motherboard's border beyond everything on it.
    static let border: Double = 0.3
    /// How far the board leans back from facing the camera (radians): a
    /// board on a desk, seen a little from above.
    static let tilt: Double = 0.30
    /// The board's aspect (width over height) the zones are packed towards:
    /// tall, like the phone held upright.
    static let aspect: Double = 0.62

    // MARK: the board's plane

    /// The board's x, y and up in the space: x across, y up the board
    /// (leaning back by `tilt`), up out of it towards the camera.
    static let right = SIMD3<Double>(1, 0, 0)
    static let forward = SIMD3<Double>(0, cos(tilt), -sin(tilt))
    static let normal = SIMD3<Double>(0, sin(tilt), cos(tilt))

    /// A point of the board (and a height above it) in the space.
    static func world(_ q: SIMD2<Double>, height: Double = 0) -> SIMD3<Double> {
        right * q.x + forward * q.y + normal * height
    }

    // MARK: sizes (the ladder)

    /// A page: 0.13 to 0.218 by length.
    static func pageSphere(words: Int) -> Double {
        let lv: Int = min(GraphUniverse.level(words: words), 8)
        return 0.13 + 0.011 * Double(lv)
    }

    /// An idea: 0.075 to 0.105 by length.
    static func ideaSphere(words: Int) -> Double {
        let lv: Int = min(GraphUniverse.level(words: words), 6)
        return 0.075 + 0.005 * Double(lv)
    }

    /// A bus header: just above the biggest idea, under any page.
    static let headerSphere: Double = 0.12

    /// A surface-mount part: 0.045 to 0.053.
    static func smdSphere(words: Int) -> Double {
        let lv: Int = min(GraphUniverse.level(words: words), 2)
        return 0.045 + 0.004 * Double(lv)
    }

    /// A processor: 0.40 to 0.54 by how many notes it holds.
    static func processorSphere(count: Int) -> Double {
        guard count > 0 else { return 0.40 }
        let size: Double = log2(1 + Double(count))
        return GraphUniverse.clamp(0.40 + 0.02 * size, 0.40, 0.54)
    }

    /// The smallest a module at depth `d` is drawn: 0.31, 0.28, 0.27, ...,
    /// always above the biggest page.
    static func moduleFloor(_ d: Int) -> Double {
        0.25 + 0.06 / Double(max(d, 1))
    }

    /// A module: by how many notes it holds, always a little smaller than
    /// the chip it sits under.
    static func moduleSphere(count: Int, depth: Int, parent: Double) -> Double {
        let size: Double = log2(1 + Double(count))
        let own: Double = GraphUniverse.clamp(0.29 + 0.012 * size, 0.29, 0.37)
        return max(min(own, parent * 0.9), moduleFloor(depth))
    }

    static let socSphere: Double = 0.44

    /// Links from which an idea is an LED.
    static let ledLinks: Int = 2

    /// Words from which a page is an inductor.
    static let inductorWords: Int = 250

    // MARK: planning

    static func plan(_ input: UniverseInput) -> ThemePlan {
        if input.notes.isEmpty && input.folders.isEmpty { return .empty }
        var planner = CircuitPlanner(input)
        return planner.run()
    }

    /// "2 processors, 3 modules, 4 capacitors, ...".
    static func summary(_ bodies: [ThemeBody]) -> String {
        var counts = [Int](repeating: 0, count: CircuitRole.allCases.count)
        for body in bodies where body.role >= 0 && body.role < counts.count { counts[body.role] += 1 }
        let words: [(CircuitRole, String, String)] = [
            (.processor, "processor", "processors"), (.soc, "system chip", "system chips"),
            (.module, "module", "modules"), (.capacitor, "capacitor", "capacitors"),
            (.inductor, "inductor", "inductors"), (.resistor, "resistor", "resistors"), (.led, "LED", "LEDs"),
            (.diode, "diode", "diodes"), (.smd, "surface-mount part", "surface-mount parts"),
            (.header, "bus header", "bus headers"), (.edgePin, "edge finger", "edge fingers"),
            (.pad, "pad", "pads")
        ]
        var parts: [String] = []
        for (role, one, many) in words {
            let n: Int = counts[role.rawValue]
            if n > 0 { parts.append("\(n) " + (n == 1 ? one : many)) }
        }
        return parts.joined(separator: ", ")
    }
}

/// One chip's own layout, in its own place (its chip at the origin): where
/// its parts sit and which way they lie, where each module inside it sits,
/// its own sub-board, and every rectangle its whole subtree keeps clear.
nonisolated struct CircuitLocal: Sendable {
    var members: [(Int, SIMD2<Double>, Bool)] = []
    var children: [(Int, SIMD2<Double>)] = []
    var patch = CircuitRect(c: SIMD2<Double>(0, 0), h: SIMD2<Double>(0, 0))
    var rects: [CircuitRect] = []
}

/// The plan's working state. Reuses the Universe planner's tree: folders
/// (a cycle cut, a missing parent made top level), each note's container,
/// counts and links.
nonisolated struct CircuitPlanner: Sendable {
    var tree: UniversePlanner
    var role: [CircuitRole] = []
    var sphere: [Double] = []
    var cSphere: [Double] = []
    var smdOf: [[Int]] = []
    var smdHost: [Int] = []
    var local: [CircuitLocal] = []
    // the output
    var bodies: [ThemeBody] = []
    var patches: [SIMD4<Float>] = []
    var noteBody: [Int] = []
    var cBody: [Int] = []
    var cPos: [SIMD2<Double>] = []
    var worldRects: [[CircuitRect]] = []
    var looseSpot: [SIMD2<Double>] = []
    var looseOrder: [Int] = []

    init(_ input: UniverseInput) {
        tree = UniversePlanner(input)
    }

    var noteCount: Int { tree.noteList.count }

    mutating func run() -> ThemePlan {
        tree.buildTree()
        tree.buildLinks()
        assignRoles()
        sizeParts()
        local = [CircuitLocal](repeating: CircuitLocal(), count: tree.cCount)
        let tops: [Int] = topOrder()
        for t in tops { layOut(t) }
        noteBody = [Int](repeating: -1, count: noteCount)
        cBody = [Int](repeating: -1, count: tree.cCount)
        cPos = [SIMD2<Double>](repeating: SIMD2<Double>(0, 0), count: tree.cCount)
        worldRects = [[CircuitRect]](repeating: [], count: tree.cCount)
        let placed: [CircuitRect] = placeTops(tops)
        let loose: [CircuitRect] = placeLoose(placed)
        return finish(tops, main: placed, loose: loose)
    }

    // MARK: roles

    mutating func assignRoles() {
        let n: Int = noteCount
        let homeC: Int = tree.homeC
        var found = [CircuitRole?](repeating: nil, count: n)
        // headers and diodes: ideas in a folder whose links leave it
        for i in 0..<n {
            let h: Int = tree.noteHome[i]
            if tree.noteList[i].isPage || h < 0 || h == homeC { continue }
            var others = Set<Int>()
            var inside: Int = 0
            for m in tree.nbr[i] {
                let o: Int = tree.noteHome[m]
                if o >= 0 && o != homeC && o != h {
                    others.insert(o)
                } else {
                    inside += 1
                }
            }
            if others.count >= 2 {
                found[i] = .header
            } else if others.count == 1 && inside == 0 {
                found[i] = .diode
            }
        }
        // surface-mount parts, shortest first: an idea under 60 words with
        // one link, to a note in the same container that is a page or has
        // other links
        smdOf = [[Int]](repeating: [], count: n)
        smdHost = [Int](repeating: -1, count: n)
        let byLength: [Int] = (0..<n).sorted { a, b in
            let wa: Int = tree.noteList[a].words
            let wb: Int = tree.noteList[b].words
            if wa != wb { return wa < wb }
            return tree.lessN(a, b)
        }
        for i in byLength {
            let h: Int = tree.noteHome[i]
            if found[i] != nil || tree.noteList[i].isPage || h < 0 { continue }
            if tree.nbr[i].count != 1 || tree.noteList[i].words >= 60 { continue }
            let p: Int = tree.nbr[i][0]
            if tree.noteHome[p] != h || found[p] == .header || found[p] == .smd { continue }
            let host: UniverseNote = tree.noteList[p]
            if !host.isPage && tree.nbr[p].count < 2 { continue }
            let cap: Int = host.isPage ? 4 : 2
            if smdOf[p].count >= cap { continue }
            smdOf[p].append(i)
            smdHost[i] = p
            found[i] = .smd
        }
        role = []
        role.reserveCapacity(n)
        for i in 0..<n {
            let note: UniverseNote = tree.noteList[i]
            if let r = found[i] {
                role.append(r)
            } else if tree.noteHome[i] < 0 {
                role.append(tree.nbr[i].isEmpty ? .pad : .edgePin)
            } else if note.isPage {
                role.append(note.words >= GraphCircuit.inductorWords ? .inductor : .capacitor)
            } else {
                role.append(tree.nbr[i].count >= GraphCircuit.ledLinks ? .led : .resistor)
            }
        }
    }

    // MARK: sizes

    mutating func sizeParts() {
        sphere = []
        sphere.reserveCapacity(noteCount)
        for i in 0..<noteCount {
            let note: UniverseNote = tree.noteList[i]
            switch role[i] {
            case .smd: sphere.append(GraphCircuit.smdSphere(words: note.words))
            case .header: sphere.append(GraphCircuit.headerSphere)
            default:
                let s: Double = note.isPage ? GraphCircuit.pageSphere(words: note.words)
                    : GraphCircuit.ideaSphere(words: note.words)
                sphere.append(s)
            }
        }
        cSphere = [Double](repeating: 0, count: tree.cCount)
        let order: [Int] = (0..<tree.cCount).sorted { a, b in
            tree.depth[a] != tree.depth[b] ? tree.depth[a] < tree.depth[b] : a < b
        }
        for c in order {
            if c == tree.homeC {
                cSphere[c] = GraphCircuit.socSphere
            } else if tree.parent[c] < 0 {
                cSphere[c] = GraphCircuit.processorSphere(count: tree.count[c])
            } else {
                let up: Double = cSphere[tree.parent[c]]
                cSphere[c] = GraphCircuit.moduleSphere(count: tree.count[c], depth: tree.depth[c], parent: up)
            }
        }
    }

    func cRole(_ c: Int) -> CircuitRole {
        if c == tree.homeC { return .soc }
        return tree.parent[c] < 0 ? .processor : .module
    }

    /// Half a part's own footprint, lying along x or (`vertical`) along y.
    func partFoot(_ i: Int, vertical: Bool) -> SIMD2<Double> {
        let f: SIMD2<Double> = role[i].foot * sphere[i]
        return vertical && role[i].isOriented ? SIMD2<Double>(f.y, f.x) : f
    }

    /// Where note `host`'s k-th surface-mount part sits, from its centre:
    /// in a row beside it, alternately above and below (left and right
    /// when it lies along y), each lying the same way as its note.
    func smdOffset(_ host: Int, _ k: Int, vertical: Bool) -> SIMD2<Double> {
        let list: [Int] = smdOf[host]
        let hostFoot: SIMD2<Double> = partFoot(host, vertical: false)
        let side: Double = k % 2 == 0 ? 1 : -1
        let row: Int = (list.count + (k % 2 == 0 ? 1 : 0)) / 2
        let index: Int = k / 2
        let g: Int = list[k]
        let own: SIMD2<Double> = CircuitRole.smd.foot * sphere[g]
        let pitch: Double = own.x * 2 + GraphCircuit.gap
        let along: Double = (Double(index) - Double(max(row, 1) - 1) * 0.5) * pitch
        let across: Double = side * (hostFoot.y + GraphCircuit.hug + own.y)
        return vertical ? SIMD2<Double>(across, along) : SIMD2<Double>(along, across)
    }

    /// Half the footprint of a note together with its surface-mount parts
    /// (the same both sides, to be safe).
    func groupFoot(_ i: Int, vertical: Bool) -> SIMD2<Double> {
        var f: SIMD2<Double> = partFoot(i, vertical: vertical)
        let list: [Int] = smdOf[i]
        for k in list.indices {
            let o: SIMD2<Double> = smdOffset(i, k, vertical: vertical)
            let own: SIMD2<Double> = partFoot(list[k], vertical: vertical)
            f.x = max(f.x, abs(o.x) + own.x)
            f.y = max(f.y, abs(o.y) + own.y)
        }
        return f
    }

    func cFoot(_ c: Int) -> SIMD2<Double> {
        cRole(c).foot * cSphere[c]
    }

    // MARK: layout, bottom up

    /// Tops by how much they hold (most first, in the middle), then name.
    func topOrder() -> [Int] {
        let tops: [Int] = (0..<tree.cCount).filter { tree.parent[$0] < 0 }
        return tops.sorted { a, b in
            if tree.count[a] != tree.count[b] { return tree.count[a] > tree.count[b] }
            return tree.lessC(a, b)
        }
    }

    /// Lays out chip `c` and everything under it, round its own origin.
    mutating func layOut(_ c: Int) {
        for k in tree.kids[c] { layOut(k) }
        let chip = CircuitRect(c: SIMD2<Double>(0, 0), h: cFoot(c))
        var placed: [CircuitRect] = [chip]
        var out = CircuitLocal()
        // its parts round it, biggest first, each in the first clear spot
        // spiralling out from the chip, lying towards it
        var members: [Int] = (0..<noteCount).filter { tree.noteHome[$0] == c && role[$0] != .smd }
        members.sort { a, b in
            let fa: SIMD2<Double> = groupFoot(a, vertical: false)
            let fb: SIMD2<Double> = groupFoot(b, vertical: false)
            let aa: Double = fa.x * fa.y
            let ab: Double = fb.x * fb.y
            if aa != ab { return aa > ab }
            return tree.lessN(a, b)
        }
        var ring: Int = 0
        for i in members {
            let spot: (SIMD2<Double>, Bool, Int) = findSpot(i, round: chip.h, placed: placed, from: ring)
            let f: SIMD2<Double> = groupFoot(i, vertical: spot.1)
            placed.append(CircuitRect(c: spot.0, h: f))
            out.members.append((i, spot.0, spot.1))
            ring = max(spot.2 - 3, 0)
        }
        // its own sub-board, under the chip and its parts
        let patch: CircuitRect = CircuitRect.bounding(placed).grown(GraphCircuit.zoneMargin)
        out.patch = patch
        var rects: [CircuitRect] = [patch]
        // the modules under it, out along the board's axes: east, south,
        // west, north, then the corners
        for (j, k) in tree.kids[c].enumerated() {
            let dir: SIMD2<Double> = Self.kidDirection(j)
            let group: [CircuitRect] = local[k].rects
            let s: Double = Self.slide(group, along: dir, step: 0.05, placed: rects, gap: GraphCircuit.gap * 2)
            let at: SIMD2<Double> = dir * s
            for r in group { rects.append(r.moved(at)) }
            out.children.append((k, at))
        }
        out.rects = rects
        local[c] = out
    }

    /// The first clear spot for part `i` round a chip of half size `round`:
    /// on square rings ever further out, each side's middle first, then
    /// out towards its corners, the four sides in turn. Returns the spot,
    /// whether it lies along y (on the chip's north or south side, pointing
    /// at it), and the ring.
    func findSpot(_ i: Int, round: SIMD2<Double>, placed: [CircuitRect],
                  from: Int) -> (SIMD2<Double>, Bool, Int) {
        let step: Double = 0.04
        let small: SIMD2<Double> = groupFoot(i, vertical: false)
        let least: Double = min(small.x, small.y)
        let first: Int = max(from, Int(((least + GraphCircuit.gap) / step).rounded(.down)))
        var k: Int = first
        while k < 4000 {
            let hx: Double = round.x + step * Double(k + 1)
            let hy: Double = round.y + step * Double(k + 1)
            let reach: Int = Int((max(hx, hy) / step).rounded(.down))
            for j in 0...(reach * 2) {
                let o: Double = Double((j + 1) / 2) * step * (j % 2 == 1 ? 1 : -1)
                for side in 0..<4 {
                    let vertical: Bool = side % 2 == 1
                    var at: SIMD2<Double>
                    switch side {
                    case 0: at = SIMD2<Double>(hx, o)
                    case 1: at = SIMD2<Double>(-o, -hy)
                    case 2: at = SIMD2<Double>(-hx, -o)
                    default: at = SIMD2<Double>(o, hy)
                    }
                    if vertical && abs(at.x) > hx { continue }
                    if !vertical && abs(at.y) > hy { continue }
                    let rect = CircuitRect(c: at, h: groupFoot(i, vertical: vertical))
                    if Self.fits([rect], placed: placed, gap: GraphCircuit.gap) { return (at, vertical, k) }
                }
            }
            k += 1
        }
        let far = SIMD2<Double>(round.x + step * Double(k + 1), 0)
        return (far, false, k)
    }

    /// The j-th module's way out from its chip: east, south, west, north,
    /// then the four corners, then round again.
    static func kidDirection(_ j: Int) -> SIMD2<Double> {
        let d: Double = 0.70710678118654752
        switch j % 8 {
        case 0: return SIMD2<Double>(1, 0)
        case 1: return SIMD2<Double>(0, -1)
        case 2: return SIMD2<Double>(-1, 0)
        case 3: return SIMD2<Double>(0, 1)
        case 4: return SIMD2<Double>(d, -d)
        case 5: return SIMD2<Double>(-d, -d)
        case 6: return SIMD2<Double>(-d, d)
        default: return SIMD2<Double>(d, d)
        }
    }

    /// Whether every rectangle of `group` is `gap` clear of every one in
    /// `placed` - checking the group's bounds first, so far groups cost
    /// almost nothing.
    static func fits(_ group: [CircuitRect], placed: [CircuitRect], gap: Double) -> Bool {
        let whole: CircuitRect = CircuitRect.bounding(group)
        for other in placed {
            if whole.clears(other, gap: gap) { continue }
            for r in group where !r.clears(other, gap: gap) { return false }
        }
        return true
    }

    /// How far along `dir` to move `group` so it clears `placed`: the
    /// first multiple of `step` that does.
    static func slide(_ group: [CircuitRect], along dir: SIMD2<Double>, step: Double, placed: [CircuitRect],
                      gap: Double, limit: Int = 20000) -> Double {
        var s: Double = 0
        var tries: Int = 0
        while tries < limit {
            let moved: [CircuitRect] = group.map { $0.moved(dir * s) }
            if fits(moved, placed: placed, gap: gap) { return s }
            s += step
            tries += 1
        }
        return s
    }

    // MARK: placing, top down

    /// The processors on the motherboard, most notes first: the first in
    /// the middle, each next slid out along whichever of the eight board
    /// directions keeps the board most compact (and tall, like the phone).
    mutating func placeTops(_ tops: [Int]) -> [CircuitRect] {
        var placed: [CircuitRect] = []
        for (k, t) in tops.enumerated() {
            let group: [CircuitRect] = local[t].rects
            var at = SIMD2<Double>(0, 0)
            if k > 0 {
                var best: Double = Double.greatestFiniteMagnitude
                for j in 0..<8 {
                    let dir: SIMD2<Double> = Self.kidDirection(j)
                    let s: Double = Self.slide(group, along: dir, step: 0.08, placed: placed,
                                               gap: GraphCircuit.gap * 4)
                    let shift: SIMD2<Double> = dir * s
                    var all: [CircuitRect] = placed
                    for r in group { all.append(r.moved(shift)) }
                    let box: CircuitRect = CircuitRect.bounding(all)
                    let wide: Double = box.h.x / GraphCircuit.aspect
                    let score: Double = max(wide, box.h.y) + 0.001 * s
                    if score < best - 1e-9 {
                        best = score
                        at = shift
                    }
                }
            }
            for r in group { placed.append(r.moved(at)) }
            place(t, at: at)
        }
        return placed
    }

    /// Where chip `c` and its subtree are on the board.
    mutating func place(_ c: Int, at origin: SIMD2<Double>) {
        cPos[c] = origin
        worldRects[c] = local[c].rects.map { $0.moved(origin) }
        for (k, at) in local[c].children { place(k, at: origin + at) }
    }

    /// Loose notes on the board's edges: edge fingers in a row along the
    /// bottom edge, each as near under the processor it links to most as
    /// it can be; pads along the top edge from the left.
    mutating func placeLoose(_ placed: [CircuitRect]) -> [CircuitRect] {
        let whole: CircuitRect = CircuitRect.bounding(placed).grown(GraphCircuit.border)
        var all: [CircuitRect] = placed
        var out: [CircuitRect] = []
        var loose: [Int] = (0..<noteCount).filter { tree.noteHome[$0] < 0 }
        loose.sort { a, b in
            if role[a] != role[b] { return role[a].rawValue < role[b].rawValue }
            return tree.lessN(a, b)
        }
        looseSpot = [SIMD2<Double>](repeating: SIMD2<Double>(0, 0), count: noteCount)
        let step: Double = 0.05
        for i in loose {
            let f: SIMD2<Double> = partFoot(i, vertical: false)
            let bottom: Bool = role[i] == .edgePin
            var want: Double = placed.isEmpty ? 0 : whole.low.x + f.x
            if bottom, let t = favouriteTop(i) { want = cPos[t].x }
            let y0: Double = bottom ? whole.low.y + f.y : whole.high.y - f.y
            let away: Double = bottom ? -1 : 1
            var spot = SIMD2<Double>(want, y0)
            var done: Bool = false
            var row: Int = 0
            while !done && row < 400 {
                let y: Double = y0 + away * Double(row) * (f.y * 2 + GraphCircuit.gap)
                let reach: Int = Int((whole.h.x * 2 / step).rounded(.up)) + 1
                for j in 0...(reach * 2) {
                    let o: Double = Double((j + 1) / 2) * step * (j % 2 == 1 ? 1 : -1)
                    let at = SIMD2<Double>(want + o, y)
                    let rect = CircuitRect(c: at, h: f)
                    if Self.fits([rect], placed: all, gap: GraphCircuit.gap * 2) {
                        spot = at
                        done = true
                        break
                    }
                }
                row += 1
            }
            let rect = CircuitRect(c: spot, h: f)
            all.append(rect)
            out.append(rect)
            looseSpot[i] = spot
        }
        looseOrder = loose
        return out
    }

    /// The processor holding most of a loose note's links (ties: by name).
    func favouriteTop(_ i: Int) -> Int? {
        var tally: [Int: Int] = [:]
        for m in tree.nbr[i] {
            let h: Int = tree.noteHome[m]
            if h >= 0 { tally[tree.top[h], default: 0] += 1 }
        }
        var best: Int?
        var most: Int = 0
        for t in tally.keys.sorted(by: { tree.lessC($0, $1) }) {
            let n: Int = tally[t] ?? 0
            if n > most {
                best = t
                most = n
            }
        }
        return best
    }

    // MARK: the bodies

    mutating func finish(_ tops: [Int], main: [CircuitRect], loose: [CircuitRect]) -> ThemePlan {
        bodies = []
        patches = []
        for t in tops { emitContainer(t) }
        for i in looseOrder { emitLoose(i) }
        var links: [ThemeLink] = []
        for (i, j) in tree.edgePairs {
            let a: Int = noteBody[i]
            let b: Int = noteBody[j]
            guard a >= 0, b >= 0 else { continue }
            let kind: Int = linkKind(i, j)
            let centre: Int = kind == 1 ? cBody[tree.top[tree.noteHome[i]]] : -1
            links.append(ThemeLink(a: a, b: b, kind: kind, centre: centre))
        }
        // every chip wired to the modules under it: its bus
        for c in 0..<tree.cCount where tree.parent[c] >= 0 {
            let up: Int = cBody[tree.parent[c]]
            let down: Int = cBody[c]
            if up >= 0 && down >= 0 { links.append(ThemeLink(a: up, b: down, kind: 4, centre: -1)) }
        }
        var systems = [[SIMD3<Float>]](repeating: [], count: bodies.count)
        for c in 0..<tree.cCount where cBody[c] >= 0 {
            let origin: SIMD3<Double> = GraphCircuit.world(cPos[c])
            systems[cBody[c]] = ThemeLayout.points(Self.balls(worldRects[c]), around: origin)
        }
        // the motherboard: everything, with a border, reaching down to the
        // edge fingers and up to the pads, which sit on its edges
        var board: CircuitRect = CircuitRect.bounding(main).grown(GraphCircuit.border)
        if main.isEmpty { board = CircuitRect.bounding(loose).grown(GraphCircuit.border) }
        if !loose.isEmpty {
            let edge: CircuitRect = CircuitRect.bounding(loose)
            let lo = SIMD2<Double>(min(board.low.x, edge.low.x), min(board.low.y, edge.low.y))
            let hi = SIMD2<Double>(max(board.high.x, edge.high.x), max(board.high.y, edge.high.y))
            board = CircuitRect.around(low: lo, high: hi)
        }
        var margin: [ThemeBall] = Self.balls(main + loose)
        for k in 0..<4 {
            let corner = SIMD2<Double>(k % 2 == 0 ? board.low.x : board.high.x, k < 2 ? board.low.y : board.high.y)
            margin.append(ThemeBall(c: GraphCircuit.world(corner), r: 0.05))
        }
        let envelope: [SIMD3<Float>] = ThemeLayout.points(margin, around: SIMD3<Double>(0, 0, 0))
        let regions: [Int] = tops.map { cBody[$0] }
        var plan = ThemePlan(bodies: bodies, links: links, envelope: envelope, systems: systems, regions: regions,
                             summary: GraphCircuit.summary(bodies))
        plan.ground = SIMD4<Float>(Float(board.low.x), Float(board.low.y), Float(board.high.x), Float(board.high.y))
        plan.patches = patches
        return plan
    }

    /// A ball round each rectangle, a little above the board (the parts
    /// stand up from it), for framing.
    static func balls(_ rects: [CircuitRect]) -> [ThemeBall] {
        rects.map { r in
            let reach: Double = (r.h.x * r.h.x + r.h.y * r.h.y).squareRoot()
            return ThemeBall(c: GraphCircuit.world(r.c, height: 0.08), r: reach + 0.05)
        }
    }

    func linkKind(_ i: Int, _ j: Int) -> Int {
        if smdHost[i] == j || smdHost[j] == i { return 3 }
        let hi: Int = tree.noteHome[i]
        let hj: Int = tree.noteHome[j]
        if hi < 0 || hj < 0 { return 2 }
        if hi == hj { return 0 }
        return tree.top[hi] == tree.top[hj] ? 1 : 2
    }

    /// A body's direction on the board: along y for a part lying that
    /// way, else along x.
    static func axis(vertical: Bool) -> SIMD3<Float> {
        GraphUniverse.float3(vertical ? GraphCircuit.forward : GraphCircuit.right)
    }

    mutating func emitContainer(_ c: Int) {
        let up: Int = tree.parent[c]
        let parentBody: Int = up >= 0 ? cBody[up] : -1
        let home: SIMD3<Double> = GraphCircuit.world(cPos[c])
        let base: SIMD3<Double> = up >= 0 ? home - GraphCircuit.world(cPos[up]) : home
        let index: Int = bodies.count
        let region: Int = up >= 0 ? cBody[tree.top[c]] : index
        let isHome: Bool = c == tree.homeC
        let name: String = tree.cName(c)
        let label: String = UniversePlanner.folderLabel(name, count: tree.count[c])
        let r: CircuitRole = cRole(c)
        bodies.append(ThemeBody(id: tree.cID(c), kind: isHome ? .home : .folder, role: r.rawValue,
                                parent: parentBody, sphere: Float(cSphere[c]), depth: tree.depth[c],
                                region: region, count: tree.count[c], links: 0, words: 0, rank: r.rank,
                                seed: tree.cSeed(c), orbit: .fixed(GraphUniverse.float3(base)),
                                home: GraphUniverse.float3(home), axis: Self.axis(vertical: true), title: name,
                                label: label))
        let p: CircuitRect = local[c].patch
        patches.append(SIMD4<Float>(Float(p.c.x), Float(p.c.y), Float(p.h.x), Float(p.h.y)))
        cBody[c] = index
        for (i, at, vertical) in local[c].members {
            emitNote(i, parent: index, region: region, at: cPos[c] + at, from: cPos[c], vertical: vertical)
            emitSmds(i, at: cPos[c] + at, region: region, vertical: vertical)
        }
        for (k, _) in local[c].children { emitContainer(k) }
    }

    mutating func emitNote(_ i: Int, parent: Int, region: Int, at: SIMD2<Double>, from: SIMD2<Double>?,
                           vertical: Bool) {
        let note: UniverseNote = tree.noteList[i]
        let home: SIMD3<Double> = GraphCircuit.world(at)
        let base: SIMD3<Double> = from.map { home - GraphCircuit.world($0) } ?? home
        let r: CircuitRole = role[i]
        noteBody[i] = bodies.count
        bodies.append(ThemeBody(id: note.id, kind: .note, role: r.rawValue, parent: parent,
                                sphere: Float(sphere[i]), depth: -1, region: region, count: 0,
                                links: tree.nbr[i].count, words: note.words, rank: r.rank, seed: tree.nSeed(i),
                                orbit: .fixed(GraphUniverse.float3(base)), home: GraphUniverse.float3(home),
                                axis: Self.axis(vertical: vertical), title: note.title,
                                label: UniversePlanner.noteLabel(note.title)))
        patches.append(SIMD4<Float>(0, 0, 0, 0))
    }

    /// A note's surface-mount parts, in their row beside it.
    mutating func emitSmds(_ host: Int, at: SIMD2<Double>, region: Int, vertical: Bool) {
        let list: [Int] = smdOf[host]
        guard !list.isEmpty else { return }
        let hostBody: Int = noteBody[host]
        for (k, g) in list.enumerated() {
            let spot: SIMD2<Double> = at + smdOffset(host, k, vertical: vertical)
            emitNote(g, parent: hostBody, region: region, at: spot, from: at, vertical: vertical)
        }
    }

    mutating func emitLoose(_ i: Int) {
        emitNote(i, parent: -1, region: -1, at: looseSpot[i], from: nil, vertical: false)
    }
}
