import Foundation

// The Universe look: the ideas' own hierarchy drawn as a universe, the
// biggest bodies for the biggest containers.
//
// - a top-level folder is a supermassive black hole at the heart of a galaxy;
// - a folder inside a folder is a star (yellow-white, orange one level
//   deeper, red deeper still), standing beside its parent as a companion;
// - a page is a gas giant (bigger is longer; a ring from 250 words), an idea
//   a rocky planet, and a short idea linked only to the note it circles is
//   that note's moon;
// - an idea linking notes in two or more other folders is its galaxy's
//   pulsar;
// - a note in no folder is a comet, swinging past the galaxy it links to
//   most; the older ones rest in the Oort cloud round the edge;
// - with no folders at all, one home star holds every note.
//
// Four rules: what a body is = what the item is; size = how much is in it;
// brightness = how many links; position = which folder holds it.
//
// Pure and deterministic: Foundation only, no SceneKit, UIKit or simd
// functions, so it runs (and is tested) on Linux. The same notes always
// give the same picture, whatever order they come in. Everything is planned
// once, off the main thread; GraphSim then only turns the orbits.

/// One note, as the plan needs it.
nonisolated struct UniverseNote: Sendable, Equatable {
    let id: UUID
    let title: String
    let isPage: Bool
    let folder: UUID?
    let words: Int
    /// When it was made (seconds since the reference date).
    let created: Double
}

nonisolated struct UniverseFolder: Sendable, Equatable {
    let id: UUID
    let name: String
    let parent: UUID?
}

nonisolated struct UniverseEdge: Sendable, Equatable {
    let a: UUID
    let b: UUID
}

nonisolated struct UniverseInput: Sendable {
    let notes: [UniverseNote]
    let folders: [UniverseFolder]
    let edges: [UniverseEdge]
    /// Seeds from names and titles instead of ids (the design preview, whose
    /// ids change every launch).
    let seedByName: Bool
}

nonisolated enum UniverseRole: String, Sendable, Equatable {
    case galaxy, star, home, gasGiant, rocky, moon, pulsar, comet, oort
}

/// How a body moves, relative to its parent's live position (or to the
/// space's origin when it has none).
nonisolated enum GraphOrbit: Sendable, Equatable {
    /// Holds still at this offset (an absolute place when there is no parent).
    case fixed(SIMD3<Float>)
    /// A circle of `radius` in the plane of `u` and `v`, at angle
    /// phase + rate * t.
    case circle(radius: Float, u: SIMD3<Float>, v: SIMD3<Float>, phase: Float, rate: Float)
    /// An ellipse with its focus at the origin: periapsis along `u`, mean
    /// anomaly phase + rate * t.
    case kepler(a: Float, e: Float, u: SIMD3<Float>, v: SIMD3<Float>, phase: Float, rate: Float)
    /// The Oort cloud: an ellipse of semi-axes x and y at height z.
    case ring(x: Float, y: Float, z: Float, phase: Float, rate: Float)
    /// Floating in place (the Neurons theme's cells in their fluid): `base`
    /// plus a slow three-axis wobble of up to `amp`, at phase + rate * t.
    case drift(base: SIMD3<Float>, amp: Float, phase: Float, rate: Float)
}

nonisolated struct UniverseBody: Sendable, Equatable {
    /// The note's id, the folder's id, or GraphUniverse.homeID.
    let id: UUID
    let role: UniverseRole
    /// The body it moves with, or -1.
    let parent: Int
    /// Who lights it: a body index, -1 the key light, -2 the nearest light.
    let light: Int
    /// The solid sphere's radius.
    let sphere: Float
    /// Star colour: 1 yellow-white, 2 orange, 3 red; 0 for anything else.
    let tier: Int
    /// A folder with no notes anywhere inside it.
    let empty: Bool
    /// A gas giant of 250 words or more.
    let ringed: Bool
    let palette: Int
    /// Its galaxy core's index, or -1 (the home star and loose notes).
    let galaxy: Int
    /// Notes inside a folder (its whole subtree); 0 for a note.
    let count: Int
    /// A note's links; 0 for a folder.
    let links: Int
    /// The orbit ring it travels on, or -1.
    let shell: Int
    let orbit: GraphOrbit
    /// Where it is at time 0, in the space's coordinates.
    let home: SIMD3<Float>
    let title: String
    /// What its name pill says.
    let label: String
}

/// One orbit ring: round `owner`, of `radius`, in the plane of `u` and `v`.
nonisolated struct UniverseShell: Sendable, Equatable {
    let owner: Int
    let radius: Float
    let u: SIMD3<Float>
    let v: SIMD3<Float>
}

/// A link between two bodies. kind: 0 same folder, 1 same galaxy, 2 across
/// galaxies or to a loose note, 3 hidden (a moon and its own planet).
/// `centre`: the galaxy core a kind-1 link bows away from; -1 the origin.
nonisolated struct UniverseLink: Sendable, Equatable {
    let a: Int
    let b: Int
    let kind: Int
    let centre: Int
}

nonisolated struct UniversePlan: Sendable {
    /// Every body, each after its parent.
    let bodies: [UniverseBody]
    let shells: [UniverseShell]
    let links: [UniverseLink]
    /// Points the whole-map framing must hold, at any time.
    let envelope: [SIMD3<Float>]
    /// For each folder body, the points its fly-in framing must hold,
    /// relative to it; empty for notes.
    let systems: [[SIMD3<Float>]]
    /// The bodies that shine (non-empty folders and the home star).
    let lights: [Int]
    /// "2 galaxies, 3 stars, 21 planets, 6 moons, 1 pulsar, 2 comets".
    let summary: String

    static let empty = UniversePlan(bodies: [], shells: [], links: [], envelope: [], systems: [],
                                    lights: [], summary: "")
}

