import Foundation

// The Neurons theme: the ideas' folders drawn as living cells, after the
// owner's board (glowing cells floating in a dark fluid, each soma round
// its nucleus, its processes reaching the next cell).
//
// - a top-level folder is a cell: a soma round a nucleus, floating on one
//   sheet facing the camera, the cells ordered by which way their links
//   run (senders first, receivers after);
// - a folder inside it is a part of that cell (an organelle) INSIDE the
//   soma, and a folder inside that a smaller part inside the part;
// - a note is the smallest thing: a page a vesicle, an idea a granule,
//   inside the folder that holds it;
// - insides load only when opened (UniverseInput.open): a closed cell is
//   its soma alone, an opened one shows its parts and notes, and an
//   opened part its own;
// - a note in no folder is a free cell at the edge: a receptor when it
//   has links (it sends in), a drifting cell when it has none;
// - with no folders at all, one home cell holds every note, always open.
//
// Links are the cells' own processes: one per pair of shown bodies,
// gathered from every note link between them (each end is the deepest
// shown body holding its note), none dropped. Each grows out of the
// sending side (the one with more links) as one piece with it and ends on
// the other; its strength (GraphAnatomy) sets its width, and what it
// carries (excitatory, inhibitory, modulatory) its dye.
//
// Four rules: what a body is = what the item is; size = how much is in it
// (a part always smaller than what holds it, a note smaller than any part
// beside it); place = which folder holds it; opening never moves or
// resizes anything already shown.
//
// Pure and deterministic: Foundation only, the same notes always give the
// same picture, and nothing meets: what floats inside a container stays
// inside its membrane and clear of its siblings and the nucleus however it
// drifts, and no two cells touch. Tested on Linux
// (Tests/NeuronHierarchyTests).

/// What each body is in the Neurons theme (ThemeBody.role).
nonisolated enum NeuronRole: Int, Sendable, CaseIterable {
    /// A top-level folder: a whole cell.
    case cell = 0
    /// A folder inside a cell or inside a part: an organelle inside it.
    case part = 1
    /// The one cell of a vault with no folders.
    case home = 2
    /// A page, inside the folder that holds it.
    case vesicle = 3
    /// An idea, inside the folder that holds it.
    case granule = 4
    /// A note in no folder with no links: a free cell drifting at the edge.
    case drifter = 5
    /// A note in no folder with links: a free cell at the edge, sending in.
    case receptor = 6

    /// Which end of a link sends when the ranks decide (ThemeBody.rank).
    var rank: Int {
        switch self {
        case .cell, .home: return 7
        case .part, .receptor: return 6
        case .vesicle: return 5
        case .granule: return 3
        case .drifter: return 1
        }
    }

    var isContainer: Bool { self == .cell || self == .part || self == .home }

    var isFree: Bool { self == .drifter || self == .receptor }
}

