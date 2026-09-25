import Foundation

// The Neurons theme: the ideas' own hierarchy drawn as a nervous system,
// laid out the way a descending pathway runs - from the brain outward.
//
// - the whole vault is the central nervous system;
// - a top-level folder is a brain region: a big pyramidal cell (an upper
//   motor neuron, like the motor cortex's Betz cells) at the heart of a
//   cluster of its notes;
// - a folder inside a folder is the next relay down one real descending
//   chain, the central autonomic pathway: a brainstem nucleus one level
//   down (as the rostral ventrolateral medulla relays the hypothalamus and
//   cortex), then a spinal cord neuron (the lateral horn's preganglionic
//   cell), then an autonomic ganglion (the postganglionic cell that
//   reaches the organ); deeper folders stay ganglion cells. Each stands
//   out along its region's outward axis, so region -> relay -> relay reads
//   like brain -> brainstem -> spinal cord -> ganglion -> organ;
// - a page is a large multipolar neuron (bigger is longer, its dendrites
//   richer), an idea a small interneuron;
// - a short idea linked only to the note it sits with is a glial cell (an
//   astrocyte) hugging that neuron;
// - an idea linking notes in two or more other folders is a commissural
//   neuron, its long fibres crossing like the corpus callosum's;
// - a note in no folder floats at the periphery: a sensory receptor when
//   it has links (it sends impulses in), a microglial cell when it has
//   none, drifting on patrol;
// - with no folders at all, one brainstem cell holds every note.
//
// Links are axons: inside a cluster short local fibres, between clusters
// of one region projection fibres, between regions long tracts; and every
// folder is wired to the folders inside it by its pathway tract. Impulses
// run from the sending end (the higher rank: regions and relays send down
// the pathway, receptors send in) to the receiving one.
//
// Four rules, as in the Universe: what a cell is = what the item is; size
// = how much is in it (every container bigger than every note, a folder
// always smaller than the one it sits in, pages bigger than ideas, glia
// smallest); position = which folder holds it; the pathway runs outward.
//
// Pure and deterministic: Foundation only, the same notes always give the
// same picture, and no two cells' reach overlaps (ThemeLayout slides each
// into the first clear place). Tested on Linux (Tests/NeuronHierarchyTests).

nonisolated enum NeuronRole: Int, Sendable, CaseIterable {
    /// A top-level folder: a brain region's pyramidal hub.
    case region = 0
    /// A folder inside a folder: a relay neuron down the pathway.
    case relay = 1
    /// The one container of a vault with no folders.
    case brainstem = 2
    /// A page: a large multipolar neuron.
    case pyramidal = 3
    /// An idea: a small interneuron.
    case interneuron = 4
    /// A short idea linked only to the note it hugs: an astrocyte.
    case glia = 5
    /// An idea linking notes in two or more other folders.
    case commissural = 6
    /// A loose note with links: a sensory receptor at the periphery.
    case receptor = 7
    /// A loose note with no links: a microglial cell drifting on patrol.
    case microglia = 8

    /// Which end of a link sends: regions and relays down the pathway,
    /// receptors inward, neurons to interneurons, never glia.
    var rank: Int {
        switch self {
        case .region, .brainstem: return 7
        case .relay, .receptor: return 6
        case .pyramidal: return 5
        case .commissural: return 4
        case .interneuron: return 3
        case .glia: return 2
        case .microglia: return 1
        }
    }

    /// How far its dendrites reach, in sizes: what must stay clear.
    var reach: Double {
        switch self {
        case .region, .relay, .brainstem: return 2.1
        case .pyramidal: return 2.3
        case .interneuron, .receptor: return 1.9
        case .commissural: return 2.0
        case .glia: return 1.5
        case .microglia: return 1.8
        }
    }

    var isContainer: Bool {
        self == .region || self == .relay || self == .brainstem
    }
}

