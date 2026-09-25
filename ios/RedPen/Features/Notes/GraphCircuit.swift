import Foundation

// The Circuit theme: the ideas' own hierarchy drawn as circuit boards on a
// dark bench - one small board per collection, each a closed circuit that
// follows real circuit logic, so it reads at a glance.
//
// - every top-level folder is its own board, with its chip - the
//   controller at the top of its hierarchy - in the top left corner;
// - a power rail (VCC) runs along each board's top edge and a ground rail
//   (GND) along its bottom; every part sits on a closed path from the power
//   rail, through the chip, through the part and back down to ground -
//   nothing dangles;
// - the hierarchy is the topology: the chip feeds a bus; a folder inside
//   it is a smaller chip on its own sub-board, on a branch of that bus,
//   with its own bus; pages are capacitors on the bus; ideas are LEDs in
//   parallel branches off the page they link to (or straight off the chip's
//   bus when they link to none); an idea's own linked ideas chain in series
//   after it; each branch ends in a tap on the ground rail;
// - links inside a collection are its traces; a link between collections
//   leaves its board at an edge connector and runs as a thin bus to the
//   other board's connector;
// - a note in no folder is a gold pad on the left edge of the board it
//   links to most (the biggest board when it links to none), wired from the
//   power rail to ground like everything else;
// - with no folders at all, one board with one chip holds every note.
//
// Current runs from the power rail through the chip, down the branches to
// the LEDs and on to ground: every link's sending end is the one nearer the
// power rail (its rank, 1000 less its steps from the rail), and the wiring
// (links of kind 5 and 6) is always sent from its first end.
//
// A big collection's board wraps its branches into tiers, each with its own
// bus fed down the chip's spine and its own ground rail, so no board grows
// ever wider. Boards sit in a tidy grid with gaps, biggest first.
//
// Pure and deterministic: Foundation only, the same notes always give the
// same boards, no two parts' footprints overlap, and everything lies flat.
// Tested on Linux (Tests/CircuitHierarchyTests).

nonisolated enum CircuitRole: Int, Sendable, CaseIterable {
    /// A top-level folder: its board's controller chip.
    case processor = 0
    /// A folder inside a folder: a smaller chip on its own sub-board.
    case module = 1
    /// The one container of a vault with no folders.
    case soc = 2
    /// A page: a capacitor.
    case capacitor = 3
    /// An idea: an LED (lit when it has links).
    case led = 6
    /// A note in no folder: a gold pad on a board's edge.
    case pad = 11
    /// Wiring (fixtures): the power rail's tap, a tap on a ground rail, a
    /// bus's tap, an edge connector for a link to another board.
    case vcc = 12
    case ground = 13
    case bus = 14
    case connector = 15

    var isContainer: Bool {
        self == .processor || self == .module || self == .soc
    }

    var isFixture: Bool {
        self == .vcc || self == .ground || self == .bus || self == .connector
    }

    /// Half its footprint, in sizes: what must stay clear.
    var foot: SIMD2<Double> {
        switch self {
        case .processor, .module, .soc: return SIMD2<Double>(1.25, 1.25)
        case .capacitor: return SIMD2<Double>(0.95, 0.95)
        case .led: return SIMD2<Double>(0.85, 0.85)
        case .pad: return SIMD2<Double>(0.9, 0.9)
        case .vcc, .ground, .bus, .connector: return SIMD2<Double>(0.5, 0.5)
        }
    }
}

