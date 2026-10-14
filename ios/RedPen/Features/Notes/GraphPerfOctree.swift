// The million map's chunks (plan 4e): the map cut into cubes in an
// octree, like a block game's chunks, so a frame only looks at what is near
// and on screen.
//
// - Bodies are sorted along a Morton curve (21 bits an axis), so every
//   cell of the octree holds one contiguous run of them ("slots"); a cell
//   with a single child is skipped, so the tree has no empty chains.
// - A cell opens into its children until it holds at most `leafSize`
//   bodies: a leaf, the chunk a frame draws, lays out and streams. Cells
//   are numbered depth first, so a cell's subtree, its leaves and the
//   bundle cells under it are each one contiguous range.
// - Every cell keeps its summary: tight box, centroid, spread (root mean
//   square distance from the centroid), how many bodies and their mixed
//   colour - what a far chunk is drawn as.
// - Positions go to the GPU as 16-bit numbers inside their leaf's box
//   (GraphPerfQuantize): 8 bytes a body with its leaf, a million in 8 MB.
// - Links are listed per leaf (a link between two leaves in both lists, its
//   home end first), and summed into bundles between the cells of one cut
//   across the tree (GraphPerfBundles) for far away.
//
// Foundation only, free of Stethoscore types: tested on Linux
// (Tests/GraphPerfChunkTests.swift).
import Foundation

