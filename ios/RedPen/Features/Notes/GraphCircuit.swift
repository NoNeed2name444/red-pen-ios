import Foundation

// The Circuit theme: the ideas' own hierarchy drawn as tidy circuits of
// light - one upright tile of dark glass per collection, side by side on a
// dark bench, each a closed loop that follows real circuit logic and reads
// at a glance.
//
// - every top-level folder is its own tile: its source cell at the top
//   centre, a feed down into the collection's controller chip, and the
//   chip's trunk running on down the middle of the tile;
// - the hierarchy is the topology: branches leave the trunk to the left and
//   right at joints - a page is a ring on its branch, fanning out at 45°
//   into one lane per chain of the ideas that link to it (capsules in
//   series, each after the one it links to); ideas that link to no page run
//   in lanes straight off the trunk; a folder inside is a smaller chip on
//   its branch, running its own trunk down beside its parent's, with its
//   own branches further out;
// - every lane runs out to the return rail on its side of the tile, and the
//   two rails run up the sides and along the top back into the source:
//   every part sits on a closed loop, nothing dangles;
// - a note in no folder is a prism on a stub off the feed of the tile it
//   links to most (the biggest when it links to none);
// - links inside a tile that are not its wiring are drawn apart (kind 2),
//   faint until one of their notes is chosen; a link between tiles leaves
//   its tile at a port on the facing edge and runs as a fibre to the other
//   tile's port;
// - with no folders at all, one tile with one chip holds every note.
//
// Current runs from the source through the chip, down the trunk, out along
// the branches and lanes and back up the rails: every link's sending end is
// the one nearer the source (its rank, 1000 less its steps from it), and
// the wiring (links of kind 5 and 6) is always sent from its first end. The
// return rails are wiring too, but take no part in the ranks: they only
// close the loops.
//
// The tiles stand upright like the phone, packed biggest first in rows as
// many abreast as keeps the whole bench closest to the phone's shape.
//
// Pure and deterministic: Foundation only, the same notes always give the
// same tiles, no two parts' footprints overlap, and everything lies flat.
// Tested on Linux (Tests/CircuitHierarchyTests).