nonisolated enum GraphNeurons {
    /// Room left between two cells' reaches.
    static let gap: Double = 0.03
    /// How far a glial cell sits off its neuron's membrane.
    static let hug: Double = 0.012

    // MARK: sizes (the ladder)

    /// A page: 0.14 to 0.228 by length.
    static func pageSphere(words: Int) -> Double {
        let lv: Int = min(GraphUniverse.level(words: words), 8)
        return 0.14 + 0.011 * Double(lv)
    }

    /// An idea: 0.085 to 0.115 by length.
    static func ideaSphere(words: Int) -> Double {
        let lv: Int = min(GraphUniverse.level(words: words), 6)
        return 0.085 + 0.005 * Double(lv)
    }

    /// A commissural neuron: just above the biggest idea, under any page.
    static let commissuralSphere: Double = 0.12

    /// A glial cell: 0.05 to 0.058.
    static func gliaSphere(words: Int) -> Double {
        let lv: Int = min(GraphUniverse.level(words: words), 2)
        return 0.05 + 0.004 * Double(lv)
    }

    /// A region: 0.40 to 0.54 by how many notes it holds.
    static func regionSphere(count: Int) -> Double {
        guard count > 0 else { return 0.40 }
        let size: Double = log2(1 + Double(count))
        return GraphUniverse.clamp(0.40 + 0.02 * size, 0.40, 0.54)
    }

    /// The smallest a relay at depth `d` is drawn: 0.31, 0.28, 0.27, ...,
    /// falling with every level and always above the biggest page.
    static func relayFloor(_ d: Int) -> Double {
        0.25 + 0.06 / Double(max(d, 1))
    }

    /// A relay: by how many notes it holds, always a little smaller than
    /// the container it sits in.
    static func relaySphere(count: Int, depth: Int, parent: Double) -> Double {
        let size: Double = log2(1 + Double(count))
        let own: Double = GraphUniverse.clamp(0.29 + 0.012 * size, 0.29, 0.37)
        return max(min(own, parent * 0.9), relayFloor(depth))
    }

    static let brainstemSphere: Double = 0.44

    // MARK: planning

    static func plan(_ input: UniverseInput) -> ThemePlan {
        if input.notes.isEmpty && input.folders.isEmpty { return .empty }
        var planner = NeuronPlanner(input)
        return planner.run()
    }

    /// "2 regions, 3 relays, 12 neurons, ...".
    static func summary(_ bodies: [ThemeBody]) -> String {
        var counts = [Int](repeating: 0, count: NeuronRole.allCases.count)
        for body in bodies where body.role >= 0 && body.role < counts.count { counts[body.role] += 1 }
        let words: [(NeuronRole, String, String)] = [
            (.region, "region", "regions"), (.brainstem, "brainstem", "brainstems"), (.relay, "relay", "relays"),
            (.pyramidal, "neuron", "neurons"), (.interneuron, "interneuron", "interneurons"),
            (.glia, "glial cell", "glia"), (.commissural, "commissural neuron", "commissural neurons"),
            (.receptor, "receptor", "receptors"), (.microglia, "microglial cell", "microglia")
        ]
        var parts: [String] = []
        for (role, one, many) in words {
            let n: Int = counts[role.rawValue]
            if n > 0 { parts.append("\(n) " + (n == 1 ? one : many)) }
        }
        return parts.joined(separator: ", ")
    }
}

/// One container's own layout, in its own frame (it at the origin, its
/// pathway along +x): where its notes sit, where each folder inside it
/// stands and how that one is turned, and every ball its whole subtree
/// needs kept clear.
nonisolated struct NeuronLocal: Sendable {
    var members: [(Int, SIMD3<Double>)] = []
    var children: [(Int, SIMD3<Double>, UniverseFrame)] = []
    var balls: [ThemeBall] = []
}