nonisolated struct GraphPerfOctree: Sendable {
    /// One cell: a cube of the octree, with the summary drawn for it far away.
    struct Cell: Sendable, Equatable {
        /// The tight box round its bodies.
        var lo: SIMD3<Float>
        var hi: SIMD3<Float>
        var centroid: SIMD3<Float>
        /// Root mean square distance of its bodies from the centroid.
        var spread: Float
        /// Its bodies: slots first ..< first + count.
        var first: Int32
        var count: Int32
        var parent: Int32
        /// Depth in the octree (the root 0; a skipped chain still counts).
        var depth: Int32
        /// Cells in its subtree, itself included: cells i ..< i + subtree.
        var subtree: Int32
        /// Its children: childList[childStart ..< childStart + childCount].
        var childStart: Int32
        var childCount: Int32
        /// The leaves under it: leafStart ..< leafEnd; its own leaf index
        /// when it is one, else -1.
        var leafStart: Int32
        var leafEnd: Int32
        var leaf: Int32
        /// The mean of its bodies' colours (RGBA8, red lowest, opaque).
        var colour: UInt32

        var isLeaf: Bool { leaf >= 0 }
        /// The ball round its box.
        var ballCentre: SIMD3<Float> { (lo + hi) * 0.5 }
        var ballRadius: Float {
            let d = hi - lo
            return max((d * d).sum().squareRoot() * 0.5, 1e-3)
        }
    }

    static let mortonBits: Int = 21
    /// The leaf index rides in 16 bits on the GPU.
    static let maxLeaves: Int = 65_535

    let cells: [Cell]
    let childList: [Int32]
    /// Leaf index to its cell.
    let leafCell: [Int32]
    /// Slot (sorted place) to body, and body to slot.
    let order: [Int32]
    let slotOf: [Int32]
    /// Slot to its leaf.
    let leafOfSlot: [UInt16]
    let leafSize: Int

    var leafCount: Int { leafCell.count }
    var bodyCount: Int { order.count }
    var root: Cell { cells[0] }

    /// The cell holding slot `s` at the leaf level.
    func leaf(ofSlot s: Int) -> Int { Int(leafOfSlot[s]) }

    func children(_ c: Int) -> ArraySlice<Int32> {
        let cell = cells[c]
        return childList[Int(cell.childStart) ..< Int(cell.childStart + cell.childCount)]
    }

    // MARK: - Building

    /// The octree of `positions` (one per body) with `colours` (RGBA8 per
    /// body). A leaf holds at most `leafSize` bodies (more only where
    /// bodies share a Morton cell at the finest level); `leafSize` grows if
    /// the leaves would not fit in 16 bits.
    init(positions: [SIMD3<Float>], colours: [UInt32], leafSize wanted: Int = 384) {
        let n = positions.count
        var size = max(wanted, 1)
        if n / size > Self.maxLeaves / 2 { size = n / (Self.maxLeaves / 2) + 1 }
        leafSize = size

        // the bounding cube
        var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
        for p in positions where p.x.isFinite && p.y.isFinite && p.z.isFinite {
            lo = pointwiseMin(lo, p)
            hi = pointwiseMax(hi, p)
        }
        if n == 0 || !lo.x.isFinite { lo = .zero; hi = .zero }
        let side: Float = max((hi - lo).max(), 1e-3) * 1.0001

        // Morton codes, sorted (ties by body, so the order never depends on the sort)
        let scale: Float = Float(1 << Self.mortonBits) / side
        let top: Float = Float((1 << Self.mortonBits) - 1)
        var keyed = [(code: UInt64, body: Int32)]()
        keyed.reserveCapacity(n)
        for i in 0..<n {
            var p = positions[i]
            if !(p.x.isFinite && p.y.isFinite && p.z.isFinite) { p = lo }
            let q = pointwiseMin(pointwiseMax((p - lo) * scale, SIMD3(repeating: 0)), SIMD3(repeating: top))
            keyed.append((Self.morton(UInt64(q.x), UInt64(q.y), UInt64(q.z)), Int32(i)))
        }
        keyed.sort { $0.code != $1.code ? $0.code < $1.code : $0.body < $1.body }
        let codes: [UInt64] = keyed.map { $0.code }
        let ord: [Int32] = keyed.map { $0.body }
        var slot = [Int32](repeating: 0, count: n)
        for s in 0..<n { slot[Int(ord[s])] = Int32(s) }
        order = ord
        slotOf = slot

        // the cells, depth first
        var built: [Cell] = []
        var kids: [[Int32]] = []
        var leaves: [Int32] = []
        built.reserveCapacity(2 * n / size + 16)
        func split(_ a: Int, _ b: Int, depth: Int) -> [(Int, Int)] {
            // the runs of a..<b that differ in the 3 bits below `depth`
            let shift = UInt64(3 * (Self.mortonBits - 1 - depth))
            var runs: [(Int, Int)] = []
            var s = a
            while s < b {
                let octant = (codes[s] >> shift) & 7
                var lo2 = s, hi2 = b
                while lo2 < hi2 {
                    let mid = (lo2 + hi2) / 2
                    if (codes[mid] >> shift) & 7 <= octant { lo2 = mid + 1 } else { hi2 = mid }
                }
                runs.append((s, lo2))
                s = lo2
            }
            return runs
        }
        func make(_ a: Int, _ b: Int, depth startDepth: Int, parent: Int32) -> Int32 {
            let index = Int32(built.count)
            built.append(Cell(lo: .zero, hi: .zero, centroid: .zero, spread: 0, first: Int32(a), count: Int32(b - a),
                              parent: parent, depth: Int32(startDepth), subtree: 1, childStart: 0, childCount: 0,
                              leafStart: Int32(leaves.count), leafEnd: Int32(leaves.count), leaf: -1, colour: 0))
            kids.append([])
            // skip levels where every body falls in one octant
            var depth = startDepth
            var runs: [(Int, Int)] = []
            while b - a > size && depth < Self.mortonBits {
                runs = split(a, b, depth: depth)
                if runs.count > 1 { break }
                depth += 1
            }
            if runs.count > 1 {
                for r in runs {
                    let child = make(r.0, r.1, depth: depth + 1, parent: index)
                    kids[Int(index)].append(child)
                }
            } else {
                built[Int(index)].leaf = Int32(leaves.count)
                leaves.append(index)
            }
            built[Int(index)].subtree = Int32(built.count) - index
            built[Int(index)].leafEnd = Int32(leaves.count)
            return index
        }
        if n > 0 { _ = make(0, n, depth: 0, parent: -1) } else {
            built.append(Cell(lo: .zero, hi: .zero, centroid: .zero, spread: 0, first: 0, count: 0, parent: -1,
                              depth: 0, subtree: 1, childStart: 0, childCount: 0, leafStart: 0, leafEnd: 1,
                              leaf: 0, colour: 0))
            kids.append([])
            leaves.append(0)
        }
        var flat: [Int32] = []
        flat.reserveCapacity(built.count)
        for c in 0..<built.count {
            built[c].childStart = Int32(flat.count)
            built[c].childCount = Int32(kids[c].count)
            flat.append(contentsOf: kids[c])
        }

        // summaries: leaves from their bodies, the rest from their children
        var sum = [SIMD3<Double>](repeating: .zero, count: built.count)
        var square = [Double](repeating: 0, count: built.count)
        var rgb = [SIMD3<Double>](repeating: .zero, count: built.count)
        var leafSlot = [UInt16](repeating: 0, count: n)
        for (k, c) in leaves.enumerated() {
            let cell = built[Int(c)]
            var l = SIMD3<Float>(repeating: .infinity), h = SIMD3<Float>(repeating: -.infinity)
            var s = SIMD3<Double>.zero, q = 0.0, col = SIMD3<Double>.zero
            for t in Int(cell.first) ..< Int(cell.first + cell.count) {
                let body = Int(ord[t])
                var p = positions[body]
                if !(p.x.isFinite && p.y.isFinite && p.z.isFinite) { p = lo }
                l = pointwiseMin(l, p)
                h = pointwiseMax(h, p)
                let d = SIMD3<Double>(Double(p.x), Double(p.y), Double(p.z))
                s += d
                q += (d * d).sum()
                let c = body < colours.count ? colours[body] : 0xFFFF_FFFF
                col += SIMD3(Double(c & 0xFF), Double(c >> 8 & 0xFF), Double(c >> 16 & 0xFF))
                leafSlot[t] = UInt16(k)
            }
            if cell.count == 0 { l = .zero; h = .zero }
            built[Int(c)].lo = l
            built[Int(c)].hi = h
            sum[Int(c)] = s
            square[Int(c)] = q
            rgb[Int(c)] = col
        }
        for c in stride(from: built.count - 1, through: 0, by: -1) where built[c].leaf < 0 {
            var l = SIMD3<Float>(repeating: .infinity), h = SIMD3<Float>(repeating: -.infinity)
            for k in kids[c] {
                l = pointwiseMin(l, built[Int(k)].lo)
                h = pointwiseMax(h, built[Int(k)].hi)
                sum[c] += sum[Int(k)]
                square[c] += square[Int(k)]
                rgb[c] += rgb[Int(k)]
            }
            built[c].lo = l
            built[c].hi = h
        }
        for c in 0..<built.count {
            let count = Double(max(built[c].count, 1))
            let mean = sum[c] / count
            built[c].centroid = SIMD3(Float(mean.x), Float(mean.y), Float(mean.z))
            built[c].spread = Float(max(square[c] / count - (mean * mean).sum(), 0).squareRoot())
            let m = rgb[c] / count
            built[c].colour = UInt32(min(m.x.rounded(), 255)) | UInt32(min(m.y.rounded(), 255)) << 8
                | UInt32(min(m.z.rounded(), 255)) << 16 | 255 << 24
        }
        cells = built
        childList = flat
        leafCell = leaves
        leafOfSlot = leafSlot
    }

    /// Spreads the low 21 bits of each axis three apart (x lowest).
    static func morton(_ x: UInt64, _ y: UInt64, _ z: UInt64) -> UInt64 {
        spread(x) | spread(y) << 1 | spread(z) << 2
    }

    static func spread(_ v: UInt64) -> UInt64 {
        var x = v & 0x1F_FFFF
        x = (x | x << 32) & 0x1F_0000_0000_FFFF
        x = (x | x << 16) & 0x1F_0000_FF00_00FF
        x = (x | x << 8) & 0x100F_00F0_0F00_F00F
        x = (x | x << 4) & 0x10C3_0C30_C30C_30C3
        x = (x | x << 2) & 0x1249_2492_4924_9249
        return x
    }

    // MARK: - What the GPU is handed

    /// Per slot: x, y, z as 16-bit steps across its leaf's box, then its leaf.
    func packedPositions(_ positions: [SIMD3<Float>]) -> [UInt16] {
        var out = [UInt16](repeating: 0, count: 4 * bodyCount)
        for s in 0..<bodyCount {
            let leaf = Int(leafOfSlot[s])
            let cell = cells[Int(leafCell[leaf])]
            let q = GraphPerfQuantize.pack(positions[Int(order[s])], lo: cell.lo, hi: cell.hi)
            out[4 * s] = q.x
            out[4 * s + 1] = q.y
            out[4 * s + 2] = q.z
            out[4 * s + 3] = UInt16(leaf)
        }
        return out
    }

    /// Per leaf: its box's low corner and extent, then its first slot and
    /// count (as floats' bits: the shader reads them as uints).
    func leafBoxes() -> [SIMD4<Float>] {
        var out = [SIMD4<Float>](repeating: .zero, count: 2 * leafCount)
        for l in 0..<leafCount {
            let cell = cells[Int(leafCell[l])]
            out[2 * l] = SIMD4(cell.lo.x, cell.lo.y, cell.lo.z, Float(bitPattern: UInt32(cell.first)))
            let d = cell.hi - cell.lo
            out[2 * l + 1] = SIMD4(d.x, d.y, d.z, Float(bitPattern: UInt32(cell.count)))
        }
        return out
    }
}