nonisolated enum GraphNeurons {
    /// What floats inside a container stays within this share of its
    /// radius (the membrane is the rest).
    static let inner: Double = 0.8
    /// A cell's nucleus, kept clear at its centre, as a share of the inner
    /// radius.
    static let nucleus: Double = 0.22
    /// The room kept between things inside a container, as a share of the
    /// inner radius: more than two wobbles, so they never meet.
    static let room: Double = 0.05
    /// How far a thing inside a container wobbles, as a share of the inner
    /// radius.
    static let wobble: Double = 0.015
    /// The most of a container's room what floats inside it fills,
    /// counting the room between things: crowded insides shrink together
    /// (sizes, room and wobble alike) to this, so they always fit.
    static let fill: Double = 0.22
    /// How far a cell on the sheet wobbles.
    static let cellDrift: Double = 0.012
    /// How far a cell's processes reach out at rest, in its radii.
    static let reach: Double = 1.9
    /// The room between neighbouring cells on the sheet, in the biggest
    /// cell's radii at a link length of 1: wide enough that two cells'
    /// dendrites never meet, however the sheet is jittered, down to 0.8
    /// of the length (0.94 * (2 + 0.8 * sheetGap) >= 2 * reach + 0.11).
    static let sheetGap: Double = 2.8
    /// The most a drift moves its body: GraphUniverse.wobble's longest
    /// diagonal for an amplitude of 1.
    static let wobbleBound: Double = 1.5653

    /// A cell's soma: bigger with more notes inside.
    static func cellSphere(count: Int) -> Double {
        GraphUniverse.clamp(0.34 + 0.035 * log2(1 + Double(count)), 0.34, 0.6)
    }

    /// A part's radius as a share of what holds it: bigger with more notes.
    static func partShare(count: Int) -> Double {
        GraphUniverse.clamp(0.22 + 0.06 * log2(1 + Double(count)), 0.22, 0.45)
    }

    /// A note's radius as a share of its folder's: a page bigger than an
    /// idea, a longer one bigger.
    static func noteShare(page: Bool, words: Int) -> Double {
        let level: Double = Double(min(GraphUniverse.level(words: words), 6))
        return page ? 0.07 + 0.003 * level : 0.05 + 0.002 * level
    }

    /// A note in no folder: a receptor bigger than a drifting cell.
    static func freeSphere(receptor: Bool, page: Bool) -> Double {
        (receptor ? 0.16 : 0.12) + (page ? 0.03 : 0)
    }

    /// How far a free cell drifts.
    static func freeDrift(receptor: Bool) -> Double {
        receptor ? 0.03 : 0.06
    }

    // MARK: planning

    static func plan(_ input: UniverseInput) -> ThemePlan {
        if input.notes.isEmpty && input.folders.isEmpty { return .empty }
        var planner = NeuronPlanner(input)
        return planner.run()
    }

    /// "2 cells, 3 parts, 12 granules, ...".
    static func summary(_ bodies: [ThemeBody]) -> String {
        var counts = [Int](repeating: 0, count: NeuronRole.allCases.count)
        for body in bodies where body.role >= 0 && body.role < counts.count { counts[body.role] += 1 }
        counts[NeuronRole.cell.rawValue] += counts[NeuronRole.home.rawValue]
        let words: [(NeuronRole, String, String)] = [
            (.cell, "cell", "cells"), (.part, "part", "parts"), (.vesicle, "vesicle", "vesicles"),
            (.granule, "granule", "granules"), (.receptor, "receptor", "receptors"),
            (.drifter, "free cell", "free cells")
        ]
        var parts: [String] = []
        for (role, one, many) in words {
            let n: Int = counts[role.rawValue]
            if n > 0 { parts.append("\(n) " + (n == 1 ? one : many)) }
        }
        return parts.joined(separator: ", ")
    }
}

/// One note link as the cells read it: GraphAnatomy's reading, or a plain
/// one where there is no anatomy.
nonisolated struct NeuronNoteLink: Sendable, Equatable {
    let from: Int
    let to: Int
    let strength: Int
    let kind: FiberKind
}

/// Something floating inside a container: a part (a container index) or a
/// note (a note index), its radius, and where it floats relative to the
/// container's centre.
nonisolated struct NeuronItem: Sendable {
    let container: Int
    let note: Int
    var radius: Double
    var at: SIMD3<Double> = SIMD3<Double>(0, 0, 0)

    var isPart: Bool { container >= 0 }
}