/// A rectangle on a board, square to its edges: its centre and half its
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
    /// How far the boards lean back from facing the camera (radians): boards
    /// on a bench, seen a little from above.
    static let tilt: Double = 0.30
    /// Room between boards on the bench.
    static let benchGap: Double = 0.55
    /// A branch's longest run of LEDs before another branch starts.
    static let longestRun: Int = 6
    /// Unlinked ideas are strung in series in strings of up to this many.
    static let stringOf: Int = 5

    // MARK: the boards' plane

    /// The bench's x, y and up in the space: x across, y up the boards
    /// (leaning back by `tilt`), up out of them towards the camera.
    static let right = SIMD3<Double>(1, 0, 0)
    static let forward = SIMD3<Double>(0, cos(tilt), -sin(tilt))
    static let normal = SIMD3<Double>(0, sin(tilt), cos(tilt))

    /// A point of the bench (and a height above it) in the space.
    static func world(_ q: SIMD2<Double>, height: Double = 0) -> SIMD3<Double> {
        right * q.x + forward * q.y + normal * height
    }

    // MARK: sizes (the ladder)

    /// A controller chip: 0.30 to 0.42 by how many notes it holds.
    static func processorSphere(count: Int) -> Double {
        guard count > 0 else { return 0.30 }
        let size: Double = log2(1 + Double(count))
        return GraphUniverse.clamp(0.30 + 0.016 * size, 0.30, 0.42)
    }

    /// A sub-folder's chip: by what it holds, always smaller than the chip
    /// it hangs from and bigger than any page.
    static func moduleSphere(count: Int, parent: Double) -> Double {
        let size: Double = log2(1 + Double(count))
        let own: Double = GraphUniverse.clamp(0.19 + 0.01 * size, 0.19, 0.27)
        return max(min(own, parent * 0.85), 0.165)
    }

    static let socSphere: Double = 0.34

    /// A page: 0.10 to 0.148 by length.
    static func pageSphere(words: Int) -> Double {
        let lv: Int = min(GraphUniverse.level(words: words), 8)
        return 0.10 + 0.006 * Double(lv)
    }

    /// An idea: 0.06 to 0.078 by length.
    static func ideaSphere(words: Int) -> Double {
        let lv: Int = min(GraphUniverse.level(words: words), 6)
        return 0.06 + 0.003 * Double(lv)
    }

    static let padSphere: Double = 0.075
    static let fixtureSphere: Double = 0.028

    // MARK: the chips' names

    /// A chip's printed model tag, by its place in the hierarchy and how
    /// much it holds: "S-12 Pro" for a board's controller (the number and
    /// suffix growing with its notes), "S7" for a chip on a sub-board. S
    /// for Stethoscore; never anyone else's name or numbering.
    static func modelTag(count: Int, depth: Int) -> String {
        let lv: Int = min(GraphUniverse.level(words: max(count, 0) * 40), 8)
        if depth > 0 {
            let n: Int = 5 + min(lv, 6) - min(depth - 1, 2)
            return "S" + String(max(n, 3))
        }
        let n: Int = 8 + lv
        var suffix: String = ""
        if count >= 40 {
            suffix = " Ultra"
        } else if count >= 16 {
            suffix = " Max"
        } else if count >= 6 {
            suffix = " Pro"
        }
        return "S-" + String(n) + suffix
    }

    // MARK: planning

    static func plan(_ input: UniverseInput) -> ThemePlan {
        if input.notes.isEmpty && input.folders.isEmpty { return .empty }
        var planner = CircuitPlanner(input)
        return planner.run()
    }

    /// "2 boards, 2 chips, 4 capacitors, 12 LEDs, 2 pads".
    static func summary(_ bodies: [ThemeBody]) -> String {
        var counts = [Int](repeating: 0, count: 16)
        var boards: Int = 0
        for body in bodies where body.role >= 0 && body.role < counts.count {
            counts[body.role] += 1
            if body.kind != .note && body.kind != .fixture && body.parent < 0 { boards += 1 }
        }
        let chips: Int = counts[CircuitRole.processor.rawValue] + counts[CircuitRole.module.rawValue]
            + counts[CircuitRole.soc.rawValue]
        var parts: [String] = []
        if boards > 0 { parts.append("\(boards) " + (boards == 1 ? "board" : "boards")) }
        if chips > 0 { parts.append("\(chips) " + (chips == 1 ? "chip" : "chips")) }
        let words: [(CircuitRole, String, String)] = [
            (.capacitor, "capacitor", "capacitors"), (.led, "LED", "LEDs"), (.pad, "pad", "pads")
        ]
        for (role, one, many) in words {
            let n: Int = counts[role.rawValue]
            if n > 0 { parts.append("\(n) " + (n == 1 ? one : many)) }
        }
        return parts.joined(separator: ", ")
    }

    /// A fixture's id: stable for its board, what it is and its number.
    static func fixtureID(_ board: UUID, _ tag: String, _ k: Int) -> UUID {
        let key: String = board.uuidString + "|" + tag + "|" + String(k)
        let a: UInt64 = GraphUniverse.fnv(key)
        let b: UInt64 = GraphUniverse.fnv(key + "#")
        var bytes: [UInt8] = []
        for s in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: a >> UInt64(s))) }
        for s in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: b >> UInt64(s))) }
        let t: uuid_t = (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                         bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: t)
    }
}

/// One column hanging from a bus: a page with its parallel branches of
/// LEDs below it, a series string of LEDs, or a sub-folder's chip with its
/// own columns beside it.
nonisolated struct CircuitColumn: Sendable {
    /// 0 a page, 1 a string of LEDs, 2 a sub-folder's chip.
    var kind: Int
    /// The page's or the chip's index (note or container); -1 for a string.
    var head: Int
    /// The branches (a page's) or the one string (a string's): notes, top
    /// to bottom, each after the one before it in series.
    var branches: [[Int]]
    var width: Double = 0
    var height: Double = 0
}