/// Positions as three 16-bit numbers across a box: a step of a 65,535th of
/// its side, so a chunk 400 spacings across still places a body within
/// 0.003 spacings.
nonisolated enum GraphPerfQuantize {
    static let steps: Float = 65_535

    static func pack(_ p: SIMD3<Float>, lo: SIMD3<Float>, hi: SIMD3<Float>) -> SIMD3<UInt16> {
        let extent = pointwiseMax(hi - lo, SIMD3(repeating: 1e-9))
        var t = (p - lo) / extent * steps
        t = pointwiseMin(pointwiseMax(t, SIMD3(repeating: 0)), SIMD3(repeating: steps))
        let r = t.rounded(.toNearestOrAwayFromZero)
        return SIMD3(UInt16(r.x), UInt16(r.y), UInt16(r.z))
    }

    static func unpack(_ q: SIMD3<UInt16>, lo: SIMD3<Float>, hi: SIMD3<Float>) -> SIMD3<Float> {
        lo + SIMD3(Float(q.x), Float(q.y), Float(q.z)) / steps * (hi - lo)
    }

    /// The most a packed position is off by, per axis.
    static func error(lo: SIMD3<Float>, hi: SIMD3<Float>) -> SIMD3<Float> { (hi - lo) / steps * 0.5 }
}

