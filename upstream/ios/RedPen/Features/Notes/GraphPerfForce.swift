// The Performance map's incremental layout: a short-range force refinement
// of the seed (GraphPerfLayout), done a slice of notes at a time so that no
// frame waits on it. The seed is already a whole, overlap-free map; this
// settles each folder's ball so linked notes draw together and crowded
// ones part, over the first second or two the map is up.
//
// - Every note is pulled towards the rest point of each link inside its
//   folder (one spacing from the other end, more round a well-linked note:
//   room on a sphere for all its neighbours), the targets averaged, so a hub
//   with 300 links lands among its neighbours instead of being torn by
//   their sum.
// - A link into another folder only leans the note a little towards that
//   side; a spring across the map would pile every such note onto one
//   point of its ball's edge.
// - Notes closer than `cutoff` push apart. They are found through a hashed
//   grid of cells twice the cutoff, so a note reads the 2 x 2 x 2 cells
//   nearest it; the grid keeps its own copy of where the notes were when
//   the sweep began, in cell order, so those reads run along memory.
// - A weak pull to the folder's centre keeps the ball round, and the note
//   is clamped into its folder's ball and clear of its hub, so systems
//   never overlap and the seed's packing stays valid. Hubs never move.
//
// Notes are visited in a fixed order along a Morton curve through space
// (from the seed), so each note's neighbours are still in cache from the
// last one. Each step visits up to `budget` notes in that order, Gauss-
// Seidel style (in place), and never runs past the end of a sweep: the
// grid is rebuilt only when a sweep begins, so the result does not depend
// on how the sweeps were sliced into steps. A step costs O(budget), the
// first step of a sweep O(notes) more for the grid. Moves are capped and the
// cap cools each sweep; after `sweeps` sweeps, or once a whole sweep moves
// nothing noticeably, it is settled and a step does nothing.
//
// Positions are kept as the GPU takes them (x, y, z, radius per body,
// notes then hubs), so the renderer copies them straight into its buffer.
// The inner loops read and write through unsafe buffer pointers: a
// quarter of the time of checked arrays in an optimised build, a sixth in
// a debug one. Foundation only, free of Stethoscore types.
import Foundation