/// The plan's working state. Reuses the Universe planner's tree: folders
/// (a cycle cut, a missing parent made top level), each note's container,
/// counts and links.
nonisolated struct CircuitPlanner: Sendable {
    var tree: UniversePlanner
    var role: [CircuitRole] = []
    var sphere: [Double] = []
    var cSphere: [Double] = []
    /// Each container's columns (its pages, strings and sub-folders).
    var columns: [[CircuitColumn]] = []
    /// Each note's board (a top container), and the loose notes each board
    /// carries as pads.
    var boardOfNote: [Int] = []
    var padsOf: [[Int]] = []
    // the boards' own layouts, then the bench
    var boardRect: [CircuitRect] = []
    var boardAt: [SIMD2<Double>] = []
    // the output
    var bodies: [ThemeBody] = []
    var patches: [SIMD4<Float>] = []
    var links: [ThemeLink] = []
    var bars: [ThemeBar] = []
    /// Wiring by body: (from, to), sent from the first.
    var wires: [(Int, Int)] = []
    /// Note links that are part of a circuit (a page to its LED, an LED to
    /// the next in series), by body.
    var topology: [(Int, Int)] = []
    var noteBody: [Int] = []
    var cBody: [Int] = []
    /// Body positions on the bench (for connectors), and each body's board.
    var at: [SIMD2<Double>] = []
    var boardOfBody: [Int] = []
    var systems: [[SIMD3<Float>]] = []

    // layout measures
    let colGap: Double = 0.10
    let rowGap: Double = 0.12
    let drop: Double = 0.16
    let railGap: Double = 0.2
    let margin: Double = 0.22

    init(_ input: UniverseInput) {
        tree = UniversePlanner(input)
    }

    var noteCount: Int { tree.noteList.count }

    mutating func run() -> ThemePlan {
        tree.buildTree()
        tree.buildLinks()
        assignRoles()
        sizeParts()
        columns = [[CircuitColumn]](repeating: [], count: tree.cCount)
        for c in 0..<tree.cCount { buildColumns(c) }
        assignPads()
        let tops: [Int] = topOrder()
        noteBody = [Int](repeating: -1, count: noteCount)
        cBody = [Int](repeating: -1, count: tree.cCount)
        measureBoards(tops)
        placeBench(tops)
        for t in tops { emitBoard(t) }
        connectBoards()
        return finish(tops)
    }

    // MARK: roles and sizes

    mutating func assignRoles() {
        role = []
        role.reserveCapacity(noteCount)
        for i in 0..<noteCount {
            if tree.noteHome[i] < 0 {
                role.append(.pad)
            } else {
                role.append(tree.noteList[i].isPage ? .capacitor : .led)
            }
        }
    }

    mutating func sizeParts() {
        sphere = []
        sphere.reserveCapacity(noteCount)
        for i in 0..<noteCount {
            let note: UniverseNote = tree.noteList[i]
            switch role[i] {
            case .pad: sphere.append(GraphCircuit.padSphere)
            case .capacitor: sphere.append(GraphCircuit.pageSphere(words: note.words))
            default: sphere.append(GraphCircuit.ideaSphere(words: note.words))
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
                cSphere[c] = GraphCircuit.moduleSphere(count: tree.count[c], parent: up)
            }
        }
    }

    func cRole(_ c: Int) -> CircuitRole {
        if c == tree.homeC { return .soc }
        return tree.parent[c] < 0 ? .processor : .module
    }

    func half(_ i: Int) -> SIMD2<Double> {
        role[i].foot * sphere[i]
    }

    func cHalf(_ c: Int) -> SIMD2<Double> {
        cRole(c).foot * cSphere[c]
    }

    /// Tops by how much they hold (most first), then name.
    func topOrder() -> [Int] {
        let tops: [Int] = (0..<tree.cCount).filter { tree.parent[$0] < 0 }
        return tops.sorted { a, b in
            if tree.count[a] != tree.count[b] { return tree.count[a] > tree.count[b] }
            return tree.lessC(a, b)
        }
    }

    // MARK: the topology

    /// Container `c`'s columns: its pages (each with the ideas that link to
    /// it in parallel branches below it, and their own linked ideas in
    /// series after them), strings of its other ideas (linked ones in
    /// series along their links, unlinked ones strung together), then its
    /// sub-folders' chips. A branch longer than `longestRun` carries on as
    /// another branch beside it.
    mutating func buildColumns(_ c: Int) {
        let members: [Int] = (0..<noteCount).filter { tree.noteHome[$0] == c }.sorted { tree.lessN($0, $1) }
        let pages: [Int] = members.filter { role[$0] == .capacitor }
        let ideas: [Int] = members.filter { role[$0] == .led }
        let ideaSet = Set<Int>(ideas)
        let pageSet = Set<Int>(pages)
        var placed = Set<Int>()
        var hosted: [Int: [Int]] = [:]
        for i in ideas {
            let linkedPages: [Int] = tree.nbr[i].filter { pageSet.contains($0) }
            guard let host = linkedPages.min(by: { tree.lessN($0, $1) }) else { continue }
            hosted[host, default: []].append(i)
            placed.insert(i)
        }
        var out: [CircuitColumn] = []
        for p in pages {
            var branches: [[Int]] = []
            for i in hosted[p] ?? [] {
                let chain: [Int] = follow(i, ideas: ideaSet, placed: &placed)
                branches.append(contentsOf: Self.pieces(chain, GraphCircuit.longestRun))
            }
            out.append(CircuitColumn(kind: 0, head: p, branches: branches))
        }
        var loners: [Int] = []
        for i in ideas where !placed.contains(i) {
            let free: Bool = tree.nbr[i].contains { ideaSet.contains($0) && !placed.contains($0) }
            if !free {
                loners.append(i)
                continue
            }
            placed.insert(i)
            let chain: [Int] = follow(i, ideas: ideaSet, placed: &placed)
            for piece in Self.pieces(chain, GraphCircuit.longestRun) {
                out.append(CircuitColumn(kind: 1, head: -1, branches: [piece]))
            }
        }
        for piece in Self.pieces(loners, GraphCircuit.stringOf) {
            out.append(CircuitColumn(kind: 1, head: -1, branches: [piece]))
        }
        for k in tree.kids[c] {
            out.append(CircuitColumn(kind: 2, head: k, branches: []))
        }
        columns[c] = out
    }

    /// Idea `i` and the ideas linked on from it not yet placed, depth
    /// first (so each is next to one it links to wherever it can be).
    func follow(_ i: Int, ideas: Set<Int>, placed: inout Set<Int>) -> [Int] {
        var order: [Int] = []
        var stack: [Int] = [i]
        placed.insert(i)
        while let x = stack.popLast() {
            order.append(x)
            for y in tree.nbr[x].reversed() where ideas.contains(y) && !placed.contains(y) {
                placed.insert(y)
                stack.append(y)
            }
        }
        return order
    }

    /// `list` cut into runs of at most `size`.
    static func pieces(_ list: [Int], _ size: Int) -> [[Int]] {
        var out: [[Int]] = []
        var k: Int = 0
        while k < list.count {
            let end: Int = min(k + size, list.count)
            out.append(Array(list[k..<end]))
            k = end
        }
        return out
    }

    /// Whether notes `a` and `b` are linked.
    func linked(_ a: Int, _ b: Int) -> Bool {
        tree.nbr[a].contains(b)
    }

    /// Loose notes: each on the board it links to most (ties: the bigger
    /// board, then by name); with no links, the biggest board.
    mutating func assignPads() {
        boardOfNote = [Int](repeating: -1, count: noteCount)
        for i in 0..<noteCount where tree.noteHome[i] >= 0 {
            boardOfNote[i] = tree.top[tree.noteHome[i]]
        }
        padsOf = [[Int]](repeating: [], count: tree.cCount)
        let tops: [Int] = topOrder()
        guard let biggest = tops.first else { return }
        let loose: [Int] = (0..<noteCount).filter { tree.noteHome[$0] < 0 }.sorted { tree.lessN($0, $1) }
        for i in loose {
            var tally: [Int: Int] = [:]
            for m in tree.nbr[i] where boardOfNote[m] >= 0 { tally[boardOfNote[m], default: 0] += 1 }
            var best: Int = biggest
            var most: Int = 0
            for t in tops {
                let n: Int = tally[t] ?? 0
                if n > most {
                    best = t
                    most = n
                }
            }
            boardOfNote[i] = best
            padsOf[best].append(i)
        }
    }

    // MARK: measuring

    /// A branch's width (its widest LED, and room).
    func branchWidth(_ branch: [Int]) -> Double {
        var w: Double = 0
        for i in branch { w = max(w, half(i).x * 2) }
        return w + colGap
    }

    /// A branch's height, top to bottom.
    func branchHeight(_ branch: [Int]) -> Double {
        var h: Double = 0
        for i in branch { h += half(i).y * 2 + rowGap }
        return h
    }

    /// A column's size: width across, height down from its top.
    func measure(_ col: CircuitColumn) -> SIMD2<Double> {
        switch col.kind {
        case 0:
            let page: SIMD2<Double> = half(col.head)
            var across: Double = 0
            var down: Double = 0
            for b in col.branches {
                across += branchWidth(b)
                down = max(down, branchHeight(b))
            }
            let w: Double = max(page.x * 2 + colGap, across)
            let h: Double = page.y * 2 + (col.branches.isEmpty ? 0 : rowGap + down)
            return SIMD2<Double>(w, h)
        case 1:
            let b: [Int] = col.branches.first ?? []
            return SIMD2<Double>(branchWidth(b), branchHeight(b))
        default:
            return measureBlock(col.head)
        }
    }

    /// A sub-folder's block: its chip, then its columns in a row beside it
    /// under its own bus.
    func measureBlock(_ c: Int) -> SIMD2<Double> {
        let chip: SIMD2<Double> = cHalf(c)
        var across: Double = chip.x * 2 + 0.3
        var down: Double = chip.y * 2
        for col in columns[c] {
            let s: SIMD2<Double> = measure(col)
            across += s.x
            down = max(down, drop + s.y + chip.y * 0.5)
        }
        return SIMD2<Double>(across + colGap, down + rowGap)
    }

    // MARK: laying out a board

    /// Each board's rectangle round its chip (the chip at the origin).
    mutating func measureBoards(_ tops: [Int]) {
        boardRect = [CircuitRect](repeating: CircuitRect(c: SIMD2<Double>(0, 0), h: SIMD2<Double>(0, 0)),
                                  count: tree.cCount)
        for t in tops {
            let layout: CircuitBoardLayout = layOutBoard(t)
            boardRect[t] = layout.rect
        }
    }

    /// Where board `t`'s tiers go: tier 1 beside the chip, the rest below,
    /// each packed to about the same width.
    func layOutBoard(_ t: Int) -> CircuitBoardLayout {
        let chip: SIMD2<Double> = cHalf(t)
        let sizes: [SIMD2<Double>] = columns[t].map { measure($0) }
        var total: Double = 0
        for s in sizes { total += s.x }
        let wrap: Double = max(2.4, min((total * 1.4).squareRoot() + 0.8, 6.5))
        var tiers: [[Int]] = [[]]
        var width: Double = 0
        for (k, s) in sizes.enumerated() {
            let full: Bool = !(tiers.last?.isEmpty ?? true) && width + s.x > wrap
            if full {
                tiers.append([])
                width = 0
            }
            tiers[tiers.count - 1].append(k)
            width += s.x
        }
        var layout = CircuitBoardLayout()
        layout.tiers = tiers
        let firstLeft: Double = chip.x + 0.34
        let laterLeft: Double = 0.3
        var right: Double = firstLeft + 0.3
        var busY: Double = chip.y * 0.5
        var gnd: [Double] = []
        var buses: [Double] = []
        for (n, tier) in tiers.enumerated() {
            var x: Double = n == 0 ? firstLeft : laterLeft
            var low: Double = n == 0 ? -chip.y : busY
            for k in tier {
                x += sizes[k].x
                low = min(low, busY - drop - sizes[k].y)
            }
            right = max(right, x)
            buses.append(busY)
            let g: Double = low - railGap
            gnd.append(g)
            busY = g - 0.26
        }
        layout.buses = buses
        layout.grounds = gnd
        let pads: Int = padsOf[t].count
        let padsLeft: Double = pads > 0 ? -chip.x - 0.42 : -chip.x - margin
        var bottom: Double = (gnd.last ?? -chip.y) - 0.16
        if pads > 0 {
            let padRun: Double = Double(pads) * (GraphCircuit.padSphere * 1.8 + rowGap)
            bottom = min(bottom, -chip.y - 0.2 - padRun - railGap - 0.16)
            layout.grounds[layout.grounds.count - 1] = min(gnd.last ?? 0, bottom + 0.16)
        }
        let top: Double = chip.y + railGap + 0.16
        layout.vcc = chip.y + railGap
        layout.left = padsLeft
        layout.rect = CircuitRect.around(low: SIMD2<Double>(padsLeft - 0.08, bottom),
                                         high: SIMD2<Double>(right + margin, top))
        return layout
    }

    // MARK: the bench

    /// Boards in a tidy grid, biggest first, rows of about the square root
    /// of how many there are, with gaps; the whole bench centred.
    mutating func placeBench(_ tops: [Int]) {
        boardAt = [SIMD2<Double>](repeating: SIMD2<Double>(0, 0), count: tree.cCount)
        let n: Int = tops.count
        guard n > 0 else { return }
        let across: Int = max(1, Int((Double(n).squareRoot() * 0.9).rounded(.up)))
        var y: Double = 0
        var k: Int = 0
        var lowX: Double = Double.greatestFiniteMagnitude
        var highX: Double = -Double.greatestFiniteMagnitude
        var lowY: Double = Double.greatestFiniteMagnitude
        var highY: Double = -Double.greatestFiniteMagnitude
        while k < n {
            let row: [Int] = Array(tops[k..<min(k + across, n)])
            var tallest: Double = 0
            for t in row { tallest = max(tallest, boardRect[t].h.y * 2) }
            var x: Double = 0
            for t in row {
                let r: CircuitRect = boardRect[t]
                // the board's top left at (x, y): its chip where that puts it
                let origin = SIMD2<Double>(x - r.low.x, y - r.high.y)
                boardAt[t] = origin
                x += r.h.x * 2 + GraphCircuit.benchGap
                let moved: CircuitRect = r.moved(origin)
                lowX = min(lowX, moved.low.x)
                highX = max(highX, moved.high.x)
                lowY = min(lowY, moved.low.y)
                highY = max(highY, moved.high.y)
            }
            y -= tallest + GraphCircuit.benchGap
            k += across
        }
        let middle = SIMD2<Double>((lowX + highX) * 0.5, (lowY + highY) * 0.5)
        for t in tops { boardAt[t] -= middle }
    }

    // MARK: emitting

    /// A body; returns its index.
    mutating func add(id: UUID, kind: ThemeBodyKind, role r: CircuitRole, parent: Int, sphere s: Double,
                      depth: Int, region: Int, count: Int, links: Int, words: Int, seed: UInt64,
                      spot: SIMD2<Double>, title: String, label: String, board: Int) -> Int {
        let home: SIMD3<Double> = GraphCircuit.world(spot)
        var base: SIMD3<Double> = home
        if parent >= 0 { base = home - GraphCircuit.world(at[parent]) }
        let index: Int = bodies.count
        let axis: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.forward)
        bodies.append(ThemeBody(id: id, kind: kind, role: r.rawValue, parent: parent, sphere: Float(s),
                                depth: depth, region: region, count: count, links: links, words: words,
                                rank: 0, seed: seed, orbit: .fixed(GraphUniverse.float3(base)),
                                home: GraphUniverse.float3(home), axis: axis, title: title, label: label))
        patches.append(SIMD4<Float>(0, 0, 0, 0))
        at.append(spot)
        boardOfBody.append(board)
        return index
    }

    mutating func addNote(_ i: Int, parent: Int, region: Int, spot: SIMD2<Double>, board: Int) -> Int {
        let note: UniverseNote = tree.noteList[i]
        let index: Int = add(id: note.id, kind: .note, role: role[i], parent: parent, sphere: sphere[i],
                             depth: -1, region: region, count: 0, links: tree.nbr[i].count, words: note.words,
                             seed: tree.nSeed(i), spot: spot, title: note.title,
                             label: UniversePlanner.noteLabel(note.title), board: board)
        noteBody[i] = index
        return index
    }

    mutating func addFixture(_ r: CircuitRole, board t: Int, tag: String, k: Int, parent: Int,
                             spot: SIMD2<Double>) -> Int {
        let id: UUID = GraphCircuit.fixtureID(tree.cID(t), tag, k)
        let region: Int = cBody[t]
        return add(id: id, kind: .fixture, role: r, parent: parent, sphere: GraphCircuit.fixtureSphere,
                   depth: -1, region: region, count: 0, links: 0, words: 0, seed: GraphUniverse.fnv(tag),
                   spot: spot, title: "", label: "", board: t)
    }

    mutating func addChip(_ c: Int, parent: Int, spot: SIMD2<Double>, board: Int) -> Int {
        let isHome: Bool = c == tree.homeC
        let name: String = tree.cName(c)
        let label: String = UniversePlanner.folderLabel(name, count: tree.count[c])
        let region: Int = parent >= 0 ? cBody[board] : bodies.count
        let index: Int = add(id: tree.cID(c), kind: isHome ? .home : .folder, role: cRole(c), parent: parent,
                             sphere: cSphere[c], depth: tree.depth[c], region: region, count: tree.count[c],
                             links: 0, words: 0, seed: tree.cSeed(c), spot: spot, title: name, label: label,
                             board: board)
        cBody[c] = index
        return index
    }

    /// Board `t`: its chip, rails, taps, tiers of columns and pads.
    mutating func emitBoard(_ t: Int) {
        let origin: SIMD2<Double> = boardAt[t]
        let layout: CircuitBoardLayout = layOutBoard(t)
        let chip: Int = addChip(t, parent: -1, spot: origin, board: t)
        let r: CircuitRect = layout.rect
        patches[chip] = SIMD4<Float>(Float(r.c.x), Float(r.c.y), Float(r.h.x), Float(r.h.y))
        let railHalf: Float = Float(r.h.x) - 0.06
        bars.append(ThemeBar(owner: chip, x: Float(r.c.x), y: Float(layout.vcc), half: railHalf, kind: 0))
        // the power tap over the chip
        let vccSpot: SIMD2<Double> = origin + SIMD2<Double>(0, layout.vcc)
        let vcc: Int = addFixture(.vcc, board: t, tag: "vcc", k: 0, parent: chip, spot: vccSpot)
        wires.append((vcc, chip))
        let chipHalf: SIMD2<Double> = cHalf(t)
        let sizes: [SIMD2<Double>] = columns[t].map { measure($0) }
        var spine: Int = chip
        var anything: Bool = false
        for (n, tier) in layout.tiers.enumerated() {
            let busY: Double = layout.buses[n]
            let gndY: Double = layout.grounds[n]
            let last: Bool = n == layout.tiers.count - 1
            // the ground rail under the tier: all the board's width for the
            // last, beside the chip's spine for the others
            if last {
                bars.append(ThemeBar(owner: chip, x: Float(r.c.x), y: Float(gndY), half: railHalf, kind: 1))
            } else {
                let from: Double = 0.14
                let to: Double = r.high.x - 0.06
                let mid: Double = (from + to) * 0.5
                bars.append(ThemeBar(owner: chip, x: Float(mid), y: Float(gndY), half: Float((to - from) * 0.5),
                                     kind: 1))
            }
            guard !tier.isEmpty else { continue }
            anything = true
            // the tier's bus tap: beside the chip for the first, on the
            // chip's spine below it for the others
            let tapX: Double = n == 0 ? chipHalf.x + 0.17 : 0
            let tapSpot: SIMD2<Double> = origin + SIMD2<Double>(tapX, busY)
            let tap: Int = addFixture(.bus, board: t, tag: "bus", k: n, parent: chip, spot: tapSpot)
            // the first tier's bus from the chip; the rest down the spine
            wires.append((n == 0 ? chip : spine, tap))
            if n > 0 { spine = tap }
            var x: Double = n == 0 ? chipHalf.x + 0.34 : 0.3
            for k in tier {
                let col: CircuitColumn = columns[t][k]
                placeColumn(col, board: t, owner: t, parentBody: chip, left: origin.x + x,
                            top: origin.y + busY - drop, gnd: origin.y + gndY, tap: tap, size: sizes[k])
                x += sizes[k].x
            }
        }
        if !anything {
            // a chip with nothing on it still closes its loop to ground
            let g: Int = addFixture(.ground, board: t, tag: "gnd", k: 0, parent: chip,
                                    spot: origin + SIMD2<Double>(0, layout.grounds[0]))
            wires.append((chip, g))
        }
        emitPads(t, layout: layout, chip: chip, origin: origin)
        var box: [ThemeBall] = []
        for k in 0..<4 {
            let cx: Double = k % 2 == 0 ? r.low.x : r.high.x
            let cy: Double = k < 2 ? r.low.y : r.high.y
            let corner: SIMD3<Double> = GraphCircuit.world(SIMD2<Double>(cx, cy), height: 0.1)
            box.append(ThemeBall(c: corner, r: 0.06))
        }
        systemsFor[chip] = ThemeLayout.points(box, around: SIMD3<Double>(0, 0, 0))
    }

    var systemsFor: [Int: [SIMD3<Float>]] = [:]

    /// A column under a bus: its head fed from the bus tap `tap`; a page's
    /// branches (and a string) down to their ground taps on the rail at
    /// `gnd`; a sub-folder's chip with its own bus and columns.
    mutating func placeColumn(_ col: CircuitColumn, board t: Int, owner c: Int, parentBody: Int, left: Double,
                              top: Double, gnd: Double, tap: Int, size: SIMD2<Double>) {
        let region: Int = cBody[t]
        switch col.kind {
        case 0:
            let page: SIMD2<Double> = half(col.head)
            let spot = SIMD2<Double>(left + size.x * 0.5, top - page.y)
            let p: Int = addNote(col.head, parent: parentBody, region: region, spot: spot, board: t)
            wires.append((tap, p))
            if col.branches.isEmpty {
                ground(from: p, x: spot.x, gnd: gnd, board: t)
                return
            }
            var across: Double = 0
            for b in col.branches { across += branchWidth(b) }
            var x: Double = left + (size.x - across) * 0.5
            let below: Double = top - page.y * 2 - rowGap
            for b in col.branches {
                let w: Double = branchWidth(b)
                placeBranch(b, from: p, fromNote: col.head, x: x + w * 0.5, top: below, gnd: gnd, board: t,
                            parent: parentBody)
                x += w
            }
        case 1:
            let b: [Int] = col.branches.first ?? []
            placeBranch(b, from: tap, fromNote: -1, x: left + size.x * 0.5, top: top, gnd: gnd, board: t,
                        parent: parentBody)
        default:
            let k: Int = col.head
            let chip: SIMD2<Double> = cHalf(k)
            let spot = SIMD2<Double>(left + chip.x + colGap * 0.5, top - chip.y)
            let m: Int = addChip(k, parent: parentBody, spot: spot, board: t)
            wires.append((tap, m))
            // its sub-board: the whole block
            let blockLow = SIMD2<Double>(left, top - size.y + rowGap * 0.5)
            let blockHigh = SIMD2<Double>(left + size.x - colGap * 0.5, top + 0.04)
            let block: CircuitRect = CircuitRect.around(low: blockLow, high: blockHigh)
            let rel: SIMD2<Double> = block.c - spot
            patches[m] = SIMD4<Float>(Float(rel.x), Float(rel.y), Float(block.h.x), Float(block.h.y))
            systemsFor[m] = [GraphUniverse.float3(GraphCircuit.world(block.low - spot)),
                             GraphUniverse.float3(GraphCircuit.world(block.high - spot)),
                             GraphUniverse.float3(GraphCircuit.world(SIMD2<Double>(block.low.x, block.high.y) - spot,
                                                                     height: 0.1)),
                             GraphUniverse.float3(GraphCircuit.world(SIMD2<Double>(block.high.x, block.low.y) - spot,
                                                                     height: 0.1))]
            let inner: [CircuitColumn] = columns[k]
            if inner.isEmpty {
                ground(from: m, x: spot.x, gnd: gnd, board: t)
                return
            }
            let busY: Double = spot.y + chip.y * 0.5
            let subTap: Int = addFixture(.bus, board: t, tag: "sub" + String(k), k: 0, parent: m,
                                         spot: SIMD2<Double>(spot.x + chip.x + 0.15, busY))
            wires.append((m, subTap))
            var x: Double = spot.x + chip.x + 0.3
            for sub in inner {
                let s: SIMD2<Double> = measure(sub)
                placeColumn(sub, board: t, owner: k, parentBody: m, left: x, top: busY - drop, gnd: gnd,
                            tap: subTap, size: s)
                x += s.x
            }
        }
    }

    /// A branch of LEDs in series, top to bottom from `top`, fed from
    /// body `from` (a page, note `fromNote`, or a bus tap), ending in a
    /// ground tap. Where two in a row are linked notes, their link is the
    /// wire; elsewhere the board's own wiring joins them.
    mutating func placeBranch(_ branch: [Int], from: Int, fromNote: Int, x: Double, top: Double, gnd: Double,
                              board t: Int, parent: Int) {
        var y: Double = top
        var before: Int = from
        var beforeNote: Int = fromNote
        let region: Int = cBody[t]
        for i in branch {
            let h: SIMD2<Double> = half(i)
            let spot = SIMD2<Double>(x, y - h.y)
            let b: Int = addNote(i, parent: parent, region: region, spot: spot, board: t)
            if beforeNote >= 0 && linked(beforeNote, i) {
                topology.append((before, b))
            } else {
                wires.append((before, b))
            }
            before = b
            beforeNote = i
            y -= h.y * 2 + rowGap
        }
        ground(from: before, x: x, gnd: gnd, board: t)
    }

    /// A tap on the ground rail under `x`, wired from `from`.
    mutating func ground(from: Int, x: Double, gnd: Double, board t: Int) {
        let k: Int = groundCount[t, default: 0]
        groundCount[t] = k + 1
        let g: Int = addFixture(.ground, board: t, tag: "gnd", k: k, parent: cBody[t],
                                spot: SIMD2<Double>(x, gnd))
        wires.append((from, g))
    }

    var groundCount: [Int: Int] = [:]

    /// Board `t`'s loose notes: gold pads down its left edge, each wired
    /// from the power rail (a tap in the margin) to ground.
    mutating func emitPads(_ t: Int, layout: CircuitBoardLayout, chip: Int, origin: SIMD2<Double>) {
        let pads: [Int] = padsOf[t]
        guard !pads.isEmpty else { return }
        let x: Double = layout.left + 0.08
        let tapSpot: SIMD2<Double> = origin + SIMD2<Double>(x, layout.vcc)
        let tap: Int = addFixture(.vcc, board: t, tag: "padVcc", k: 0, parent: chip, spot: tapSpot)
        let chipHalf: SIMD2<Double> = cHalf(t)
        var y: Double = -chipHalf.y - 0.2
        let gnd: Double = layout.grounds.last ?? (y - 1)
        for i in pads {
            let h: SIMD2<Double> = half(i)
            let spot: SIMD2<Double> = origin + SIMD2<Double>(x, y - h.y)
            let p: Int = addNote(i, parent: chip, region: -1, spot: spot, board: t)
            wires.append((tap, p))
            let k: Int = groundCount[t, default: 0]
            groundCount[t] = k + 1
            let g: Int = addFixture(.ground, board: t, tag: "gnd", k: k, parent: chip,
                                    spot: SIMD2<Double>(spot.x, origin.y + gnd))
            wires.append((p, g))
            y -= h.y * 2 + rowGap
        }
    }

    // MARK: between boards

    /// Every link between two boards: hidden as itself, drawn as a trace
    /// out to an edge connector on each board and a thin bus between
    /// them, sent from the end nearer its power rail.
    mutating func connectBoards() {
        var crossing: [(Int, Int)] = []
        for (i, j) in tree.edgePairs {
            let bi: Int = boardOfNote[i]
            let bj: Int = boardOfNote[j]
            guard bi >= 0, bj >= 0, bi != bj, noteBody[i] >= 0, noteBody[j] >= 0 else { continue }
            crossing.append((i, j))
        }
        guard !crossing.isEmpty else { return }
        let depth: [Int] = flowDepths()
        // each board's connectors on the edge facing the other board
        var slots: [String: [(Int, Double)]] = [:]
        var plans: [(Int, Int, Int, Int, Int, Int)] = []
        for (n, (i, j)) in crossing.enumerated() {
            let a: Int = noteBody[i]
            let b: Int = noteBody[j]
            let da: Int = depth[a]
            let db: Int = depth[b]
            let send: Bool = da < db || (da == db && lessBoard(boardOfNote[i], boardOfNote[j]))
            let from: Int = send ? a : b
            let to: Int = send ? b : a
            let bf: Int = boardOfBody[from]
            let bt: Int = boardOfBody[to]
            let edgeF: Int = facing(bf, bt)
            let edgeT: Int = facing(bt, bf)
            let keyF: String = String(bf) + ":" + String(edgeF)
            let keyT: String = String(bt) + ":" + String(edgeT)
            slots[keyF, default: []].append((n, sortKey(at[to], edge: edgeF)))
            slots[keyT, default: []].append((n, sortKey(at[from], edge: edgeT)))
            plans.append((from, to, bf, bt, edgeF, edgeT))
        }
        var connectorOf: [String: Int] = [:]
        for key in slots.keys.sorted() {
            guard let list = slots[key] else { continue }
            let parts: [Substring] = key.split(separator: ":")
            guard parts.count == 2, let t = Int(parts[0]), let e = Int(parts[1]) else { continue }
            let sorted: [(Int, Double)] = list.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }
            for (k, entry) in sorted.enumerated() {
                let spot: SIMD2<Double> = edgeSpot(t, edge: e, k: k, of: sorted.count)
                let c: Int = addFixture(.connector, board: t, tag: "edge" + String(e), k: k, parent: cBody[t],
                                        spot: spot)
                connectorOf[key + ":" + String(entry.0)] = c
            }
        }
        for (n, p) in plans.enumerated() {
            let keyF: String = String(p.2) + ":" + String(p.4) + ":" + String(n)
            let keyT: String = String(p.3) + ":" + String(p.5) + ":" + String(n)
            guard let cf = connectorOf[keyF], let ct = connectorOf[keyT] else { continue }
            links.append(ThemeLink(a: p.0, b: cf, kind: 5, centre: -1))
            links.append(ThemeLink(a: cf, b: ct, kind: 6, centre: -1))
            links.append(ThemeLink(a: ct, b: p.1, kind: 5, centre: -1))
            hiddenPairs.insert(pairKey(p.0, p.1))
        }
    }

    var hiddenPairs = Set<Int>()

    func pairKey(_ a: Int, _ b: Int) -> Int {
        min(a, b) * 1_000_003 + max(a, b)
    }

    func lessBoard(_ a: Int, _ b: Int) -> Bool {
        let order: [Int] = topOrder()
        let ia: Int = order.firstIndex(of: a) ?? 0
        let ib: Int = order.firstIndex(of: b) ?? 0
        return ia < ib
    }

    /// Which edge of board `t` faces board `u`: 0 right, 1 bottom, 2 left,
    /// 3 top.
    func facing(_ t: Int, _ u: Int) -> Int {
        let a: SIMD2<Double> = boardRect[t].c + boardAt[t]
        let b: SIMD2<Double> = boardRect[u].c + boardAt[u]
        let d: SIMD2<Double> = b - a
        if abs(d.x) >= abs(d.y) { return d.x >= 0 ? 0 : 2 }
        return d.y >= 0 ? 3 : 1
    }

    /// Where along an edge a connector's partner lies (so their buses do
    /// not cross).
    func sortKey(_ partner: SIMD2<Double>, edge: Int) -> Double {
        edge % 2 == 0 ? -partner.y : partner.x
    }

    /// Connector `k` of `n` on edge `e` of board `t`, spread along it, just
    /// inside.
    func edgeSpot(_ t: Int, edge e: Int, k: Int, of n: Int) -> SIMD2<Double> {
        let r: CircuitRect = boardRect[t].moved(boardAt[t])
        let share: Double = (Double(k) + 1) / (Double(n) + 1)
        let inset: Double = 0.07
        switch e {
        case 0:
            let y: Double = r.high.y - 0.35 - (r.h.y * 2 - 0.7) * share
            return SIMD2<Double>(r.high.x - inset, y)
        case 2:
            let y: Double = r.high.y - 0.35 - (r.h.y * 2 - 0.7) * share
            return SIMD2<Double>(r.low.x + inset, y)
        case 1:
            let x: Double = r.low.x + 0.35 + (r.h.x * 2 - 0.7) * share
            return SIMD2<Double>(x, r.low.y + inset)
        default:
            let x: Double = r.low.x + 0.35 + (r.h.x * 2 - 0.7) * share
            return SIMD2<Double>(x, r.high.y - inset)
        }
    }

    // MARK: the flow

    /// Each body's steps from its board's power rail along the wiring and
    /// the circuit's note links (-1: not reached).
    func flowDepths() -> [Int] {
        var next = [[Int]](repeating: [], count: bodies.count)
        for (a, b) in wires { next[a].append(b) }
        for (a, b) in topology { next[a].append(b) }
        var depth = [Int](repeating: -1, count: bodies.count)
        var queue: [Int] = []
        for (i, body) in bodies.enumerated() where body.role == CircuitRole.vcc.rawValue {
            depth[i] = 0
            queue.append(i)
        }
        var head: Int = 0
        while head < queue.count {
            let x: Int = queue[head]
            head += 1
            for y in next[x] where depth[y] < 0 {
                depth[y] = depth[x] + 1
                queue.append(y)
            }
        }
        return depth
    }

    // MARK: the plan

    mutating func finish(_ tops: [Int]) -> ThemePlan {
        let depth: [Int] = flowDepths()
        var feeds = [Int](repeating: -1, count: bodies.count)
        for (a, b) in wires where feeds[b] < 0 && depth[a] >= 0 && depth[b] == depth[a] + 1 { feeds[b] = a }
        for (a, b) in topology where feeds[b] < 0 && depth[a] >= 0 && depth[b] == depth[a] + 1 { feeds[b] = a }
        // ranks: nearer the power rail sends
        var ranked: [ThemeBody] = []
        ranked.reserveCapacity(bodies.count)
        for (i, b) in bodies.enumerated() {
            let steps: Int = depth[i] >= 0 ? depth[i] : 999
            ranked.append(ThemeBody(id: b.id, kind: b.kind, role: b.role, parent: b.parent, sphere: b.sphere,
                                    depth: b.depth, region: b.region, count: b.count, links: b.links,
                                    words: b.words, rank: 1000 - steps, seed: b.seed, orbit: b.orbit,
                                    home: b.home, axis: b.axis, title: b.title, label: b.label))
        }
        bodies = ranked
        // the notes' own links: inside a board a trace, between boards
        // hidden (drawn through the connectors instead)
        var all: [ThemeLink] = []
        for (i, j) in tree.edgePairs {
            let a: Int = noteBody[i]
            let b: Int = noteBody[j]
            guard a >= 0, b >= 0 else { continue }
            let kind: Int = hiddenPairs.contains(pairKey(a, b)) ? 3 : 0
            all.append(ThemeLink(a: a, b: b, kind: kind, centre: -1))
        }
        for (a, b) in wires { all.append(ThemeLink(a: a, b: b, kind: 5, centre: -1)) }
        all.append(contentsOf: links)
        var systems = [[SIMD3<Float>]](repeating: [], count: bodies.count)
        for (i, points) in systemsFor { systems[i] = points }
        var margin: [ThemeBall] = []
        for t in tops {
            let r: CircuitRect = boardRect[t].moved(boardAt[t])
            for k in 0..<4 {
                let cx: Double = k % 2 == 0 ? r.low.x : r.high.x
                let cy: Double = k < 2 ? r.low.y : r.high.y
                margin.append(ThemeBall(c: GraphCircuit.world(SIMD2<Double>(cx, cy), height: 0.1), r: 0.08))
            }
        }
        for b in bodies where b.kind != .fixture {
            let reach: Double = Double(b.sphere) * 1.3
            margin.append(ThemeBall(c: SIMD3<Double>(Double(b.home.x), Double(b.home.y), Double(b.home.z)),
                                    r: reach))
        }
        let envelope: [SIMD3<Float>] = ThemeLayout.points(margin, around: SIMD3<Double>(0, 0, 0))
        let regions: [Int] = tops.map { cBody[$0] }
        var plan = ThemePlan(bodies: bodies, links: all, envelope: envelope, systems: systems, regions: regions,
                             summary: GraphCircuit.summary(bodies))
        plan.patches = patches
        plan.bars = bars
        plan.feeds = feeds
        return plan
    }
}

/// A board's own layout round its chip: its tiers (column indices), each
/// tier's bus and ground rail heights, the power rail's height, its left
/// edge (the pads' margin) and its rectangle.
nonisolated struct CircuitBoardLayout: Sendable {
    var tiers: [[Int]] = []
    var buses: [Double] = []
    var grounds: [Double] = []
    var vcc: Double = 0
    var left: Double = 0
    var rect = CircuitRect(c: SIMD2<Double>(0, 0), h: SIMD2<Double>(0, 0))
}