/// The plan's working state. Reuses the Universe planner's tree: folders
/// (a cycle cut, a missing parent made top level), each note's container,
/// counts and links.
nonisolated struct NeuronPlanner: Sendable {
    var tree: UniversePlanner
    /// Whether each container shows (a top-level one, or one inside an
    /// opened one), and whether it is opened.
    var shown: [Bool] = []
    var opened: [Bool] = []
    /// Every note link, read once.
    var noteLinks: [NeuronNoteLink] = []
    /// How strongly each top-level container's notes link to each other
    /// one's, and how much more it sends than it receives.
    var sends: [[Int: Int]] = []
    var score: [Int] = []
    /// The top-level containers in the sheet's order.
    var tops: [Int] = []
    /// The biggest cell on the sheet, and the room between neighbours.
    var biggest: Double = 0
    var gap: Double = 0
    /// Each container's radius (once known) and a top cell's place.
    var cSphere: [Double] = []
    var cWorld: [SIMD3<Double>] = []
    /// The notes each container holds itself.
    var notesIn: [[Int]] = []
    /// The free cells' room, for the framing.
    var looseBalls: [ThemeBall] = []
    // the output
    var bodies: [ThemeBody] = []
    var noteBody: [Int] = []
    var cBody: [Int] = []
    var systems: [[SIMD3<Float>]] = []

    init(_ input: UniverseInput) {
        tree = UniversePlanner(input)
    }

    mutating func run() -> ThemePlan {
        tree.buildTree()
        tree.buildLinks()
        readLinks()
        markShown()
        readFlow()
        orderTops()
        placeTops()
        notesIn = [[Int]](repeating: [], count: tree.cCount)
        for (i, home) in tree.noteHome.enumerated() where home >= 0 { notesIn[home].append(i) }
        noteBody = [Int](repeating: -1, count: tree.noteList.count)
        cBody = [Int](repeating: -1, count: tree.cCount)
        for c in tops { emitTop(c) }
        let regions: [Int] = tops.map { cBody[$0] }
        placeLoose()
        var balls: [ThemeBall] = []
        for c in tops { balls.append(ThemeBall(c: cWorld[c], r: topReach(c) + 0.1)) }
        for ball in looseBalls { balls.append(ThemeBall(c: ball.c, r: ball.r + 0.1)) }
        let envelope: [SIMD3<Float>] = ThemeLayout.points(balls, around: SIMD3<Double>(0, 0, 0))
        return ThemePlan(bodies: bodies, links: processes(), envelope: envelope, systems: systems,
                         regions: regions, summary: GraphNeurons.summary(bodies))
    }

    // MARK: reading

    /// Every link between two notes, each way it runs: as GraphAnatomy
    /// reads it when both notes are in the anatomy, else (or when it reads
    /// none) a plain excitatory link of strength 4 each way the vault has.
    mutating func readLinks() {
        var anatomy: [UUID: AnatomyNote] = [:]
        if let notes = tree.input.anatomy?.notes {
            for note in notes { anatomy[note.id] = note }
        }
        let n: Int = tree.noteList.count
        var index: [UUID: Int] = [:]
        for (i, note) in tree.noteList.enumerated() { index[note.id] = i }
        var ways = Set<Int>()
        for edge in tree.input.edges {
            guard let i = index[edge.a], let j = index[edge.b], i != j else { continue }
            ways.insert(i * n + j)
        }
        noteLinks = []
        for (i, j) in tree.edgePairs {
            var read: Int = 0
            if let a = anatomy[tree.noteList[i].id], let b = anatomy[tree.noteList[j].id] {
                if let link = GraphAnatomy.link(a, b) {
                    noteLinks.append(NeuronNoteLink(from: i, to: j, strength: link.strength, kind: link.kind))
                    read += 1
                }
                if let link = GraphAnatomy.link(b, a) {
                    noteLinks.append(NeuronNoteLink(from: j, to: i, strength: link.strength, kind: link.kind))
                    read += 1
                }
            }
            guard read == 0 else { continue }
            if ways.contains(i * n + j) {
                noteLinks.append(NeuronNoteLink(from: i, to: j, strength: 4, kind: .excitatory))
            }
            if ways.contains(j * n + i) {
                noteLinks.append(NeuronNoteLink(from: j, to: i, strength: 4, kind: .excitatory))
            }
        }
    }

    /// A container shows when it is top level or inside an opened one, and
    /// opens when it shows and its folder is in UniverseInput.open (the
    /// home cell of a vault with no folders is always open: it is the
    /// vault).
    mutating func markShown() {
        let wanted = Set<UUID>(tree.input.open)
        shown = [Bool](repeating: false, count: tree.cCount)
        opened = [Bool](repeating: false, count: tree.cCount)
        let outerFirst: [Int] = (0..<tree.cCount).sorted { tree.depth[$0] < tree.depth[$1] }
        for c in outerFirst {
            let p: Int = tree.parent[c]
            shown[c] = p < 0 || (shown[p] && opened[p])
            opened[c] = shown[c] && (!tree.hasFolders || wanted.contains(tree.cID(c)))
        }
    }

    /// How the top-level containers link to each other, whatever is open.
    mutating func readFlow() {
        sends = [[Int: Int]](repeating: [:], count: tree.cCount)
        score = [Int](repeating: 0, count: tree.cCount)
        for link in noteLinks {
            let a: Int = tree.noteHome[link.from]
            let b: Int = tree.noteHome[link.to]
            guard a >= 0, b >= 0 else { continue }
            let ta: Int = tree.top[a]
            let tb: Int = tree.top[b]
            guard ta != tb else { continue }
            sends[ta][tb, default: 0] += link.strength
            score[ta] += link.strength
            score[tb] -= link.strength
        }
    }

    // MARK: the sheet

    /// Senders first, then by size, then by name.
    mutating func orderTops() {
        tops = (0..<tree.cCount).filter { tree.parent[$0] < 0 }
        tops.sort { a, b in
            if score[a] != score[b] { return score[a] > score[b] }
            if tree.count[a] != tree.count[b] { return tree.count[a] > tree.count[b] }
            return tree.lessC(a, b)
        }
    }

    /// The cells in rows facing the camera, read like text that snakes
    /// back on every other row, a partial last row centred, each row
    /// nudged sideways and each cell jittered a little (all in the pitch,
    /// so the whole sheet grows with the link length), and a little depth.
    mutating func placeTops() {
        cSphere = [Double](repeating: 0, count: tree.cCount)
        cWorld = [SIMD3<Double>](repeating: SIMD3<Double>(0, 0, 0), count: tree.cCount)
        biggest = 0
        for c in tops {
            cSphere[c] = GraphNeurons.cellSphere(count: tree.count[c])
            biggest = max(biggest, cSphere[c])
        }
        gap = GraphNeurons.sheetGap * biggest * tree.input.spacing
        let pitch: Double = 2 * biggest + gap
        let n: Int = tops.count
        let cols: Int = n <= 2 ? 1 : (n <= 6 ? 2 : max(3, Int((Double(n) * 0.5).squareRoot().rounded(.up))))
        let rows: Int = (n + cols - 1) / cols
        for (k, c) in tops.enumerated() {
            let row: Int = k / cols
            let inRow: Int = min(cols, n - row * cols)
            var col: Int = k % cols
            if row % 2 == 1 { col = inRow - 1 - col }
            var random = UniverseRandom(tree.cSeed(c) ^ 0x5EE7)
            var x: Double = Double(col) - Double(inRow - 1) * 0.5
            if rows > 1 { x += row % 2 == 0 ? 0.18 : -0.18 }
            x += random.signed() * 0.03
            let y: Double = Double(rows - 1) * 0.5 - Double(row) + random.signed() * 0.03
            let z: Double = random.signed() * 0.3 * biggest
            cWorld[c] = SIMD3<Double>(x * pitch, y * pitch, z)
        }
    }

    /// How far a top cell's processes reach, drifting.
    func topReach(_ c: Int) -> Double {
        cSphere[c] * GraphNeurons.reach + GraphNeurons.cellDrift * GraphNeurons.wobbleBound
    }

    /// A top cell faces the cell it sends to most, else down the sheet.
    func topAxis(_ c: Int) -> SIMD3<Double> {
        var best: Int = -1
        var most: Int = 0
        for (t, s) in sends[c] where s > most || (s == most && best >= 0 && tree.lessC(t, best)) {
            best = t
            most = s
        }
        guard best >= 0 else { return SIMD3<Double>(0, -1, 0) }
        let d: SIMD3<Double> = GraphUniverse.normalize(cWorld[best] - cWorld[c])
        return GraphUniverse.length(d) > 0.5 ? d : SIMD3<Double>(0, -1, 0)
    }

    // MARK: the bodies

    /// A top-level container: a cell on the sheet, floating in place.
    mutating func emitTop(_ c: Int) {
        var random = UniverseRandom(tree.cSeed(c) ^ 0xD81F)
        let phase = Float(2 * Double.pi * random.unit())
        let rate = Float(0.12 + 0.08 * random.unit())
        let orbit: GraphOrbit = .drift(base: GraphUniverse.float3(cWorld[c]), amp: Float(GraphNeurons.cellDrift),
                                       phase: phase, rate: rate)
        emitContainer(c, radius: cSphere[c], parent: -1, region: -1, orbit: orbit, axis: topAxis(c))
    }

    /// A container's body, then (when it is opened) what floats inside it:
    /// its parts first, each with its own insides, then its notes.
    mutating func emitContainer(_ c: Int, radius: Double, parent: Int, region: Int, orbit: GraphOrbit,
                                axis: SIMD3<Double>) {
        let role: NeuronRole = !tree.hasFolders ? .home : (tree.depth[c] == 0 ? .cell : .part)
        let index: Int = bodies.count
        let base: SIMD3<Float> = parent >= 0 ? bodies[parent].home : SIMD3<Float>(0, 0, 0)
        let mine: Int = region >= 0 ? region : index
        bodies.append(ThemeBody(id: tree.cID(c), kind: role == .home ? .home : .folder, role: role.rawValue,
                                parent: parent, sphere: Float(radius), depth: tree.depth[c], region: mine,
                                count: tree.count[c], links: 0, words: 0, rank: role.rank, seed: tree.cSeed(c),
                                orbit: orbit, home: base + GraphUniverse.offset(orbit, time: 0),
                                axis: GraphUniverse.float3(axis), title: tree.cName(c),
                                label: UniversePlanner.folderLabel(tree.cName(c), count: tree.count[c])))
        cBody[c] = index
        cSphere[c] = radius
        systems.append(ThemeLayout.points([ThemeBall(c: SIMD3<Double>(0, 0, 0), r: radius * 1.1)],
                                          around: SIMD3<Double>(0, 0, 0)))
        guard opened[c] else { return }
        let inside: (items: [NeuronItem], amp: Double) = pack(c, radius: radius)
        let amp = Float(inside.amp)
        for item in inside.items where item.isPart {
            let k: Int = item.container
            emitContainer(k, radius: item.radius, parent: index, region: mine,
                          orbit: drift(item.at, amp: amp, seed: tree.cSeed(k)), axis: outward(item.at))
        }
        for item in inside.items where !item.isPart {
            let i: Int = item.note
            let role: NeuronRole = tree.noteList[i].isPage ? .vesicle : .granule
            emitNote(i, role: role, radius: item.radius, parent: index, region: mine,
                     orbit: drift(item.at, amp: amp, seed: tree.nSeed(i)), axis: outward(item.at))
        }
    }

    /// A note's body: inside its folder, or free at the edge.
    mutating func emitNote(_ i: Int, role: NeuronRole, radius: Double, parent: Int, region: Int, orbit: GraphOrbit,
                           axis: SIMD3<Double>) {
        let note: UniverseNote = tree.noteList[i]
        let base: SIMD3<Float> = parent >= 0 ? bodies[parent].home : SIMD3<Float>(0, 0, 0)
        noteBody[i] = bodies.count
        bodies.append(ThemeBody(id: note.id, kind: .note, role: role.rawValue, parent: parent, sphere: Float(radius),
                                depth: -1, region: region, count: 0, links: tree.nbr[i].count, words: note.words,
                                rank: role.rank, seed: tree.nSeed(i), orbit: orbit,
                                home: base + GraphUniverse.offset(orbit, time: 0), axis: GraphUniverse.float3(axis),
                                title: note.title, label: UniversePlanner.noteLabel(note.title)))
        systems.append([])
    }

    /// A slow wobble round a place.
    func drift(_ at: SIMD3<Double>, amp: Float, seed: UInt64) -> GraphOrbit {
        var random = UniverseRandom(seed ^ 0xF1A7)
        let phase = Float(2 * Double.pi * random.unit())
        let rate = Float(0.15 + 0.1 * random.unit())
        return .drift(base: GraphUniverse.float3(at), amp: amp, phase: phase, rate: rate)
    }

    /// Away from a container's centre (up from the centre itself).
    func outward(_ at: SIMD3<Double>) -> SIMD3<Double> {
        GraphUniverse.length(at) > 1e-12 ? GraphUniverse.normalize(at) : SIMD3<Double>(0, 1, 0)
    }

    // MARK: inside a container

    /// Where everything inside a container floats: its parts and its notes,
    /// biggest first, each at the first of a fixed run of random places in
    /// the room inside the membrane that keeps clear of the nucleus and of
    /// everything already placed by the room between them (more than both
    /// wobbles, so they never meet). Crowded insides shrink together,
    /// sizes, room and wobble alike, until they fit. Returns them and the
    /// wobble.
    func pack(_ c: Int, radius: Double) -> (items: [NeuronItem], amp: Double) {
        var items: [NeuronItem] = []
        for k in tree.kids[c] {
            items.append(NeuronItem(container: k, note: -1,
                                    radius: GraphNeurons.partShare(count: tree.count[k]) * radius))
        }
        for i in notesIn[c] {
            let note: UniverseNote = tree.noteList[i]
            items.append(NeuronItem(container: -1, note: i,
                                    radius: GraphNeurons.noteShare(page: note.isPage, words: note.words) * radius))
        }
        guard !items.isEmpty else { return ([], 0) }
        items.sort { a, b in
            if a.radius != b.radius { return a.radius > b.radius }
            if a.isPart != b.isPart { return a.isPart }
            return a.isPart ? tree.lessC(a.container, b.container) : tree.lessN(a.note, b.note)
        }
        let room: Double = GraphNeurons.inner * radius
        let core: Double = tree.depth[c] == 0 ? GraphNeurons.nucleus * room : 0
        let gap: Double = GraphNeurons.room * room
        let amp: Double = GraphNeurons.wobble * room
        let sway: Double = amp * GraphNeurons.wobbleBound
        // start within the fill, with the biggest fitting beside the
        // nucleus (or alone) and the two biggest side by side
        var need: Double = 0
        for item in items { need += pow(item.radius + gap * 0.5, 3) }
        var scale: Double = min(1, cbrt(GraphNeurons.fill * (pow(room, 3) - pow(core, 3)) / need))
        let r1: Double = items[0].radius
        scale = min(scale, core > 0 ? (room - core) / (2 * r1 + gap + sway) : room / (r1 + sway))
        if items.count > 1 {
            scale = min(scale, 2 * room / (2 * (r1 + items[1].radius) + gap + 2 * sway))
        }
        var random = UniverseRandom(tree.cSeed(c) ^ 0xC0FF_EE11)
        let m: Int = max(600, 16 * items.count)
        var spots: [SIMD3<Double>] = []
        spots.reserveCapacity(m)
        while spots.count < m {
            let p = SIMD3<Double>(random.signed(), random.signed(), random.signed())
            if GraphUniverse.dot(p, p) <= 1 { spots.append(p) }
        }
        for _ in 0..<80 {
            if let placed = NeuronPlanner.place(items, spots: spots, room: room, core: core, gap: gap * scale,
                                                sway: sway * scale, scale: scale) {
                return (placed, amp * scale)
            }
            scale *= 0.85
        }
        // not reached: long before this everything is small enough to fit
        return (items.map { NeuronItem(container: $0.container, note: $0.note, radius: 0) }, 0)
    }

    /// One try at placing `items` at `scale`: each at the first spot after
    /// the last one taken that is clear; nil when one finds none.
    static func place(_ items: [NeuronItem], spots: [SIMD3<Double>], room: Double, core: Double, gap: Double,
                      sway: Double, scale: Double) -> [NeuronItem]? {
        var placed: [ThemeBall] = core > 0 ? [ThemeBall(c: SIMD3<Double>(0, 0, 0), r: core)] : []
        placed.reserveCapacity(items.count + 1)
        var out: [NeuronItem] = []
        out.reserveCapacity(items.count)
        var next: Int = 0
        for item in items {
            let r: Double = item.radius * scale
            let reach: Double = room - r - sway
            guard reach >= 0 else { return nil }
            var j: Int = next
            while j < spots.count && clearance(spots[j] * reach, r, placed, gap: gap) < 0 { j += 1 }
            guard j < spots.count else { return nil }
            let at: SIMD3<Double> = spots[j] * reach
            placed.append(ThemeBall(c: at, r: r))
            out.append(NeuronItem(container: item.container, note: item.note, radius: r, at: at))
            next = j + 1
        }
        return out
    }

    /// How far a ball at p of radius r keeps clear of every placed ball
    /// beyond the gap: below 0 it is too close (it stops at the first).
    static func clearance(_ p: SIMD3<Double>, _ r: Double, _ placed: [ThemeBall], gap: Double) -> Double {
        var least: Double = .infinity
        for ball in placed {
            let d: SIMD3<Double> = p - ball.c
            let clear: Double = GraphUniverse.dot(d, d).squareRoot() - r - ball.r - gap
            if clear < 0 { return clear }
            least = min(least, clear)
        }
        return least
    }

    // MARK: free cells

    /// The notes in no folder: free cells round the sheet's edge, a
    /// receptor out beyond the cell it links to most (receptors facing
    /// one cell fanned either side), the rest spread round the edge, each
    /// slid outward until it clears everything placed.
    mutating func placeLoose() {
        let loose: [Int] = (0..<tree.noteList.count).filter { tree.noteHome[$0] < 0 }.sorted { tree.lessN($0, $1) }
        guard !loose.isEmpty else { return }
        var placed: [ThemeBall] = tops.map { ThemeBall(c: cWorld[$0], r: topReach($0)) }
        var low = SIMD3<Double>(0, 0, 0)
        var high = SIMD3<Double>(0, 0, 0)
        if let first = placed.first {
            low = first.c - SIMD3<Double>(repeating: first.r)
            high = first.c + SIMD3<Double>(repeating: first.r)
        }
        for ball in placed {
            low = pointwiseMin(low, ball.c - SIMD3<Double>(repeating: ball.r))
            high = pointwiseMax(high, ball.c + SIMD3<Double>(repeating: ball.r))
        }
        let centre: SIMD3<Double> = (low + high) * 0.5
        let half: SIMD3<Double> = (high - low) * 0.5
        let margin: Double = 0.5 * max(biggest, GraphNeurons.cellSphere(count: 0)) * tree.input.spacing
        let ax: Double = half.x * 2.0.squareRoot() + margin
        let ay: Double = half.y * 2.0.squareRoot() + margin
        var facing: [Int: Int] = [:]
        for (k, i) in loose.enumerated() {
            let receptor: Bool = !tree.nbr[i].isEmpty
            var angle: Double = 0.5 + GraphUniverse.golden * Double(k)
            let toward: Int = receptor ? favouriteTop(i) : -1
            if toward >= 0 {
                // out beyond that cell (fanned), unless it is the sheet's
                // middle: then round it like the rest, still facing it
                let d: SIMD3<Double> = cWorld[toward] - centre
                if d.x * d.x + d.y * d.y > 1e-6 {
                    let j: Int = facing[toward, default: 0]
                    facing[toward] = j + 1
                    angle = atan2(d.y / ay, d.x / ax) + 0.35 * Double((j + 1) / 2) * (j % 2 == 0 ? 1 : -1)
                }
            }
            let sphere: Double = GraphNeurons.freeSphere(receptor: receptor, page: tree.noteList[i].isPage)
            let amp: Double = GraphNeurons.freeDrift(receptor: receptor)
            let reach: Double = sphere * (receptor ? GraphNeurons.reach : 1.15) + amp * GraphNeurons.wobbleBound
            var random = UniverseRandom(tree.nSeed(i) ^ 0x10C5)
            let flat = SIMD3<Double>(ax * cos(angle), ay * sin(angle), 0)
            let start: SIMD3<Double> = centre + flat + SIMD3<Double>(0, 0, random.signed() * 0.15)
            var out: SIMD3<Double> = GraphUniverse.normalize(flat)
            if GraphUniverse.length(out) < 0.5 { out = SIMD3<Double>(1, 0, 0) }
            let s: Double = ThemeLayout.slide([ThemeBall(c: start, r: reach)], along: out, start: 0, step: 0.04,
                                              placed: placed, gap: 0.04)
            let at: SIMD3<Double> = start + out * s
            placed.append(ThemeBall(c: at, r: reach))
            looseBalls.append(ThemeBall(c: at, r: reach))
            var axis: SIMD3<Double> = out
            if toward >= 0 {
                let d: SIMD3<Double> = GraphUniverse.normalize(cWorld[toward] - at)
                if GraphUniverse.length(d) > 0.5 { axis = d }
            }
            emitNote(i, role: receptor ? .receptor : .drifter, radius: sphere, parent: -1, region: -1,
                     orbit: drift(at, amp: Float(amp), seed: tree.nSeed(i)), axis: axis)
        }
    }

    /// The top cell a free note links to most (both ways), or -1.
    func favouriteTop(_ i: Int) -> Int {
        var with: [Int: Int] = [:]
        for link in noteLinks where link.from == i || link.to == i {
            let other: Int = link.from == i ? link.to : link.from
            let home: Int = tree.noteHome[other]
            guard home >= 0 else { continue }
            with[tree.top[home], default: 0] += link.strength
        }
        var best: Int = -1
        var most: Int = 0
        for (t, s) in with where s > most || (s == most && best >= 0 && tree.lessC(t, best)) {
            best = t
            most = s
        }
        return best
    }

    // MARK: processes

    /// The cells' processes: one per pair of shown bodies with note links
    /// between them, gathered from every note link (each end the deepest
    /// shown body holding its note), none dropped. It runs from the side
    /// with more links (ties by name); its strength is the links' mean
    /// strength plus a little for how many, and its dye the kind most of
    /// their strength carries.
    func processes() -> [ThemeLink] {
        struct Pair: Hashable {
            let a: Int
            let b: Int
        }
        var forward: [Pair: [NeuronNoteLink]] = [:]
        var backward: [Pair: [NeuronNoteLink]] = [:]
        for link in noteLinks {
            let x: Int = shownBody(link.from)
            let y: Int = shownBody(link.to)
            guard x >= 0, y >= 0, x != y else { continue }
            if x < y {
                forward[Pair(a: x, b: y), default: []].append(link)
            } else {
                backward[Pair(a: y, b: x), default: []].append(link)
            }
        }
        let keys: [Pair] = Set(forward.keys).union(backward.keys).sorted { $0.a != $1.a ? $0.a < $1.a : $0.b < $1.b }
        var out: [ThemeLink] = []
        out.reserveCapacity(keys.count)
        for key in keys {
            let ab: [NeuronNoteLink] = forward[key] ?? []
            let ba: [NeuronNoteLink] = backward[key] ?? []
            let sends: Bool = ab.count != ba.count ? ab.count > ba.count : lessBody(key.a, key.b)
            let all: [NeuronNoteLink] = ab + ba
            var total: Int = 0
            var weight: [Int] = [0, 0, 0]
            for link in all {
                total += link.strength
                weight[link.kind.rawValue] += link.strength
            }
            let mean: Double = Double(total) / Double(all.count)
            let strength = Int(GraphUniverse.clamp((mean + log2(Double(all.count))).rounded(), 1, 10))
            var kind: FiberKind = .excitatory
            if weight[1] > weight[0] && weight[1] >= weight[2] {
                kind = .inhibitory
            } else if weight[2] > weight[0] && weight[2] > weight[1] {
                kind = .modulatory
            }
            let from: Int = sends ? key.a : key.b
            let to: Int = sends ? key.b : key.a
            let inside: Bool = bodies[from].region >= 0 && bodies[from].region == bodies[to].region
            out.append(ThemeLink(a: from, b: to, kind: inside ? 5 : 6, centre: -1, tag: kind.rawValue,
                                 width: Float(0.55 + 0.12 * Double(strength))))
        }
        return out
    }

    /// The deepest shown body holding note i: its own when its folder is
    /// opened, else its folder's (or the closed one round that).
    func shownBody(_ i: Int) -> Int {
        if noteBody[i] >= 0 { return noteBody[i] }
        var c: Int = tree.noteHome[i]
        var steps: Int = 0
        while c >= 0 && cBody[c] < 0 && steps <= tree.cCount {
            c = tree.parent[c]
            steps += 1
        }
        return c >= 0 ? cBody[c] : -1
    }

    /// Bodies by name, then id.
    func lessBody(_ x: Int, _ y: Int) -> Bool {
        (bodies[x].title.lowercased(), bodies[x].id.uuidString) < (bodies[y].title.lowercased(), bodies[y].id.uuidString)
    }
}