nonisolated struct GraphPerfForce: Sendable {
    struct Tuning: Sendable, Equatable {
        /// How far towards its links' averaged rest point a note moves per
        /// visit, and at most how far (in spacings): never so far that the
        /// push of a crowded neighbour cannot hold it off.
        var spring: Float = 0.3
        var springCap: Float = 0.08
        /// How far (in spacings) links into other folders lean a note, at most.
        var lean: Float = 0.03
        /// Notes closer than this many spacings push apart...
        var cutoff: Float = 0.9
        /// ...each correcting this share of its half of the overlap per visit.
        var repel: Float = 1
        /// The pull to the system's centre, per visit.
        var centre: Float = 0.002
        /// The most a note moves in one visit, in spacings, in the first
        /// sweep; it shrinks by `cooling` every sweep after.
        var maxStep: Float = 0.3
        var cooling: Float = 0.85
        /// Sweeps before it settles.
        var sweeps: Int = 16
        /// A sweep whose largest move is under this many spacings settles it early.
        var still: Float = 0.004
    }

    let tuning: Tuning
    let noteCount: Int
    let nodeCount: Int
    let spacing: Float
    /// x, y, z, radius per body: notes (graph slots), then one hub per folder.
    private(set) var xyzr: [Float]
    /// The next place in the visiting order a step takes, and the sweep it is in.
    private(set) var cursor: Int = 0
    private(set) var sweep: Int = 0
    /// The largest move in the sweep so far, and in the last whole sweep (world units).
    private(set) var sweepLargest: Float = 0
    private(set) var lastSweepLargest: Float = .infinity
    /// Bumped by every step that moved something (the renderer's upload key).
    private(set) var version: Int = 0
    private var settledEarly = false

    // the graph, as the loops read it
    private let adjStart: [Int32]
    private let adjacency: [Int32]
    private let system: [Int32]
    /// Per note: its links' rest length, in spacings (more round a well-linked note).
    private let reach: [Float]
    /// Per system: centre x, y, z, and how near and far a note's centre may
    /// be from it (before taking off the note's own radius).
    private let ball: [Float]
    /// The notes in visiting order: along a Morton curve through the seed.
    private let order: [Int32]

    // the grid: notes bucketed by hashed cell, and per bucket entry the
    // note, its cell key and where it was when the sweep began
    private var bucketStart: [Int32]
    private var entryNote: [Int32]
    private var entryKey: [Int64]
    private var entryXYZ: [Float]
    private var noteKey: [Int64]
    private let tableBits: Int
    private let cell: Float

    init(graph g: GraphPerfGraph, layout: GraphPerfLayout, tuning: Tuning = Tuning()) {
        self.tuning = tuning
        noteCount = g.noteCount
        nodeCount = g.nodeCount
        spacing = layout.spacing
        var p = [Float](repeating: 0, count: 4 * g.nodeCount)
        for i in 0..<g.nodeCount {
            p[4 * i] = layout.positions[i].x
            p[4 * i + 1] = layout.positions[i].y
            p[4 * i + 2] = layout.positions[i].z
            p[4 * i + 3] = layout.radius[i]
        }
        xyzr = p
        adjStart = g.adjStart
        adjacency = g.adjacency
        system = g.systemOfNote
        // round a note with D links, room for D on a sphere: 4 pi r^2 >= 1.1 D
        reach = (0..<g.noteCount).map { max(1, 0.3 * Float(g.degree($0)).squareRoot()) }
        var b = [Float](repeating: 0, count: 5 * g.systemCount)
        for s in 0..<g.systemCount {
            let c = layout.systemCentre[s]
            b[5 * s] = c.x
            b[5 * s + 1] = c.y
            b[5 * s + 2] = c.z
            // clear of the hub (a folder's) by a hair, inside the ball
            b[5 * s + 3] = s < g.folderCount ? layout.radius[g.noteCount + s] + 0.01 : 0
            b[5 * s + 4] = layout.coreRadius[s] - 0.001
        }
        ball = b
        cell = max(2 * tuning.cutoff * layout.spacing, 1e-3)
        order = Self.mortonOrder(layout.positions, count: g.noteCount, cell: cell)
        var bits = 1
        while (1 << bits) < 2 * max(g.noteCount, 1) { bits += 1 }
        tableBits = bits
        bucketStart = [Int32](repeating: 0, count: (1 << bits) + 1)
        entryNote = [Int32](repeating: 0, count: g.noteCount)
        entryKey = [Int64](repeating: 0, count: g.noteCount)
        entryXYZ = [Float](repeating: 0, count: 3 * g.noteCount)
        noteKey = [Int64](repeating: 0, count: g.noteCount)
    }

    var isSettled: Bool { noteCount == 0 || sweep >= tuning.sweeps || settledEarly }

    /// The step cap this sweep, in world units.
    var stepCap: Float { tuning.maxStep * spacing * pow(tuning.cooling, Float(sweep)) }

    /// Body `i`'s position.
    func position(_ i: Int) -> SIMD3<Float> {
        SIMD3(xyzr[4 * i], xyzr[4 * i + 1], xyzr[4 * i + 2])
    }

    /// Visits up to `budget` notes from the cursor, stopping at the end of
    /// the sweep. Returns how many it visited (0 once settled).
    @discardableResult
    mutating func step(budget: Int) -> Int {
        guard !isSettled, budget > 0 else { return 0 }
        if cursor == 0 { rebuildGrid() }
        let from = cursor
        let to = min(noteCount, cursor + budget)
        let largest = relax(from: from, to: to)
        sweepLargest = max(sweepLargest, largest)
        cursor = to
        version += 1
        if cursor == noteCount {
            cursor = 0
            sweep += 1
            lastSweepLargest = sweepLargest
            if sweepLargest < tuning.still * spacing { settledEarly = true }
            sweepLargest = 0
        }
        return to - from
    }

    /// Runs whole sweeps until settled (tests, and a map shown still).
    mutating func settle() {
        while !isSettled { step(budget: max(noteCount, 1)) }
    }

    // MARK: - The grid

    @inline(__always)
    private static func coordinate(_ v: Float, _ cell: Float) -> Int64 {
        Int64((v / cell).rounded(.down))
    }

    /// Three 21-bit cell coordinates (offset to be positive) in one key.
    @inline(__always)
    private static func key(_ cx: Int64, _ cy: Int64, _ cz: Int64) -> Int64 {
        let o: Int64 = 1 << 20
        return ((cx + o) & 0x1F_FFFF) << 42 | ((cy + o) & 0x1F_FFFF) << 21 | ((cz + o) & 0x1F_FFFF)
    }

    @inline(__always)
    private static func bucket(_ key: Int64, _ bits: Int) -> Int {
        Int(truncatingIfNeeded: (UInt64(bitPattern: key) &* 0x9E37_79B9_7F4A_7C15) >> UInt64(64 - bits))
    }

    /// Spreads the low 21 bits of `v` to every third bit.
    private static func spread(_ v: UInt64) -> UInt64 {
        var x = v & 0x1F_FFFF
        x = (x | x << 32) & 0x1F_0000_0000_FFFF
        x = (x | x << 16) & 0x1F_0000_FF00_00FF
        x = (x | x << 8) & 0x100F_00F0_0F00_F00F
        x = (x | x << 4) & 0x10C3_0C30_C30C_30C3
        x = (x | x << 2) & 0x1249_2492_4924_9249
        return x
    }

    /// Note slots sorted along a Morton curve through their cells.
    private static func mortonOrder(_ positions: [SIMD3<Float>], count: Int, cell: Float) -> [Int32] {
        guard count > 0 else { return [] }
        var lo = positions[0]
        for i in 0..<count { lo = pointwiseMin(lo, positions[i]) }
        var keys = [UInt64](repeating: 0, count: count)
        var biggest: UInt64 = 0
        for i in 0..<count {
            let c = (positions[i] - lo) / cell
            let code = spread(UInt64(max(c.x, 0))) | spread(UInt64(max(c.y, 0))) << 1 | spread(UInt64(max(c.z, 0))) << 2
            keys[i] = code
            biggest = max(biggest, code)
        }
        // code, then slot, in one key when they fit; else a comparison sort
        let slotBits = 64 - UInt64(max(count - 1, 1)).leadingZeroBitCount
        let codeBits = 64 - max(biggest, 1).leadingZeroBitCount
        if codeBits + slotBits <= 64 {
            var packed = (0..<count).map { keys[$0] << UInt64(slotBits) | UInt64($0) }
            GraphPerfGraph.radixSort(&packed, maxKey: max(biggest, 1) << UInt64(slotBits) | UInt64(count))
            let mask: UInt64 = (1 << UInt64(slotBits)) - 1
            return packed.map { Int32(truncatingIfNeeded: $0 & mask) }
        }
        return (0..<count).sorted { keys[$0] != keys[$1] ? keys[$0] < keys[$1] : $0 < $1 }.map { Int32($0) }
    }

    private mutating func rebuildGrid() {
        let n = noteCount, bits = tableBits, size = 1 << bits, c = cell
        xyzr.withUnsafeBufferPointer { P in
        noteKey.withUnsafeMutableBufferPointer { K in
        bucketStart.withUnsafeMutableBufferPointer { S in
        entryNote.withUnsafeMutableBufferPointer { I in
        entryKey.withUnsafeMutableBufferPointer { EK in
        entryXYZ.withUnsafeMutableBufferPointer { E in
            for b in 0...size { S[b] = 0 }
            for i in 0..<n {
                let k = Self.key(Self.coordinate(P[4 * i], c), Self.coordinate(P[4 * i + 1], c),
                                 Self.coordinate(P[4 * i + 2], c))
                K[i] = k
                S[Self.bucket(k, bits) + 1] += 1
            }
            for b in 0..<size { S[b + 1] += S[b] }
            // fill, then put the starts back (fill walked them on)
            for i in 0..<n {
                let b = Self.bucket(K[i], bits)
                let q = Int(S[b])
                I[q] = Int32(i)
                EK[q] = K[i]
                E[3 * q] = P[4 * i]
                E[3 * q + 1] = P[4 * i + 1]
                E[3 * q + 2] = P[4 * i + 2]
                S[b] += 1
            }
            var b = size
            while b > 0 {
                S[b] = S[b - 1]
                b -= 1
            }
            S[0] = 0
        }
        }
        }
        }
        }
        }
    }

    // MARK: - The relaxation

    /// Moves the notes at places from..<to of the visiting order; returns the largest move.
    private mutating func relax(from: Int, to: Int) -> Float {
        let t = tuning
        let unit = spacing
        let cut = tuning.cutoff * spacing
        let cut2 = cut * cut
        let size = cell
        let cap = stepCap
        let lean = tuning.lean * spacing
        let springCap = tuning.springCap * spacing
        let bits = tableBits
        var largest: Float = 0
        order.withUnsafeBufferPointer { O in
        adjStart.withUnsafeBufferPointer { AS in
        adjacency.withUnsafeBufferPointer { A in
        system.withUnsafeBufferPointer { SY in
        reach.withUnsafeBufferPointer { R in
        ball.withUnsafeBufferPointer { B in
        bucketStart.withUnsafeBufferPointer { BS in
        entryNote.withUnsafeBufferPointer { EN in
        entryKey.withUnsafeBufferPointer { EK in
        entryXYZ.withUnsafeBufferPointer { E in
        xyzr.withUnsafeMutableBufferPointer { P in
            for place in from..<to {
                let i = Int(O[place])
                let px = P[4 * i], py = P[4 * i + 1], pz = P[4 * i + 2], pr = P[4 * i + 3]
                let s = Int(SY[i])
                var dx: Float = 0, dy: Float = 0, dz: Float = 0

                // links inside the folder: towards the mean of their rest
                // points; links out of it: a lean towards their side
                var tx: Float = 0, ty: Float = 0, tz: Float = 0, tw: Float = 0
                var lx: Float = 0, ly: Float = 0, lz: Float = 0, ln: Float = 0
                let mine = R[i]
                var e = Int(AS[i])
                let end = Int(AS[i + 1])
                while e < end {
                    let j = Int(A[e])
                    e += 1
                    let vx = P[4 * j] - px, vy = P[4 * j + 1] - py, vz = P[4 * j + 2] - pz
                    let len = (vx * vx + vy * vy + vz * vz).squareRoot()
                    guard len > 1e-6 else { continue }
                    if Int(SY[j]) == s {
                        let k = unit * max(mine, R[j]) / len
                        tx += P[4 * j] - vx * k
                        ty += P[4 * j + 1] - vy * k
                        tz += P[4 * j + 2] - vz * k
                        tw += 1
                    } else {
                        lx += vx / len
                        ly += vy / len
                        lz += vz / len
                        ln += 1
                    }
                }
                if tw > 0 {
                    var ax = (tx / tw - px) * t.spring, ay = (ty / tw - py) * t.spring, az = (tz / tw - pz) * t.spring
                    let am = (ax * ax + ay * ay + az * az).squareRoot()
                    if am > springCap {
                        let k = springCap / am
                        ax *= k
                        ay *= k
                        az *= k
                    }
                    dx += ax
                    dy += ay
                    dz += az
                }
                if ln > 0 {
                    let m = (lx * lx + ly * ly + lz * lz).squareRoot()
                    if m > 1e-6 {
                        let k = lean * min(ln, 3) / 3 / m
                        dx += lx * k
                        dy += ly * k
                        dz += lz * k
                    }
                }

                // close neighbours: apart, from the 2 x 2 x 2 cells nearest
                let fx = px / size, fy = py / size, fz = pz / size
                let cx = Int64(fx.rounded(.down)), cy = Int64(fy.rounded(.down)), cz = Int64(fz.rounded(.down))
                let sx: Int64 = fx - Float(cx) < 0.5 ? -1 : 1
                let sy: Int64 = fy - Float(cy) < 0.5 ? -1 : 1
                let sz: Int64 = fz - Float(cz) < 0.5 ? -1 : 1
                var rx: Float = 0, ry: Float = 0, rz: Float = 0
                var corner = 0
                while corner < 8 {
                    let key = Self.key(cx + (corner & 1 == 0 ? 0 : sx), cy + (corner & 2 == 0 ? 0 : sy),
                                       cz + (corner & 4 == 0 ? 0 : sz))
                    corner += 1
                    let b = Self.bucket(key, bits)
                    var q = Int(BS[b])
                    let qEnd = Int(BS[b + 1])
                    while q < qEnd {
                        let k = Int(EN[q])
                        let same = EK[q] == key
                        let ex = E[3 * q], ey = E[3 * q + 1], ez = E[3 * q + 2]
                        q += 1
                        if k == i || !same { continue }
                        let vx = px - ex, vy = py - ey, vz = pz - ez
                        let d2 = vx * vx + vy * vy + vz * vz
                        if d2 >= cut2 { continue }
                        if d2 < 1e-12 {
                            // on top of each other: the lower slot steps aside
                            if i < k { rx += cut * 0.5 } else { rx -= cut * 0.5 }
                            continue
                        }
                        let d = d2.squareRoot()
                        let push = (cut - d) / d * 0.5
                        rx += vx * push
                        ry += vy * push
                        rz += vz * push
                    }
                }
                dx += rx * t.repel
                dy += ry * t.repel
                dz += rz * t.repel

                // the system's centre
                let bx = B[5 * s], by = B[5 * s + 1], bz = B[5 * s + 2]
                dx += (bx - px) * t.centre
                dy += (by - py) * t.centre
                dz += (bz - pz) * t.centre

                // capped, then clamped into the ball and clear of the hub
                let m = (dx * dx + dy * dy + dz * dz).squareRoot()
                if m > cap {
                    let k = cap / m
                    dx *= k
                    dy *= k
                    dz *= k
                }
                var nx = px + dx, ny = py + dy, nz = pz + dz
                let gx = nx - bx, gy = ny - by, gz = nz - bz
                let r = (gx * gx + gy * gy + gz * gz).squareRoot()
                let inner = B[5 * s + 3] > 0 ? B[5 * s + 3] + pr : 0
                let outer = max(B[5 * s + 4] - pr, inner)
                if r > outer, r > 1e-6 {
                    let k = outer / r
                    nx = bx + gx * k
                    ny = by + gy * k
                    nz = bz + gz * k
                } else if r < inner {
                    if r > 1e-6 {
                        let k = inner / r
                        nx = bx + gx * k
                        ny = by + gy * k
                        nz = bz + gz * k
                    } else {
                        nx = bx + inner
                        ny = by
                        nz = bz
                    }
                }
                let mx = nx - px, my = ny - py, mz = nz - pz
                largest = max(largest, (mx * mx + my * my + mz * mz).squareRoot())
                P[4 * i] = nx
                P[4 * i + 1] = ny
                P[4 * i + 2] = nz
            }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        return largest
    }
}