nonisolated enum CircuitRole: Int, Sendable, CaseIterable {
    /// A top-level folder: its tile's controller chip.
    case processor = 0
    /// A folder inside a folder: a smaller chip on a branch, with its own
    /// trunk.
    case module = 1
    /// The one container of a vault with no folders.
    case soc = 2
    /// A page: a ring of light on a branch.
    case capacitor = 3
    /// An idea: a glass capsule in a lane (lit when it has links).
    case led = 6
    /// A note in no folder: a prism on a stub off the feed.
    case pad = 11
    /// Wiring (fixtures): the tile's source cell, a joint on a return rail
    /// (and each rail's top corner), a joint on the feed or a trunk, a port
    /// on the tile's edge for a link to another tile.
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

    /// Half its footprint, in sizes: what must stay clear. A capsule lies
    /// along its lane.
    var foot: SIMD2<Double> {
        switch self {
        case .processor, .module, .soc: return SIMD2<Double>(1.25, 1.25)
        case .capacitor: return SIMD2<Double>(1.0, 1.0)
        case .led: return SIMD2<Double>(1.3, 0.62)
        case .pad: return SIMD2<Double>(1.0, 1.0)
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
    /// How far the tiles lean back from facing the camera (radians): tiles
    /// on a bench, seen a little from above, but not so much that the
    /// bench foreshortens into bands of empty dark.
    static let tilt: Double = 0.24
    /// Room between tiles on the bench.
    static let benchGap: Double = 0.6
    /// The bench's shape as it shows (width over height) that the packing
    /// aims for: the phone's, upright.
    static let benchAspect: Double = 0.46
    /// A branch's longest run of capsules before another lane starts.
    static let longestRun: Int = 6
    /// Unlinked ideas are strung in series in lanes of up to this many.
    static let stringOf: Int = 5
    /// How far a ring's links are trimmed from its centre, in its sizes
    /// (GraphShape.linkTrim times GraphCircuitLook's reach), and how far
    /// past that its lanes' fan splits (GraphLinkBoard.stem).
    static let ringTrim: Double = 1.08
    static let stem: Double = 0.07

    // MARK: the boards' plane

    /// The bench's x, y and up in the space: x across, y up the tiles
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

    /// A page's ring: 0.10 to 0.148 by length.
    static func pageSphere(words: Int) -> Double {
        let lv: Int = min(GraphUniverse.level(words: words), 8)
        return 0.10 + 0.006 * Double(lv)
    }

    /// An idea's capsule: 0.06 to 0.078 by length.
    static func ideaSphere(words: Int) -> Double {
        let lv: Int = min(GraphUniverse.level(words: words), 6)
        return 0.06 + 0.003 * Double(lv)
    }

    /// The longest capsule's half length: every lane's capsules sit on one
    /// grid, whatever their own lengths.
    static let capsuleHalf: Double = 1.3 * 0.078

    static let padSphere: Double = 0.08
    static let fixtureSphere: Double = 0.028
    /// The source cell at the top of each tile.
    static let sourceSphere: Double = 0.12

    // MARK: the chips' names

    /// A chip's printed model tag, by its place in the hierarchy and how
    /// much it holds: "S-12 Pro" for a tile's controller (the number and
    /// suffix growing with its notes), "S7" for a chip in a folder. S for
    /// Stethoscore; never anyone else's name or numbering.
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

    /// "3 circuits, 6 chips, 11 rings, 24 capsules, 2 prisms".
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
        if boards > 0 { parts.append("\(boards) " + (boards == 1 ? "circuit" : "circuits")) }
        if chips > 0 { parts.append("\(chips) " + (chips == 1 ? "chip" : "chips")) }
        let words: [(CircuitRole, String, String)] = [
            (.capacitor, "ring", "rings"), (.led, "capsule", "capsules"), (.pad, "prism", "prisms")
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

/// One branch hanging from a trunk: a page with its lanes of capsules, a
/// lane of capsules on its own, or a sub-folder's chip with its own trunk.
nonisolated struct CircuitColumn: Sendable {
    /// 0 a page, 1 a lane of capsules, 2 a sub-folder's chip.
    var kind: Int
    /// The page's or the chip's index (note or container); -1 for a lane.
    var head: Int
    /// The lanes (a page's) or the one lane: notes, out from the trunk,
    /// each after the one before it in series.
    var branches: [[Int]]
    var width: Double = 0
    var height: Double = 0
}

/// A branch's shape in its trunk's frame: how far down the trunk it takes
/// (`height`), where on that its joint with the trunk is (`tap`, from its
/// top), and how far out from the trunk it reaches (`reach`).
nonisolated struct CircuitBand: Sendable, Equatable {
    var height: Double
    var tap: Double
    var reach: Double
}

/// A branch placed on a trunk: which of its owner's columns, which side
/// (-1 left, 1 right) and the bench height of its band's top.
nonisolated struct CircuitHang: Sendable {
    var col: Int
    var side: Int
    var top: Double
}

/// A tile's own layout, measured down from its source (at the origin):
/// where the loose notes' prisms and the chip sit on the feed, each
/// branch's side and band top on the trunk, the return rails' distance
/// out, and the tile's rectangle.
nonisolated struct CircuitTileLayout: Sendable {
    var padAlong: [Double] = []
    var padSide: [Int] = []
    var chipAlong: Double = 0
    var side: [Int] = []
    var top: [Double] = []
    var railX: Double = 0
    var rect = CircuitRect(c: SIMD2<Double>(0, 0), h: SIMD2<Double>(0, 0))
}

/// The plan's working state. Reuses the Universe planner's tree: folders
/// (a cycle cut, a missing parent made top level), each note's container,
/// counts and links.
nonisolated struct CircuitPlanner: Sendable {
    var tree: UniversePlanner
    var role: [CircuitRole] = []
    var sphere: [Double] = []
    var cSphere: [Double] = []
    /// Each container's columns (its pages, lanes and sub-folders).
    var columns: [[CircuitColumn]] = []
    /// Each note's tile (a top container), and the loose notes each tile
    /// carries as prisms.
    var boardOfNote: [Int] = []
    var padsOf: [[Int]] = []
    // the tiles' own layouts, then the bench (each tile's source)
    var layouts: [CircuitTileLayout] = []
    var boardAt: [SIMD2<Double>] = []
    // the output
    var bodies: [ThemeBody] = []
    var patches: [SIMD4<Float>] = []
    var links: [ThemeLink] = []
    /// Wiring by body: (from, to), sent from the first.
    var wires: [(Int, Int)] = []
    /// The return rails by body, bottom to top and into the source: wiring
    /// too, but no part of the ranks.
    var rails: [(Int, Int)] = []
    /// Note links that are part of a circuit (a page to its capsule, a
    /// capsule to the next in series), by body.
    var topology: [(Int, Int)] = []
    var noteBody: [Int] = []
    var cBody: [Int] = []
    /// Body positions on the bench, and each body's tile.
    var at: [SIMD2<Double>] = []
    var boardOfBody: [Int] = []
    var systemsFor: [Int: [SIMD3<Float>]] = [:]
    /// The tile being wired's lane ends on each rail (left, right): height
    /// and body.
    var railTaps: [[(Double, Int)]] = [[], []]
    var groundCount: [Int: Int] = [:]
    var hiddenPairs = Set<Int>()

    /// The link length (UniverseInput.spacing): every gap on a tile and
    /// between tiles is planned at this times its size, so the guides
    /// between parts grow or shrink and the tiles with them; the parts
    /// keep their sizes.
    let spacing: Double
    // layout measures
    /// Down the trunk between two lanes of one page, or one lane's room.
    let lanePitch: Double
    /// Between two branches on one side of a trunk.
    let bandGap: Double
    /// From a trunk to the near edge of a part on its branch.
    let rung: Double
    /// After a ring's fan, before its lanes' first capsules.
    let tail: Double
    /// Between two capsules in series.
    let chainGap: Double
    /// From the farthest part to the return rail, and the rail to the
    /// tile's edge.
    let railGap: Double
    let margin: Double
    /// A folder's inlay round its branch.
    let inlayPad: Double
    /// Below the source before the feed's first joint.
    let topGap: Double
    /// No two branches leave a trunk closer than this.
    let minTap: Double

    init(_ input: UniverseInput) {
        tree = UniversePlanner(input)
        let space: Double = input.spacing
        spacing = space
        lanePitch = 0.34 * space
        bandGap = 0.24 * space
        rung = 0.30 * space
        tail = 0.12 * space
        chainGap = 0.16 * space
        railGap = 0.26 * space
        margin = 0.26 * space
        inlayPad = 0.10 * space
        topGap = 0.26 * space
        minTap = 0.2 * space
    }

    var noteCount: Int { tree.noteList.count }

    /// From one capsule's centre to the next one's in a lane.
    var chain: Double { GraphCircuit.capsuleHalf * 2 + chainGap }

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
        layouts = [CircuitTileLayout](repeating: CircuitTileLayout(), count: tree.cCount)
        for t in tops { layouts[t] = layOutTile(t) }
        placeBench(tops)
        for t in tops { emitTile(t) }
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
    /// it in lanes out from it, and their own linked ideas in series after
    /// them), lanes of its other ideas (linked ones in series along their
    /// links, unlinked ones strung together), then its sub-folders' chips.
    /// A lane longer than `longestRun` carries on as another lane beside it.
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

    /// Loose notes: each on the tile it links to most (ties: the bigger
    /// tile, then by name); with no links, the biggest tile.
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

    // MARK: measuring a branch

    /// Where a lane's capsules end, out from the trunk, when its first
    /// capsule's centre is `first` out and it holds `count`.
    func laneReach(first: Double, count: Int) -> Double {
        first + Double(max(count, 1) - 1) * chain + GraphCircuit.capsuleHalf
    }

    /// How far out from its trunk a page's lanes' first capsules sit: past
    /// its ring, the ring's stem, the fan (as wide as its lanes are apart)
    /// and a tail.
    func firstCapsule(_ col: CircuitColumn) -> Double {
        let r: Double = sphere[col.head]
        let n: Int = col.branches.count
        let spread: Double = Double(max(n - 1, 0)) * 0.5 * lanePitch
        let split: Double = rung + r + r * GraphCircuit.ringTrim + GraphCircuit.stem
        return split + spread + tail + GraphCircuit.capsuleHalf
    }

    /// A branch's shape: a page's ring with its lanes above and below it, a
    /// lane of its own, or a sub-folder's block.
    func band(_ col: CircuitColumn) -> CircuitBand {
        switch col.kind {
        case 0:
            let r: Double = sphere[col.head]
            let n: Int = col.branches.count
            let height: Double = max(Double(max(n, 1)) * lanePitch, r * 2 + 0.12 * spacing)
            guard n > 0 else { return CircuitBand(height: height, tap: height * 0.5, reach: rung + r * 2) }
            var longest: Int = 1
            for b in col.branches { longest = max(longest, b.count) }
            let reach: Double = laneReach(first: firstCapsule(col), count: longest)
            return CircuitBand(height: height, tap: height * 0.5, reach: reach)
        case 1:
            let n: Int = col.branches.first?.count ?? 1
            let reach: Double = laneReach(first: rung + GraphCircuit.capsuleHalf, count: n)
            return CircuitBand(height: lanePitch, tap: lanePitch * 0.5, reach: reach)
        default:
            return blockBand(col.head)
        }
    }

    /// A sub-folder's block: its chip on the branch, its own trunk down
    /// from it with its branches all further out, and its inlay's margin
    /// all round.
    func blockBand(_ c: Int) -> CircuitBand {
        let h: Double = cHalf(c).x
        let chipOut: Double = rung + h
        var along: Double = inlayPad + h * 2
        var reach: Double = chipOut + h
        for col in columns[c] {
            let b: CircuitBand = band(col)
            along += bandGap + b.height
            reach = max(reach, chipOut + b.reach)
        }
        return CircuitBand(height: along + inlayPad, tap: inlayPad + h, reach: reach)
    }

    // MARK: laying out a tile

    /// Tile `t`, down from its source: the loose notes' prisms on the feed
    /// (alternately left and right), the chip, then its branches - each to
    /// the side with less on it, tallest first, kept in folder order on
    /// each side, the shorter side spread out to the longer's length - and
    /// the return rails just past the farthest branch on either side.
    func layOutTile(_ t: Int) -> CircuitTileLayout {
        var lay = CircuitTileLayout()
        let chip: Double = cHalf(t).x
        let source: Double = GraphCircuit.sourceSphere
        var along: Double = source + topGap
        var reach: Double = chip
        for (k, p) in padsOf[t].enumerated() {
            lay.padAlong.append(along + lanePitch * 0.5)
            lay.padSide.append(k % 2 == 0 ? -1 : 1)
            reach = max(reach, rung + half(p).x * 2)
            along += lanePitch
        }
        if !padsOf[t].isEmpty { along += bandGap * 0.5 }
        lay.chipAlong = along + chip
        let trunkTop: Double = lay.chipAlong + chip + bandGap
        let cols: [CircuitColumn] = columns[t]
        let bands: [CircuitBand] = cols.map { band($0) }
        lay.side = sides(bands)
        lay.top = stack(bands, sides: lay.side, from: trunkTop)
        var bottom: Double = lay.chipAlong + chip
        for k in cols.indices {
            reach = max(reach, bands[k].reach)
            bottom = max(bottom, lay.top[k] + bands[k].height)
        }
        lay.railX = reach + railGap
        let edge: Double = lay.railX + margin
        let low = SIMD2<Double>(-edge, -(bottom + margin))
        let high = SIMD2<Double>(edge, source + margin)
        lay.rect = CircuitRect.around(low: low, high: high)
        return lay
    }

    /// Each branch's side: tallest first, to the side with less on it.
    func sides(_ bands: [CircuitBand]) -> [Int] {
        var load: [Double] = [0, 0]
        var out = [Int](repeating: 1, count: bands.count)
        let tallest: [Int] = bands.indices.sorted { a, b in
            bands[a].height != bands[b].height ? bands[a].height > bands[b].height : a < b
        }
        for k in tallest {
            let s: Int = load[0] <= load[1] ? 0 : 1
            out[k] = s == 0 ? -1 : 1
            load[s] += bands[k].height + bandGap
        }
        return out
    }

    /// Each branch's band top, down the trunk from `from`: each side's in
    /// order, the shorter side's gaps widened so it ends near the longer;
    /// then any branch leaving the trunk within `minTap` of one on the
    /// other side moved down (with the rest of its side), so no joint is a
    /// crossing.
    func stack(_ bands: [CircuitBand], sides: [Int], from: Double) -> [Double] {
        var load: [Double] = [0, 0]
        var count: [Int] = [0, 0]
        for k in bands.indices {
            let s: Int = sides[k] < 0 ? 0 : 1
            load[s] += bands[k].height + bandGap
            count[s] += 1
        }
        let longest: Double = max(load[0], load[1])
        var gap: [Double] = [bandGap, bandGap]
        var cursor: [Double] = [from, from]
        for s in 0..<2 where count[s] > 0 && load[s] < longest {
            let extra: Double = min((longest - load[s]) / Double(count[s]), 1.2 * spacing)
            gap[s] = bandGap + extra
            cursor[s] = from + extra * 0.5
        }
        var top = [Double](repeating: 0, count: bands.count)
        for k in bands.indices {
            let s: Int = sides[k] < 0 ? 0 : 1
            top[k] = cursor[s]
            cursor[s] += bands[k].height + gap[s]
        }
        var rounds: Int = 0
        while rounds <= bands.count * bands.count + 8 {
            rounds += 1
            let order: [Int] = bands.indices.sorted { a, b in
                let ta: Double = top[a] + bands[a].tap
                let tb: Double = top[b] + bands[b].tap
                return ta != tb ? ta < tb : a < b
            }
            var moved: Bool = false
            for n in order.indices.dropFirst() {
                let a: Int = order[n - 1]
                let b: Int = order[n]
                let apart: Double = (top[b] + bands[b].tap) - (top[a] + bands[a].tap)
                guard apart < minTap - 1e-9 else { continue }
                let push: Double = minTap - apart
                let start: Double = top[b]
                for k in bands.indices where sides[k] == sides[b] && top[k] >= start { top[k] += push }
                moved = true
                break
            }
            if !moved { break }
        }
        return top
    }

    // MARK: the bench

    /// Tiles in rows, biggest first, as many abreast as makes the bench's
    /// shape as it shows (foreshortened by the tilt) closest to the
    /// phone's; each row centred, its tiles' tops in line; the whole bench
    /// centred.
    mutating func placeBench(_ tops: [Int]) {
        boardAt = [SIMD2<Double>](repeating: SIMD2<Double>(0, 0), count: tree.cCount)
        guard !tops.isEmpty else { return }
        let gap: Double = GraphCircuit.benchGap * spacing
        let widths: [Double] = tops.map { layouts[$0].rect.h.x * 2 }
        let heights: [Double] = tops.map { layouts[$0].rect.h.y * 2 }
        let widest: Double = widths.max() ?? 1
        var best: [[Int]] = [Array(tops.indices)]
        var bestMiss: Double = Double.greatestFiniteMagnitude
        let squash: Double = cos(GraphCircuit.tilt)
        for j in 0..<30 {
            let limit: Double = widest * (1 + 0.2 * Double(j)) + 0.001
            let rows: [[Int]] = Self.rows(widths, limit: limit, gap: gap)
            let size: SIMD2<Double> = Self.benchSize(rows, widths: widths, heights: heights, gap: gap)
            let shown: Double = size.x / max(size.y * squash, 0.001)
            let miss: Double = abs(log(shown / GraphCircuit.benchAspect))
            if miss < bestMiss - 1e-9 {
                best = rows
                bestMiss = miss
            }
        }
        var y: Double = 0
        for row in best {
            var rowWidth: Double = gap * Double(row.count - 1)
            var rowHeight: Double = 0
            for k in row {
                rowWidth += widths[k]
                rowHeight = max(rowHeight, heights[k])
            }
            var x: Double = -rowWidth * 0.5
            for k in row {
                let r: CircuitRect = layouts[tops[k]].rect
                boardAt[tops[k]] = SIMD2<Double>(x - r.low.x, y - r.high.y)
                x += widths[k] + gap
            }
            y -= rowHeight + gap
        }
        var rects: [CircuitRect] = []
        for t in tops { rects.append(layouts[t].rect.moved(boardAt[t])) }
        let whole: CircuitRect = CircuitRect.bounding(rects)
        for t in tops { boardAt[t] -= whole.c }
    }

    /// Tiles (by their widths, in order) in rows no wider than `limit`.
    static func rows(_ widths: [Double], limit: Double, gap: Double) -> [[Int]] {
        var out: [[Int]] = []
        var row: [Int] = []
        var used: Double = 0
        for (k, w) in widths.enumerated() {
            let more: Double = row.isEmpty ? w : used + gap + w
            if !row.isEmpty && more > limit {
                out.append(row)
                row = [k]
                used = w
            } else {
                row.append(k)
                used = more
            }
        }
        if !row.isEmpty { out.append(row) }
        return out
    }

    /// The bench's width and depth for these rows.
    static func benchSize(_ rows: [[Int]], widths: [Double], heights: [Double], gap: Double) -> SIMD2<Double> {
        var wide: Double = 0
        var deep: Double = gap * Double(max(rows.count - 1, 0))
        for row in rows {
            var w: Double = gap * Double(max(row.count - 1, 0))
            var h: Double = 0
            for k in row {
                w += widths[k]
                h = max(h, heights[k])
            }
            wide = max(wide, w)
            deep += h
        }
        return SIMD2<Double>(wide, deep)
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
                             spot: SIMD2<Double>, sphere s: Double = GraphCircuit.fixtureSphere) -> Int {
        let id: UUID = GraphCircuit.fixtureID(tree.cID(t), tag, k)
        let region: Int = cBody[t]
        return add(id: id, kind: .fixture, role: r, parent: parent, sphere: s,
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

    /// Four points round a rectangle, relative to `spot`, for a fly-in.
    func framing(_ r: CircuitRect, from spot: SIMD2<Double>) -> [SIMD3<Float>] {
        var box: [ThemeBall] = []
        for k in 0..<4 {
            let cx: Double = k % 2 == 0 ? r.low.x : r.high.x
            let cy: Double = k < 2 ? r.low.y : r.high.y
            let corner: SIMD3<Double> = GraphCircuit.world(SIMD2<Double>(cx, cy) - spot, height: 0.1)
            box.append(ThemeBall(c: corner, r: 0.06))
        }
        return ThemeLayout.points(box, around: SIMD3<Double>(0, 0, 0))
    }

    /// Tile `t`: its chip, its source and the feed down into the chip
    /// (a joint for each loose note's prism), the trunk with its branches,
    /// and the return rails closing every loop.
    mutating func emitTile(_ t: Int) {
        let lay: CircuitTileLayout = layouts[t]
        let origin: SIMD2<Double> = boardAt[t]
        railTaps = [[], []]
        let chipSpot: SIMD2<Double> = origin + SIMD2<Double>(0, -lay.chipAlong)
        let chip: Int = addChip(t, parent: -1, spot: chipSpot, board: t)
        let rect: CircuitRect = lay.rect.moved(origin)
        let rel: SIMD2<Double> = rect.c - chipSpot
        patches[chip] = SIMD4<Float>(Float(rel.x), Float(rel.y), Float(rect.h.x), Float(rect.h.y))
        systemsFor[chip] = framing(rect, from: chipSpot)
        let source: Int = addFixture(.vcc, board: t, tag: "vcc", k: 0, parent: chip, spot: origin,
                                     sphere: GraphCircuit.sourceSphere)
        var feed: Int = source
        for (k, p) in padsOf[t].enumerated() {
            let y: Double = origin.y - lay.padAlong[k]
            let joint: Int = addFixture(.bus, board: t, tag: "feed", k: k, parent: chip,
                                        spot: SIMD2<Double>(origin.x, y))
            wires.append((feed, joint))
            feed = joint
            let side: Int = lay.padSide[k]
            let out: Double = rung + half(p).x
            let spot = SIMD2<Double>(origin.x + Double(side) * out, y)
            let pad: Int = addNote(p, parent: chip, region: -1, spot: spot, board: t)
            wires.append((joint, pad))
            ground(from: pad, side: side, y: y, board: t)
        }
        wires.append((feed, chip))
        let cols: [CircuitColumn] = columns[t]
        if cols.isEmpty {
            // a chip with nothing on it still closes its loop
            ground(from: chip, side: 1, y: chipSpot.y, board: t)
        } else {
            var hanging: [CircuitHang] = []
            for k in cols.indices {
                hanging.append(CircuitHang(col: k, side: lay.side[k], top: origin.y - lay.top[k]))
            }
            emitTrunk(owner: t, ownerBody: chip, x: origin.x, hanging: hanging, board: t)
        }
        closeRails(board: t, source: source)
    }

    /// A trunk down from chip `ownerBody` (container `owner`) at `x`: a
    /// joint where each branch leaves it, top to bottom, each fed from the
    /// one above (the first from the chip), and the branches.
    mutating func emitTrunk(owner c: Int, ownerBody: Int, x: Double, hanging: [CircuitHang], board t: Int) {
        let cols: [CircuitColumn] = columns[c]
        let bands: [CircuitBand] = hanging.map { band(cols[$0.col]) }
        let order: [Int] = hanging.indices.sorted { a, b in
            let ya: Double = hanging[a].top - bands[a].tap
            let yb: Double = hanging[b].top - bands[b].tap
            return ya != yb ? ya > yb : a < b
        }
        var above: Int = ownerBody
        for (n, k) in order.enumerated() {
            let h: CircuitHang = hanging[k]
            let y: Double = h.top - bands[k].tap
            let joint: Int = addFixture(.bus, board: t, tag: "bus" + String(c), k: n, parent: ownerBody,
                                        spot: SIMD2<Double>(x, y))
            wires.append((above, joint))
            above = joint
            placeColumn(cols[h.col], side: h.side, trunkX: x, top: h.top, band: bands[k], tap: joint,
                        parentBody: ownerBody, board: t)
        }
    }

    /// A branch off the trunk at `trunkX`, its band from `top` down, fed
    /// from the joint `tap`: a page's ring with its lanes fanning out past
    /// it, a lane of capsules, or a sub-folder's chip with its inlay, its
    /// own trunk and branches.
    mutating func placeColumn(_ col: CircuitColumn, side s: Int, trunkX: Double, top: Double, band b: CircuitBand,
                              tap: Int, parentBody: Int, board t: Int) {
        let region: Int = cBody[t]
        let sd: Double = Double(s)
        switch col.kind {
        case 0:
            let r: Double = sphere[col.head]
            let y: Double = top - b.tap
            let spot = SIMD2<Double>(trunkX + sd * (rung + r), y)
            let p: Int = addNote(col.head, parent: parentBody, region: region, spot: spot, board: t)
            wires.append((tap, p))
            if col.branches.isEmpty {
                ground(from: p, side: s, y: y, board: t)
                return
            }
            let n: Int = col.branches.count
            let first: Double = trunkX + sd * firstCapsule(col)
            for (k, branch) in col.branches.enumerated() {
                let laneY: Double = y - (Double(k) - Double(n - 1) * 0.5) * lanePitch
                placeLane(branch, from: p, fromNote: col.head, x: first, y: laneY, side: s, parent: parentBody,
                          board: t)
            }
        case 1:
            let branch: [Int] = col.branches.first ?? []
            let first: Double = trunkX + sd * (rung + GraphCircuit.capsuleHalf)
            placeLane(branch, from: tap, fromNote: -1, x: first, y: top - b.tap, side: s, parent: parentBody,
                      board: t)
        default:
            placeBlock(col.head, side: s, trunkX: trunkX, top: top, band: b, tap: tap, parentBody: parentBody,
                       board: t)
        }
    }

    /// A sub-folder `k`'s block: its chip on the branch, its inlay (the
    /// block's band, from just inside the chip out to the return rail, open
    /// on that side so no lane crosses its edge), and its own trunk down
    /// from the chip with its branches, all on the same side.
    mutating func placeBlock(_ k: Int, side s: Int, trunkX: Double, top: Double, band b: CircuitBand, tap: Int,
                             parentBody: Int, board t: Int) {
        let sd: Double = Double(s)
        let h: Double = cHalf(k).x
        let chipOut: Double = rung + h
        let spot = SIMD2<Double>(trunkX + sd * chipOut, top - inlayPad - h)
        let m: Int = addChip(k, parent: parentBody, spot: spot, board: t)
        wires.append((tap, m))
        let rail: Double = boardAt[t].x + sd * layouts[t].railX
        let inner: Double = trunkX + sd * (chipOut - h - inlayPad)
        let low = SIMD2<Double>(min(inner, rail), top - b.height)
        let high = SIMD2<Double>(max(inner, rail), top)
        let inlay: CircuitRect = CircuitRect.around(low: low, high: high)
        let rel: SIMD2<Double> = inlay.c - spot
        patches[m] = SIMD4<Float>(Float(rel.x), Float(rel.y), Float(inlay.h.x), Float(inlay.h.y))
        systemsFor[m] = framing(inlay, from: spot)
        let cols: [CircuitColumn] = columns[k]
        if cols.isEmpty {
            ground(from: m, side: s, y: spot.y, board: t)
            return
        }
        var cursor: Double = top - inlayPad - h * 2
        var hanging: [CircuitHang] = []
        for (j, col) in cols.enumerated() {
            cursor -= bandGap
            hanging.append(CircuitHang(col: j, side: s, top: cursor))
            cursor -= band(col).height
        }
        emitTrunk(owner: k, ownerBody: m, x: spot.x, hanging: hanging, board: t)
    }

    /// A lane of capsules in series, out from `x` at height `y`, fed from
    /// body `from` (a ring, note `fromNote`, or a trunk's joint), ending on
    /// the return rail. Where two in a row are linked notes, their link is
    /// the wire; elsewhere the tile's own wiring joins them.
    mutating func placeLane(_ branch: [Int], from: Int, fromNote: Int, x: Double, y: Double, side s: Int,
                            parent: Int, board t: Int) {
        var along: Double = x
        var before: Int = from
        var beforeNote: Int = fromNote
        let region: Int = cBody[t]
        for i in branch {
            let b: Int = addNote(i, parent: parent, region: region, spot: SIMD2<Double>(along, y), board: t)
            if beforeNote >= 0 && linked(beforeNote, i) {
                topology.append((before, b))
            } else {
                wires.append((before, b))
            }
            before = b
            beforeNote = i
            along += Double(s) * chain
        }
        ground(from: before, side: s, y: y, board: t)
    }

    /// A joint on the return rail on side `s`, at height `y`, where the
    /// lane from `from` ends.
    mutating func ground(from: Int, side s: Int, y: Double, board t: Int) {
        let k: Int = groundCount[t, default: 0]
        groundCount[t] = k + 1
        let x: Double = boardAt[t].x + Double(s) * layouts[t].railX
        let g: Int = addFixture(.ground, board: t, tag: "gnd", k: k, parent: cBody[t], spot: SIMD2<Double>(x, y))
        wires.append((from, g))
        railTaps[s < 0 ? 0 : 1].append((y, g))
    }

    /// Each side's return rail: from its lowest joint up through the
    /// others to a corner level with the source, and in along the top.
    mutating func closeRails(board t: Int, source: Int) {
        for s in 0..<2 {
            let taps: [(Double, Int)] = railTaps[s].sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
            guard let highest = taps.last else { continue }
            for n in taps.indices.dropFirst() { rails.append((taps[n - 1].1, taps[n].1)) }
            let sd: Double = s == 0 ? -1 : 1
            let spot = SIMD2<Double>(boardAt[t].x + sd * layouts[t].railX, boardAt[t].y)
            let corner: Int = addFixture(.ground, board: t, tag: "corner", k: s, parent: cBody[t], spot: spot)
            rails.append((highest.1, corner))
            rails.append((corner, source))
        }
        railTaps = [[], []]
    }

    // MARK: between tiles

    /// Every link between two tiles: hidden as itself, drawn as a leg out
    /// to a port on its tile's edge facing the other tile, a fibre across
    /// the dark to the other tile's port and a leg in - sent from the end
    /// nearer its source. The ports of two tiles face each other square
    /// across the gap, so every fibre runs straight.
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
        var groups: [Int: [(Int, Int)]] = [:]
        var order: [Int] = []
        for (i, j) in crossing {
            let a: Int = noteBody[i]
            let b: Int = noteBody[j]
            let send: Bool = depth[a] < depth[b] || (depth[a] == depth[b] && a < b)
            let from: Int = send ? a : b
            let to: Int = send ? b : a
            let key: Int = pairKey(boardOfBody[from], boardOfBody[to])
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append((from, to))
        }
        for key in order {
            if let list = groups[key] { joinTiles(list) }
        }
    }

    /// The links between one pair of tiles, ports spread along the stretch
    /// of edge the two share (in order of where their notes are, so the
    /// fibres do not cross).
    mutating func joinTiles(_ list: [(Int, Int)]) {
        guard let firstLink = list.first else { return }
        let u: Int = min(boardOfBody[firstLink.0], boardOfBody[firstLink.1])
        let w: Int = max(boardOfBody[firstLink.0], boardOfBody[firstLink.1])
        let ru: CircuitRect = layouts[u].rect.moved(boardAt[u])
        let rw: CircuitRect = layouts[w].rect.moved(boardAt[w])
        let stacked: Bool = ru.low.y >= rw.high.y || rw.low.y >= ru.high.y
        let sorted: [(Int, Int)] = list.sorted { p, q in
            let kp: Double = stacked ? at[p.0].x + at[p.1].x : at[p.0].y + at[p.1].y
            let kq: Double = stacked ? at[q.0].x + at[q.1].x : at[q.0].y + at[q.1].y
            return kp != kq ? kp < kq : p.0 < q.0
        }
        for (k, link) in sorted.enumerated() {
            let share: Double = Double(k + 1) / Double(sorted.count + 1)
            let spots: (SIMD2<Double>, SIMD2<Double>) = portSpots(ru, rw, stacked: stacked, share: share)
            let cu: Int = addFixture(.connector, board: u, tag: "port" + String(w), k: k, parent: cBody[u],
                                     spot: spots.0)
            let cw: Int = addFixture(.connector, board: w, tag: "port" + String(u), k: k, parent: cBody[w],
                                     spot: spots.1)
            let fromU: Bool = boardOfBody[link.0] == u
            let cf: Int = fromU ? cu : cw
            let ct: Int = fromU ? cw : cu
            links.append(ThemeLink(a: link.0, b: cf, kind: 6, centre: -1))
            links.append(ThemeLink(a: cf, b: ct, kind: 6, centre: -1))
            links.append(ThemeLink(a: ct, b: link.1, kind: 6, centre: -1))
            hiddenPairs.insert(pairKey(link.0, link.1))
        }
    }

    /// A port on each of two tiles' facing edges, `share` of the way along
    /// the stretch of edge they share (or, where they share none, along
    /// each one's own edge towards the other), just inside each edge.
    func portSpots(_ ru: CircuitRect, _ rw: CircuitRect, stacked: Bool,
                   share: Double) -> (SIMD2<Double>, SIMD2<Double>) {
        let inset: Double = 0.07
        let keep: Double = 0.3
        if stacked {
            let lo: Double = max(ru.low.x, rw.low.x) + keep
            let hi: Double = min(ru.high.x, rw.high.x) - keep
            var xu: Double = lo + (hi - lo) * share
            var xw: Double = xu
            if lo > hi {
                xu = GraphUniverse.clamp(rw.c.x, ru.low.x + keep, ru.high.x - keep)
                xw = GraphUniverse.clamp(ru.c.x, rw.low.x + keep, rw.high.x - keep)
            }
            let uAbove: Bool = ru.low.y >= rw.high.y
            let yu: Double = uAbove ? ru.low.y + inset : ru.high.y - inset
            let yw: Double = uAbove ? rw.high.y - inset : rw.low.y + inset
            return (SIMD2<Double>(xu, yu), SIMD2<Double>(xw, yw))
        }
        let lo: Double = max(ru.low.y, rw.low.y) + keep
        let hi: Double = min(ru.high.y, rw.high.y) - keep
        var yu: Double = lo + (hi - lo) * share
        var yw: Double = yu
        if lo > hi {
            yu = GraphUniverse.clamp(rw.c.y, ru.low.y + keep, ru.high.y - keep)
            yw = GraphUniverse.clamp(ru.c.y, rw.low.y + keep, rw.high.y - keep)
        }
        let uLeft: Bool = ru.c.x <= rw.c.x
        let xu: Double = uLeft ? ru.high.x - inset : ru.low.x + inset
        let xw: Double = uLeft ? rw.low.x + inset : rw.high.x - inset
        return (SIMD2<Double>(xu, yu), SIMD2<Double>(xw, yw))
    }

    func pairKey(_ a: Int, _ b: Int) -> Int {
        min(a, b) * 1_000_003 + max(a, b)
    }

    // MARK: the flow

    /// Each body's steps from its tile's source along the wiring and the
    /// circuit's note links (-1: not reached). The return rails take no
    /// part.
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
        // ranks: nearer the source sends
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
        // the notes' own links: part of the circuit (0), apart from it (2),
        // or between tiles, hidden (3: drawn through the ports instead)
        var inCircuit = Set<Int>()
        for (a, b) in topology { inCircuit.insert(pairKey(a, b)) }
        var all: [ThemeLink] = []
        for (i, j) in tree.edgePairs {
            let a: Int = noteBody[i]
            let b: Int = noteBody[j]
            guard a >= 0, b >= 0 else { continue }
            var kind: Int = inCircuit.contains(pairKey(a, b)) ? 0 : 2
            if hiddenPairs.contains(pairKey(a, b)) { kind = 3 }
            all.append(ThemeLink(a: a, b: b, kind: kind, centre: -1))
        }
        for (a, b) in wires { all.append(ThemeLink(a: a, b: b, kind: 5, centre: -1)) }
        for (a, b) in rails { all.append(ThemeLink(a: a, b: b, kind: 5, centre: -1)) }
        all.append(contentsOf: links)
        var systems = [[SIMD3<Float>]](repeating: [], count: bodies.count)
        for (i, points) in systemsFor { systems[i] = points }
        var margin: [ThemeBall] = []
        for t in tops {
            let r: CircuitRect = layouts[t].rect.moved(boardAt[t])
            for k in 0..<4 {
                let cx: Double = k % 2 == 0 ? r.low.x : r.high.x
                let cy: Double = k < 2 ? r.low.y : r.high.y
                margin.append(ThemeBall(c: GraphCircuit.world(SIMD2<Double>(cx, cy), height: 0.1), r: 0.08))
            }
        }
        for b in bodies {
            let reach: Double = Double(b.sphere) * 1.3
            margin.append(ThemeBall(c: SIMD3<Double>(Double(b.home.x), Double(b.home.y), Double(b.home.z)),
                                    r: reach))
        }
        let envelope: [SIMD3<Float>] = ThemeLayout.points(margin, around: SIMD3<Double>(0, 0, 0))
        let regions: [Int] = tops.map { cBody[$0] }
        var plan = ThemePlan(bodies: bodies, links: all, envelope: envelope, systems: systems, regions: regions,
                             summary: GraphCircuit.summary(bodies))
        plan.patches = patches
        plan.feeds = feeds
        return plan
    }
}

// MARK: - The pulse of light

/// A body as the circuit's pulse of light sees it: where it rests on the
/// bench, how far along the wiring the light has come from its tile's
/// source to reach it, and what it is (GraphCircuitMap's kinds: 0 a note's
/// part, 1 a chip, 2 a joint on the feed or a trunk, 3 a joint on a return
/// rail, 4 a source, 5 a port). GraphCircuitLook makes the routes' map and
/// each part's flash from these.
nonisolated struct CircuitPulseSpot: Sendable, Equatable {
    let at: SIMD2<Double>
    let dist: Double
    let kind: Int
}

extension GraphCircuit {
    /// One pulse of light every 6 s: this far apart along the wiring (a
    /// fifth of the 64 units a link's texture coordinate steps by, so the
    /// shader can drop the seed above them), at this speed.
    static let pulseSpacing: Double = 12.8
    static let pulseSpeed: Double = 12.8 / 6.0
    /// Each tile's beat starts this share of a period after the first's,
    /// by its place on the bench, so the tiles never pulse in step.
    static let stagger: [Double] = [0, 0.37, 0.71, 0.18]

    static func pulseKind(_ role: CircuitRole) -> Int {
        switch role {
        case .processor, .module, .soc: return 1
        case .bus: return 2
        case .ground: return 3
        case .vcc: return 4
        case .connector: return 5
        default: return 0
        }
    }

    /// A body's place on the bench.
    static func onBench(_ p: SIMD3<Float>) -> SIMD2<Double> {
        let q = SIMD3<Double>(Double(p.x), Double(p.y), Double(p.z))
        let x: Double = GraphUniverse.dot(q, right)
        let y: Double = GraphUniverse.dot(q, forward)
        return SIMD2<Double>(x, y)
    }

    /// A guide's length from `p` to `q`, routed square and at 45°.
    static func routeLength(_ p: SIMD2<Double>, _ q: SIMD2<Double>) -> Double {
        let dx: Double = abs(q.x - p.x)
        let dy: Double = abs(q.y - p.y)
        let minor: Double = min(dx, dy)
        return max(dx, dy) - minor + minor * 2.0.squareRoot()
    }

    /// Every body's spot: the light's distance to it is the shortest way
    /// along the wiring (kinds 5 and 6, from their first end), the circuit's
    /// note links (from the higher rank) and the return rails, from its
    /// tile's source, plus its tile's stagger. A body the light never
    /// reaches rests at 0.
    static func pulseSpots(_ plan: ThemePlan) -> [CircuitPulseSpot] {
        let n: Int = plan.bodies.count
        var spots: [SIMD2<Double>] = []
        spots.reserveCapacity(n)
        for b in plan.bodies { spots.append(onBench(b.home)) }
        var next = [[(Int, Double)]](repeating: [], count: n)
        for l in plan.links {
            var a: Int = l.a
            var b: Int = l.b
            if l.kind == 0 {
                if plan.bodies[b].rank > plan.bodies[a].rank {
                    a = l.b
                    b = l.a
                }
            } else if l.kind != 5 && l.kind != 6 {
                continue
            }
            next[a].append((b, routeLength(spots[a], spots[b])))
        }
        var dist = [Double](repeating: Double.infinity, count: n)
        var heap = CircuitHeap()
        for (i, b) in plan.bodies.enumerated() where b.role == CircuitRole.vcc.rawValue {
            let k: Int = plan.regions.firstIndex(of: b.region) ?? 0
            dist[i] = stagger[k % stagger.count] * pulseSpacing
            heap.push(dist[i], i)
        }
        while let (d, x) = heap.pop() {
            if d > dist[x] { continue }
            for (y, w) in next[x] where d + w < dist[y] {
                dist[y] = d + w
                heap.push(dist[y], y)
            }
        }
        var out: [CircuitPulseSpot] = []
        out.reserveCapacity(n)
        for (i, b) in plan.bodies.enumerated() {
            let role: CircuitRole = CircuitRole(rawValue: b.role) ?? .led
            let d: Double = dist[i].isFinite ? dist[i] : 0
            out.append(CircuitPulseSpot(at: spots[i], dist: d, kind: pulseKind(role)))
        }
        return out
    }
}

/// A small binary heap of (distance, body), nearest first.
nonisolated struct CircuitHeap: Sendable {
    var items: [(Double, Int)] = []

    mutating func push(_ d: Double, _ i: Int) {
        items.append((d, i))
        var k: Int = items.count - 1
        while k > 0 {
            let up: Int = (k - 1) / 2
            if items[up].0 <= items[k].0 { break }
            items.swapAt(up, k)
            k = up
        }
    }

    mutating func pop() -> (Double, Int)? {
        guard let first = items.first else { return nil }
        let last: (Double, Int) = items.removeLast()
        if items.isEmpty { return first }
        items[0] = last
        var k: Int = 0
        while true {
            let l: Int = k * 2 + 1
            let r: Int = l + 1
            var m: Int = k
            if l < items.count && items[l].0 < items[m].0 { m = l }
            if r < items.count && items[r].0 < items[m].0 { m = r }
            if m == k { break }
            items.swapAt(m, k)
            k = m
        }
        return first
    }
}