nonisolated enum GraphUniverse {
    /// The home star's id, when there are no folders.
    static let homeID: UUID = UUID(uuidString: "00000000-0000-0000-0000-00000000A11C") ?? UUID()
    static let golden: Double = 2.3999632297
    /// Word counts at which a note steps up a size.
    static let levels: [Int] = [15, 30, 60, 120, 250, 500, 1000, 2000]
    /// Loose notes past this many (the oldest) rest in the Oort cloud.
    static let activeComets: Int = 12
    static let cometE: Double = 0.45

    // MARK: words

    /// Runs of non-whitespace bytes in the UTF-8 (whitespace: space, tab,
    /// LF, CR).
    static func wordCount(_ text: String) -> Int {
        var count: Int = 0
        var inWord: Bool = false
        for byte in text.utf8 {
            let blank: Bool = byte == 32 || byte == 9 || byte == 10 || byte == 13
            if blank {
                inWord = false
            } else if !inWord {
                inWord = true
                count += 1
            }
        }
        return count
    }

    /// How many of `levels` are at or below `words`.
    static func level(words: Int) -> Int {
        var n: Int = 0
        for t in levels where words >= t { n += 1 }
        return n
    }

    // MARK: moving

    /// Where an orbit puts its body, relative to its parent, at `time`.
    static func offset(_ orbit: GraphOrbit, time: Double) -> SIMD3<Float> {
        switch orbit {
        case .fixed(let p):
            return p
        case .circle(let radius, let u, let v, let phase, let rate):
            let turn: Double = Double(rate) * time
            let angle: Float = phase + Float(turn.truncatingRemainder(dividingBy: 2 * Double.pi))
            let x: Float = cos(angle) * radius
            let y: Float = sin(angle) * radius
            return u * x + v * y
        case .kepler(let a, let e, let u, let v, let phase, let rate):
            let turn: Double = Double(rate) * time
            let m: Float = phase + Float(turn.truncatingRemainder(dividingBy: 2 * Double.pi))
            let big: Float = eccentric(m, e: e)
            let x: Float = a * (cos(big) - e)
            let root: Float = (1 - e * e).squareRoot()
            let y: Float = a * root * sin(big)
            return u * x + v * y
        case .ring(let x, let y, let z, let phase, let rate):
            let turn: Double = Double(rate) * time
            let angle: Float = phase + Float(turn.truncatingRemainder(dividingBy: 2 * Double.pi))
            let px: Float = x * cos(angle)
            let py: Float = y * sin(angle)
            return SIMD3<Float>(px, py, z)
        case .drift(let base, let amp, let phase, let rate):
            return base + wobble(amp: amp, phase: phase, rate: rate, time: time)
        }
    }

    /// A drifting body's wobble: three slow sines at unrelated rates, so it
    /// never retraces a simple loop. Each argument is wrapped first, so a
    /// long session keeps a 32-bit float fine.
    static func wobble(amp: Float, phase: Float, rate: Float, time: Double) -> SIMD3<Float> {
        guard amp > 0 else { return SIMD3<Float>(0, 0, 0) }
        let full: Double = 2 * Double.pi
        let t: Double = Double(rate) * time
        let a: Float = phase + Float(t.truncatingRemainder(dividingBy: full))
        let t2: Double = t * 1.31
        let b: Float = phase * 1.7 + Float(t2.truncatingRemainder(dividingBy: full))
        let t3: Double = t * 0.77
        let c: Float = phase * 0.6 + Float(t3.truncatingRemainder(dividingBy: full))
        let x: Float = sin(a) * amp
        let y: Float = sin(b + 1.1) * amp * 0.8
        let z: Float = cos(c) * amp * 0.9
        return SIMD3<Float>(x, y, z)
    }

    /// Kepler's equation, four Newton steps.
    private static func eccentric(_ m: Float, e: Float) -> Float {
        var big: Float = m + e * sin(m)
        for _ in 0..<4 {
            let f: Float = big - e * sin(big) - m
            let slope: Float = 1 - e * cos(big)
            big -= f / slope
        }
        return big
    }

    /// Where body `i` is at `time`, in the space's coordinates.
    static func position(of i: Int, in plan: UniversePlan, time: Double) -> SIMD3<Float> {
        var p = SIMD3<Float>(0, 0, 0)
        var at: Int = i
        var steps: Int = 0
        while at >= 0 && at < plan.bodies.count && steps <= plan.bodies.count {
            let body: UniverseBody = plan.bodies[at]
            p += offset(body.orbit, time: time)
            at = body.parent
            steps += 1
        }
        return p
    }

    // MARK: planning

    static func plan(_ input: UniverseInput) -> UniversePlan {
        if input.notes.isEmpty && input.folders.isEmpty { return .empty }
        var planner = UniversePlanner(input)
        return planner.run()
    }

    // MARK: helpers (zero-safe)

    static func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let p: SIMD3<Double> = a * b
        return p.x + p.y + p.z
    }

    static func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
        let x: Double = a.y * b.z - a.z * b.y
        let y: Double = a.z * b.x - a.x * b.z
        let z: Double = a.x * b.y - a.y * b.x
        return SIMD3<Double>(x, y, z)
    }

    static func length(_ a: SIMD3<Double>) -> Double {
        dot(a, a).squareRoot()
    }

    static func length(_ a: SIMD2<Double>) -> Double {
        let p: SIMD2<Double> = a * a
        return (p.x + p.y).squareRoot()
    }

    static func normalize(_ a: SIMD3<Double>) -> SIMD3<Double> {
        let n: Double = length(a)
        guard n > 1e-12 else { return SIMD3<Double>(0, 0, 0) }
        return a / n
    }

    /// `v` turned by `angle` about `axis` (Rodrigues).
    static func rotate(_ v: SIMD3<Double>, axis: SIMD3<Double>, angle: Double) -> SIMD3<Double> {
        let k: SIMD3<Double> = normalize(axis)
        let c: Double = cos(angle)
        let s: Double = sin(angle)
        let along: SIMD3<Double> = k * (dot(k, v) * (1 - c))
        let turned: SIMD3<Double> = cross(k, v) * s
        return v * c + turned + along
    }

    static func rotX(_ angle: Double) -> UniverseFrame {
        let c: Double = cos(angle)
        let s: Double = sin(angle)
        return UniverseFrame(x: SIMD3<Double>(1, 0, 0), y: SIMD3<Double>(0, c, s), z: SIMD3<Double>(0, -s, c))
    }

    static func rotZ(_ angle: Double) -> UniverseFrame {
        let c: Double = cos(angle)
        let s: Double = sin(angle)
        return UniverseFrame(x: SIMD3<Double>(c, s, 0), y: SIMD3<Double>(-s, c, 0), z: SIMD3<Double>(0, 0, 1))
    }

    /// FNV-1a 64 over UTF-8.
    static func fnv(_ text: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01b3
        }
        return h
    }

    /// The smallest a star at depth `d` is drawn (1: inside a galaxy),
    /// and a dark star's size there: 0.278, 0.270, 0.267, ... - falling
    /// with every level, so a folder is always drawn a little smaller than
    /// the one it sits in, and always above the biggest gas giant (0.26).
    static func starFloor(_ d: Int) -> Double {
        0.262 + 0.016 / Double(max(d, 1))
    }

    static func clamp(_ x: Double, _ low: Double, _ high: Double) -> Double {
        max(low, min(high, x))
    }

    /// Rounded to `places` decimals, halves away from zero.
    static func rounded(_ x: Double, _ scale: Double) -> Double {
        (x * scale).rounded() / scale
    }

    static func float3(_ v: SIMD3<Double>) -> SIMD3<Float> {
        SIMD3<Float>(Float(v.x), Float(v.y), Float(v.z))
    }
}

/// A turn, as its three columns: where x, y and z go.
nonisolated struct UniverseFrame: Sendable, Equatable {
    var x: SIMD3<Double>
    var y: SIMD3<Double>
    var z: SIMD3<Double>

    static let identity = UniverseFrame(x: SIMD3<Double>(1, 0, 0), y: SIMD3<Double>(0, 1, 0),
                                        z: SIMD3<Double>(0, 0, 1))

    func apply(_ v: SIMD3<Double>) -> SIMD3<Double> {
        let a: SIMD3<Double> = x * v.x
        let b: SIMD3<Double> = y * v.y
        let c: SIMD3<Double> = z * v.z
        return a + b + c
    }

    /// This turn after `inner` (the matrix product self * inner).
    func times(_ inner: UniverseFrame) -> UniverseFrame {
        UniverseFrame(x: apply(inner.x), y: apply(inner.y), z: apply(inner.z))
    }

    /// A turn of `angle` about `axis`.
    static func about(_ axis: SIMD3<Double>, _ angle: Double) -> UniverseFrame {
        let ex: SIMD3<Double> = GraphUniverse.rotate(SIMD3<Double>(1, 0, 0), axis: axis, angle: angle)
        let ey: SIMD3<Double> = GraphUniverse.rotate(SIMD3<Double>(0, 1, 0), axis: axis, angle: angle)
        let ez: SIMD3<Double> = GraphUniverse.rotate(SIMD3<Double>(0, 0, 1), axis: axis, angle: angle)
        return UniverseFrame(x: ex, y: ey, z: ez)
    }
}