/// Every link listed under each leaf it touches, home end first: a leaf
/// drawn in full draws its own list, so a link out of it reaches into its
/// neighbour whatever that neighbour shows. A link between two leaves both
/// drawn in full is drawn once (from the lower leaf; the shader folds the
/// other copy to nothing).
nonisolated struct GraphPerfLeafLinks: Sendable {
    /// Per leaf: its entries are start[l] ..< start[l + 1].
    let start: [Int32]
    /// Per entry: home slot, other slot.
    let pairs: [UInt32]

    var entryCount: Int { pairs.count / 2 }
    func count(_ leaf: Int) -> Int { Int(start[leaf + 1] - start[leaf]) }

    /// From links as body pairs (a[k], b[k]); a link to itself or out of
    /// range is left out.
    init(octree t: GraphPerfOctree, a: [Int32], b: [Int32]) {
        let leaves = t.leafCount
        let n = t.bodyCount
        var counts = [Int32](repeating: 0, count: leaves + 1)
        let m = min(a.count, b.count)
        func ok(_ k: Int) -> Bool {
            a[k] >= 0 && b[k] >= 0 && Int(a[k]) < n && Int(b[k]) < n && a[k] != b[k]
        }
        for k in 0..<m where ok(k) {
            let la = t.leaf(ofSlot: Int(t.slotOf[Int(a[k])]))
            let lb = t.leaf(ofSlot: Int(t.slotOf[Int(b[k])]))
            counts[la] += 1
            if lb != la { counts[lb] += 1 }
        }
        var s = [Int32](repeating: 0, count: leaves + 1)
        for l in 0..<leaves { s[l + 1] = s[l] + counts[l] }
        var fill = Array(s[0..<leaves])
        var out = [UInt32](repeating: 0, count: 2 * Int(s[leaves]))
        for k in 0..<m where ok(k) {
            let sa = Int(t.slotOf[Int(a[k])]), sb = Int(t.slotOf[Int(b[k])])
            let la = t.leaf(ofSlot: sa), lb = t.leaf(ofSlot: sb)
            var at = Int(fill[la]); fill[la] += 1
            out[2 * at] = UInt32(sa); out[2 * at + 1] = UInt32(sb)
            if lb != la {
                at = Int(fill[lb]); fill[lb] += 1
                out[2 * at] = UInt32(sb); out[2 * at + 1] = UInt32(sa)
            }
        }
        start = s
        pairs = out
    }
}