/// The plan's working state. Reuses the Universe planner's tree: folders
/// (a cycle cut, a missing parent made top level), each note's container,
/// counts and links.
nonisolated struct NeuronPlanner: Sendable {
    var tree: UniversePlanner
    var role: [NeuronRole] = []
    var sphere: [Double] = []
    var cSphere: [Double] = []
    var gliaOf: [[Int]] = []
    var gliaHost: [Int] = []
    var local: [NeuronLocal] = []
    // the output
    var bodies: [ThemeBody] = []
    var noteBody: [Int] = []
    var cBody: [Int] = []
    var cWorld: [SIMD3<Double>] = []
    var cFrame: [UniverseFrame] = []
    var worldBalls: [[ThemeBall]] = []

    init(_ input: UniverseInput) {
        tree = UniversePlanner(input)
    }

    var noteCount: Int { tree.noteList.count }

    /// The room left between two cells' reaches: GraphNeurons.gap, less
    /// with shorter links (never none).
    var gap: Double {
        GraphNeurons.gap * (0.4 + 0.6 * tree.tight)
    }

    /// ThemeLayout.slide; with shorter links, then brought back to just
    /// clear (the slide's steps otherwise leave up to a step of room).
    func settle(_ group: [ThemeBall], along dir: SIMD3<Double>, start: Double, step: Double,
                placed: [ThemeBall], gap: Double) -> Double {
        let s: Double = ThemeLayout.slide(group, along: dir, start: start, step: step, placed: placed, gap: gap)
        guard tree.tight < 1, s > start else { return s }
        let whole: ThemeBall = ThemeLayout.enclosing(group)
        var low: Double = max(start, s - step)
        var high: Double = s
        for _ in 0..<8 {
            let mid: Double = (low + high) * 0.5
            let shift: SIMD3<Double> = dir * mid
            if ThemeLayout.fits(group, whole: whole, shift: shift, placed: placed, gap: gap) {
                high = mid
            } else {
                low = mid
            }
        }
        return high
    }

    mutating func run() -> ThemePlan {
        tree.buildTree()
        tree.buildLinks()
        assignRoles()
        sizeCells()
        local = [NeuronLocal](repeating: NeuronLocal(), count: tree.cCount)
        let tops: [Int] = topOrder()
        for t in tops { layOut(t, alone: tops.count == 1) }
        noteBody = [Int](repeating: -1, count: noteCount)
        cBody = [Int](repeating: -1, count: tree.cCount)
        cWorld = [SIMD3<Double>](repeating: SIMD3<Double>(0, 0, 0), count: tree.cCount)
        cFrame = [UniverseFrame](repeating: .identity, count: tree.cCount)
        worldBalls = [[ThemeBall]](repeating: [], count: tree.cCount)
        let placed: [ThemeBall] = placeTops(tops)
        let looseBalls: [ThemeBall] = placeLoose(placed)
        let all: [ThemeBall] = spreadOut(placed + looseBalls)
        return finish(tops, all: all)
    }

    // MARK: roles

    mutating func assignRoles() {
        let n: Int = noteCount
        let homeC: Int = tree.homeC
        var found = [NeuronRole?](repeating: nil, count: n)
        // commissural: an idea in a folder whose links reach notes in two
        // or more other folders
        for i in 0..<n {
            let h: Int = tree.noteHome[i]
            if tree.noteList[i].isPage || h < 0 || h == homeC { continue }
            var others = Set<Int>()
            for m in tree.nbr[i] {
                let o: Int = tree.noteHome[m]
                if o >= 0 && o != homeC && o != h { others.insert(o) }
            }
            if others.count >= 2 { found[i] = .commissural }
        }
        // glia, shortest first: an idea under 60 words with one link, to a
        // note in the same container that is a page or has other links
        gliaOf = [[Int]](repeating: [], count: n)
        gliaHost = [Int](repeating: -1, count: n)
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
            if tree.noteHome[p] != h || found[p] == .commissural || found[p] == .glia { continue }
            let host: UniverseNote = tree.noteList[p]
            if !host.isPage && tree.nbr[p].count < 2 { continue }
            let cap: Int = host.isPage ? 4 : 2
            if gliaOf[p].count >= cap { continue }
            gliaOf[p].append(i)
            gliaHost[i] = p
            found[i] = .glia
        }
        role = []
        role.reserveCapacity(n)
        for i in 0..<n {
            if let r = found[i] {
                role.append(r)
            } else if tree.noteHome[i] < 0 {
                role.append(tree.nbr[i].isEmpty ? .microglia : .receptor)
            } else {
                role.append(tree.noteList[i].isPage ? .pyramidal : .interneuron)
            }
        }
    }

    // MARK: sizes

    mutating func sizeCells() {
        sphere = []
        sphere.reserveCapacity(noteCount)
        for i in 0..<noteCount {
            let note: UniverseNote = tree.noteList[i]
            switch role[i] {
            case .glia: sphere.append(GraphNeurons.gliaSphere(words: note.words))
            case .commissural: sphere.append(GraphNeurons.commissuralSphere)
            default:
                let s: Double = note.isPage ? GraphNeurons.pageSphere(words: note.words)
                    : GraphNeurons.ideaSphere(words: note.words)
                sphere.append(s)
            }
        }
        cSphere = [Double](repeating: 0, count: tree.cCount)
        let order: [Int] = (0..<tree.cCount).sorted { a, b in
            tree.depth[a] != tree.depth[b] ? tree.depth[a] < tree.depth[b] : a < b
        }
        for c in order {
            if c == tree.homeC {
                cSphere[c] = GraphNeurons.brainstemSphere
            } else if tree.parent[c] < 0 {
                cSphere[c] = GraphNeurons.regionSphere(count: tree.count[c])
            } else {
                let up: Double = cSphere[tree.parent[c]]
                cSphere[c] = GraphNeurons.relaySphere(count: tree.count[c], depth: tree.depth[c], parent: up)
            }
        }
    }

    func cRole(_ c: Int) -> NeuronRole {
        if c == tree.homeC { return .brainstem }
        return tree.parent[c] < 0 ? .region : .relay
    }

    /// How far a note keeps others away: its dendrites, or its glia.
    func foot(_ i: Int) -> Double {
        var f: Double = sphere[i] * role[i].reach
        for g in gliaOf[i] {
            let out: Double = sphere[i] + GraphNeurons.hug + sphere[g] * (1 + NeuronRole.glia.reach)
            f = max(f, out)
        }
        return f
    }

    func cFoot(_ c: Int) -> Double {
        cSphere[c] * cRole(c).reach
    }

    // MARK: layout, bottom up

    /// Tops by how much they hold (most first, near the middle), then name.
    func topOrder() -> [Int] {
        let tops: [Int] = (0..<tree.cCount).filter { tree.parent[$0] < 0 }
        return tops.sorted { a, b in
            if tree.count[a] != tree.count[b] { return tree.count[a] > tree.count[b] }
            return tree.lessC(a, b)
        }
    }

    /// Lays out container `c` and everything inside it, in its own frame.
    mutating func layOut(_ c: Int, alone: Bool) {
        for k in tree.kids[c] { layOut(k, alone: false) }
        var random = UniverseRandom(tree.cSeed(c) ^ 0xCE11)
        var placed: [ThemeBall] = [ThemeBall(c: SIMD3<Double>(0, 0, 0), r: cFoot(c))]
        var out = NeuronLocal()
        // its notes round it, biggest first, each slid out from the soma
        // along its own even direction until clear
        var members: [Int] = (0..<noteCount).filter { tree.noteHome[$0] == c && role[$0] != .glia }
        members.sort { a, b in
            if sphere[a] != sphere[b] { return sphere[a] > sphere[b] }
            return tree.lessN(a, b)
        }
        let spin: UniverseFrame = ThemeLayout.frame(along: randomDirection(&random), twist: random.unit() * 6.2)
        for (k, i) in members.enumerated() {
            let dir: SIMD3<Double> = spin.apply(ThemeLayout.fibonacci(k, members.count))
            let f: Double = foot(i)
            let ball = ThemeBall(c: SIMD3<Double>(0, 0, 0), r: f)
            let start: Double = cFoot(c) + f + gap
            let s: Double = settle([ball], along: dir, start: start, step: 0.03, placed: placed,
                                              gap: gap)
            let at: SIMD3<Double> = dir * s
            placed.append(ThemeBall(c: at, r: f))
            out.members.append((i, at))
        }
        // the folders inside it, out along the pathway: straight on for
        // one, fanned in a cone for more (all round for a lone region)
        let kids: [Int] = tree.kids[c]
        let fan: Double = 2 * Double.pi * random.unit()
        for (j, k) in kids.enumerated() {
            let dir: SIMD3<Double> = kidDirection(j, of: kids.count, alone: alone, fan: fan)
            let turn: UniverseFrame = ThemeLayout.frame(along: dir, twist: random.unit() * 6.2)
            var group: [ThemeBall] = []
            for b in local[k].balls { group.append(ThemeBall(c: turn.apply(b.c), r: b.r)) }
            let start: Double = cFoot(c) + cFoot(k) + gap
            let s: Double = settle(group, along: dir, start: start, step: 0.06, placed: placed,
                                              gap: gap * 3)
            let at: SIMD3<Double> = dir * s
            for b in group { placed.append(ThemeBall(c: b.c + at, r: b.r)) }
            out.children.append((k, at, turn))
        }
        out.balls = placed
        local[c] = out
    }

    func kidDirection(_ j: Int, of n: Int, alone: Bool, fan: Double) -> SIMD3<Double> {
        if n == 1 { return SIMD3<Double>(1, 0, 0) }
        if alone { return ThemeLayout.fibonacci(j, n) }
        let theta: Double = min(0.35 + 0.16 * Double(n), 1.35)
        let phi: Double = fan + 2 * Double.pi * Double(j) / Double(n)
        return ThemeLayout.cone(theta: theta, phi: phi)
    }

    func randomDirection(_ random: inout UniverseRandom) -> SIMD3<Double> {
        let y: Double = random.signed()
        let angle: Double = random.unit() * 2 * Double.pi
        let ring: Double = max(1 - y * y, 0).squareRoot()
        return SIMD3<Double>(cos(angle) * ring, y, sin(angle) * ring)
    }

    // MARK: placing, top down

    /// The regions round the middle, most notes first: each slid out along
    /// its own even direction until its whole pathway is clear of the ones
    /// before; its pathway points outward, the way it slid.
    mutating func placeTops(_ tops: [Int]) -> [ThemeBall] {
        var placed: [ThemeBall] = []
        for (k, t) in tops.enumerated() {
            var random = UniverseRandom(tree.cSeed(t) ^ 0x70B)
            let dir: SIMD3<Double> = tops.count == 1 ? SIMD3<Double>(1, 0, 0) : ThemeLayout.fibonacci(k, tops.count)
            let turn: UniverseFrame = ThemeLayout.frame(along: dir, twist: random.unit() * 6.2)
            var group: [ThemeBall] = []
            for b in local[t].balls { group.append(ThemeBall(c: turn.apply(b.c), r: b.r)) }
            let s: Double = settle(group, along: dir, start: 0, step: 0.08, placed: placed,
                                              gap: gap * 4)
            let at: SIMD3<Double> = dir * s
            for b in group { placed.append(ThemeBall(c: b.c + at, r: b.r)) }
            place(t, at: at, frame: turn)
        }
        return placed
    }

    /// Where container `c` and its subtree are, in the space.
    mutating func place(_ c: Int, at origin: SIMD3<Double>, frame: UniverseFrame) {
        cWorld[c] = origin
        cFrame[c] = frame
        var balls: [ThemeBall] = []
        for b in local[c].balls { balls.append(ThemeBall(c: origin + frame.apply(b.c), r: b.r)) }
        worldBalls[c] = balls
        for (k, at, turn) in local[c].children {
            place(k, at: origin + frame.apply(at), frame: frame.times(turn))
        }
    }

    /// Loose notes at the periphery: a receptor out past the region it
    /// links to most, a microglial cell anywhere round the edge; each slid
    /// out from near the edge until clear.
    mutating func placeLoose(_ placed: [ThemeBall]) -> [ThemeBall] {
        var edge: Double = 0
        for b in placed { edge = max(edge, GraphUniverse.length(b.c) + b.r) }
        var all: [ThemeBall] = placed
        var out: [ThemeBall] = []
        var loose: [Int] = (0..<noteCount).filter { tree.noteHome[$0] < 0 }
        loose.sort { a, b in
            if role[a] != role[b] { return role[a].rawValue < role[b].rawValue }
            return tree.lessN(a, b)
        }
        looseHome = [SIMD3<Double>](repeating: SIMD3<Double>(0, 0, 0), count: noteCount)
        for (k, i) in loose.enumerated() {
            var random = UniverseRandom(tree.nSeed(i) ^ 0x1005E)
            var dir: SIMD3<Double> = ThemeLayout.fibonacci(k, loose.count)
            if let t = favouriteTop(i) {
                let towards: SIMD3<Double> = cWorld[t]
                if GraphUniverse.length(towards) > 0.01 { dir = GraphUniverse.normalize(towards) }
                let side: SIMD3<Double> = ThemeLayout.frame(along: dir, twist: random.unit() * 6.2).y
                dir = GraphUniverse.rotate(dir, axis: side, angle: 0.5 * random.signed())
            }
            let f: Double = foot(i) + Double(looseDrift(i))
            let ball = ThemeBall(c: SIMD3<Double>(0, 0, 0), r: f)
            let s: Double = settle([ball], along: dir, start: edge * 0.85, step: 0.05, placed: all,
                                              gap: gap * 2)
            let at: SIMD3<Double> = dir * s
            let placedBall = ThemeBall(c: at, r: f)
            all.append(placedBall)
            out.append(placedBall)
            looseHome[i] = at
        }
        looseOrder = loose
        return out
    }

    var looseHome: [SIMD3<Double>] = []
    var looseOrder: [Int] = []

    /// The region holding most of a loose note's links (ties: by name).
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

    /// Longer links: the whole plan, laid out as at 1, spread out from the
    /// middle by the link length (UniverseInput.stretch) - every pathway,
    /// every cluster round its soma, every receptor out at the edge. Cells
    /// keep their sizes, a glial cell stays on its neuron, and as every
    /// distance between centres grows by the same factor, nothing that
    /// was clear can meet.
    mutating func spreadOut(_ all: [ThemeBall]) -> [ThemeBall] {
        let k: Double = tree.stretch
        guard k > 1 else { return all }
        for c in 0..<tree.cCount {
            cWorld[c] = cWorld[c] * k
            var balls: [ThemeBall] = []
            for b in worldBalls[c] { balls.append(ThemeBall(c: b.c * k, r: b.r)) }
            worldBalls[c] = balls
            var members: [(Int, SIMD3<Double>)] = []
            for (i, at) in local[c].members { members.append((i, at * k)) }
            local[c].members = members
        }
        for i in looseHome.indices { looseHome[i] = looseHome[i] * k }
        var out: [ThemeBall] = []
        for b in all { out.append(ThemeBall(c: b.c * k, r: b.r)) }
        return out
    }

    // MARK: the bodies

    mutating func finish(_ tops: [Int], all: [ThemeBall]) -> ThemePlan {
        bodies = []
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
        // every folder wired to the folders inside it: the pathway
        for c in 0..<tree.cCount where tree.parent[c] >= 0 {
            let up: Int = cBody[tree.parent[c]]
            let down: Int = cBody[c]
            if up >= 0 && down >= 0 { links.append(ThemeLink(a: up, b: down, kind: 4, centre: -1)) }
        }
        var systems = [[SIMD3<Float>]](repeating: [], count: bodies.count)
        for c in 0..<tree.cCount where cBody[c] >= 0 {
            systems[cBody[c]] = ThemeLayout.points(worldBalls[c], around: cWorld[c])
        }
        var margin: [ThemeBall] = []
        for b in all { margin.append(ThemeBall(c: b.c, r: b.r + 0.1)) }
        let envelope: [SIMD3<Float>] = ThemeLayout.points(margin, around: SIMD3<Double>(0, 0, 0))
        let regions: [Int] = tops.map { cBody[$0] }
        return ThemePlan(bodies: bodies, links: links, envelope: envelope, systems: systems, regions: regions,
                         summary: GraphNeurons.summary(bodies))
    }

    func linkKind(_ i: Int, _ j: Int) -> Int {
        if gliaHost[i] == j || gliaHost[j] == i { return 3 }
        let hi: Int = tree.noteHome[i]
        let hj: Int = tree.noteHome[j]
        if hi < 0 || hj < 0 { return 2 }
        if hi == hj { return 0 }
        return tree.top[hi] == tree.top[hj] ? 1 : 2
    }

    mutating func emitContainer(_ c: Int) {
        let up: Int = tree.parent[c]
        let parentBody: Int = up >= 0 ? cBody[up] : -1
        let base: SIMD3<Double> = up >= 0 ? cWorld[c] - cWorld[up] : cWorld[c]
        let seed: UInt64 = tree.cSeed(c)
        var random = UniverseRandom(seed ^ 0xD81F)
        let phase: Float = Float(random.unit() * 6.28)
        let rate: Float = Float(0.12 + 0.08 * random.unit())
        let orbit: GraphOrbit = .drift(base: GraphUniverse.float3(base), amp: 0.012, phase: phase, rate: rate)
        let index: Int = bodies.count
        let region: Int = up >= 0 ? cBody[tree.top[c]] : index
        let isHome: Bool = c == tree.homeC
        let name: String = tree.cName(c)
        let label: String = UniversePlanner.folderLabel(name, count: tree.count[c])
        let r: NeuronRole = cRole(c)
        bodies.append(ThemeBody(id: tree.cID(c), kind: isHome ? .home : .folder, role: r.rawValue,
                                parent: parentBody, sphere: Float(cSphere[c]), depth: tree.depth[c],
                                region: region, count: tree.count[c], links: 0, words: 0, rank: r.rank,
                                seed: seed, orbit: orbit, home: GraphUniverse.float3(cWorld[c]),
                                axis: GraphUniverse.float3(cFrame[c].x), title: name, label: label))
        cBody[c] = index
        for (i, at) in local[c].members {
            let world: SIMD3<Double> = cWorld[c] + cFrame[c].apply(at)
            let offset: SIMD3<Double> = world - cWorld[c]
            emitNote(i, parent: index, region: region, base: offset, home: world, amp: 0.022)
            emitGlia(i, region: region)
        }
        for (k, _, _) in local[c].children { emitContainer(k) }
    }

    mutating func emitNote(_ i: Int, parent: Int, region: Int, base: SIMD3<Double>, home: SIMD3<Double>,
                           amp: Float) {
        let note: UniverseNote = tree.noteList[i]
        let seed: UInt64 = tree.nSeed(i)
        var random = UniverseRandom(seed ^ 0xF10A7)
        let phase: Float = Float(random.unit() * 6.28)
        let rate: Float = Float(0.22 + 0.2 * random.unit())
        let orbit: GraphOrbit = .drift(base: GraphUniverse.float3(base), amp: amp, phase: phase, rate: rate)
        let r: NeuronRole = role[i]
        let away: SIMD3<Double> = GraphUniverse.length(base) > 1e-6 ? GraphUniverse.normalize(base)
            : SIMD3<Double>(0, 1, 0)
        noteBody[i] = bodies.count
        bodies.append(ThemeBody(id: note.id, kind: .note, role: r.rawValue, parent: parent,
                                sphere: Float(sphere[i]), depth: -1, region: region, count: 0,
                                links: tree.nbr[i].count, words: note.words, rank: r.rank, seed: seed,
                                orbit: orbit, home: GraphUniverse.float3(home), axis: GraphUniverse.float3(away),
                                title: note.title, label: UniversePlanner.noteLabel(note.title)))
    }

    /// A neuron's glia, hugging its membrane on even sides of it.
    mutating func emitGlia(_ host: Int, region: Int) {
        let list: [Int] = gliaOf[host]
        guard !list.isEmpty else { return }
        let hostBody: Int = noteBody[host]
        let hostHome: SIMD3<Double> = bodies[hostBody].home.doubles
        var random = UniverseRandom(tree.nSeed(host) ^ 0x6114)
        let spin: UniverseFrame = ThemeLayout.frame(along: randomDirection(&random), twist: random.unit() * 6.2)
        for (k, g) in list.enumerated() {
            let dir: SIMD3<Double> = spin.apply(ThemeLayout.fibonacci(k, list.count))
            let d: Double = sphere[host] + GraphNeurons.hug + sphere[g]
            let offset: SIMD3<Double> = dir * d
            emitNote(g, parent: hostBody, region: region, base: offset, home: hostHome + offset, amp: 0.004)
        }
    }

    mutating func emitLoose(_ i: Int) {
        let at: SIMD3<Double> = looseHome[i]
        emitNote(i, parent: -1, region: -1, base: at, home: at, amp: looseDrift(i))
    }

    /// How far a loose cell wanders: a microglial cell on patrol further.
    func looseDrift(_ i: Int) -> Float {
        role[i] == .microglia ? 0.09 : 0.03
    }
}

extension SIMD3 where Scalar == Float {
    /// The same point in doubles, for planning.
    nonisolated var doubles: SIMD3<Double> {
        SIMD3<Double>(Double(x), Double(y), Double(z))
    }
}