/// SplitMix64, with the same constants as ForceLayout3D; unit() in [0, 1).
nonisolated struct UniverseRandom: Sendable {
    private var state: UInt64

    init(_ seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z: UInt64 = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double {
        let top: UInt64 = next() >> 11
        return Double(top) / 9_007_199_254_740_992.0
    }

    /// A number between -1 and 1.
    mutating func signed() -> Double {
        unit() * 2 - 1
    }
}

/// A circle in a plane: its centre and radius.
nonisolated struct UniverseCircle: Sendable {
    let q: SIMD2<Double>
    let r: Double
}

/// One orbit round a container while planning.
nonisolated struct UniverseOrbitPlan: Sendable {
    let radius: Double
    let members: [Int]
    let foot: Double
}

/// Where a child container stands in its parent's plane.
nonisolated struct UniversePlace: Sendable {
    let child: Int
    let offset: SIMD2<Double>
    let turn: Double
}

/// The plan's working state. Notes are 0..<n, containers 0..<c (the folders,
/// and the home star when there are none).
nonisolated struct UniversePlanner: Sendable {
    let input: UniverseInput
    let noteList: [UniverseNote]
    let folderList: [UniverseFolder]
    let hasFolders: Bool
    /// The home star's container index, or -1.
    let homeC: Int
    var cCount: Int = 0
    var parent: [Int] = []
    var depth: [Int] = []
    var top: [Int] = []
    var kids: [[Int]] = []
    var count: [Int] = []
    var noteHome: [Int] = []
    var nbr: [[Int]] = []
    var edgePairs: [(Int, Int)] = []
    /// 0 gas, 1 rocky, 2 moon, 3 pulsar, 4 comet, 5 oort.
    var role: [Int] = []
    var moonsOf: [[Int]] = []
    var moonPlanet: [Int] = []
    var sphere: [Double] = []
    var ringed: [Bool] = []
    var cSphere: [Double] = []
    var orbits: [[UniverseOrbitPlan]] = []
    var core: [Double] = []
    var comp: [[UniverseCircle]] = []
    var places: [[UniversePlace]] = []
    var palette: [Int] = []
    var loose: [Int] = []

    // the output
    var bodies: [UniverseBody] = []
    var shells: [UniverseShell] = []
    var noteBody: [Int] = []
    var cBody: [Int] = []
    var cFrame: [UniverseFrame] = []
    var cHome: [SIMD3<Double>] = []

    init(_ input: UniverseInput) {
        self.input = input
        // a fixed order, whatever order they came in; duplicates dropped
        var seenNotes = Set<UUID>()
        var notes: [UniverseNote] = []
        for note in input.notes where seenNotes.insert(note.id).inserted { notes.append(note) }
        notes.sort { $0.id.uuidString < $1.id.uuidString }
        var seenFolders = Set<UUID>()
        var folders: [UniverseFolder] = []
        for folder in input.folders where seenFolders.insert(folder.id).inserted { folders.append(folder) }
        folders.sort { $0.id.uuidString < $1.id.uuidString }
        noteList = notes
        folderList = folders
        hasFolders = !folders.isEmpty
        homeC = folders.isEmpty ? folders.count : -1
    }

    // MARK: names and seeds

    func cName(_ c: Int) -> String {
        c < folderList.count ? folderList[c].name : "Ideas"
    }

    func cID(_ c: Int) -> UUID {
        c < folderList.count ? folderList[c].id : GraphUniverse.homeID
    }

    func cSeed(_ c: Int) -> UInt64 {
        let key: String = input.seedByName ? cName(c) : cID(c).uuidString
        return GraphUniverse.fnv(key)
    }

    func nSeed(_ n: Int) -> UInt64 {
        let note: UniverseNote = noteList[n]
        let key: String = input.seedByName ? note.title : note.id.uuidString
        return GraphUniverse.fnv(key)
    }

    func nKey(_ n: Int) -> (String, String) {
        (noteList[n].title.lowercased(), noteList[n].id.uuidString)
    }

    func cKey(_ c: Int) -> (String, String) {
        (cName(c).lowercased(), cID(c).uuidString)
    }

    func isGalaxy(_ c: Int) -> Bool {
        c != homeC && depth[c] == 0
    }

    mutating func run() -> UniversePlan {
        buildTree()
        buildLinks()
        assignRoles()
        sizeBodies()
        buildOrbits()
        let tops: [Int] = (0..<cCount).filter { parent[$0] < 0 }
        for t in tops { compose(t) }
        let placed: GalaxyPlacement = placeGalaxies(tops)
        emit(placed)
        let box: SIMD2<Double> = placed.half
        emitComets(box)
        return finish(placed)
    }

    // MARK: the tree

    mutating func buildTree() {
        let f: Int = folderList.count
        cCount = hasFolders ? f : 1
        var index: [UUID: Int] = [:]
        for (i, folder) in folderList.enumerated() { index[folder.id] = i }
        parent = [Int](repeating: -1, count: cCount)
        for (i, folder) in folderList.enumerated() {
            guard let p = folder.parent, let at = index[p], at != i else { continue }
            parent[i] = at
        }
        // a cycle is cut at its member with the smallest uuidString (the
        // lowest index, as folders are sorted by it)
        for start in 0..<f {
            var seen: [Int] = []
            var onWalk = Set<Int>()
            var cur: Int = start
            while cur >= 0 && !onWalk.contains(cur) {
                seen.append(cur)
                onWalk.insert(cur)
                cur = parent[cur]
            }
            guard cur >= 0, let from = seen.firstIndex(of: cur) else { continue }
            let cycle: ArraySlice<Int> = seen[from...]
            let cut: Int = cycle.min() ?? cur
            parent[cut] = -1
        }
        depth = [Int](repeating: 0, count: cCount)
        top = Array(0..<cCount)
        for c in 0..<cCount {
            var d: Int = 0
            var cur: Int = c
            while parent[cur] >= 0 {
                cur = parent[cur]
                d += 1
            }
            depth[c] = d
            top[c] = cur
        }
        var children = [[Int]](repeating: [], count: cCount)
        for c in 0..<cCount where parent[c] >= 0 { children[parent[c]].append(c) }
        for c in 0..<cCount { children[c].sort { lessC($0, $1) } }
        kids = children
        // each note's home container
        noteHome = []
        for note in noteList {
            if !hasFolders {
                noteHome.append(homeC)
            } else if let folder = note.folder, let at = index[folder] {
                noteHome.append(at)
            } else {
                noteHome.append(-1)
            }
        }
        count = [Int](repeating: 0, count: cCount)
        for h in noteHome where h >= 0 {
            var cur: Int = h
            while cur >= 0 {
                count[cur] += 1
                cur = parent[cur]
            }
        }
        // palettes: each folder's place in a depth-first outline, mod 3
        palette = [Int](repeating: 0, count: cCount)
        if hasFolders {
            let roots: [Int] = (0..<cCount).filter { parent[$0] < 0 }.sorted { lessC($0, $1) }
            var order: Int = 0
            var stack: [Int] = roots.reversed()
            while let c = stack.popLast() {
                palette[c] = order % 3
                order += 1
                for k in kids[c].reversed() { stack.append(k) }
            }
        }
    }

    func lessC(_ a: Int, _ b: Int) -> Bool {
        let ka: (String, String) = cKey(a)
        let kb: (String, String) = cKey(b)
        return ka < kb
    }

    func lessN(_ a: Int, _ b: Int) -> Bool {
        let ka: (String, String) = nKey(a)
        let kb: (String, String) = nKey(b)
        return ka < kb
    }

    mutating func buildLinks() {
        var index: [UUID: Int] = [:]
        for (i, note) in noteList.enumerated() { index[note.id] = i }
        var sets: [Set<Int>] = [Set<Int>](repeating: [], count: noteList.count)
        var pairs = Set<Int>()
        let n: Int = noteList.count
        var list: [(Int, Int)] = []
        for edge in input.edges {
            guard let i = index[edge.a], let j = index[edge.b], i != j else { continue }
            let low: Int = min(i, j)
            let high: Int = max(i, j)
            guard pairs.insert(low * n + high).inserted else { continue }
            sets[i].insert(j)
            sets[j].insert(i)
            list.append((low, high))
        }
        list.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
        edgePairs = list
        nbr = sets.map { $0.sorted() }
    }

    // MARK: roles

    mutating func assignRoles() {
        let n: Int = noteList.count
        role = [Int](repeating: -1, count: n)
        // pulsars: an idea in a folder whose links reach 2 other folders,
        // with 3 such links; the strongest one per galaxy
        var best: [Int: (Int, Int, Int)] = [:]
        for i in 0..<n {
            let h: Int = noteHome[i]
            if noteList[i].isPage || h < 0 || h == homeC { continue }
            var others: [Int] = []
            for m in nbr[i] {
                let o: Int = noteHome[m]
                if o >= 0 && o != homeC && o != h { others.append(o) }
            }
            let distinct: Int = Set(others).count
            guard distinct >= 2 && others.count >= 3 else { continue }
            let g: Int = top[h]
            if let held = best[g] {
                if pulsarBeats(i, distinct, others.count, held) { best[g] = (i, distinct, others.count) }
            } else {
                best[g] = (i, distinct, others.count)
            }
        }
        for (_, held) in best { role[held.0] = 3 }

        // moons, shortest first
        moonsOf = [[Int]](repeating: [], count: n)
        moonPlanet = [Int](repeating: -1, count: n)
        let byLength: [Int] = (0..<n).sorted { a, b in
            let wa: Int = noteList[a].words
            let wb: Int = noteList[b].words
            if wa != wb { return wa < wb }
            return lessN(a, b)
        }
        for i in byLength {
            let h: Int = noteHome[i]
            if role[i] >= 0 || noteList[i].isPage || h < 0 { continue }
            if nbr[i].count != 1 || noteList[i].words >= 60 { continue }
            let p: Int = nbr[i][0]
            if noteHome[p] != h || role[p] == 3 { continue }
            if !noteList[p].isPage && nbr[p].count < 2 { continue }
            let cap: Int = noteList[p].isPage ? 4 : 2
            if moonsOf[p].count >= cap { continue }
            moonsOf[p].append(i)
            moonPlanet[i] = p
            role[i] = 2
        }

        // loose notes: the 12 newest fly, the rest rest in the Oort cloud
        var free: [Int] = (0..<n).filter { noteHome[$0] < 0 }
        free.sort { a, b in
            let ca: Double = noteList[a].created
            let cb: Double = noteList[b].created
            if ca != cb { return ca > cb }
            return lessN(a, b)
        }
        loose = free
        for (k, i) in free.enumerated() { role[i] = k < GraphUniverse.activeComets ? 4 : 5 }
        for i in 0..<n where role[i] < 0 { role[i] = noteList[i].isPage ? 0 : 1 }
    }

    func pulsarBeats(_ i: Int, _ distinct: Int, _ total: Int, _ held: (Int, Int, Int)) -> Bool {
        if distinct != held.1 { return distinct > held.1 }
        if total != held.2 { return total > held.2 }
        return lessN(i, held.0)
    }

    // MARK: sizes

    mutating func sizeBodies() {
        let n: Int = noteList.count
        sphere = [Double](repeating: 0, count: n)
        ringed = [Bool](repeating: false, count: n)
        for i in 0..<n {
            let lv: Int = GraphUniverse.level(words: noteList[i].words)
            switch role[i] {
            case 0:
                sphere[i] = 0.19 + 0.01 * Double(min(lv, 7))
                ringed[i] = noteList[i].words >= 250
            case 1: sphere[i] = 0.12 + 0.006 * Double(min(lv, 6))
            case 2: sphere[i] = 0.075 + 0.003 * Double(min(lv, 2))
            case 3: sphere[i] = 0.07
            case 4: sphere[i] = 0.09
            default: sphere[i] = 0.06
            }
        }
        cSphere = [Double](repeating: 0, count: cCount)
        let order: [Int] = (0..<cCount).sorted { depth[$0] != depth[$1] ? depth[$0] < depth[$1] : $0 < $1 }
        for c in order { cSphere[c] = containerSphere(c) }
    }

    func containerSphere(_ c: Int) -> Double {
        let size: Double = log2(1 + Double(count[c]))
        if isGalaxy(c) {
            if count[c] == 0 { return 0.40 }
            return GraphUniverse.clamp(0.40 + 0.015 * size, 0.40, 0.52)
        }
        if count[c] == 0 { return GraphUniverse.starFloor(depth[c]) }
        let v: Double = GraphUniverse.clamp(0.30 + 0.01 * size, 0.30, 0.38)
        guard c != homeC, depth[c] >= 2 else { return v }
        let under: Double = cSphere[parent[c]] * 0.9
        return max(min(v, under), GraphUniverse.starFloor(depth[c]))
    }

    func moonRing(_ p: Int) -> Double {
        let moons: [Int] = moonsOf[p]
        guard !moons.isEmpty else { return 0 }
        let biggest: Double = moons.map { sphere[$0] }.max() ?? 0
        let k: Double = ringed[p] ? 2.5 : 1.8
        return k * sphere[p] + biggest + 0.03
    }

    func foot(_ i: Int) -> Double {
        if role[i] == 3 { return 0.22 }
        let moons: [Int] = moonsOf[i]
        if !moons.isEmpty {
            let biggest: Double = moons.map { sphere[$0] }.max() ?? 0
            return moonRing(i) + biggest + 0.03
        }
        let k: Double = ringed[i] ? 2.4 : 1.25
        return k * sphere[i] + 0.03
    }

    func clear(_ c: Int) -> Double {
        let s: Double = cSphere[c]
        if isGalaxy(c) { return count[c] > 0 ? 2.5 * s + 0.10 : 1.6 * s }
        return count[c] > 0 || c == homeC ? 1.8 * s : 1.4 * s
    }

    // MARK: orbits

    mutating func buildOrbits() {
        var direct = [[Int]](repeating: [], count: cCount)
        for i in noteList.indices {
            let h: Int = noteHome[i]
            if h >= 0 && role[i] <= 1 || h >= 0 && role[i] == 3 { direct[h].append(i) }
        }
        orbits = [[UniverseOrbitPlan]](repeating: [], count: cCount)
        core = [Double](repeating: 0, count: cCount)
        for c in 0..<cCount {
            var rock: [Int] = direct[c].filter { role[$0] == 1 }
            rock.sort { a, b in
                if nbr[a].count != nbr[b].count { return nbr[a].count > nbr[b].count }
                return lessN(a, b)
            }
            var gas: [Int] = direct[c].filter { role[$0] == 0 }
            gas.sort { a, b in
                if sphere[a] != sphere[b] { return sphere[a] > sphere[b] }
                return lessN(a, b)
            }
            var pulsars: [Int] = direct[c].filter { role[$0] == 3 }
            pulsars.sort { lessN($0, $1) }
            let groups: [[Int]] = [rock, gas + pulsars].filter { !$0.isEmpty }
            var out: [UniverseOrbitPlan] = []
            var lastR: Double = -1
            var lastF: Double = 0
            for group in groups {
                var rest: ArraySlice<Int> = group[...]
                while !rest.isEmpty {
                    let f: Double = rest.map { foot($0) }.max() ?? 0
                    let r: Double = lastR < 0 ? clear(c) + f + 0.08 : lastR + lastF + f + 0.08
                    let room: Double = 2 * Double.pi * r / (2 * f + 0.10)
                    let cap: Int = max(1, Int(room.rounded(.down)))
                    let take: [Int] = Array(rest.prefix(cap))
                    rest = rest.dropFirst(cap)
                    out.append(UniverseOrbitPlan(radius: r, members: take, foot: f))
                    lastR = r
                    lastF = f
                }
            }
            orbits[c] = out
            core[c] = lastR < 0 ? clear(c) : lastR + lastF
        }
    }

    // MARK: systems, packed bottom up

    static func extent(_ circles: [UniverseCircle]) -> Double {
        var most: Double = 0
        for c in circles { most = max(most, GraphUniverse.length(c.q) + c.r) }
        return most
    }

    static func enclosing(_ circles: [UniverseCircle]) -> UniverseCircle {
        guard let first = circles.first else { return UniverseCircle(q: SIMD2<Double>(0, 0), r: 0) }
        var lo: SIMD2<Double> = first.q - first.r
        var hi: SIMD2<Double> = first.q + first.r
        for c in circles {
            lo = pointwiseMin(lo, c.q - c.r)
            hi = pointwiseMax(hi, c.q + c.r)
        }
        let centre: SIMD2<Double> = (lo + hi) * 0.5
        var r: Double = 0
        for c in circles { r = max(r, GraphUniverse.length(c.q - centre) + c.r) }
        return UniverseCircle(q: centre, r: r)
    }

    /// How far along `u` the circles `moving` (placed round the origin)
    /// must stand to clear every circle in `placed` by `gap`: the exact
    /// first contact sliding in from infinity.
    static func slide(_ u: SIMD2<Double>, _ moving: [UniverseCircle], _ placed: [UniverseCircle],
                      gap: Double) -> Double {
        var best: Double = 0
        for m in moving {
            for p in placed {
                let w: SIMD2<Double> = m.q - p.q
                let b: Double = u.x * w.x + u.y * w.y
                let reach: Double = m.r + p.r + gap
                let cc: Double = w.x * w.x + w.y * w.y - reach * reach
                let disc: Double = b * b - cc
                guard disc > 0 else { continue }
                let d: Double = disc.squareRoot() - b
                if d > best { best = d }
            }
        }
        return best
    }

    static func turned(_ circles: [UniverseCircle], by a: Double) -> [UniverseCircle] {
        let c: Double = cos(a)
        let s: Double = sin(a)
        return circles.map { k in
            let x: Double = c * k.q.x - s * k.q.y
            let y: Double = s * k.q.x + c * k.q.y
            return UniverseCircle(q: SIMD2<Double>(x, y), r: k.r)
        }
    }

    /// The smallest non-negative angle difference, folded to [0, pi].
    static func angleGap(_ a: Double, _ b: Double) -> Double {
        let full: Double = 2 * Double.pi
        var d: Double = (a - b + Double.pi).truncatingRemainder(dividingBy: full)
        if d < 0 { d += full }
        return abs(d - Double.pi)
    }

    mutating func compose(_ c: Int) {
        if comp.isEmpty {
            comp = [[UniverseCircle]](repeating: [], count: cCount)
            places = [[UniversePlace]](repeating: [], count: cCount)
        }
        for k in kids[c] { compose(k) }
        var placed: [UniverseCircle] = [UniverseCircle(q: SIMD2<Double>(0, 0), r: core[c])]
        var reach: Double = core[c]
        let children: [Int] = kids[c].sorted { a, b in
            let ea: Double = Self.extent(comp[a])
            let eb: Double = Self.extent(comp[b])
            if ea != eb { return ea > eb }
            return lessC(a, b)
        }
        let big: Bool = children.count > 12
        var random = UniverseRandom(cSeed(c))
        let base: Double = 2 * Double.pi * random.unit()
        var out: [UniversePlace] = []
        for (ki, k) in children.enumerated() {
            let circles: [UniverseCircle] = big ? [Self.enclosing(comp[k])] : comp[k]
            var centroid = SIMD2<Double>(0, 0)
            for circle in circles { centroid += circle.q }
            centroid /= Double(circles.count)
            let preferred: Double = base + Double(ki) * GraphUniverse.golden
            var bestKey: (Double, Double, Int)?
            var bestPlace: UniversePlace?
            var bestCircles: [UniverseCircle] = []
            var bestReach: Double = 0
            let centred: Bool = GraphUniverse.length(centroid) <= 1e-4
            let facing: Double = atan2(centroid.y, centroid.x)
            for j in 0..<72 {
                let th: Double = Double(j) * Double.pi / 36
                let u = SIMD2<Double>(cos(th), sin(th))
                let a: Double = centred ? 0 : th - facing
                let turned: [UniverseCircle] = Self.turned(circles, by: a)
                let d: Double = Self.slide(u, turned, placed, gap: 0.15)
                let shift: SIMD2<Double> = u * d
                let moved: [UniverseCircle] = turned.map { UniverseCircle(q: $0.q + shift, r: $0.r) }
                let ext: Double = max(reach, Self.extent(moved))
                let dp: Double = Self.angleGap(th, preferred)
                let key: (Double, Double, Int) = (GraphUniverse.rounded(ext, 100), GraphUniverse.rounded(dp, 10000), j)
                if let held = bestKey, !(key < held) { continue }
                bestKey = key
                bestPlace = UniversePlace(child: k, offset: shift, turn: a)
                bestCircles = moved
                bestReach = ext
            }
            guard let place = bestPlace else { continue }
            placed.append(contentsOf: bestCircles)
            reach = bestReach
            out.append(place)
        }
        comp[c] = placed
        places[c] = out
    }

    // MARK: galaxies, the local group

    struct GalaxyPlacement: Sendable {
        var order: [Int] = []
        var centre: [Int: SIMD2<Double>] = [:]
        var frame: [Int: UniverseFrame] = [:]
        var lo = SIMD2<Double>(0, 0)
        var hi = SIMD2<Double>(0, 0)
        var turn: Bool = false
        var half: SIMD2<Double> = SIMD2<Double>(0, 0)
    }

    func projected(_ g: Int, _ m: UniverseFrame) -> [UniverseCircle] {
        var circles: [UniverseCircle] = comp[g]
        if circles.count > 12 { circles = [Self.enclosing(circles)] }
        return circles.map { k in
            let p: SIMD3<Double> = m.apply(SIMD3<Double>(k.q.x, k.q.y, 0))
            return UniverseCircle(q: SIMD2<Double>(p.x, p.y), r: k.r)
        }
    }

    static func box(_ circles: [UniverseCircle]) -> (SIMD2<Double>, SIMD2<Double>) {
        guard let first = circles.first else { return (SIMD2<Double>(0, 0), SIMD2<Double>(0, 0)) }
        var lo: SIMD2<Double> = first.q - first.r
        var hi: SIMD2<Double> = first.q + first.r
        for c in circles {
            lo = pointwiseMin(lo, c.q - c.r)
            hi = pointwiseMax(hi, c.q + c.r)
        }
        return (lo, hi)
    }

    func placeGalaxies(_ tops: [Int]) -> GalaxyPlacement {
        var result = GalaxyPlacement()
        let gal: [Int] = tops.sorted { a, b in
            if count[a] != count[b] { return count[a] > count[b] }
            return lessC(a, b)
        }
        result.order = gal
        for g in gal {
            var random = UniverseRandom(cSeed(g) ^ 0x7A11)
            let inclination: Double = (30 + 10 * random.unit()) * Double.pi / 180
            let phi: Double = 2 * Double.pi * random.unit()
            result.frame[g] = GraphUniverse.rotZ(phi).times(GraphUniverse.rotX(inclination))
        }
        // links between galaxies
        var shared: [Int: Int] = [:]
        let span: Int = cCount
        for (i, j) in edgePairs {
            let hi: Int = noteHome[i]
            let hj: Int = noteHome[j]
            guard hi >= 0, hj >= 0 else { continue }
            let gi: Int = top[hi]
            let gj: Int = top[hj]
            guard gi != gj else { continue }
            shared[gi * span + gj, default: 0] += 1
            shared[gj * span + gi, default: 0] += 1
        }
        guard let first = gal.first, let firstFrame = result.frame[first] else { return result }
        result.centre[first] = SIMD2<Double>(0, 0)
        var placed: [UniverseCircle] = projected(first, firstFrame)
        var placedOrder: [Int] = [first]
        var (lo, hi) = Self.box(placed)
        for g in gal.dropFirst() {
            guard let frame = result.frame[g] else { continue }
            let circles: [UniverseCircle] = projected(g, frame)
            var partner: Int = placedOrder[0]
            var partnerLinks: Int = shared[g * span + partner] ?? 0
            for h in placedOrder.dropFirst() {
                let links: Int = shared[g * span + h] ?? 0
                if links > partnerLinks {
                    partner = h
                    partnerLinks = links
                }
            }
            let partnerAt: SIMD2<Double> = result.centre[partner] ?? SIMD2<Double>(0, 0)
            var bestKey: (Double, Double, Int)?
            var bestShift = SIMD2<Double>(0, 0)
            var bestCircles: [UniverseCircle] = []
            for j in 0..<72 {
                let th: Double = Double(j) * Double.pi / 36
                let u = SIMD2<Double>(cos(th), sin(th))
                let d: Double = Self.slide(u, circles, placed, gap: 0.30)
                let shift: SIMD2<Double> = u * d
                let moved: [UniverseCircle] = circles.map { UniverseCircle(q: $0.q + shift, r: $0.r) }
                let (mlo, mhi) = Self.box(moved)
                let size: SIMD2<Double> = pointwiseMax(hi, mhi) - pointwiseMin(lo, mlo)
                let long: Double = max(size.x, size.y)
                let fit: Double = max(long, min(size.x, size.y) / 0.5)
                let apart: Double = GraphUniverse.length(shift - partnerAt)
                let key: (Double, Double, Int) = (GraphUniverse.rounded(fit, 100), GraphUniverse.rounded(apart, 100), j)
                if let held = bestKey, !(key < held) { continue }
                bestKey = key
                bestShift = shift
                bestCircles = moved
            }
            result.centre[g] = bestShift
            placed.append(contentsOf: bestCircles)
            placedOrder.append(g)
            let (mlo, mhi) = Self.box(bestCircles)
            lo = pointwiseMin(lo, mlo)
            hi = pointwiseMax(hi, mhi)
        }
        result.lo = lo
        result.hi = hi
        let size: SIMD2<Double> = hi - lo
        result.turn = size.x > size.y
        let half: SIMD2<Double> = size * 0.5
        result.half = result.turn ? SIMD2<Double>(half.y, half.x) : half
        return result
    }

    // MARK: the bodies

    mutating func emit(_ placed: GalaxyPlacement) {
        noteBody = [Int](repeating: -1, count: noteList.count)
        cBody = [Int](repeating: -1, count: cCount)
        cFrame = [UniverseFrame](repeating: .identity, count: cCount)
        cHome = [SIMD3<Double>](repeating: SIMD3<Double>(0, 0, 0), count: cCount)
        let middle: SIMD2<Double> = (placed.lo + placed.hi) * 0.5
        let quarter: UniverseFrame = GraphUniverse.rotZ(Double.pi / 2)
        for g in placed.order {
            let xy: SIMD2<Double> = (placed.centre[g] ?? middle) - middle
            var home = SIMD3<Double>(xy.x, xy.y, 0)
            var frame: UniverseFrame = placed.frame[g] ?? .identity
            if placed.turn {
                home = SIMD3<Double>(-xy.y, xy.x, 0)
                frame = quarter.times(frame)
            }
            putContainer(g, home: home, frame: frame, parentC: -1)
        }
    }

    mutating func putContainer(_ c: Int, home: SIMD3<Double>, frame: UniverseFrame, parentC: Int) {
        cHome[c] = home
        cFrame[c] = frame
        let parentBody: Int = parentC >= 0 ? cBody[parentC] : -1
        let galaxyBody: Int = containerGalaxy(c, parentC: parentC)
        var orbit: GraphOrbit = .fixed(GraphUniverse.float3(home))
        if parentC >= 0 {
            let local: SIMD3<Double> = home - cHome[parentC]
            orbit = .fixed(GraphUniverse.float3(local))
        }
        let me: Int = bodies.count
        cBody[c] = me
        let isHome: Bool = c == homeC
        let kind: UniverseRole = isHome ? .home : (isGalaxy(c) ? .galaxy : .star)
        var tier: Int = 0
        if kind == .home { tier = 1 }
        if kind == .star { tier = min(depth[c], 3) }
        let title: String = cName(c)
        let body = UniverseBody(id: cID(c), role: kind, parent: parentBody, light: -1,
                                sphere: Float(cSphere[c]), tier: tier, empty: count[c] == 0 && !isHome,
                                ringed: false, palette: palette[c], galaxy: kind == .galaxy ? me : galaxyBody,
                                count: count[c], links: 0, shell: -1, orbit: orbit,
                                home: GraphUniverse.float3(home), title: title,
                                label: Self.folderLabel(title, count: count[c]))
        bodies.append(body)
        let myGalaxy: Int = kind == .galaxy ? me : galaxyBody
        putOrbits(c, home: home, frame: frame, galaxy: myGalaxy)
        for place in places[c] {
            let k: Int = place.child
            var random = UniverseRandom(cSeed(k) ^ 0xC0DE)
            let beta: Double = 10 * Double.pi / 180 * random.signed()
            let psi: Double = 2 * Double.pi * random.unit()
            let axis = SIMD3<Double>(cos(psi), sin(psi), 0)
            let lean: UniverseFrame = GraphUniverse.rotZ(place.turn).times(UniverseFrame.about(axis, beta))
            let childFrame: UniverseFrame = frame.times(lean)
            let step: SIMD3<Double> = frame.apply(SIMD3<Double>(place.offset.x, place.offset.y, 0))
            putContainer(k, home: home + step, frame: childFrame, parentC: c)
        }
    }

    func containerGalaxy(_ c: Int, parentC: Int) -> Int {
        guard parentC >= 0 else { return -1 }
        let g: Int = top[c]
        return cBody[g]
    }

    static func folderLabel(_ name: String, count n: Int) -> String {
        let shown: String = name.count > 20 ? String(name.prefix(20)) + "\u{2026}" : name
        if n == 0 { return shown + " \u{00B7} empty" }
        let noun: String = n == 1 ? "note" : "notes"
        return shown + " \u{00B7} \(n) " + noun
    }

    static func noteLabel(_ title: String) -> String {
        title.isEmpty ? "Untitled" : title
    }

    mutating func putOrbits(_ c: Int, home: SIMD3<Double>, frame: UniverseFrame, galaxy: Int) {
        var random = UniverseRandom(cSeed(c) ^ 0x5E11)
        let base: Double = 2 * Double.pi * random.unit()
        let owner: Int = cBody[c]
        for (k, orbit) in orbits[c].enumerated() {
            let gamma: Double = 4 * Double.pi / 180 * random.signed()
            let psi: Double = 2 * Double.pi * random.unit()
            let axis = SIMD3<Double>(cos(psi), sin(psi), 0)
            let plane: UniverseFrame = frame.times(UniverseFrame.about(axis, gamma))
            let r: Double = orbit.radius
            let scaled: Double = pow(r / 1.5, 1.5) * 90
            let period: Double = GraphUniverse.clamp(scaled, 45, 480)
            let rate: Double = 2 * Double.pi / period
            let start: Double = base + Double(k) * GraphUniverse.golden
            let shellIndex: Int = shells.count
            shells.append(UniverseShell(owner: owner, radius: Float(r), u: GraphUniverse.float3(plane.x),
                                        v: GraphUniverse.float3(plane.y)))
            let m: Double = Double(orbit.members.count)
            for (j, i) in orbit.members.enumerated() {
                let phase: Double = start + 2 * Double.pi * Double(j) / m
                let path: GraphOrbit = .circle(radius: Float(r), u: GraphUniverse.float3(plane.x),
                                               v: GraphUniverse.float3(plane.y), phase: Float(phase),
                                               rate: Float(rate))
                let at: SIMD3<Double> = home + ring(plane, r, phase)
                putNote(i, parent: owner, light: owner, galaxy: galaxy, shell: shellIndex, orbit: path,
                        home: at, palette: palette[c])
                putMoons(i, plane: plane, planetHome: at, light: owner, galaxy: galaxy)
            }
        }
    }

    func ring(_ plane: UniverseFrame, _ r: Double, _ angle: Double) -> SIMD3<Double> {
        let x: SIMD3<Double> = plane.x * (cos(angle) * r)
        let y: SIMD3<Double> = plane.y * (sin(angle) * r)
        return x + y
    }

    mutating func putMoons(_ p: Int, plane: UniverseFrame, planetHome: SIMD3<Double>, light: Int, galaxy: Int) {
        let moons: [Int] = moonsOf[p]
        guard !moons.isEmpty else { return }
        var random = UniverseRandom(nSeed(p) ^ 0x300)
        let delta: Double = 10 * Double.pi / 180 * random.signed()
        let psi: Double = 2 * Double.pi * random.unit()
        let axis = SIMD3<Double>(cos(psi), sin(psi), 0)
        let tilted: UniverseFrame = plane.times(UniverseFrame.about(axis, delta))
        let am: Double = moonRing(p)
        let scaled: Double = pow(am / 0.4, 1.5) * 24
        let period: Double = GraphUniverse.clamp(scaled, 16, 40)
        let rate: Double = 2 * Double.pi / period
        let start: Double = 2 * Double.pi * random.unit()
        let m: Double = Double(moons.count)
        let planetBody: Int = noteBody[p]
        for (j, i) in moons.enumerated() {
            let phase: Double = start + 2 * Double.pi * Double(j) / m
            let path: GraphOrbit = .circle(radius: Float(am), u: GraphUniverse.float3(tilted.x),
                                           v: GraphUniverse.float3(tilted.y), phase: Float(phase),
                                           rate: Float(rate))
            let at: SIMD3<Double> = planetHome + ring(tilted, am, phase)
            putNote(i, parent: planetBody, light: light, galaxy: galaxy, shell: -1, orbit: path, home: at,
                    palette: 0)
        }
    }

    mutating func putNote(_ i: Int, parent: Int, light: Int, galaxy: Int, shell: Int, orbit: GraphOrbit,
                          home: SIMD3<Double>, palette: Int) {
        let note: UniverseNote = noteList[i]
        let kinds: [UniverseRole] = [.gasGiant, .rocky, .moon, .pulsar, .comet, .oort]
        let body = UniverseBody(id: note.id, role: kinds[role[i]], parent: parent, light: light,
                                sphere: Float(sphere[i]), tier: 0, empty: false, ringed: ringed[i],
                                palette: palette, galaxy: galaxy, count: 0, links: nbr[i].count,
                                shell: shell, orbit: orbit, home: GraphUniverse.float3(home),
                                title: note.title, label: Self.noteLabel(note.title))
        noteBody[i] = bodies.count
        bodies.append(body)
    }

    // MARK: comets

    mutating func emitComets(_ half: SIMD2<Double>) {
        let e: Double = GraphUniverse.cometE
        var galaxyRank: [Int: Int] = [:]
        let gal: [Int] = (0..<cCount).filter { parent[$0] < 0 }.sorted { a, b in
            if count[a] != count[b] { return count[a] > count[b] }
            return lessC(a, b)
        }
        for (k, g) in gal.enumerated() { galaxyRank[g] = k }
        for (k, i) in loose.enumerated() {
            if k >= GraphUniverse.activeComets {
                putOort(i, index: k - GraphUniverse.activeComets, half: half)
                continue
            }
            var tally: [Int: Int] = [:]
            for m in nbr[i] where noteHome[m] >= 0 { tally[top[noteHome[m]], default: 0] += 1 }
            var target: Int = -1
            for (g, n) in tally {
                guard target >= 0 else {
                    target = g
                    continue
                }
                let held: Int = tally[target] ?? 0
                if n != held {
                    if n > held { target = g }
                } else if count[g] != count[target] {
                    if count[g] > count[target] { target = g }
                } else if (galaxyRank[g] ?? 0) < (galaxyRank[target] ?? 0) {
                    target = g
                }
            }
            var random = UniverseRandom(nSeed(i) ^ 0xC0)
            var u = SIMD2<Double>(0, 0)
            var found: Bool = false
            if target >= 0 {
                let at: SIMD3<Double> = cHome[target]
                let xy = SIMD2<Double>(at.x, at.y)
                let size: Double = GraphUniverse.length(xy)
                if size > 0.5 {
                    u = xy / size
                    found = true
                }
            }
            if !found {
                let angle: Double = 2 * Double.pi * random.unit() + Double(k) * GraphUniverse.golden
                u = SIMD2<Double>(cos(angle), sin(angle))
            }
            let v = SIMD2<Double>(-u.y, u.x)
            let ax: Double = Self.reach(u.x, v.x, half.x, e: e)
            let ay: Double = Self.reach(u.y, v.y, half.y, e: e)
            let a: Double = min(ax, ay)
            let beta: Double = 12 * Double.pi / 180 * random.signed()
            let big = SIMD3<Double>(u.x, u.y, 0)
            let side = SIMD3<Double>(v.x, v.y, 0)
            let tilted: SIMD3<Double> = GraphUniverse.rotate(side, axis: big, angle: beta)
            let scaled: Double = pow(a / 5, 1.5) * 240
            let period: Double = GraphUniverse.clamp(scaled, 150, 600)
            let spread: Double = Double(k) * 0.618034 + random.unit()
            let frac: Double = spread - spread.rounded(.down)
            let m0: Double = 2 * Double.pi * frac
            let path: GraphOrbit = .kepler(a: Float(a), e: Float(e), u: GraphUniverse.float3(big),
                                           v: GraphUniverse.float3(tilted), phase: Float(m0),
                                           rate: Float(2 * Double.pi / period))
            let start: SIMD3<Float> = GraphUniverse.offset(path, time: 0)
            putLoose(i, orbit: path, home: start, light: -2)
        }
    }

    /// The largest semi-major axis that keeps a comet's ellipse (focus at
    /// the origin) inside `half` along one axis.
    static func reach(_ ux: Double, _ vx: Double, _ half: Double, e: Double) -> Double {
        let squeeze: Double = 1 - e * e
        let across: Double = (ux * ux + squeeze * vx * vx).squareRoot()
        let need: Double = e * abs(ux) + across
        guard need > 1e-9 else { return 1e9 }
        return 0.95 * half / need
    }

    mutating func putOort(_ i: Int, index j: Int, half: SIMD2<Double>) {
        var random = UniverseRandom(nSeed(i))
        let z: Double = 0.25 * random.signed()
        let ox: Double = half.x * 1.06 + 0.3
        let oy: Double = half.y * 1.06 + 0.3
        let phase: Double = Double(j) * GraphUniverse.golden
        let path: GraphOrbit = .ring(x: Float(ox), y: Float(oy), z: Float(z), phase: Float(phase),
                                     rate: Float(2 * Double.pi / 1200))
        let start: SIMD3<Float> = GraphUniverse.offset(path, time: 0)
        putLoose(i, orbit: path, home: start, light: -1)
    }

    mutating func putLoose(_ i: Int, orbit: GraphOrbit, home: SIMD3<Float>, light: Int) {
        let note: UniverseNote = noteList[i]
        let kind: UniverseRole = role[i] == 4 ? .comet : .oort
        let body = UniverseBody(id: note.id, role: kind, parent: -1, light: light, sphere: Float(sphere[i]),
                                tier: 0, empty: false, ringed: false, palette: 0, galaxy: -1, count: 0,
                                links: nbr[i].count, shell: -1, orbit: orbit, home: home, title: note.title,
                                label: Self.noteLabel(note.title))
        noteBody[i] = bodies.count
        bodies.append(body)
    }

    // MARK: links, framing and the summary

    mutating func finish(_ placed: GalaxyPlacement) -> UniversePlan {
        var links: [UniverseLink] = []
        for (i, j) in edgePairs {
            let a: Int = noteBody[i]
            let b: Int = noteBody[j]
            guard a >= 0, b >= 0 else { continue }
            links.append(UniverseLink(a: a, b: b, kind: linkKind(i, j), centre: linkCentre(i, j)))
        }
        var envelope: [SIMD3<Float>] = []
        for g in placed.order {
            envelope += sample(g, around: cHome[g])
        }
        for body in bodies where body.role == .comet || body.role == .oort {
            envelope += Self.trace(body.orbit)
        }
        var systems = [[SIMD3<Float>]](repeating: [], count: bodies.count)
        var lights: [Int] = []
        for c in 0..<cCount {
            let b: Int = cBody[c]
            guard b >= 0 else { continue }
            systems[b] = sample(c, around: SIMD3<Double>(0, 0, 0))
            if !bodies[b].empty { lights.append(b) }
        }
        lights.sort()
        return UniversePlan(bodies: bodies, shells: shells, links: links, envelope: envelope,
                            systems: systems, lights: lights, summary: Self.summary(bodies))
    }

    func linkKind(_ i: Int, _ j: Int) -> Int {
        if moonPlanet[i] == j || moonPlanet[j] == i { return 3 }
        let hi: Int = noteHome[i]
        let hj: Int = noteHome[j]
        if hi < 0 || hj < 0 { return 2 }
        if hi == hj { return 0 }
        return top[hi] == top[hj] ? 1 : 2
    }

    func linkCentre(_ i: Int, _ j: Int) -> Int {
        guard linkKind(i, j) == 1 else { return -1 }
        return cBody[top[noteHome[i]]]
    }

    /// A container's composite circles, 8 points each, in space
    /// coordinates about `origin`.
    func sample(_ c: Int, around origin: SIMD3<Double>) -> [SIMD3<Float>] {
        var out: [SIMD3<Float>] = []
        let frame: UniverseFrame = cFrame[c]
        for circle in comp[c] {
            for k in 0..<8 {
                let a: Double = Double(k) * Double.pi / 4
                let x: Double = circle.q.x + circle.r * cos(a)
                let y: Double = circle.q.y + circle.r * sin(a)
                let p: SIMD3<Double> = origin + frame.apply(SIMD3<Double>(x, y, 0))
                out.append(GraphUniverse.float3(p))
            }
        }
        return out
    }

    /// Points round a comet's ellipse (16) or the Oort ring (24).
    static func trace(_ orbit: GraphOrbit) -> [SIMD3<Float>] {
        var out: [SIMD3<Float>] = []
        switch orbit {
        case .kepler(let a, let e, let u, let v, _, _):
            let b: Float = a * (1 - e * e).squareRoot()
            for k in 0..<16 {
                let big: Float = Float(k) * Float.pi / 8
                let x: Float = a * (cos(big) - e)
                let y: Float = b * sin(big)
                out.append(u * x + v * y)
            }
        case .ring(let x, let y, let z, _, _):
            for k in 0..<24 {
                let angle: Float = Float(k) * Float.pi / 12
                out.append(SIMD3<Float>(x * cos(angle), y * sin(angle), z))
            }
        default:
            break
        }
        return out
    }

    static func summary(_ bodies: [UniverseBody]) -> String {
        var galaxies: Int = 0
        var stars: Int = 0
        var planets: Int = 0
        var moons: Int = 0
        var pulsars: Int = 0
        var comets: Int = 0
        for body in bodies {
            switch body.role {
            case .galaxy: galaxies += 1
            case .star, .home: stars += 1
            case .gasGiant, .rocky: planets += 1
            case .moon: moons += 1
            case .pulsar: pulsars += 1
            case .comet, .oort: comets += 1
            }
        }
        let parts: [(Int, String, String)] = [
            (galaxies, "galaxy", "galaxies"), (stars, "star", "stars"), (planets, "planet", "planets"),
            (moons, "moon", "moons"), (pulsars, "pulsar", "pulsars"), (comets, "comet", "comets")
        ]
        var words: [String] = []
        for (n, one, many) in parts where n > 0 {
            words.append("\(n) " + (n == 1 ? one : many))
        }
        return words.joined(separator: ", ")
    }
}