/// Far links as bundles: one cut across the octree (the biggest cells
/// opened in turn until there are about `maxCells`), and between each pair
/// of its cells one bundle carrying how many links run between them.
nonisolated struct GraphPerfBundles: Sendable {
    /// The cut's cells (octree cells, in depth-first order).
    let cells: [Int32]
    /// Per octree cell: the cut cells under it, cutStart ..< cutEnd (for a
    /// cell inside a cut cell, that one cell).
    let cutStart: [Int32]
    let cutEnd: [Int32]
    /// Per bundle: its two cut cells (indices into `cells`) and how many links.
    let a: [UInt32]
    let b: [UInt32]
    let weight: [Float]

    var count: Int { weight.count }

    init(octree t: GraphPerfOctree, a la: [Int32], b lb: [Int32], maxCells: Int = 384) {
        // the cut: open the cell with the most bodies until full
        var cut: [Int32] = [0]
        while cut.count < maxCells {
            var best = -1, most: Int32 = 0
            for (k, c) in cut.enumerated() where !t.cells[Int(c)].isLeaf && t.cells[Int(c)].count > most {
                best = k
                most = t.cells[Int(c)].count
            }
            guard best >= 0 else { break }
            let opened = t.children(Int(cut[best]))
            if cut.count - 1 + opened.count > maxCells { break }
            cut.remove(at: best)
            cut.append(contentsOf: opened)
        }
        cut.sort()
        cells = cut
        // per octree cell, the cut cells under it (or the one holding it)
        let total = t.cells.count
        var start = [Int32](repeating: 0, count: total)
        var end = [Int32](repeating: 0, count: total)
        var cutOfCell = [Int32](repeating: -1, count: total)
        for (k, c) in cut.enumerated() {
            let lo = Int(c), hi = lo + Int(t.cells[lo].subtree)
            for d in lo..<hi { cutOfCell[d] = Int32(k) }
        }
        for c in 0..<total {
            if cutOfCell[c] >= 0 {
                start[c] = cutOfCell[c]
                end[c] = cutOfCell[c] + 1
            } else {
                // above the cut: the cut cells inside its subtree (contiguous, depth first)
                let lo = Int32(c), hi = Int32(c) + t.cells[c].subtree
                var s = 0, e = cut.count
                while s < e { let m = (s + e) / 2; if cut[m] < lo { s = m + 1 } else { e = m } }
                var f = s
                while f < cut.count && cut[f] < hi { f += 1 }
                start[c] = Int32(s)
                end[c] = Int32(f)
            }
        }
        cutStart = start
        cutEnd = end
        // each leaf's cut cell, then the links summed per pair
        var cutOfLeaf = [Int32](repeating: 0, count: t.leafCount)
        for l in 0..<t.leafCount { cutOfLeaf[l] = cutOfCell[Int(t.leafCell[l])] }
        var sums: [UInt64: Int] = [:]
        let n = t.bodyCount
        for k in 0..<min(la.count, lb.count) {
            guard la[k] >= 0, lb[k] >= 0, Int(la[k]) < n, Int(lb[k]) < n else { continue }
            let ca = cutOfLeaf[t.leaf(ofSlot: Int(t.slotOf[Int(la[k])]))]
            let cb = cutOfLeaf[t.leaf(ofSlot: Int(t.slotOf[Int(lb[k])]))]
            guard ca != cb else { continue }
            let key = UInt64(UInt32(min(ca, cb))) << 32 | UInt64(UInt32(max(ca, cb)))
            sums[key, default: 0] += 1
        }
        let keys = sums.keys.sorted()
        a = keys.map { UInt32($0 >> 32) }
        b = keys.map { UInt32($0 & 0xFFFF_FFFF) }
        weight = keys.map { Float(sums[$0] ?? 0) }
    }
}
